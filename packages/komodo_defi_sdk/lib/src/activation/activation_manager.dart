import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
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

  final Map<AssetId, Completer<void>> _activationCompleters = {};
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

  /// Activate multiple assets
  Stream<ActivationProgress> activateAssets(List<Asset> assets) async* {
    if (_isDisposed) {
      throw StateError('ActivationManager has been disposed');
    }

    final groups = _AssetGroup._groupByPrimary(assets);

    for (final group in groups) {
      // Check activation status atomically
      final activationStatus = await _checkActivationStatus(group);
      if (activationStatus.isComplete) {
        yield activationStatus;
        continue;
      }

      // Register activation attempt; if one is already in progress, join it
      final primaryCompleter = await _registerActivation(group.primary.id);
      if (primaryCompleter == null) {
        debugPrint(
          'Activation already in progress for ${group.primary.id.name} (joining)',
        );
        // Join the existing activation and emit a synthetic completion when done
        final existing = _activationCompleters[group.primary.id];
        if (existing != null) {
          yield ActivationProgress(
            status: 'Joining existing activation for ${group.primary.id.name}...',
            progressDetails: const ActivationProgressDetails(
              currentStep: ActivationStep.initialization,
              stepCount: 1,
            ),
          );
          try {
            await existing.future;
            yield ActivationProgress.alreadyActiveSuccess(
              assetName: group.primary.id.name,
              childCount: group.children?.length ?? 0,
            );
          } catch (e) {
            yield ActivationProgress.error(message: e.toString());
          }
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

        await for (final progress in activator.activate(
          parentAsset ?? group.primary,
          group.children?.toList(),
        )) {
          yield progress;

          if (progress.isComplete) {
            await _handleActivationComplete(group, progress, primaryCompleter);
          }
        }
      } catch (e) {
        debugPrint('Activation failed: $e');
        if (!primaryCompleter.isCompleted) {
          primaryCompleter.completeError(e);
        }
        rethrow;
      } finally {
        try {
          await _cleanupActivation(group.primary.id);
        } catch (e) {
          debugPrint('Failed to cleanup activation: $e');
        }
      }
    }
  }

  /// Check if asset and its children are already activated
  Future<ActivationProgress> _checkActivationStatus(_AssetGroup group) async {
    try {
      // Use cache instead of direct RPC call to avoid excessive requests
      final enabledAssetIds = await _activatedAssetsCache.getActivatedAssetIds();

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

  /// Register new activation attempt
  Future<Completer<void>?> _registerActivation(AssetId assetId) async {
    return _protectedOperation(() async {
      // If activation is already in progress for this asset, signal caller to join
      if (_activationCompleters.containsKey(assetId)) {
        return null;
      }

      final completer = Completer<void>();
      _activationCompleters[assetId] = completer;
      return completer;
    });
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
