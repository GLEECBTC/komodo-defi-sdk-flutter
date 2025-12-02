import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Interface defining the contract for balance management operations
abstract class IBalanceManager {
  /// Gets the current balance for an asset.
  /// Will ensure the asset is activated before querying.
  ///
  /// Note: If the asset was recently activated through [ActivationManager],
  /// the balance will typically be pre-cached and return immediately. However,
  /// this should not be relied upon as a way to check activation status.
  ///
  /// Throws [AuthException] if user is not signed in.
  /// Throws [ArgumentError] if asset is not found.
  /// May throw [TimeoutException] if balance fetch times out.
  Future<BalanceInfo> getBalance(AssetId assetId);

  /// Gets a stream of balance updates for an asset.
  /// The stream will emit the current balance immediately if available,
  /// and then emit updates whenever the balance changes.
  ///
  /// If [activateIfNeeded] is false, will not trigger activation but will
  /// wait for the asset to be activated externally.
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  });

  /// Gets the last known balance for an asset without triggering a refresh.
  /// Returns null if no balance has been fetched yet.
  BalanceInfo? lastKnown(AssetId assetId);

  /// Disposes of all resources and stops all balance watching
  Future<void> dispose();

  /// Pre-caches the balance for an asset.
  /// This is an internal method used during activation to optimize initial balance fetches.
  Future<void> precacheBalance(Asset asset);
}

/// Implementation of the [IBalanceManager] interface for managing asset balances.
///
/// This class provides balance management operations with efficient caching
/// and update mechanisms using appropriate balance strategies based on asset type.
class BalanceManager implements IBalanceManager {
  /// Creates a new instance of [BalanceManager].
  ///
  /// Requires an [IAssetLookup] to find asset information and [KomodoDefiLocalAuth] for auth.
  /// The [activationCoordinator] and [pubkeyManager] can be initialized as null and set later
  /// to break circular dependencies.
  BalanceManager({
    required IAssetLookup assetLookup,
    required KomodoDefiLocalAuth auth,
    required PubkeyManager? pubkeyManager,
    required SharedActivationCoordinator? activationCoordinator,
    required EventStreamingManager eventStreamingManager,
    AssetHistoryStorage? assetHistoryStorage,
  }) : _activationCoordinator = activationCoordinator,
       _pubkeyManager = pubkeyManager,
       _assetLookup = assetLookup,
       _auth = auth,
       _eventStreamingManager = eventStreamingManager,
       _assetHistoryStorage = assetHistoryStorage ?? AssetHistoryStorage() {
    // Listen for auth state changes
    _authSubscription = _auth.authStateChanges.listen(_handleAuthStateChanged);
    _logger.fine('Initialized');
  }
  static final Logger _logger = Logger('BalanceManager');

  SharedActivationCoordinator? _activationCoordinator;
  PubkeyManager? _pubkeyManager;
  final IAssetLookup _assetLookup;
  final KomodoDefiLocalAuth _auth;
  final EventStreamingManager _eventStreamingManager;
  final AssetHistoryStorage _assetHistoryStorage;
  StreamSubscription<KdfUser?>? _authSubscription;
  final Duration _defaultPollingInterval = const Duration(seconds: 30);

  /// Enable debug logging for balance polling fallback
  static bool enableDebugLogging = true;

  /// Cache of the latest known balances for each asset
  final Map<AssetId, BalanceInfo> _balanceCache = {};

  /// Track active balance watch streams by asset ID
  final Map<AssetId, StreamSubscription<dynamic>> _activeWatchers = {};
  final Map<AssetId, StreamSubscription<AssetPubkeys>> _pubkeyHintWatchers = {};
  final Set<AssetId> _pendingFastRefresh = <AssetId>{};

  /// Stream controllers for each asset being watched
  final Map<AssetId, StreamController<BalanceInfo>> _balanceControllers = {};

  /// Stale-guard timers to periodically refresh balances even while streaming
  final Map<AssetId, Timer> _staleBalanceTimers = {};

  /// Current wallet ID being tracked
  WalletId? _currentWalletId;

  /// Flag indicating if the manager has been disposed
  bool _isDisposed = false;

  /// Getter for activationCoordinator to make it accessible
  SharedActivationCoordinator? get activationCoordinator =>
      _activationCoordinator;

  /// Getter for pubkeyManager to make it accessible
  PubkeyManager? get pubkeyManager => _pubkeyManager;

