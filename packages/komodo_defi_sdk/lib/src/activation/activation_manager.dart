import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mutex/mutex.dart';

/// Manager responsible for handling asset activation lifecycle
class ActivationManager {
  /// Manager responsible for handling asset activation lifecycle
  ActivationManager(
    this._client,
    this._auth,
    this._assetHistory,
    this._assetLookup,
    this._balanceManager,
    this._configService,
    this._assetsUpdateManager,
    this._activatedAssetsCache, {
    TronGaslessProviderConfig? tronGaslessProvider,
    GaslessCapabilityRegistry? gaslessCapabilities,
  }) : _tronGaslessProvider = tronGaslessProvider,
       _gaslessCapabilities =
           gaslessCapabilities ??
           GaslessCapabilityRegistry(configuredAssetIds: const <String>[]);

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final AssetHistoryStorage _assetHistory;
  final IAssetLookup _assetLookup;
  final IBalanceManager _balanceManager;
  final ActivationConfigService _configService;
  final KomodoAssetsUpdateManager _assetsUpdateManager;
  final ActivatedAssetsCache _activatedAssetsCache;

  /// Optional Tron GasFree provider config, attached to TRX platform
  /// activations to enable gas-free TRC20 transfers. Held in memory only.
  final TronGaslessProviderConfig? _tronGaslessProvider;
  final GaslessCapabilityRegistry _gaslessCapabilities;
  final Map<AssetId, String> _resolvedGaslessProviders = {};
  final Map<AssetId, _GaslessRuntimeContract> _gaslessRuntimeContracts = {};
  final _activationMutex = Mutex();
  static const _operationTimeout = Duration(seconds: 30);
  static const SdkErrorMapper _errorMapper = SdkErrorMapper();

  final Map<AssetId, Completer<void>> _activationCompleters = {};
  final Map<AssetId, String> _cancelledActivations = <AssetId, String>{};
  bool _isDisposed = false;

  /// Helper for mutex-protected operations with timeout
  Future<T> _protectedOperation<T>(Future<T> Function() operation) {
    return _activationMutex
        .protect(operation)
        .timeout(
          _operationTimeout,
          onTimeout: () =>
              throw TimeoutException('Operation timed out', _operationTimeout),
        );
  }

  /// Activate a single asset
  Stream<ActivationProgress> activateAsset(Asset asset) {
    final parentId = asset.id.parentId;
    if (asset.protocol is Trc20Protocol &&
        _tronGaslessProvider != null &&
        _gaslessCapabilities.isConfigured(asset) &&
        parentId != null) {
      final parentAsset = _assetLookup.fromId(parentId);
      if (parentAsset != null) {
        return activateAssets([parentAsset, asset]);
      }
    }

    return activateAssets([asset]);
  }

  /// Whether an active TRC20 token still needs a provider-aware activation
  /// attempt in this SDK session.
  bool shouldRefreshTronGaslessActivation(Asset asset) =>
      _tronGaslessProvider != null &&
      _gaslessCapabilities.isConfigured(asset) &&
      !_gaslessCapabilities.isReady(asset.id) &&
      !_gaslessCapabilities.canReceiveGaslessFromStatus(asset.id);

  /// Clear per-session activation hints when the active wallet changes.
  void resetActivationSessionState() {
    _gaslessCapabilities.resetSession();
    _resolvedGaslessProviders.clear();
    _gaslessRuntimeContracts.clear();
  }

  /// Request cancellation of an in-flight activation for [assetId].
  ///
  /// Cancellation is best-effort. The current activation stream is terminated
  /// at the next progress boundary and emits an error completion state.
  void cancelActivation(
    AssetId assetId, {
    String reason = 'Activation cancelled by caller',
  }) {
    if (_isDisposed) return;
    // Only record cancellation for activations that are currently in-flight.
    // This avoids stale cancellation markers cancelling future fresh attempts.
    if (!_activationCompleters.containsKey(assetId)) {
      _cancelledActivations.remove(assetId);
      return;
    }
    _cancelledActivations[assetId] = reason;
  }

