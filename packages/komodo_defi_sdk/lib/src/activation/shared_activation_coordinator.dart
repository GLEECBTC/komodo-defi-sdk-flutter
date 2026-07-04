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

  /// Track active activation streams for joining
  final Map<AssetId, StreamController<ActivationProgress>> _activeStreams = {};

  /// Track failed activations
  final Set<AssetId> _failedActivations = <AssetId>{};

  /// Stream controller for broadcasting failed activations changes
  final StreamController<Set<AssetId>> _failedActivationsController =
      StreamController<Set<AssetId>>.broadcast();

  /// Stream controller for broadcasting pending activations changes
  final StreamController<Set<AssetId>> _pendingActivationsController =
      StreamController<Set<AssetId>>.broadcast();

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

    // Close all active streams
    for (final controller in _activeStreams.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _activeStreams.clear();

    // Clear failed activations
    _failedActivations.clear();

    // Notify stream watchers of state changes
    _broadcastPendingActivations();
    _broadcastFailedActivations();
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
    if (_failedActivations.remove(asset.id)) {
      _broadcastFailedActivations();
    }

    // Broadcast that this asset is now pending
    _broadcastPendingActivations();

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
              _failedActivations.add(asset.id);
              _broadcastFailedActivations();
              final result = ActivationResult.failure(
                asset.id,
                'Activation completed but coin did not become available: $e',
              );
              if (!completer.isCompleted) {
                completer.complete(result);
              }
            }
          } else {
            _failedActivations.add(asset.id);
            _broadcastFailedActivations();
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
        _failedActivations.add(asset.id);
        _broadcastFailedActivations();
        log(
          'Activation failed for ${asset.id.id}: $e',
          name: 'SharedActivationCoordinator',
          error: e,
          stackTrace: stackTrace,
        );
        completer.complete(ActivationResult.failure(asset.id, e.toString()));
      }
    } finally {
      _pendingActivations.remove(asset.id);
      _broadcastPendingActivations();
    }

    return completer.future;
  }

  /// Get activation progress stream for an asset.
  /// Multiple subscribers will share the same stream.
  Stream<ActivationProgress> activateAssetStream(Asset asset) {
    if (_isDisposed) {
      throw StateError('SharedActivationCoordinator has been disposed');
    }

    // Check if there's already an active stream for this asset
    var controller = _activeStreams[asset.id];
    if (controller != null && !controller.isClosed) {
      log(
        'Joining existing activation stream for ${asset.id.id}',
        name: 'SharedActivationCoordinator',
      );
      return controller.stream;
    }

    // Create new broadcast controller
    controller = StreamController<ActivationProgress>.broadcast(
      onCancel: () {
        // Clean up when all listeners cancel
        if (controller?.hasListener == false) {
          _activeStreams.remove(asset.id);
          controller?.close();
        }
      },
    );
    _activeStreams[asset.id] = controller;

    // Start activation and forward progress to subscribers
    _activationManager
        .activateAsset(asset)
        .listen(
          (progress) {
            final currentController = _activeStreams[asset.id];
            if (currentController != null && !currentController.isClosed) {
              currentController.add(progress);
            }

            // Clean up when activation completes
            if (progress.isComplete) {
              // For stream-based activation, we don't wait for coin availability
              // as subscribers may want to handle this themselves
              Timer.run(() {
                final controllerToClose = _activeStreams.remove(asset.id);
                if (controllerToClose != null && !controllerToClose.isClosed) {
                  controllerToClose.close();
                }
              });
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            final currentController = _activeStreams[asset.id];
            if (currentController != null && !currentController.isClosed) {
              currentController.addError(error, stackTrace);
              _activeStreams.remove(asset.id);
              currentController.close();
            }
          },
          onDone: () {
            final controllerToClose = _activeStreams.remove(asset.id);
            if (controllerToClose != null && !controllerToClose.isClosed) {
              controllerToClose.close();
            }
          },
        );

    return controller.stream;
  }

  /// Check if an asset is currently being activated
  bool isActivationInProgress(AssetId assetId) {
    return _pendingActivations.containsKey(assetId) ||
        _activeStreams.containsKey(assetId);
  }

  /// Check if an asset is active (delegated to ActivationManager)
  Future<bool> isAssetActive(AssetId assetId) {
    return _activationManager.isAssetActive(assetId);
  }

  /// Watch failed activations.
  /// Returns a stream that emits the current set of failed asset IDs
  /// whenever it changes.
  Stream<Set<AssetId>> watchFailedActivations() {
    if (_isDisposed) {
      throw StateError('SharedActivationCoordinator has been disposed');
    }
    return _failedActivationsController.stream;
  }

  /// Watch pending activations.
  /// Returns a stream that emits the current set of pending asset IDs
  /// whenever it changes.
  Stream<Set<AssetId>> watchPendingActivations() {
    if (_isDisposed) {
      throw StateError('SharedActivationCoordinator has been disposed');
    }
    return _pendingActivationsController.stream;
  }

  /// Get current set of failed activations
  Set<AssetId> get failedActivations => Set<AssetId>.from(_failedActivations);

  /// Get current set of pending activations
  Set<AssetId> get pendingActivations => _pendingActivations.keys.toSet();

  /// Clear failed activation status for an asset
  void clearFailedActivation(AssetId assetId) {
    if (_failedActivations.remove(assetId)) {
      _broadcastFailedActivations();
    }
  }

  /// Clear all failed activations
  void clearAllFailedActivations() {
    if (_failedActivations.isNotEmpty) {
      _failedActivations.clear();
      _broadcastFailedActivations();
    }
  }

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

  /// Broadcast current failed activations to stream listeners
  void _broadcastFailedActivations() {
    if (!_failedActivationsController.isClosed) {
      _failedActivationsController.add(Set<AssetId>.from(_failedActivations));
    }
  }

  /// Broadcast current pending activations to stream listeners
  void _broadcastPendingActivations() {
    if (!_pendingActivationsController.isClosed) {
      _pendingActivationsController.add(_pendingActivations.keys.toSet());
    }
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
    for (final controller in _activeStreams.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _activeStreams.clear();

    // Close state tracking streams
    if (!_failedActivationsController.isClosed) {
      _failedActivationsController.close();
    }
    if (!_pendingActivationsController.isClosed) {
      _pendingActivationsController.close();
    }

    // Clear state tracking sets
    _failedActivations.clear();
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
