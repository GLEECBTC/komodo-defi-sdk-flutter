import 'dart:async';
import 'dart:developer' show log;

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Shared coordinator for asset activations across all managers.
/// Prevents race conditions by ensuring only one activation per asset at a time
/// and sharing the result with all requesting managers.
///
/// **CRITICAL TIMING ISSUE HANDLING:**
/// This coordinator addresses a race condition where activation RPC can complete
/// successfully, but the coin may not immediately appear in the enabled coins list.
/// This can cause subsequent operations (balance fetching, address generation) to
/// fail with "No such coin" errors. The coordinator waits for coin availability
/// verification before declaring activation successful.
class SharedActivationCoordinator {
  SharedActivationCoordinator(this._activationManager, this._auth) {
    // Listen for auth state changes
    _authSubscription = _auth.authStateChanges.listen(_handleAuthStateChanged);
  }

  final ActivationManager _activationManager;
  final KomodoDefiLocalAuth _auth;
  StreamSubscription<KdfUser?>? _authSubscription;

  /// Track pending activations to prevent duplicates
  final Map<AssetId, Completer<ActivationResult>> _pendingActivations = {};

  /// Current wallet ID being tracked
  WalletId? _currentWalletId;

  bool _isDisposed = false;

  /// Handle authentication state changes
  Future<void> _handleAuthStateChanged(KdfUser? user) async {
    if (_isDisposed) return;
    final newWalletId = user?.walletId;
    // If the wallet ID has changed, reset all state
    if (_currentWalletId != newWalletId) {
      await _resetState();
      _activationManager.resetActivationSessionState();
      _currentWalletId = newWalletId;
    }
  }