  /// Request cancellation for all in-flight activations.
  void cancelAllActivations({
    String reason = 'Activation cancelled by caller',
  }) {
    if (_isDisposed) return;
    final pendingIds = _activationCompleters.keys.toList();
    for (final assetId in pendingIds) {
      _cancelledActivations[assetId] = reason;
    }
  }

  /// Activate multiple assets
  Stream<ActivationProgress> activateAssets(List<Asset> assets) async* {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    final groups = _AssetGroup._groupByPrimary(assets, _assetLookup);

    for (final group in groups) {
      if (_cancelledActivations.containsKey(group.primary.id)) {
        final reason =
            _cancelledActivations[group.primary.id] ??
            'Activation cancelled by caller';
        yield ActivationProgress.error(
          message: reason,
          errorCode: 'ACTIVATION_CANCELLED',
        );
        _cancelledActivations.remove(group.primary.id);
        continue;
      }

      final shouldRefreshTronGaslessActivation =
          _shouldRefreshTronGaslessActivation(group);

      // Check activation status atomically
      final activationStatus = await _checkActivationStatus(group);
      if (activationStatus.isComplete) {
        if (!shouldRefreshTronGaslessActivation) {
          yield activationStatus;
          continue;
        }
        // Always bind an already-active runtime to the configured provider and
        // token set through gasless::configure. A successful status probe alone
        // cannot prove that the live provider matches the current security pin.
      }

      // Register activation attempt.
      final registration = await _registerActivation(group.primary.id);
      final primaryCompleter = registration.completer;
      if (!registration.shouldStartActivation) {
        debugPrint(
          'Activation already in progress for ${group.primary.id.name}',
        );
        try {
          await primaryCompleter.future;
        } catch (e, st) {
          final mappedError = _mapError(e, group.primary.id);
          yield ActivationProgress.error(
            message: mappedError.fallbackMessage,
            sdkError: mappedError,
            stackTrace: st,
          );
          continue;
        }

        // In-flight activations are keyed on the primary asset id alone, so the
        // activation we just joined may have enabled the platform WITHOUT our
        // child tokens — e.g. a concurrent standalone TRX activation racing a
        // `[TRX, USDT-TRC20]` group. Verify the children are actually enabled
        // before reporting success: reporting a child as active without ever
        // registering it in KDF is invisible here and only surfaces later as a
        // `NoSuchCoin` error at withdraw/preview time.
        final joinedStatus = await _checkActivationStatus(
          group,
          forceRefresh: true,
        );
        if (joinedStatus.isComplete) {
          final verified = shouldRefreshTronGaslessActivation
              ? await _verifyGaslessCapability(group, joinedStatus)
              : joinedStatus;
          yield verified;
          continue;
        }

        // Platform active but our children are missing: fall through to the
        // activation block below. With the platform already active, the
        // strategy activates only the still-missing children individually
        // (enable_erc20, retaining the gasless config) instead of re-running
        // the platform batch (which KDF would reject as already activated).
      }

      yield ActivationProgress(
        status: 'Starting activation for ${group.primary.id.name}...',
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.groupStart,
          stepCount: 1,
          additionalInfo: {
            'primaryAsset': group.primary.id.name,
            'childCount': group.children.length,
          },
        ),
      );

      try {
        // Get the current user's auth options to retrieve privKeyPolicy
        final currentUser = await _auth.currentUser;
        final privKeyPolicy =
            currentUser?.walletId.authOptions.privKeyPolicy ??
            const PrivateKeyPolicy.contextPrivKey();

        final gaslessProvider = privKeyPolicy == const PrivateKeyPolicy.trezor()
            ? null
            : _gaslessProviderFor(group);

        // Create activator with the user's privKeyPolicy
        final activator = ActivationStrategyFactory.createStrategy(
          _client,
          privKeyPolicy,
          _configService,
          _activatedAssetsCache,
          tronGaslessProvider: gaslessProvider,
          tronGaslessAssetIds: _gaslessCapabilities.configuredAssetIds,
        );

        var completionHandled = false;
        final activationStream =
            activationStatus.isComplete &&
                shouldRefreshTronGaslessActivation &&
                gaslessProvider != null
            ? _reconfigureGaslessRuntime(group, gaslessProvider)
            : activator.activate(group.primary, group.children.toList());
        await for (final rawProgress in activationStream) {
          if (_cancelledActivations.containsKey(group.primary.id)) {
            final reason =
                _cancelledActivations[group.primary.id] ??
                'Activation cancelled by caller';
            final cancellationError = ActivationCancelledException(
              assetId: group.primary.id,
              message: reason,
            );
            if (!primaryCompleter.isCompleted) {
              primaryCompleter.completeError(cancellationError);
            }
            yield ActivationProgress.error(
              message: reason,
              errorCode: 'ACTIVATION_CANCELLED',
            );
            break;
          }

          var progress = _attachSdkError(rawProgress, group.primary.id);
          if (progress.isComplete &&
              progress.isSuccess &&
              shouldRefreshTronGaslessActivation) {
            progress = await _verifyGaslessCapability(group, progress);
          }

          // Complete the join completer BEFORE yielding the terminal progress.
          // The coordinator breaks out of its `await for` as soon as it
          // receives a terminal progress, which cancels this async* generator
          // at the `yield` suspension point below. Concurrent activations that
          // joined this batch await `primaryCompleter.future` (e.g. a standalone
          // platform activation racing a `[platform, token]` group); completing
          // it only inside `_handleActivationComplete` (which runs after the
          // yield) would never fire once the stream is cancelled, leaving the
          // joined activation — and therefore the platform coin — hung forever.
          if (progress.isComplete && !completionHandled) {
            if (progress.isSuccess) {
              if (!primaryCompleter.isCompleted) {
                primaryCompleter.complete();
              }
            } else if (!primaryCompleter.isCompleted) {
              primaryCompleter.completeError(
                progress.errorMessage ?? 'Unknown error',
              );
            }
          }

          yield progress;

          if (progress.isComplete) {
            if (completionHandled) {
              debugPrint(
                'Ignoring duplicate completion event for '
                '${group.primary.id.name}',
              );
              continue;
            }
            completionHandled = true;
            await _handleActivationComplete(group, progress, primaryCompleter);
          }
        }

        // The strategy can finish WITHOUT emitting a terminal completion event
        // when the platform and all requested children are already active (the
        // individual-children path skips already-active children and yields
        // nothing). Without a terminal event the coordinator's Future
        // (shared_activation_coordinator) would await forever — emit a synthetic
        // completion (or failure) so it always resolves.
        if (!completionHandled &&
            !_cancelledActivations.containsKey(group.primary.id)) {
          final status = await _checkActivationStatus(
            group,
            forceRefresh: true,
          );
          completionHandled = true;
          if (status.isComplete) {
            final verified = shouldRefreshTronGaslessActivation
                ? await _verifyGaslessCapability(group, status)
                : status;
            await _handleActivationComplete(group, verified, primaryCompleter);
            yield verified;
          } else {
            final mappedError = _mapError(
              StateError(
                'Activation produced no result for ${group.primary.id.name}',
              ),
              group.primary.id,
            );
            if (!primaryCompleter.isCompleted) {
              primaryCompleter.completeError(mappedError);
            }
            yield ActivationProgress.error(
              message: mappedError.fallbackMessage,
              sdkError: mappedError,
            );
          }
        }
      } catch (e, st) {
        final recoveredProgress = shouldRefreshTronGaslessActivation
            ? null
            : await _tryRecoverAlreadyActivated(group, e);
        if (recoveredProgress != null) {
          if (!primaryCompleter.isCompleted) {
            primaryCompleter.complete();
          }
          yield recoveredProgress;
          continue;
        }

        debugPrint('Activation failed: $e');
        final mappedError = _mapError(e, group.primary.id);
        if (!primaryCompleter.isCompleted) {
          primaryCompleter.completeError(mappedError);
        }
        yield ActivationProgress.error(
          message: mappedError.fallbackMessage,
          sdkError: mappedError,
          stackTrace: st,
        );
      } finally {
        try {
          await _cleanupActivation(group.primary.id);
        } catch (e) {
          debugPrint('Failed to cleanup activation: $e');
        }
      }
    }
  }

  ActivationProgress _attachSdkError(
    ActivationProgress progress,
    AssetId assetId,
  ) {
    if (!progress.isError || progress.sdkError != null) {
      return progress;
    }

    final errorMessage = progress.errorMessage ?? 'Activation failed';
    final sdkError = _mapError(errorMessage, assetId);

    return progress.copyWith(
      errorMessage: sdkError.fallbackMessage,
      sdkError: sdkError,
    );
  }

  SdkError _mapError(Object error, AssetId assetId) {
    return _errorMapper.map(
      error,
      context: SdkErrorContext(operation: 'activation', assetId: assetId.id),
    );
  }

  /// Check if asset and its children are already activated.
  Future<ActivationProgress> _checkActivationStatus(
    _AssetGroup group, {
    bool forceRefresh = false,
  }) async {
    try {
      // Use cache instead of direct RPC call to avoid excessive requests
      final enabledAssetIds = await _activatedAssetsCache.getActivatedAssetIds(
        forceRefresh: forceRefresh,
      );

      final isActive = enabledAssetIds.contains(group.primary.id);
      final childrenActive = group.children.every(
        (child) => enabledAssetIds.contains(child.id),
      );

      if (isActive && childrenActive) {
        return ActivationProgress.alreadyActiveSuccess(
          assetName: group.primary.id.name,
          childCount: group.children.length,
        );
      }
    } catch (e) {
      debugPrint('Failed to check activation status: $e');
    }

    return const ActivationProgress(
      status: 'Needs activation',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.init,
        stepCount: 1,
      ),
    );
  }

  /// Register a new activation attempt or join an existing one.
  Future<_ActivationRegistration> _registerActivation(AssetId assetId) async {
    return _protectedOperation(() async {
      final existingCompleter = _activationCompleters[assetId];
      if (existingCompleter != null) {
        return _ActivationRegistration(
          completer: existingCompleter,
          shouldStartActivation: false,
        );
      }

      final completer = Completer<void>();
      // A sole activation attempt has no joiner awaiting this future. Attach a
      // side listener so completing it with an error does not become an
      // unhandled zone error; concurrent joiners still receive the same error.
      unawaited(completer.future.catchError((Object _) {}));
      _activationCompleters[assetId] = completer;
      return _ActivationRegistration(
        completer: completer,
        shouldStartActivation: true,
      );
    });
  }

  Future<ActivationProgress?> _tryRecoverAlreadyActivated(
    _AssetGroup group,
    Object error,
  ) async {
    if (!_isAlreadyActivatedError(error)) {
      return null;
    }

    _activatedAssetsCache.invalidate();
    final refreshedStatus = await _checkActivationStatus(
      group,
      forceRefresh: true,
    );
    return refreshedStatus.isComplete ? refreshedStatus : null;
  }

  bool _isAlreadyActivatedError(Object error) {
    final message = error.toString();
    return message.contains('PlatformIsAlreadyActivated') ||
        message.contains('CoinIsAlreadyActivated') ||
        message.contains('activated already');
  }

  /// Handle completion of activation
  Future<void> _handleActivationComplete(
    _AssetGroup group,
    ActivationProgress progress,
    Completer<void> completer,
  ) async {
    if (progress.isSuccess) {
      final user = await _auth.currentUser;
      if (user != null) {
        // Store custom tokens using CoinConfigManager
        if (group.primary.protocol.isCustomToken) {
          await _assetsUpdateManager.assets.storeCustomToken(group.primary);
        } else {
          await _assetHistory.addAssetToWallet(
            user.walletId,
            group.primary.id.id,
          );
        }

        final allAssets = [group.primary, ...group.children];

        for (final asset in allAssets) {
          if (asset.protocol.isCustomToken) {
            await _assetsUpdateManager.assets.storeCustomToken(asset);
          }

          // Pre-cache balance for the activated asset
          await _balanceManager.precacheBalance(asset);
        }

        _activatedAssetsCache.invalidate();
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    } else {
      if (!completer.isCompleted) {
        completer.completeError(progress.errorMessage ?? 'Unknown error');
      }
    }
  }

  bool _shouldRefreshTronGaslessActivation(_AssetGroup group) {
    if (_tronGaslessProvider == null) {
      return false;
    }

    if (group.primary.protocol is Trc20Protocol) {
      return shouldRefreshTronGaslessActivation(group.primary);
    }

    if (group.primary.protocol is TrxProtocol) {
      return group.children.any(shouldRefreshTronGaslessActivation);
    }

    return false;
  }

  TronGaslessProviderConfig? _gaslessProviderFor(_AssetGroup group) {
    if (_tronGaslessProvider == null) return null;
    return _gaslessAssets(group).isEmpty ? null : _tronGaslessProvider;
  }

  Stream<ActivationProgress> _reconfigureGaslessRuntime(
    _AssetGroup group,
    TronGaslessProviderConfig provider,
  ) async* {
    final tokens = _gaslessAssets(group)
        .where((asset) => asset.protocol is Trc20Protocol)
        .map((asset) => GaslessConfigureToken(coin: asset.id.id))
        .toList();
    if (tokens.isEmpty) {
      throw StateError(
        'GasFree runtime reconfiguration requires a TRC20 token',
      );
    }

    yield const ActivationProgress(
      status: 'Configuring gas-free runtime...',
      progressDetails: ActivationProgressDetails(
        currentStep: ActivationStep.processing,
        stepCount: 2,
      ),
    );

    final contract = await _configureGaslessRuntime(group, provider, tokens);

    yield ActivationProgress.success(
      details: ActivationProgressDetails(
        currentStep: ActivationStep.complete,
        stepCount: 2,
        additionalInfo: {
          'method': contract == _GaslessRuntimeContract.boundConfigure
              ? 'gasless::configure'
              : 'gasless::account_status',
          'tokenCount': tokens.length,
        },
      ),
    );
  }

  Future<_GaslessRuntimeContract> _configureGaslessRuntime(
    _AssetGroup group,
    TronGaslessProviderConfig provider,
    List<GaslessConfigureToken> tokens,
  ) async {
    final GaslessConfigureResponse response;
    try {
      response = await _client.rpc.withdraw.configureGasless(
        platformCoin: group.primary.id.id,
        provider: provider,
        tokens: tokens,
      );
    } catch (error) {
      final isMethodMissing =
          error is DispatcherErrorNoSuchMethodException ||
          error is GeneralErrorResponse && error.errorType == 'NoSuchMethod';
      if (!isMethodMissing) rethrow;

      // KDF PR #9 has no runtime configure RPC. Its activation request still
      // installs the provider, so retain the explicit local pin and require an
      // authoritative account-status probe before the capability can be ready.
      final pinnedProvider = provider.serviceProvider?.trim();
      if (pinnedProvider == null || pinnedProvider.isEmpty) {
        throw const _GaslessSecurityMismatch(
          reasonCode: 'legacy_provider_pin_missing',
        );
      }
      final configuredCoins = tokens.map((token) => token.coin).toSet();
      for (final asset in _gaslessAssets(group)) {
        if (configuredCoins.contains(asset.id.id)) {
          _resolvedGaslessProviders[asset.id] = pinnedProvider;
          _gaslessRuntimeContracts[asset.id] =
              _GaslessRuntimeContract.legacyAccountStatus;
        }
      }
      return _GaslessRuntimeContract.legacyAccountStatus;
    }
    if (response.platformCoin != group.primary.id.id) {
      throw const _GaslessSecurityMismatch(
        reasonCode: 'configure_platform_mismatch',
      );
    }
    final configuredCoins = response.tokens.map((token) => token.coin).toSet();
    final expectedCoins = tokens.map((token) => token.coin).toSet();
    if (!configuredCoins.containsAll(expectedCoins) ||
        configuredCoins.length != expectedCoins.length) {
      throw const _GaslessSecurityMismatch(
        reasonCode: 'configure_token_mismatch',
      );
    }
    final pinnedProvider = provider.serviceProvider?.trim();
    if (pinnedProvider != null &&
        pinnedProvider.isNotEmpty &&
        response.serviceProvider != pinnedProvider) {
      throw const _GaslessSecurityMismatch(
        reasonCode: 'configure_provider_mismatch',
      );
    }
    if (response.serviceProvider.trim().isEmpty) {
      throw const _GaslessSecurityMismatch(
        reasonCode: 'configure_provider_missing',
      );
    }
    for (final asset in _gaslessAssets(group)) {
      if (expectedCoins.contains(asset.id.id)) {
        _resolvedGaslessProviders[asset.id] = response.serviceProvider;
        _gaslessRuntimeContracts[asset.id] =
            _GaslessRuntimeContract.boundConfigure;
      }
    }
    return _GaslessRuntimeContract.boundConfigure;
  }

  Iterable<Asset> _gaslessAssets(_AssetGroup group) sync* {
    if (_gaslessCapabilities.isConfigured(group.primary)) {
      yield group.primary;
    }
    for (final child in group.children) {
      if (_gaslessCapabilities.isConfigured(child)) yield child;
    }
  }

  Future<ActivationProgress> _verifyGaslessCapability(
    _AssetGroup group,
    ActivationProgress success,
  ) async {
    try {
      final assets = _gaslessAssets(group).toList();
      if (assets.isEmpty) return success;
      final user = await _auth.currentUser;
      final softwareWallet =
          user != null &&
          user.walletId.authOptions.privKeyPolicy ==
              const PrivateKeyPolicy.contextPrivKey();
      if (!softwareWallet) {
        throw StateError('GasFree requires a primary software wallet');
      }
      if (_tronGaslessProvider == null) {
        throw StateError('GasFree provider configuration is unavailable');
      }
      if (assets.any(
        (asset) => !_resolvedGaslessProviders.containsKey(asset.id),
      )) {
        final tokens = assets
            .map((asset) => GaslessConfigureToken(coin: asset.id.id))
            .toList();
        await _configureGaslessRuntime(group, _tronGaslessProvider, tokens);
      }
      for (final asset in assets) {
        final requestedPath = asset.id.derivationPath;
        final walletType = switch (user.walletId.authOptions.derivationMethod) {
          DerivationMethod.hdWallet => GaslessWalletType.softwareHd,
          DerivationMethod.iguana => GaslessWalletType.softwareIguana,
        };
        final capabilityPath = switch (walletType) {
          GaslessWalletType.softwareHd =>
            GaslessCapabilityRegistry.canonicalPrimaryDerivationPath,
          GaslessWalletType.softwareIguana => '',
        };
        final sourceIsCanonical = switch (walletType) {
          GaslessWalletType.softwareHd =>
            requestedPath == null ||
                requestedPath == "m/44'/195'" ||
                requestedPath == capabilityPath,
          GaslessWalletType.softwareIguana =>
            requestedPath == null || requestedPath == "m/44'/195'",
        };
        if (!sourceIsCanonical) {
          throw StateError('GasFree requires the canonical TRON derivation');
        }
        _gaslessCapabilities.markChecking(asset.id);
        final status = await _client.rpc.withdraw.gaslessAccountStatus(
          coin: asset.id.id,
        );
        if (!status.hasExplicitAvailability) {
          throw const _GaslessTemporarilyUnavailable(
            reasonCode: 'availability_unattested',
          );
        }
        switch (status.availability) {
          case GaslessAccountAvailability.available:
            break;
          case GaslessAccountAvailability.pendingTransfer:
            throw const _GaslessTemporarilyUnavailable(
              reasonCode: 'pending_transfer',
            );
          case GaslessAccountAvailability.tokenUnsupported:
            throw const _GaslessUnsupported(reasonCode: 'token_unsupported');
          case GaslessAccountAvailability.providerUnreachable:
            throw const _GaslessTemporarilyUnavailable(
              reasonCode: 'provider_unreachable',
            );
        }
        if (status.gasfreeAddress.isEmpty ||
            status.reasonCode != null ||
            status.active == null ||
            status.frozenBalance == null ||
            status.spendableBalance == null ||
            status.transferFee == null ||
            status.maxWithdrawable == null) {
          throw StateError(
            'GasFree account status is not provider-authoritative',
          );
        }
        final protocol = asset.protocol as Trc20Protocol;
        final topLevelContract = protocol.config['contract_address'];
        final protocolJson = protocol.config['protocol'];
        final protocolData = protocolJson is Map
            ? protocolJson['protocol_data']
            : null;
        final nestedContract = protocolData is Map
            ? protocolData['contract_address']
            : null;
        final contractAddress = topLevelContract is String
            ? topLevelContract
            : nestedContract is String
            ? nestedContract
            : null;
        final providerAddress = _resolvedGaslessProviders[asset.id];
        final walletPubkeyHash = user.walletId.pubkeyHash;
        if (contractAddress == null ||
            providerAddress == null ||
            walletPubkeyHash == null) {
          throw const _GaslessSecurityMismatch(
            reasonCode: 'capability_identity_mismatch',
          );
        }
        final identity = GaslessCapabilityIdentity(
          assetId: asset.id,
          platform: protocol.platform,
          contractAddress: contractAddress,
          providerAddress: providerAddress,
          walletPubkeyHash: walletPubkeyHash,
          walletType: walletType,
          derivationPath: capabilityPath,
        );
        final isLegacy =
            _gaslessRuntimeContracts[asset.id] ==
            _GaslessRuntimeContract.legacyAccountStatus;
        if (isLegacy && status.serviceProvider != providerAddress) {
          throw const _GaslessSecurityMismatch(
            reasonCode: 'provider_identity_mismatch',
          );
        }
        final accepted = isLegacy
            ? _gaslessCapabilities.markStatusAttestedFor(
                asset,
                identity,
                status,
              )
            : _gaslessCapabilities.markReadyFor(asset, identity);
        if (!accepted) {
          throw const _GaslessSecurityMismatch(
            reasonCode: 'capability_identity_mismatch',
          );
        }
      }
      return success;
    } catch (error, stackTrace) {
      for (final asset in _gaslessAssets(group)) {
        if (_gaslessCapabilities.markAccountStatusError(asset.id, error)) {
          continue;
        } else if (error case _GaslessSecurityMismatch(:final reasonCode)) {
          _gaslessCapabilities.markSecurityMismatch(
            asset.id,
            reasonCode: reasonCode,
          );
        } else if (error case _GaslessUnsupported(:final reasonCode)) {
          _gaslessCapabilities.markUnsupported(
            asset.id,
            reasonCode: reasonCode,
          );
        } else if (error case _GaslessTemporarilyUnavailable(
          :final reasonCode,
        )) {
          _gaslessCapabilities.markStale(asset.id, reasonCode: reasonCode);
        } else if (error case _GaslessDisabled(:final reasonCode)) {
          _gaslessCapabilities.markDisabled(asset.id, reasonCode: reasonCode);
        } else {
          _gaslessCapabilities.markUnconfirmed(asset.id);
        }
      }
      final mappedError = _mapError(error, group.primary.id);
      return ActivationProgress.error(
        message: mappedError.fallbackMessage,
        sdkError: mappedError,
        stackTrace: stackTrace,
      );
    }
  }

  /// Cleanup after activation attempt
  Future<void> _cleanupActivation(AssetId assetId) async {
    await _protectedOperation(() async {
      _activationCompleters.remove(assetId);
      _cancelledActivations.remove(assetId);
    });
  }

  /// Get currently activated assets
  Future<Set<AssetId>> getActiveAssets() async {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    try {
      return await _activatedAssetsCache.getActivatedAssetIds();
    } catch (e) {
      debugPrint('Failed to get active assets: $e');
      return {};
    }
  }

  /// Check if specific asset is active
  Future<bool> isAssetActive(
    AssetId assetId, {
    bool forceRefresh = false,
  }) async {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    try {
      final activeAssets = forceRefresh
          ? await _activatedAssetsCache.getActivatedAssetIds(forceRefresh: true)
          : await getActiveAssets();
      return activeAssets.contains(assetId);
    } catch (e) {
      debugPrint('Failed to check if asset is active: $e');
      return false;
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    if (_isDisposed) return;

    await _protectedOperation(() async {
      _isDisposed = true;

      // Complete any pending completers with errors
      final completers = List<Completer<void>>.from(
        _activationCompleters.values,
      );
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.completeError('ActivationManager disposed');
        }
      }

      _activationCompleters.clear();
      _cancelledActivations.clear();
    });
  }
}