  /// Setter for activationCoordinator to resolve circular dependencies
  void setActivationCoordinator(SharedActivationCoordinator coordinator) {
    _activationCoordinator = coordinator;
  }

  /// Setter for pubkeyManager to resolve circular dependencies
  void setPubkeyManager(PubkeyManager manager) {
    _pubkeyManager = manager;
  }

  bool _supportsBalanceStreaming(Asset asset) => asset.supportsBalanceStreaming;

  /// Handle authentication state changes
  Future<void> _handleAuthStateChanged(KdfUser? user) async {
    if (_isDisposed) return;
    final newWalletId = user?.walletId;
    // If the wallet ID has changed, reset all state
    _logger.fine(
      'Auth state changed. wallet: $_currentWalletId -> $newWalletId',
    );
    if (_currentWalletId != newWalletId) {
      await _resetState();
      _currentWalletId = newWalletId;
    }
  }

  /// Reset all internal state when wallet changes
  Future<void> _resetState() async {
    _logger.fine('Resetting state');
    final stopwatch = Stopwatch()..start();

    final List<Future<void>> cleanupFutures = <Future<void>>[];
    final List<StreamSubscription<dynamic>> watcherSubs = _activeWatchers.values
        .toList();
    _activeWatchers.clear();

    for (final subscription in watcherSubs) {
      cleanupFutures.add(
        subscription.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling balance watcher', e, s);
        }),
      );
    }

    // Cancel all stale balance timers to prevent timer leak on wallet change
    for (final timer in _staleBalanceTimers.values) {
      timer.cancel();
    }
    _staleBalanceTimers.clear();

    final List<StreamController<BalanceInfo>> controllers = _balanceControllers
        .values
        .toList();
    _balanceControllers.clear();

    for (final controller in controllers) {
      if (!controller.isClosed) {
        // Add error to signal disconnection before closing
        controller.addError(
          const WalletChangedDisconnectException(
            'Wallet changed, reconnecting balance watchers',
          ),
        );

        cleanupFutures.add(
          controller.close().catchError((Object e, StackTrace s) {
            _logger.warning('Error closing balance controller', e, s);
          }),
        );
      }
    }

    if (cleanupFutures.isNotEmpty) {
      await Future.wait(cleanupFutures);
    }

    _balanceCache.clear();
    stopwatch.stop();
    _logger.fine(
      'State reset completed in ${stopwatch.elapsedMilliseconds}ms '
      '(${watcherSubs.length} subscriptions, ${controllers.length} controllers)',
    );
  }

  @override
  Future<BalanceInfo> getBalance(AssetId assetId) async {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }

    // Check if dependencies are properly initialized
    if (_pubkeyManager == null) {
      throw StateError('PubkeyManager is not initialized');
    }

    // Check if user is authenticated
    final user = await _auth.currentUser;
    if (user == null) {
      throw AuthException.notSignedIn();
    }

    final asset = _assetLookup.fromId(assetId);
    if (asset == null) {
      throw ArgumentError('Asset not found for balance check: $assetId');
    }

    try {
      final balance = await _pubkeyManager!
          .getPubkeys(asset)
          .then((pubkeys) => pubkeys.balance);
      // Update cache with the latest balance
      _balanceCache[assetId] = balance;
      return balance;
    } catch (e) {
      // Rethrow with more context
      throw StateError('Failed to get balance for ${assetId.name}: $e');
    }
  }

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  }) async* {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }

    final lastKnownBalance = lastKnown(assetId);
    if (lastKnownBalance != null) {
      yield lastKnownBalance;
    }

    final controller = _balanceControllers.putIfAbsent(
      assetId,
      () => StreamController<BalanceInfo>.broadcast(
        onListen: () {
          _logger.fine(
            'onListen: ${assetId.name}, activateIfNeeded: $activateIfNeeded',
          );
          _startWatchingBalance(assetId, activateIfNeeded);
        },
        onCancel: () {
          _logger.fine('onCancel: ${assetId.name}');
          _stopWatchingBalance(assetId);
        },
      ),
    );

    yield* controller.stream;
  }

  /// Ensures an asset is activated using the shared activation coordinator
  Future<bool> _ensureAssetActivated(Asset asset, bool activateIfNeeded) async {
    // Check if activationCoordinator is initialized
    if (_activationCoordinator == null) {
      _logger.fine(
        'SharedActivationCoordinator not initialized, cannot activate asset',
      );
      return false;
    }

    if (!activateIfNeeded) {
      return _activationCoordinator!.isAssetActive(asset.id);
    }

    final isActive = await _activationCoordinator!.isAssetActive(asset.id);
    if (isActive) {
      return true;
    }

    try {
      // Use the shared coordinator to activate the asset
      final result = await _activationCoordinator!.activateAsset(asset);
      return result.isSuccess;
    } catch (e) {
      _logger.fine('Failed to activate asset ${asset.id.name}: $e');
      return false;
    }
  }

  /// Start watching the balance for a specific asset
  Future<void> _startWatchingBalance(
    AssetId assetId,
    bool activateIfNeeded,
  ) async {
    final controller = _balanceControllers[assetId];
    if (controller == null || _isDisposed) return;

    // Check if dependencies are initialized
    if (_activationCoordinator == null || _pubkeyManager == null) {
      if (!controller.isClosed) {
        controller.addError(
          StateError('Dependencies not fully initialized yet'),
        );
      }
      return;
    }

    // Cancel any existing watcher for this asset
    await _activeWatchers[assetId]?.cancel();
    _activeWatchers.remove(assetId);

    final asset = _assetLookup.fromId(assetId);
    if (asset == null) {
      controller.addError(
        ArgumentError('Asset not found for balance watch: $assetId'),
      );
      return;
    }

    // Check if user is authenticated
    final user = await _auth.currentUser;
    if (user == null) {
      // Don't throw an error, just wait for authentication
      _logger.fine(
        'Delaying balance watcher start for ${assetId.name}: unauthenticated',
      );
      return;
    }

    // Keep track of the wallet ID this balance is for
    _currentWalletId = user.walletId;
    _logger.fine('Starting balance watcher for ${assetId.name}');

    // Optimization: Check if this is a newly created wallet (not imported)
    final previouslyEnabledAssets = await _assetHistoryStorage.getWalletAssets(
      user.walletId,
    );
    final isFirstTimeEnabling = !previouslyEnabledAssets.contains(assetId.id);

    // Check metadata to determine if this was an imported wallet
    // Only optimize for genuinely new wallets, not imported ones
    final isImported = user.metadata['isImported'] == true;
    final isNewWallet = previouslyEnabledAssets.isEmpty && !isImported;

    // Emit the last known balance immediately if available
    final maybeKnownBalance = lastKnown(assetId);
    if (maybeKnownBalance != null) {
      controller.add(maybeKnownBalance);
      _logger.fine('Emitted initial balance for ${assetId.name}');
    } else if (isFirstTimeEnabling && isNewWallet) {
      // For newly created wallets (not imported) on first-time asset enablement,
      // assume zero balance to reduce RPC spam
      final zeroBalance = BalanceInfo(
        total: Decimal.zero,
        spendable: Decimal.zero,
        unspendable: Decimal.zero,
      );
      _balanceCache[assetId] = zeroBalance;
      controller.add(zeroBalance);
      _logger.fine(
        'Emitted zero balance for first-time asset ${assetId.name} in new wallet',
      );
    }

    try {
      // Ensure asset is activated if needed
      final isActive = await _ensureAssetActivated(asset, activateIfNeeded);

      // If activation was requested but failed, emit error
      if (activateIfNeeded && !isActive) {
        if (!controller.isClosed) {
          controller.addError(
            ActivationFailedException(
              assetId: assetId,
              message: 'Asset activation failed',
              errorCode: 'BALANCE_ACTIVATION_ERROR',
            ),
          );
        }
        return;
      }

      // Mark asset as seen after successful activation
      if (isActive && isFirstTimeEnabling) {
        await _assetHistoryStorage.addAssetToWallet(user.walletId, assetId.id);

        // Fetch real balance (will update from zero for new wallets)
        final balance = await getBalance(assetId);
        if (!controller.isClosed) controller.add(balance);
      } else if (isActive) {
        // If active but not first time, still get balance
        final balance = await getBalance(assetId);
        if (!controller.isClosed) controller.add(balance);
      }

      // Subscribe to balance event stream for real-time updates
      if (!_supportsBalanceStreaming(asset)) {
        _attachPubkeyHintListener(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
        );
        await _startBalancePolling(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
        );
        return;
      }

      _logger.fine('Subscribing to balance stream for ${assetId.id}');
      final balanceStreamSubscription = await _eventStreamingManager
          .subscribeToBalance(coin: assetId.id);

      var hasFallenBack = false;
      Future<void> fallbackToPolling({
        String reason = 'stream stopped',
        Object? error,
        StackTrace? stackTrace,
      }) async {
        if (hasFallenBack || _isDisposed) return;
        hasFallenBack = true;

        _logger.info(
          'Falling back to balance polling for ${assetId.name}: $reason',
        );

        try {
          await balanceStreamSubscription.cancel();
        } catch (cancelError, cancelStack) {
          _logger.fine(
            'Error cancelling balance stream for ${assetId.name}',
            cancelError,
            cancelStack,
          );
        }

        if (_activeWatchers[assetId] == balanceStreamSubscription) {
          await _startBalancePolling(
            asset: asset,
            assetId: assetId,
            controller: controller,
            activateIfNeeded: activateIfNeeded,
          );
        }

        if (error != null) {
          _logger.warning(
            'Balance stream fallback reason for ${assetId.name}: $error',
            error,
            stackTrace,
          );
        }
      }

      _activeWatchers[assetId] = balanceStreamSubscription
        ..onData((balanceEvent) {
          if (_isDisposed) return;

          // Verify the event is for the correct coin
          if (balanceEvent.coin != assetId.id) return;

          // Update cache with the new balance
          _balanceCache[assetId] = balanceEvent.balance;

          // Emit the balance update to listeners
          if (!controller.isClosed) {
            controller.add(balanceEvent.balance);
            _logger.fine(
              'Balance update received for ${assetId.name}: ${balanceEvent.balance.total}',
            );
          }

          // Trigger background refresh to sync per-address balances
          // This ensures address balances match the updated total
          // and notifies any watchPubkeys stream listeners
          if (_pubkeyManager != null) {
            _pubkeyManager!
                .precachePubkeys(asset)
                .then((_) {
                  _logger.fine(
                    'Pubkeys refreshed after balance update for '
                    '${assetId.name}',
                  );
                })
                .catchError((Object e, StackTrace s) {
                  _logger.fine(
                    'Failed to refresh pubkeys for ${assetId.name}',
                    e,
                    s,
                  );
                })
                .ignore();
          }
        })
        ..onError((Object error, StackTrace stackTrace) {
          unawaited(
            fallbackToPolling(
              reason: 'stream error',
              error: error,
              stackTrace: stackTrace,
            ),
          );
        })
        ..onDone(() {
          unawaited(fallbackToPolling(reason: 'stream closed'));
        });

      // Start stale-guard to periodically confirm balance in case of missed events
      _startStaleBalanceGuard(
        asset: asset,
        assetId: assetId,
        controller: controller,
        activateIfNeeded: activateIfNeeded,
      );
    } catch (e, s) {
      _logger.warning(
        'Failed to start balance watcher for ${assetId.name}',
        e,
        s,
      );
      await _startBalancePolling(
        asset: asset,
        assetId: assetId,
        controller: controller,
        activateIfNeeded: activateIfNeeded,
      );
    }
  }

  Future<void> _startBalancePolling({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required bool activateIfNeeded,
  }) async {
    if (_isDisposed || controller.isClosed) return;

    _logger.fine('Starting balance polling fallback for ${assetId.name}');

    final periodicStream = Stream<void>.periodic(_defaultPollingInterval);
    final subscription = periodicStream
        .asyncMap<BalanceInfo?>((_) async {
          if (_isDisposed) return null;

          if (_activationCoordinator == null || _pubkeyManager == null) {
            return null;
          }

          final currentUser = await _auth.currentUser;
          if (currentUser == null || currentUser.walletId != _currentWalletId) {
            return null;
          }

          if (enableDebugLogging) {
            _logger.info(
              '[POLLING] Fetching balance for ${assetId.name} '
              '(every ${_defaultPollingInterval.inSeconds}s)',
            );
          }

          try {
            final isActive = await _ensureAssetActivated(
              asset,
              activateIfNeeded,
            );

            if (isActive) {
              final balance = await getBalance(assetId);
              if (enableDebugLogging) {
                _logger.info(
                  '[POLLING] Balance fetched for ${assetId.name}: '
                  '${balance.total}',
                );
              }
              return balance;
            }
          } catch (error, stackTrace) {
            if (enableDebugLogging) {
              _logger.warning(
                '[POLLING] Balance fetch failed for ${assetId.name}',
                error,
                stackTrace,
              );
            }
          }

          return lastKnown(assetId);
        })
        .listen(
          (balance) {
            if (balance != null && !controller.isClosed) {
              controller.add(balance);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error);
            }
            _logger.warning(
              'Balance polling error for ${assetId.name}',
              error,
              stackTrace,
            );
          },
          onDone: () {
            _stopWatchingBalance(assetId);
            _logger.fine('Balance polling closed for ${assetId.name}');
          },
          cancelOnError: false,
        );

    _activeWatchers[assetId] = subscription;
  }

  /// Stop watching the balance for a specific asset
  void _stopWatchingBalance(AssetId assetId) {
    final watcher = _activeWatchers[assetId];
    if (watcher != null) {
      watcher.cancel();
      _activeWatchers.remove(assetId);
      _logger.fine('Stopped watcher for ${assetId.name}');
    }
    _stopPubkeyHintListener(assetId);
    _stopStaleBalanceGuard(assetId);
    // Don't close the controller here, just remove the watcher
    // The controller will be closed when all listeners are gone
  }

  void _startStaleBalanceGuard({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required bool activateIfNeeded,
  }) {
    // Cancel any existing timer first
    _staleBalanceTimers[assetId]?.cancel();

    _staleBalanceTimers[assetId] = Timer.periodic(_defaultPollingInterval, (
      _,
    ) async {
      if (_isDisposed || controller.isClosed) return;
      try {
        final isActive = await _ensureAssetActivated(asset, activateIfNeeded);
        if (!isActive) return;

        final latest = await getBalance(assetId);
        final previous = _balanceCache[assetId];
        final changed =
            previous == null ||
            previous.total != latest.total ||
            previous.spendable != latest.spendable ||
            previous.unspendable != latest.unspendable;
        if (changed) {
          _balanceCache[assetId] = latest;
          if (!controller.isClosed) {
            controller.add(latest);
          }
        }
      } catch (_) {
        // best-effort; swallow transient errors
      }
    });

    // Kick off an immediate one-shot refresh
    unawaited(() async {
      try {
        final isActive = await _ensureAssetActivated(asset, activateIfNeeded);
        if (!isActive) return;
        final latest = await getBalance(assetId);
        final previous = _balanceCache[assetId];
        final changed =
            previous == null ||
            previous.total != latest.total ||
            previous.spendable != latest.spendable ||
            previous.unspendable != latest.unspendable;
        if (changed && !controller.isClosed) {
          _balanceCache[assetId] = latest;
          controller.add(latest);
        }
      } catch (_) {}
    }());
  }

  void _stopStaleBalanceGuard(AssetId assetId) {
    _staleBalanceTimers[assetId]?.cancel();
    _staleBalanceTimers.remove(assetId);
  }

  void _attachPubkeyHintListener({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required bool activateIfNeeded,
  }) {
    final pubkeyManager = _pubkeyManager;
    if (pubkeyManager == null || _isDisposed) return;

    _pubkeyHintWatchers[assetId]?.cancel();
    _pubkeyHintWatchers[assetId] = pubkeyManager
        .watchPubkeys(asset, activateIfNeeded: activateIfNeeded)
        .listen(
          (AssetPubkeys pubkeys) {
            unawaited(
              _handlePubkeyBalanceHint(
                asset: asset,
                assetId: assetId,
                controller: controller,
                pubkeys: pubkeys,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            _logger.fine(
              'Pubkey hint watcher error for ${assetId.name}',
              error,
              stackTrace,
            );
          },
        );
  }

  void _stopPubkeyHintListener(AssetId assetId) {
    _pubkeyHintWatchers.remove(assetId)?.cancel();
  }

  Future<void> _handlePubkeyBalanceHint({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required AssetPubkeys pubkeys,
  }) async {
    if (_isDisposed || _supportsBalanceStreaming(asset)) return;

    final latest = pubkeys.balance;
    final previous = _balanceCache[assetId];
    final changed =
        previous == null ||
        previous.total != latest.total ||
        previous.spendable != latest.spendable ||
        previous.unspendable != latest.unspendable;
    if (!changed) return;

    _balanceCache[assetId] = latest;
    if (!controller.isClosed) {
      controller.add(latest);
    }

    _pendingFastRefresh.add(assetId);
    unawaited(
      _performImmediateBalanceRefresh(
        asset: asset,
        assetId: assetId,
        controller: controller,
      ),
    );
  }

  Future<void> _performImmediateBalanceRefresh({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
  }) async {
    if (_isDisposed) return;
    if (!_pendingFastRefresh.contains(assetId)) return;

    try {
      final refreshed = await getBalance(assetId);
      _balanceCache[assetId] = refreshed;
      if (!controller.isClosed) {
        controller.add(refreshed);
      }
    } catch (error, stackTrace) {
      _logger.fine(
        'Immediate balance refresh failed for ${assetId.name}',
        error,
        stackTrace,
      );
    } finally {
      _pendingFastRefresh.remove(assetId);
    }
  }

  @override
  BalanceInfo? lastKnown(AssetId assetId) {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }
    return _balanceCache[assetId];
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    // Take snapshots to avoid concurrent modification while cancelling/closing
    final StreamSubscription<KdfUser?>? authSub = _authSubscription;
    _authSubscription = null;

    final List<StreamSubscription<dynamic>> watcherSubs =
        List<StreamSubscription<dynamic>>.from(_activeWatchers.values);
    _activeWatchers.clear();

    // Cancel auth subscription and all watchers concurrently; swallow errors
    final List<Future<void>> cancelFutures = <Future<void>>[];
    if (authSub != null) {
      cancelFutures.add(
        authSub.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling auth subscription', e, s);
        }),
      );
    }
    for (final StreamSubscription<dynamic> sub in watcherSubs) {
      cancelFutures.add(
        sub.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling balance watcher', e, s);
        }),
      );
    }
    if (cancelFutures.isNotEmpty) {
      await Future.wait(cancelFutures);
    }

    // Snapshot controllers and close all concurrently; swallow errors
    final List<StreamSubscription<AssetPubkeys>> pubkeyHintSubs =
        List<StreamSubscription<AssetPubkeys>>.from(
          _pubkeyHintWatchers.values,
        );
    _pubkeyHintWatchers.clear();
    for (final StreamSubscription<AssetPubkeys> sub in pubkeyHintSubs) {
      cancelFutures.add(
        sub.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling pubkey hint watcher', e, s);
        }),
      );
    }

    final List<StreamController<BalanceInfo>> controllers =
        List<StreamController<BalanceInfo>>.from(_balanceControllers.values);
    _balanceControllers.clear();

    final List<Future<void>> closeFutures = <Future<void>>[];
    for (final StreamController<BalanceInfo> controller in controllers) {
      if (!controller.isClosed) {
        closeFutures.add(
          controller.close().catchError((Object e, StackTrace s) {
            _logger.warning('Error closing balance controller', e, s);
          }),
        );
      }
    }
    if (closeFutures.isNotEmpty) {
      await Future.wait(closeFutures);
    }

    // Clear all other resources
    _balanceCache.clear();
    _currentWalletId = null;
    _logger.fine('Disposed');

    // Cancel any remaining stale-guard timers
    for (final timer in _staleBalanceTimers.values) {
      timer.cancel();
    }
    _staleBalanceTimers.clear();
  }

  @override
  Future<void> precacheBalance(Asset asset) async {
    if (_isDisposed) return;

    // Check if pubkeyManager is initialized
    if (_pubkeyManager == null) {
      _logger.fine('Cannot pre-cache balance: PubkeyManager not initialized');
      return;
    }

    final user = await _auth.currentUser;
    if (user == null) return;

    // Retry logic to handle timing issues after activation
    const maxRetries = 3;
    const baseDelay = Duration(milliseconds: 200);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final balance = await _pubkeyManager!
            .getPubkeys(asset)
            .then((pubkeys) => pubkeys.balance);
        _balanceCache[asset.id] = balance;

        // If there's an active stream controller for this asset, emit the balance
        final controller = _balanceControllers[asset.id];
        if (controller != null && !controller.isClosed) {
          controller.add(balance);
        }
        return; // Success, exit retry loop
      } catch (e) {
        final isLastAttempt = attempt == maxRetries - 1;
        final errorStr = e.toString().toLowerCase();
        final isCoinNotFound =
            errorStr.contains('no such coin') ||
            errorStr.contains('coin not found') ||
            errorStr.contains('not activated') ||
            errorStr.contains('invalid coin');

        if (isCoinNotFound && !isLastAttempt) {
          _logger.fine(
            'Balance pre-cache retry ${attempt + 1}: ${asset.id.name} not yet available',
          );
          await Future<void>.delayed(baseDelay * (attempt + 1));
          continue;
        }

        // Either not a timing issue or final attempt - fail silently
        _logger.fine('Failed to pre-cache balance for ${asset.id.name}: $e');
        return;
      }
    }
  }
}
