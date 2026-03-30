import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
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
    this._activatedAssetsCache,
  );

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final AssetHistoryStorage _assetHistory;
  final IAssetLookup _assetLookup;
  final IBalanceManager _balanceManager;
  final ActivationConfigService _configService;
  final KomodoAssetsUpdateManager _assetsUpdateManager;
  final ActivatedAssetsCache _activatedAssetsCache;
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
  Stream<ActivationProgress> activateAsset(Asset asset) =>
      activateAssets([asset]);

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

    final groups = _AssetGroup._groupByPrimary(assets);

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

      // Check activation status atomically
      final activationStatus = await _checkActivationStatus(group);
      if (activationStatus.isComplete) {
        yield activationStatus;
        continue;
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
          yield ActivationProgress.alreadyActiveSuccess(
            assetName: group.primary.id.name,
            childCount: group.children?.length ?? 0,
          );
        } catch (e, st) {
          final mappedError = _mapError(e, group.primary.id);
          yield ActivationProgress.error(
            message: mappedError.fallbackMessage,
            sdkError: mappedError,
            stackTrace: st,
          );
        }
        continue;
      }

      final parentAsset = group.parentId == null
          ? null
          : _assetLookup.fromId(group.parentId!) ??
                (throw StateError('Parent asset ${group.parentId} not found'));

      yield ActivationProgress(
        status: 'Starting activation for ${group.primary.id.name}...',
        progressDetails: ActivationProgressDetails(
          currentStep: ActivationStep.groupStart,
          stepCount: 1,
          additionalInfo: {
            'primaryAsset': group.primary.id.name,
            'childCount': group.children?.length ?? 0,
          },
        ),
      );

      try {
        // Get the current user's auth options to retrieve privKeyPolicy
        final currentUser = await _auth.currentUser;
        final privKeyPolicy =
            currentUser?.walletId.authOptions.privKeyPolicy ??
            const PrivateKeyPolicy.contextPrivKey();

        // Create activator with the user's privKeyPolicy
        final activator = ActivationStrategyFactory.createStrategy(
          _client,
          privKeyPolicy,
          _configService,
          _activatedAssetsCache,
        );

        var completionHandled = false;
        await for (final progress in activator.activate(
          parentAsset ?? group.primary,
          group.children?.toList(),
        )) {
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

          yield _attachSdkError(progress, group.primary.id);

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
      } catch (e, st) {
        final recoveredProgress = await _tryRecoverAlreadyActivated(group, e);
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
      final childrenActive =
          group.children?.every(
            (child) => enabledAssetIds.contains(child.id),
          ) ??
          true;

      if (isActive && childrenActive) {
        return ActivationProgress.alreadyActiveSuccess(
          assetName: group.primary.id.name,
          childCount: group.children?.length ?? 0,
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

        final allAssets = [group.primary, ...(group.children?.toList() ?? [])];

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

/// Internal class for grouping related assets
class _AssetGroup {
  _AssetGroup({required this.primary, this.children})
    : assert(
        children == null ||
            children.every((asset) => asset.id.parentId == primary.id),
        'All child assets must have the parent asset as their parent',
      );

  final Asset primary;
  final Set<Asset>? children;

  AssetId? get parentId =>
      children?.firstWhereOrNull((asset) => asset.id.isChildAsset)?.id.parentId;

  static List<_AssetGroup> _groupByPrimary(List<Asset> assets) {
    final groups = <AssetId, _AssetGroup>{};

    for (final asset in assets) {
      if (asset.id.parentId != null) {
        // Child asset
        final group = groups.putIfAbsent(
          asset.id.parentId!,
          () => _AssetGroup(primary: asset, children: {}),
        );
        group.children?.add(asset);
      } else {
        // Primary asset
        groups.putIfAbsent(asset.id, () => _AssetGroup(primary: asset));
      }
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