class _GaslessSecurityMismatch implements Exception {
  const _GaslessSecurityMismatch({required this.reasonCode});

  final String reasonCode;

  @override
  String toString() => 'GasFree security validation failed';
}

class _GaslessUnsupported implements Exception {
  const _GaslessUnsupported({required this.reasonCode});

  final String reasonCode;

  @override
  String toString() => 'GasFree is unsupported for this token';
}

class _GaslessTemporarilyUnavailable implements Exception {
  const _GaslessTemporarilyUnavailable({required this.reasonCode});

  final String reasonCode;

  @override
  String toString() => 'GasFree is temporarily unavailable';
}

class _GaslessDisabled implements Exception {
  const _GaslessDisabled({required this.reasonCode});

  final String reasonCode;

  @override
  String toString() => 'GasFree provider authentication is unavailable';
}

enum _GaslessRuntimeContract { legacyAccountStatus, boundConfigure }

/// Internal class for grouping related assets
class _AssetGroup {
  _AssetGroup({required this.primary, Set<Asset>? children})
    : children = children ?? <Asset>{},
      assert(
        (children ?? const <Asset>{}).every(
          (asset) => asset.id.parentId == primary.id,
        ),
        'All child assets must have the parent asset as their parent',
      );

  final Asset primary;
  final Set<Asset> children;

  static List<_AssetGroup> _groupByPrimary(
    List<Asset> assets,
    IAssetLookup assetLookup,
  ) {
    final groups = <AssetId, _AssetGroup>{};

    for (final asset in assets) {
      final parentId = asset.id.parentId;
      if (parentId == null || asset.protocol.isCustomToken) {
        groups.putIfAbsent(asset.id, () => _AssetGroup(primary: asset));
        continue;
      }

      final parentAsset = assetLookup.fromId(parentId);
      if (parentAsset == null) {
        groups.putIfAbsent(asset.id, () => _AssetGroup(primary: asset));
        continue;
      }

      final group = groups.putIfAbsent(
        parentId,
        () => _AssetGroup(primary: parentAsset),
      );
      group.children.add(asset);
    }

    return groups.values.toList();
  }
}

class _ActivationRegistration {
  const _ActivationRegistration({
    required this.completer,
    required this.shouldStartActivation,
  });

  final Completer<void> completer;
  final bool shouldStartActivation;
}
