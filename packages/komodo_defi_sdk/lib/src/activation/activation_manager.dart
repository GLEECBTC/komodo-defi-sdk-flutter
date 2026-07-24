import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
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
  final _activationMutex = Mutex();
  static const _operationTimeout = Duration(seconds: 30);
  static const SdkErrorMapper _errorMapper = SdkErrorMapper();

  final Map<AssetId, Completer<void>> _activationCompleters = {};
  final Map<AssetId, _ActivationCancellation> _cancelledActivations = {};
  int _activationSessionGeneration = 0;
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

  /// Whether an active TRC20 token may refresh its provider-backed status.
  ///
  /// Disabled activations and hard security mismatches require a controlled
  /// reactivation/session reset instead of another in-place status attempt.
  bool shouldRefreshTronGaslessActivation(Asset asset) =>
      _tronGaslessProvider != null &&
      _gaslessCapabilities.isConfigured(asset) &&
      !_gaslessCapabilities.isReady(asset.id) &&
      _gaslessCapabilities.canRefreshAccountStatus(asset);

  /// Clear per-session activation hints when the active wallet changes.
  void resetActivationSessionState() {
    _activationSessionGeneration++;
    final staleCompleters = _activationCompleters.values.toList();
    _activationCompleters.clear();
    _cancelledActivations.clear();
    _gaslessCapabilities.resetSession();

    for (final completer in staleCompleters) {
      if (!completer.isCompleted) {
        completer.completeError(
          const WalletChangedDisconnectException(
            'Wallet changed during asset activation',
          ),
        );
      }
    }
  }

  Future<_GaslessActivationContext> _captureGaslessContext() async {
    final generation = _gaslessCapabilities.sessionGeneration;
    final user = await _auth.currentUser;
    if (user == null ||
        !_gaslessCapabilities.ensureWalletSession(user.walletId.pubkeyHash) ||
        generation != _gaslessCapabilities.sessionGeneration) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree activation',
      );
    }
    return _GaslessActivationContext(
      walletId: user.walletId,
      sessionGeneration: generation,
    );
  }

  Future<void> _requireGaslessContextCurrent(
    _GaslessActivationContext context,
  ) async {
    if (context.sessionGeneration != _gaslessCapabilities.sessionGeneration) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree activation',
      );
    }
    final user = await _auth.currentUser;
    if (user == null ||
        !_gaslessCapabilities.ensureWalletSession(user.walletId.pubkeyHash) ||
        context.sessionGeneration != _gaslessCapabilities.sessionGeneration ||
        !isSameStableWallet(context.walletId, user.walletId)) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree activation',
      );
    }
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
    final completer = _activationCompleters[assetId];
    if (completer == null) {
      _cancelledActivations.remove(assetId);
      return;
    }
    _cancelledActivations[assetId] = _ActivationCancellation(
      completer: completer,
      sessionGeneration: _activationSessionGeneration,
      reason: reason,
    );
  }

  /// Request cancellation for all in-flight activations.
  void cancelAllActivations({
    String reason = 'Activation cancelled by caller',
  }) {
    if (_isDisposed) return;
    final pendingActivations = _activationCompleters.entries.toList();
    for (final entry in pendingActivations) {
      _cancelledActivations[entry.key] = _ActivationCancellation(
        completer: entry.value,
        sessionGeneration: _activationSessionGeneration,
        reason: reason,
      );
    }
  }

  /// Activate multiple assets
  Stream<ActivationProgress> activateAssets(List<Asset> assets) async* {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    final groups = _AssetGroup._groupByPrimary(assets, _assetLookup);

    for (final group in groups) {
      final activationSessionGeneration = _activationSessionGeneration;
      final pendingCancellation = _currentCancellation(group.primary.id);
      if (pendingCancellation != null) {
        yield ActivationProgress.error(
          message: pendingCancellation.reason,
          errorCode: 'ACTIVATION_CANCELLED',
        );
        continue;
      }

      final gaslessRefreshCandidate = _shouldRefreshTronGaslessActivation(
        group,
      );
      final candidateGaslessContext = gaslessRefreshCandidate
          ? await _captureGaslessContext()
          : null;
      final shouldRefreshTronGaslessActivation =
          candidateGaslessContext != null &&
          candidateGaslessContext.walletId.authOptions.privKeyPolicy !=
              const PrivateKeyPolicy.trezor();
      final gaslessContext = shouldRefreshTronGaslessActivation
          ? candidateGaslessContext
          : null;

      // Check activation status atomically
      final activationStatus = await _checkActivationStatus(group);
      if (activationStatus.isComplete) {
        if (!shouldRefreshTronGaslessActivation) {
          yield activationStatus;
          continue;
        }
        // An already-active token cannot be reconfigured in place. Probe its
        // activation-scoped GasFree status; `GaslessNotConfigured` is retained
        // as `reactivation_required` while Standard TRON remains available.
      }

      // Register activation attempt.
      final registration = await _registerActivation(
        group.primary.id,
        activationSessionGeneration,
      );
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
              ? await _verifyGaslessCapability(
                  group,
                  joinedStatus,
                  gaslessContext!,
                )
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
            // The standard asset is already active. Feed that successful
            // status through the capability verifier, whose GasFree-only
            // failures are deliberately non-terminal for Standard TRON.
            ? Stream<ActivationProgress>.value(activationStatus)
            : activator.activate(group.primary, group.children.toList());
        await for (final rawProgress in activationStream) {
          final cancellation = _cancellationFor(group.primary.id, registration);
          if (cancellation != null) {
            final cancellationError = ActivationCancelledException(
              assetId: group.primary.id,
              message: cancellation.reason,
            );
            if (!primaryCompleter.isCompleted) {
              primaryCompleter.completeError(cancellationError);
            }
            yield ActivationProgress.error(
              message: cancellation.reason,
              errorCode: 'ACTIVATION_CANCELLED',
            );
            break;
          }

          var progress = _attachSdkError(rawProgress, group.primary.id);
          if (progress.isComplete &&
              progress.isSuccess &&
              shouldRefreshTronGaslessActivation) {
            progress = await _verifyGaslessCapability(
              group,
              progress,
              gaslessContext!,
            );
          }

          // Complete the join completer BEFORE yielding the terminal progress.
          // The coordinator breaks out of its `await for` as soon as it
          // receives a terminal progress, which cancels this async* generator
          // at the `yield` suspension point below. Concurrent activations that
          // joined this batch await `primaryCompleter.future` (for example, a
          // standalone platform activation racing a `[platform, token]` group);
          // completing
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
            await _handleActivationComplete(
              group,
              progress,
              primaryCompleter,
              gaslessContext: gaslessContext,
            );
          }
        }

        // The strategy can finish WITHOUT emitting a terminal completion event
        // when the platform and all requested children are already active (the
        // individual-children path skips already-active children and yields
        // nothing). Without a terminal event the coordinator's Future
        // (shared_activation_coordinator) would await forever. Emit a
        // synthetic completion (or failure) so it always resolves.
        if (!completionHandled &&
            _cancellationFor(group.primary.id, registration) == null) {
          final status = await _checkActivationStatus(
            group,
            forceRefresh: true,
          );
          completionHandled = true;
          if (status.isComplete) {
            final verified = shouldRefreshTronGaslessActivation
                ? await _verifyGaslessCapability(group, status, gaslessContext!)
                : status;
            await _handleActivationComplete(
              group,
              verified,
              primaryCompleter,
              gaslessContext: gaslessContext,
            );
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
          await _cleanupActivation(group.primary.id, registration);
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

  _ActivationCancellation? _currentCancellation(AssetId assetId) {
    final cancellation = _cancelledActivations[assetId];
    if (cancellation == null ||
        cancellation.sessionGeneration != _activationSessionGeneration ||
        !identical(_activationCompleters[assetId], cancellation.completer)) {
      return null;
    }
    return cancellation;
  }

  _ActivationCancellation? _cancellationFor(
    AssetId assetId,
    _ActivationRegistration registration,
  ) {
    final cancellation = _cancelledActivations[assetId];
    if (cancellation == null ||
        cancellation.sessionGeneration != registration.sessionGeneration ||
        !identical(cancellation.completer, registration.completer)) {
      return null;
    }
    return cancellation;
  }

  /// Register a new activation attempt or join an existing one.
  Future<_ActivationRegistration> _registerActivation(
    AssetId assetId,
    int expectedSessionGeneration,
  ) async {
    return _protectedOperation(() async {
      if (expectedSessionGeneration != _activationSessionGeneration) {
        throw const WalletChangedDisconnectException(
          'Wallet changed during asset activation',
        );
      }

      final existingCompleter = _activationCompleters[assetId];
      if (existingCompleter != null) {
        return _ActivationRegistration(
          completer: existingCompleter,
          sessionGeneration: expectedSessionGeneration,
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
        sessionGeneration: expectedSessionGeneration,
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
    Completer<void> completer, {
    _GaslessActivationContext? gaslessContext,
  }) async {
    if (progress.isSuccess) {
      if (gaslessContext != null) {
        await _requireGaslessContextCurrent(gaslessContext);
      }
      final user = await _auth.currentUser;
      if (gaslessContext != null) {
        await _requireGaslessContextCurrent(gaslessContext);
      }
      if (user != null) {
        // Store custom tokens using CoinConfigManager
        if (group.primary.protocol.isCustomToken) {
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
          await _assetsUpdateManager.assets.storeCustomToken(group.primary);
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
        } else {
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
          await _assetHistory.addAssetToWallet(
            user.walletId,
            group.primary.id.id,
          );
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
        }

        final allAssets = [group.primary, ...group.children];

        for (final asset in allAssets) {
          if (asset.protocol.isCustomToken) {
            if (gaslessContext != null) {
              await _requireGaslessContextCurrent(gaslessContext);
            }
            await _assetsUpdateManager.assets.storeCustomToken(asset);
            if (gaslessContext != null) {
              await _requireGaslessContextCurrent(gaslessContext);
            }
          }

          // Pre-cache balance for the activated asset
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
          await _balanceManager.precacheBalance(asset);
          if (gaslessContext != null) {
            await _requireGaslessContextCurrent(gaslessContext);
          }
        }

        if (gaslessContext != null) {
          await _requireGaslessContextCurrent(gaslessContext);
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
    final provider = _tronGaslessProvider;
    if (provider == null) return null;
    // Provider configuration is activation-scoped on the TRX platform. Attach
    // it even when TRX is activated before any enrolled token; KDF has no
    // supported runtime mutation RPC for an already-active platform.
    if (group.primary.protocol is TrxProtocol) return provider;
    return _gaslessAssets(group).isEmpty ? null : provider;
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
    _GaslessActivationContext context,
  ) async {
    try {
      await _requireGaslessContextCurrent(context);
      final assets = _gaslessAssets(group).toList();
      if (assets.isEmpty) return success;
      final softwareWallet =
          context.walletId.authOptions.privKeyPolicy ==
          const PrivateKeyPolicy.contextPrivKey();
      if (!softwareWallet) {
        throw StateError('GasFree requires a primary software wallet');
      }
      if (_tronGaslessProvider == null) {
        throw StateError('GasFree provider configuration is unavailable');
      }
      for (final asset in assets) {
        final requestedPath = asset.id.derivationPath;
        final walletType =
            switch (context.walletId.authOptions.derivationMethod) {
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
          _gaslessCapabilities.markSecurityMismatch(asset.id);
          continue;
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
        final walletPubkeyHash = context.walletId.pubkeyHash;
        if (contractAddress == null || walletPubkeyHash == null) {
          _gaslessCapabilities.markSecurityMismatch(asset.id);
          continue;
        }
        final activatedIdentity = GaslessCapabilityIdentity(
          assetId: asset.id,
          platform: protocol.platform,
          contractAddress: contractAddress,
          providerAddress: _tronGaslessProvider.serviceProvider?.trim() ?? '',
          walletPubkeyHash: walletPubkeyHash,
          walletType: walletType,
          derivationPath: capabilityPath,
        );
        if (!_gaslessCapabilities.bindActivatedIdentity(
          asset,
          activatedIdentity,
        )) {
          continue;
        }
        final statusEpoch = _gaslessCapabilities.beginAccountStatusProbe(
          asset.id,
        );
        _gaslessCapabilities.markChecking(asset.id);
        try {
          final status = await _client.rpc.withdraw.gaslessAccountStatus(
            coin: asset.id.id,
          );
          await _requireGaslessContextCurrent(context);
          if (!_gaslessCapabilities.isCurrentAccountStatusProbe(
            asset.id,
            statusEpoch,
          )) {
            continue;
          }
          _gaslessCapabilities.refreshAccountStatus(asset, status);
        } catch (error) {
          await _requireGaslessContextCurrent(context);
          if (!_gaslessCapabilities.isCurrentAccountStatusProbe(
            asset.id,
            statusEpoch,
          )) {
            continue;
          }
          if (!_gaslessCapabilities.markAccountStatusError(asset.id, error)) {
            _gaslessCapabilities.markUnconfirmed(asset.id);
          }
        }
      }
      return success;
    } catch (error, stackTrace) {
      Object effectiveError = error;
      try {
        await _requireGaslessContextCurrent(context);
      } on WalletChangedDisconnectException catch (walletError) {
        effectiveError = walletError;
      }
      if (effectiveError is WalletChangedDisconnectException) {
        final mappedError = _mapError(effectiveError, group.primary.id);
        return ActivationProgress.error(
          message: mappedError.fallbackMessage,
          sdkError: mappedError,
          stackTrace: stackTrace,
        );
      }
      for (final asset in _gaslessAssets(group)) {
        if (_gaslessCapabilities.markAccountStatusError(asset.id, error)) {
          continue;
        } else {
          _gaslessCapabilities.markUnconfirmed(asset.id);
        }
      }
      // GasFree readiness is an optional rail layered on a successful KDF
      // activation. The typed account status and capability state gate the
      // optional rail while Standard TRON remains usable.
      return success;
    }
  }

  /// Cleanup after activation attempt
  Future<void> _cleanupActivation(
    AssetId assetId,
    _ActivationRegistration registration,
  ) async {
    await _protectedOperation(() async {
      if (registration.sessionGeneration != _activationSessionGeneration ||
          !identical(_activationCompleters[assetId], registration.completer)) {
        return;
      }
      _activationCompleters.remove(assetId);
      final cancellation = _cancelledActivations[assetId];
      if (cancellation == null ||
          identical(cancellation.completer, registration.completer)) {
        _cancelledActivations.remove(assetId);
      }
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

class _GaslessActivationContext {
  const _GaslessActivationContext({
    required this.walletId,
    required this.sessionGeneration,
  });

  final WalletId walletId;
  final int sessionGeneration;
}

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
    required this.sessionGeneration,
    required this.shouldStartActivation,
  });

  final Completer<void> completer;
  final int sessionGeneration;
  final bool shouldStartActivation;
}

class _ActivationCancellation {
  const _ActivationCancellation({
    required this.completer,
    required this.sessionGeneration,
    required this.reason,
  });

  final Completer<void> completer;
  final int sessionGeneration;
  final String reason;
}