  /// Reset all internal state when wallet changes
  Future<void> _resetState() async {
    log(
      'Resetting SharedActivationCoordinator state due to wallet change',
      name: 'SharedActivationCoordinator',
    );

    // Cancel all pending activations
    for (final completer in _pendingActivations.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Wallet changed, activation cancelled'),
        );
      }
    }
    _pendingActivations.clear();
  }

  /// Activate an asset with coordination across all managers.
  /// Returns a Future that completes when activation is finished.
  /// Multiple concurrent calls for the same asset will share the same result.
  Future<ActivationResult> activateAsset(Asset asset) async {
    if (_isDisposed) {
      throw StateError('SharedActivationCoordinator has been disposed');
    }

    // Check if activation is already in progress
    final existingActivation = _pendingActivations[asset.id];
    if (existingActivation != null) {
      log(
        'Joining existing activation for ${asset.id.id}',
        name: 'SharedActivationCoordinator',
      );
      return existingActivation.future;
    }

    final shouldRefreshTronGaslessActivation = _activationManager
        .shouldRefreshTronGaslessActivation(asset);

    // Check if asset is already active
    final isActive = await _activationManager.isAssetActive(asset.id);
    if (isActive && !shouldRefreshTronGaslessActivation) {
      return ActivationResult.success(asset.id);
    }

    final completer = Completer<ActivationResult>();
    _pendingActivations[asset.id] = completer;

    // Clear any previous failed status for this asset

    // Broadcast that this asset is now pending
    try {
      // Subscribe to activation stream and wait for completion
      await for (final progress in _activationManager.activateAsset(asset)) {
        if (progress.isComplete) {
          if (progress.isSuccess) {
            // Wait for coin to actually become available before declaring success
            try {
              await _waitForCoinAvailability(asset.id);
              final result = ActivationResult.success(asset.id);
              if (!completer.isCompleted) {
                completer.complete(result);
              }
            } catch (e) {
              _activationManager.recordActivationFailure(
                asset.id,
                'Activation completed but the coin did not become available',
              );
              final result = ActivationResult.failure(
                asset.id,
                'Activation completed but coin did not become available: $e',
              );
              if (!completer.isCompleted) {
                completer.complete(result);
              }
            }
          } else {
            final result = ActivationResult.failure(
              asset.id,
              progress.errorMessage ?? 'Unknown activation error',
            );
            if (!completer.isCompleted) {
              completer.complete(result);
            }
          }
          break;
        }
      }
    } catch (e, stackTrace) {
      if (!completer.isCompleted) {
        log(
          'Activation failed for ${asset.id.id}: $e',
          name: 'SharedActivationCoordinator',
          error: e,
          stackTrace: stackTrace,
        );
        completer.complete(ActivationResult.failure(asset.id, e.toString()));
      }
    } finally {
      // The `await for` above only completes the completer when it sees a
      // terminal `progress.isComplete`. A progress stream that ends without one
      // - an activation strategy returning early, a controller closed by a
      // session reset, an empty stream - falls straight through to here with
      // the completer still pending, and `completer.future` below then never
      // resolves.
      //
      // That future is awaited by every caller of this coordinator:
      // `BalanceManager._ensureAssetActivated` (so the balance watcher never
      // starts) and the wallet's login fan-out via `ensureAssetActivated` (so
      // `Future.wait` over the whole batch never returns, the coin holds
      // `activating` forever, and the app's post-login bookkeeping never runs).
      // Anyone who joined through `_pendingActivations` hangs with it.
      //
      // Fail closed instead: a failure is recoverable - the caller retries, and
      // the app's reconcile pass corrects the row if KDF did activate it after
      // all - whereas a pending future is not.
      if (!completer.isCompleted) {
        log(
          'Activation stream for ${asset.id.id} ended without a terminal '
          'progress event; failing the activation rather than hanging',
          name: 'SharedActivationCoordinator',
        );
        _activationManager.recordActivationFailure(
          asset.id,
          'Activation stream ended without a terminal progress event',
        );
        completer.complete(
          ActivationResult.failure(
            asset.id,
            'Activation stream ended without a terminal progress event',
          ),
        );
      }
      _pendingActivations.remove(asset.id);
    }

    return completer.future;
  }

  /// Check if an asset is active (delegated to ActivationManager)
  Future<bool> isAssetActive(AssetId assetId) {
    return _activationManager.isAssetActive(assetId);
  }

  /// Current activation state of every asset the SDK has observed.
  Map<AssetId, AssetActivationState> get activationStates =>
      _activationManager.activationStates;

  /// Current activation states, then every subsequent change.
  ///
  /// See [ActivationManager.watchActivationStates].
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() =>
      _activationManager.watchActivationStates();

  /// Current state for [assetId], then every subsequent change to it.
  Stream<AssetActivationState?> watchActivationStateOf(AssetId assetId) =>
      _activationManager.watchActivationStateOf(assetId);

  /// Wait for a coin to become available after activation completes.
  /// This addresses the timing issue where activation RPC completes successfully
  /// but the coin needs a few milliseconds to appear in the enabled coins list.
  Future<void> _waitForCoinAvailability(AssetId assetId) async {
    const maxRetries = 15; // Up to ~3 seconds with exponential backoff
    const baseDelay = Duration(milliseconds: 50);
    const maxDelay = Duration(milliseconds: 500);

    log(
      'Waiting for coin ${assetId.id} to become available after activation',
      name: 'SharedActivationCoordinator',
    );

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Force refresh to bypass cache and get fresh data from backend
        final isAvailable = await _activationManager.isAssetActive(
          assetId,
          forceRefresh: true,
        );
        if (isAvailable) {
          log(
            'Coin ${assetId.id} became available after ${attempt + 1} attempts',
            name: 'SharedActivationCoordinator',
          );
          return;
        }
      } catch (e) {
        log(
          'Error checking coin availability (attempt ${attempt + 1}): $e',
          name: 'SharedActivationCoordinator',
        );
      }

      if (attempt < maxRetries - 1) {
        // Exponential backoff with max cap
        final delayMs = (baseDelay.inMilliseconds * (1 << attempt)).clamp(
          baseDelay.inMilliseconds,
          maxDelay.inMilliseconds,
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    throw StateError(
      'Coin ${assetId.id} did not become available after activation '
      '(waited $maxRetries attempts)',
    );
  }

  /// Dispose of the coordinator and clean up resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    log(
      'Disposing SharedActivationCoordinator',
      name: 'SharedActivationCoordinator',
    );

    // Cancel auth subscription
    await _authSubscription?.cancel();
    _authSubscription = null;

    // Cancel all pending activations
    for (final completer in _pendingActivations.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('SharedActivationCoordinator disposed'),
        );
      }
    }
    _pendingActivations.clear();

    // Close all active streams
    // Close state tracking streams

    // Clear state tracking sets
  }
}

/// Result of an asset activation operation
class ActivationResult {
  const ActivationResult._(this.assetId, this.isSuccess, this.errorMessage);

  factory ActivationResult.success(AssetId assetId) {
    return ActivationResult._(assetId, true, null);
  }

  factory ActivationResult.failure(AssetId assetId, String errorMessage) {
    return ActivationResult._(assetId, false, errorMessage);
  }

  final AssetId assetId;
  final bool isSuccess;
  final String? errorMessage;

  bool get isFailure => !isSuccess;

  @override
  String toString() {
    return isSuccess
        ? 'ActivationResult.success(${assetId.id})'
        : 'ActivationResult.failure(${assetId.id}, $errorMessage)';
  }
}
