import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
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
  ///
  /// The returned stream is a **broadcast** stream that is safe to hold for the
  /// lifetime of a widget or repository: it may be listened to, cancelled and
  /// listened to again (a `StreamBuilder` unmounting and remounting), and it
  /// re-establishes itself after the transient failures that are normal around
  /// sign-in and wallet switches - an auth read that lands before the session
  /// is observable, a wallet-generation change, the per-asset controller being
  /// recycled by an internal state reset.
  ///
  /// Those failures are still *reported*: each one is forwarded to listeners as
  /// a stream error before recovery is attempted, so callers keep whatever
  /// transient-error handling they already have. What the stream does not do is
  /// end. It completes only when the manager is disposed.
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  });

  /// Returns whether [assetId] currently has an active watcher subscription.
  bool hasActiveWatcher(AssetId assetId);

  /// Counts how many [assetIds] do not currently have active watcher coverage.
  int countMissingWatchersForAssets(Iterable<AssetId> assetIds);

  /// Returns true when any asset in [assetIds] lacks active watcher coverage.
  bool hasMissingWatchersForAssets(Iterable<AssetId> assetIds);

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
    Duration watcherStartRetryDelay = _defaultWatcherStartRetryDelay,
    Duration watcherStartMaxRetryDelay = _defaultWatcherStartMaxRetryDelay,
    int maxWatcherStartRetries = _defaultMaxWatcherStartRetries,
  }) : _activationCoordinator = activationCoordinator,
       _pubkeyManager = pubkeyManager,
       _assetLookup = assetLookup,
       _auth = auth,
       _eventStreamingManager = eventStreamingManager,
       _assetHistoryStorage = assetHistoryStorage ?? AssetHistoryStorage(),
       _watcherStartRetryDelay = watcherStartRetryDelay,
       _watcherStartMaxRetryDelay = watcherStartMaxRetryDelay,
       _maxWatcherStartRetries = maxWatcherStartRetries {
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

  /// Pending deferred watcher teardowns, keyed by asset. See the `onCancel`
  /// hook in [_controllerFor].
  final Map<AssetId, Timer> _watcherTeardownTimers = {};

  /// How long a per-asset watcher survives after its last listener leaves.
  /// Long enough to absorb an unsubscribe/resubscribe within the same frame or
  /// two, short enough that a genuinely closed page stops polling promptly.
  static const Duration _watcherTeardownGrace = Duration(milliseconds: 500);

  /// Pending retries of [_startWatchingBalance], keyed by asset.
  final Map<AssetId, Timer> _watcherStartRetryTimers = {};

  /// Retry attempts already spent per asset, reset once a start succeeds.
  final Map<AssetId, int> _watcherStartRetries = {};

  /// Base delay between watcher-start retries; doubles up to
  /// [_watcherStartMaxRetryDelay].
  final Duration _watcherStartRetryDelay;

  final Duration _watcherStartMaxRetryDelay;

  /// Bounded so a genuinely un-startable asset stops retrying. ~45s of wall
  /// clock at the default backoff, which comfortably outlasts a login.
  final int _maxWatcherStartRetries;

  static const Duration _defaultWatcherStartRetryDelay = Duration(
    milliseconds: 400,
  );
  static const Duration _defaultWatcherStartMaxRetryDelay = Duration(
    seconds: 5,
  );
  static const int _defaultMaxWatcherStartRetries = 15;

  /// Assets whose watcher start has exhausted [_maxWatcherStartRetries] for the
  /// current wallet generation.
  ///
  /// This bound is only real if nothing hands the asset a fresh budget.
  /// [_watcherStartRetries] is keyed by asset and cleared on give-up, and the
  /// start is re-armed by a controller's 0->1 listener transition - so a
  /// subscriber that reconnects (which is exactly what [watchBalance]'s
  /// re-attach does on the error the give-up emits) would otherwise restart the
  /// count from zero, every time, forever. Two independently bounded retry
  /// layers compose into an unbounded one unless one of them can see that the
  /// other has stopped.
  ///
  /// Cleared by [_resetState], so a wallet change or a fresh sign-in gets a
  /// clean budget.
  final Set<AssetId> _watcherStartGaveUp = <AssetId>{};

  /// Live [watchBalance] attachments, i.e. those with at least one listener.
  ///
  /// Held so [_resetState] can wake any that went dormant on a give-up and
  /// [dispose] can close them. Entries are added on a 0->1 listener transition
  /// and removed on 1->0, so this is bounded by the number of subscribed
  /// callers rather than by the number of streams ever handed out.
  final Set<_BalanceStreamAttachment> _streamAttachments =
      <_BalanceStreamAttachment>{};

  /// Retries a watcher start that bailed out for a transient reason.
  ///
  /// Broadcast controllers only run `onListen` on a 0->1 listener transition,
  /// so a listener that is already attached when the start fails has nothing
  /// left to trigger another attempt. Without this the asset's controller stays
  /// registered and subscribed with no producer behind it - indistinguishable,
  /// to the UI, from a balance that is still loading.
  void _scheduleWatcherStartRetry(
    AssetId assetId,
    bool activateIfNeeded,
    String reason,
  ) {
    if (_isDisposed) return;

    final attempt = (_watcherStartRetries[assetId] ?? 0) + 1;
    if (attempt > _maxWatcherStartRetries) {
      _logger.warning(
        'Giving up starting the balance watcher for ${assetId.name} after '
        '$_maxWatcherStartRetries attempts ($reason)',
      );
      // Latch before emitting the error. The error is what makes a subscriber
      // re-attach, and the re-attach is what would hand this asset a fresh
      // budget - so the flag has to be visible by the time that happens.
      _watcherStartGaveUp.add(assetId);
      final controller = _balanceControllers[assetId];
      // Surface it rather than staying silent: a caller that can recover (the
      // wallet re-subscribes on error) needs the signal, and a caller that
      // cannot at least shows an error instead of an eternal spinner.
      if (controller != null && !controller.isClosed) {
        controller.addError(
          StateError(
            'Could not start balance watcher for ${assetId.id}: $reason',
          ),
        );
      }
      _watcherStartRetries.remove(assetId);
      return;
    }
    _watcherStartRetries[assetId] = attempt;

    final shift = (attempt - 1).clamp(0, 10);
    final delay = Duration(
      microseconds: (_watcherStartRetryDelay.inMicroseconds * (1 << shift))
          .clamp(
            _watcherStartRetryDelay.inMicroseconds,
            _watcherStartMaxRetryDelay.inMicroseconds,
          ),
    );

    _watcherStartRetryTimers[assetId]?.cancel();
    _watcherStartRetryTimers[assetId] = Timer(delay, () {
      _watcherStartRetryTimers.remove(assetId);
      if (_isDisposed) return;
      final controller = _balanceControllers[assetId];
      // Nothing to feed, or somebody already started one.
      if (controller == null ||
          controller.isClosed ||
          !controller.hasListener ||
          _activeWatchers.containsKey(assetId)) {
        _watcherStartRetries.remove(assetId);
        return;
      }
      unawaited(_startWatchingBalance(assetId, activateIfNeeded));
    });
  }

  void _cancelWatcherStartRetries() {
    for (final timer in _watcherStartRetryTimers.values) {
      timer.cancel();
    }
    _watcherStartRetryTimers.clear();
    _watcherStartRetries.clear();
    _watcherStartGaveUp.clear();
  }

  /// Current wallet ID being tracked
  WalletId? _currentWalletId;

  /// Invalidates every in-flight fetch as soon as authentication changes.
  int _walletGeneration = 0;

  /// Flag indicating if the manager has been disposed
  bool _isDisposed = false;

  /// Getter for activationCoordinator to make it accessible
  SharedActivationCoordinator? get activationCoordinator =>
      _activationCoordinator;

  /// Getter for pubkeyManager to make it accessible
  PubkeyManager? get pubkeyManager => _pubkeyManager;

  @override
  bool hasActiveWatcher(AssetId assetId) {
    if (_isDisposed) return false;
    return _activeWatchers.containsKey(assetId);
  }

  @override
  int countMissingWatchersForAssets(Iterable<AssetId> assetIds) {
    if (_isDisposed) return assetIds.toSet().length;
    final uniqueIds = assetIds.toSet();
    return uniqueIds
        .where((assetId) => !_activeWatchers.containsKey(assetId))
        .length;
  }

  @override
  bool hasMissingWatchersForAssets(Iterable<AssetId> assetIds) {
    return countMissingWatchersForAssets(assetIds) > 0;
  }

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
    final currentWalletId = _currentWalletId;
    if (_sameOptionalWallet(currentWalletId, newWalletId)) {
      if (currentWalletId != null && newWalletId != null) {
        _currentWalletId = preferEnrichedWalletIdentity(
          currentWalletId,
          newWalletId,
        );
      }
      return;
    }

    // A transient `get_public_key_hash` failure makes the auth service emit the
    // *same* wallet without its pubkeyHash. Resetting on that would clear the
    // balance cache and error-and-close every per-asset controller in the app
    // for a wallet that never changed - and since the identity RPC is most
    // likely to blip exactly when KDF is saturated with login activations,
    // that is a post-login stall, not a rare edge case. Keep the enriched
    // identity and the live state; the next successful read re-confirms it.
    if (currentWalletId != null &&
        newWalletId != null &&
        isDegradedWalletIdentity(currentWalletId, newWalletId)) {
      _logger.warning(
        'Ignoring a degraded wallet identity for ${currentWalletId.name} '
        '(identity RPC unavailable); keeping balance state',
      );
      return;
    }

    // Change identity before awaiting cleanup so an already-completing RPC
    // cannot commit into the next wallet's cache in the reset window.
    _walletGeneration++;
    _currentWalletId = newWalletId;
    await _resetState();
  }

  bool _sameOptionalWallet(WalletId? previous, WalletId? current) {
    if (previous == null || current == null) return previous == current;
    return isSameStableWallet(previous, current);
  }

  Future<WalletOperationContext> _captureWalletContext() async {
    final user = await _auth.currentUser;
    if (user == null) throw AuthException.notSignedIn();

    final currentWalletId = _currentWalletId;
    late final WalletId operationWalletId;
    if (currentWalletId == null) {
      _currentWalletId = user.walletId;
      operationWalletId = user.walletId;
    } else if (isSameStableWallet(currentWalletId, user.walletId)) {
      operationWalletId = preferEnrichedWalletIdentity(
        currentWalletId,
        user.walletId,
      );
      _currentWalletId = operationWalletId;
    } else if (isDegradedWalletIdentity(currentWalletId, user.walletId)) {
      // Same wallet, identity RPC temporarily unavailable. See the matching
      // branch in [_handleAuthStateChanged] - operate under the enriched
      // identity we already hold rather than resetting every balance watcher.
      operationWalletId = currentWalletId;
    } else {
      // Auth streams are asynchronous. Proactively invalidate here too so a
      // caller cannot observe the prior wallet's cache before the event lands.
      _walletGeneration++;
      _currentWalletId = user.walletId;
      operationWalletId = user.walletId;
      await _resetState();
    }

    return WalletOperationContext(
      walletId: operationWalletId,
      generation: _walletGeneration,
    );
  }

  bool _isWalletContextCurrentSync(WalletOperationContext context) {
    final current = _currentWalletId;
    return !_isDisposed &&
        context.generation == _walletGeneration &&
        current != null &&
        isSameStableWallet(context.walletId, current);
  }

  Future<bool> _isWalletContextCurrent(WalletOperationContext context) async {
    if (!_isWalletContextCurrentSync(context)) return false;
    final currentUser = await _auth.currentUser;
    return currentUser != null &&
        _isWalletContextCurrentSync(context) &&
        isSameStableWallet(context.walletId, currentUser.walletId);
  }

  Future<void> _requireWalletContextCurrent(
    WalletOperationContext context,
  ) async {
    if (await _isWalletContextCurrent(context)) return;
    throw const WalletChangedDisconnectException(
      'Wallet changed while fetching balance',
    );
  }

  /// Reset all internal state when wallet changes
  Future<void> _resetState() async {
    _logger.fine('Resetting state');
    final stopwatch = Stopwatch()..start();

    // Clear wallet-owned values before awaiting cancellation. This prevents a
    // newly signed-in caller from observing the previous wallet during cleanup.
    _balanceCache.clear();
    _pendingFastRefresh.clear();

    final List<Future<void>> cleanupFutures = <Future<void>>[];
    final List<StreamSubscription<dynamic>> watcherSubs = _activeWatchers.values
        .toList();
    _activeWatchers.clear();
    final List<StreamSubscription<AssetPubkeys>> pubkeyHintSubs =
        _pubkeyHintWatchers.values.toList();
    _pubkeyHintWatchers.clear();

    for (final subscription in watcherSubs) {
      cleanupFutures.add(
        subscription.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling balance watcher', e, s);
        }),
      );
    }
    for (final subscription in pubkeyHintSubs) {
      cleanupFutures.add(
        subscription.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling pubkey hint watcher', e, s);
        }),
      );
    }

    // Cancel all stale balance timers to prevent timer leak on wallet change
    for (final timer in _staleBalanceTimers.values) {
      timer.cancel();
    }
    _staleBalanceTimers.clear();

    // Deferred teardowns are meaningless once the controllers are discarded.
    for (final timer in _watcherTeardownTimers.values) {
      timer.cancel();
    }
    _watcherTeardownTimers.clear();
    _cancelWatcherStartRetries();

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

    // Every controller above was closed, so each live subscriber is about to
    // see `done` and re-attach on its own. The exception is an attachment that
    // stood down because its asset's watcher had given up: the latch it was
    // waiting on is cleared by [_cancelWatcherStartRetries] above, and nothing
    // else would ever tell it so. `_currentWalletId` is already the incoming
    // wallet by this point, so re-attaching now captures the right context.
    if (!_isDisposed) {
      for (final attachment in _streamAttachments.toList()) {
        attachment.wakeIfDormant();
      }
    }

    stopwatch.stop();
    _logger.fine(
      'State reset completed in ${stopwatch.elapsedMilliseconds}ms '
      '(${watcherSubs.length + pubkeyHintSubs.length} subscriptions, '
      '${controllers.length} controllers)',
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

    final walletContext = await _captureWalletContext();

    final asset = _assetLookup.fromId(assetId);
    if (asset == null) {
      throw ArgumentError('Asset not found for balance check: $assetId');
    }

    try {
      final balance = await _pubkeyManager!
          .getPubkeys(asset)
          .then((pubkeys) => pubkeys.balance);
      await _requireWalletContextCurrent(walletContext);
      // Update cache with the latest balance
      _balanceCache[assetId] = balance;
      return balance;
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (e) {
      // Rethrow with more context
      throw StateError('Failed to get balance for ${assetId.name}: $e');
    }
  }

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  }) {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }
    return _BalanceStreamAttachment(
      manager: this,
      assetId: assetId,
      activateIfNeeded: activateIfNeeded,
    ).stream;
  }

  /// The shared per-asset controller every subscriber of [assetId] attaches to.
  ///
  /// [walletContext] belongs to whichever subscriber caused the controller to
  /// be created; its `onListen`/`onCancel` hooks use it only to check that the
  /// controller is still the live one for the current wallet.
  StreamController<BalanceInfo> _controllerFor(
    AssetId assetId,
    bool activateIfNeeded,
    WalletOperationContext walletContext,
  ) {
    return _balanceControllers.putIfAbsent(assetId, () {
      late final StreamController<BalanceInfo> createdController;
      createdController = StreamController<BalanceInfo>.broadcast(
        onListen: () {
          // Claim the pending teardown only once this controller is known to
          // be the live one. `_watcherTeardownTimers` is keyed by asset, not
          // by controller, so cancelling before these guards would let a
          // listener on a stale controller swallow the *current* controller's
          // teardown - leaking its KDF subscription and stale guard. A timer
          // left pending is harmless: _stopWatchingBalance re-checks identity.
          if (!_isWalletContextCurrentSync(walletContext) ||
              !identical(_balanceControllers[assetId], createdController)) {
            return;
          }

          // A pending teardown means the last listener left within the grace
          // window - typically a widget rebuild handing StreamBuilder a new
          // stream object. Keep the live watcher instead of restarting it.
          final pendingTeardown = _watcherTeardownTimers.remove(assetId);
          pendingTeardown?.cancel();

          if (pendingTeardown != null && _activeWatchers.containsKey(assetId)) {
            _logger.fine('onListen: ${assetId.name} reused live watcher');
            return;
          }

          // The start already exhausted its budget for this wallet generation.
          // Re-arming it here is precisely what would make that bound
          // meaningless - see [_watcherStartGaveUp]. The next [_resetState]
          // clears the latch and wakes the attachments that stood down.
          if (_watcherStartGaveUp.contains(assetId)) {
            _logger.fine(
              'onListen: ${assetId.name} not restarting a watcher that gave up',
            );
            return;
          }
          _logger.fine(
            'onListen: ${assetId.name}, activateIfNeeded: $activateIfNeeded',
          );
          _startWatchingBalance(assetId, activateIfNeeded);
        },
        onCancel: () {
          // A stale controller must not replace the live controller's
          // asset-keyed teardown timer.
          if (!_isWalletContextCurrentSync(walletContext) ||
              !identical(_balanceControllers[assetId], createdController)) {
            return;
          }

          // Defer the teardown. Broadcast controllers fire onCancel on every
          // 1->0 listener transition, so an unsubscribe/resubscribe flap would
          // otherwise cancel the KDF subscription and stale guard and pay the
          // full restart cost (storage read, activation check, getPubkeys,
          // subscribe_to_balance) to end up exactly where it started.
          _watcherTeardownTimers[assetId]?.cancel();
          _watcherTeardownTimers[assetId] = Timer(_watcherTeardownGrace, () {
            _watcherTeardownTimers.remove(assetId);
            if (createdController.isClosed || createdController.hasListener) {
              return;
            }
            _logger.fine('onCancel: ${assetId.name} (grace elapsed)');
            _stopWatchingBalance(
              assetId,
              expectedController: createdController,
            );
          });
        },
      );
      return createdController;
    });
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

  /// Starts the balance watcher for [assetId], retrying if it does not stick.
  ///
  /// This is dispatched un-awaited from a broadcast controller's `onListen`,
  /// which fires only on a 0->1 listener transition. A subscriber that stays
  /// subscribed therefore gets exactly one chance at a producer: every path
  /// through [_startWatchingBalanceOnce] that returns without registering a
  /// watcher - a storage read that throws, an auth read that comes back null,
  /// a context check that loses a race - leaves a live, subscribed controller
  /// with nothing feeding it and no way to ever try again. To the UI that is
  /// indistinguishable from a balance that is still loading.
  ///
  /// Rather than auditing each early return, check the postcondition: if the
  /// controller is still the registered, open, listened-to one and no watcher
  /// was registered for it, the start did not stick. A genuine wallet change
  /// fails that check on its own, because [_resetState] clears
  /// [_balanceControllers] and closes the controller.
  Future<void> _startWatchingBalance(
    AssetId assetId,
    bool activateIfNeeded,
  ) async {
    var failureReason = 'watcher did not start';
    try {
      await _startWatchingBalanceOnce(assetId, activateIfNeeded);
    } catch (e, s) {
      // Not all of the work below is inside the method's own try block - the
      // secure-storage reads in particular are not - so a throw here would
      // otherwise escape into this un-awaited future and skip the retry.
      failureReason = 'watcher start threw: $e';
      _logger.warning('Balance watcher start failed for ${assetId.name}', e, s);
    }

    if (_isDisposed) return;
    if (_activeWatchers.containsKey(assetId)) {
      // Started successfully - the next failure gets a fresh retry budget.
      _watcherStartRetries.remove(assetId);
      _watcherStartGaveUp.remove(assetId);
      return;
    }
    final controller = _balanceControllers[assetId];
    if (controller == null ||
        controller.isClosed ||
        !controller.hasListener ||
        _watcherStartRetryTimers.containsKey(assetId)) {
      return;
    }
    _scheduleWatcherStartRetry(assetId, activateIfNeeded, failureReason);
  }

  Future<void> _startWatchingBalanceOnce(
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
    final previousWatcher = _activeWatchers.remove(assetId);
    await previousWatcher?.cancel();

    final asset = _assetLookup.fromId(assetId);
    if (asset == null) {
      controller.addError(
        ArgumentError('Asset not found for balance watch: $assetId'),
      );
      return;
    }

    final WalletOperationContext walletContext;
    try {
      walletContext = await _captureWalletContext();
    } on AuthException {
      // "Wait for authentication" - but nothing was actually waiting. A
      // broadcast controller only runs `onListen` on a 0->1 listener
      // transition, so returning here left a registered, subscribed controller
      // with no producer and no trigger to ever get one: the asset's balance
      // never appeared for the rest of the session.
      //
      // This is reachable on the normal login path. `watchBalance` subscribes
      // as soon as the wallet rows are rendered, which can precede the SDK's
      // own auth read resolving.
      _logger.fine(
        'Delaying balance watcher start for ${assetId.name}: unauthenticated',
      );
      _scheduleWatcherStartRetry(assetId, activateIfNeeded, 'unauthenticated');
      return;
    }
    if (controller.isClosed ||
        !identical(_balanceControllers[assetId], controller) ||
        !_isWalletContextCurrentSync(walletContext)) {
      return;
    }
    final user = await _auth.currentUser;
    if (user == null ||
        !isSameStableWallet(walletContext.walletId, user.walletId)) {
      return;
    }
    _logger.fine('Starting balance watcher for ${assetId.name}');

    // Optimization: Check if this is a newly created wallet (not imported)
    final previouslyEnabledAssets = await _assetHistoryStorage.getWalletAssets(
      walletContext.walletId,
    );
    if (!await _isWalletContextCurrent(walletContext)) return;
    final isFirstTimeEnabling = !previouslyEnabledAssets.contains(assetId.id);

    // Check metadata to determine if this was an imported wallet
    // Only optimize for genuinely new wallets, not imported ones
    final isImported = user.metadata['isImported'] == true;
    var isNewWallet = previouslyEnabledAssets.isEmpty && !isImported;
    if (isNewWallet) {
      final hasAmbiguousLegacyHistory = await _assetHistoryStorage
          .hasAmbiguousLegacyHistory(walletContext.walletId);
      if (!await _isWalletContextCurrent(walletContext)) return;
      isNewWallet = !hasAmbiguousLegacyHistory;
    }

    // Emit the last known balance immediately if available
    final maybeKnownBalance = lastKnownForWallet(
      assetId,
      walletContext.walletId,
    );
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
      if (!await _isWalletContextCurrent(walletContext)) return;

      // If activation was requested but failed, emit error
      if (activateIfNeeded && !isActive) {
        final activationError = ActivationFailedException(
          assetId: assetId,
          message: 'Asset activation failed',
          errorCode: 'BALANCE_ACTIVATION_ERROR',
        );

        if (!controller.isClosed) {
          controller.addError(activationError);
        }

        // Recovery mode: keep this watcher alive and retry in the background
        // so callers do not need to re-subscribe after startup races.
        _logger.warning(
          'Activation unavailable for ${assetId.name}; '
          'starting recovery watchers',
          activationError,
        );
        _startStaleBalanceGuard(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
          walletContext: walletContext,
        );
        await _startBalancePolling(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
          walletContext: walletContext,
        );
        return;
      }

      // Mark asset as seen after successful activation
      if (isActive && isFirstTimeEnabling) {
        await _assetHistoryStorage.addAssetToWallet(user.walletId, assetId.id);
        if (!await _isWalletContextCurrent(walletContext)) return;

        // Fetch real balance (will update from zero for new wallets)
        final balance = await getBalance(assetId);
        if (_isWalletContextCurrentSync(walletContext) &&
            !controller.isClosed) {
          controller.add(balance);
        }
      } else if (isActive) {
        // If active but not first time, still get balance
        final balance = await getBalance(assetId);
        if (_isWalletContextCurrentSync(walletContext) &&
            !controller.isClosed) {
          controller.add(balance);
        }
      }

      // Subscribe to balance event stream for real-time updates.
      if (!_supportsBalanceStreaming(asset)) {
        _attachPubkeyHintListener(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
          walletContext: walletContext,
        );
        await _startBalancePolling(
          asset: asset,
          assetId: assetId,
          controller: controller,
          activateIfNeeded: activateIfNeeded,
          walletContext: walletContext,
        );
        return;
      }

      _logger.fine('Subscribing to balance stream for ${assetId.id}');
      final balanceStreamSubscription = await _eventStreamingManager
          .subscribeToBalance(coin: assetId.id);
      if (!await _isWalletContextCurrent(walletContext)) {
        await balanceStreamSubscription.cancel();
        return;
      }

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
            walletContext: walletContext,
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
          if (!_isWalletContextCurrentSync(walletContext)) return;

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
        walletContext: walletContext,
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
        walletContext: walletContext,
      );
    }
  }

  Future<void> _startBalancePolling({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required bool activateIfNeeded,
    required WalletOperationContext walletContext,
  }) async {
    if (controller.isClosed ||
        !identical(_balanceControllers[assetId], controller) ||
        !_isWalletContextCurrentSync(walletContext)) {
      return;
    }

    _logger.fine('Starting balance polling fallback for ${assetId.name}');

    Future<BalanceInfo?> fetchLatestBalance() async {
      if (!_isWalletContextCurrentSync(walletContext)) return null;

      if (_activationCoordinator == null || _pubkeyManager == null) {
        return null;
      }

      if (!await _isWalletContextCurrent(walletContext)) {
        return null;
      }

      if (enableDebugLogging) {
        _logger.info(
          '[POLLING] Fetching balance for ${assetId.name} '
          '(every ${_defaultPollingInterval.inSeconds}s)',
        );
      }

      try {
        final isActive = await _ensureAssetActivated(asset, activateIfNeeded);

        if (isActive) {
          final balance = await getBalance(assetId);
          if (!await _isWalletContextCurrent(walletContext)) return null;
          if (enableDebugLogging) {
            _logger.info(
              '[POLLING] Balance fetched for ${assetId.name}: '
              '${balance.total}',
            );
          }
          return balance;
        }
      } on Object catch (error, stackTrace) {
        if (enableDebugLogging) {
          _logger.warning(
            '[POLLING] Balance fetch failed for ${assetId.name}',
            error,
            stackTrace,
          );
        }
      }

      if (!_isWalletContextCurrentSync(walletContext)) return null;
      return lastKnownForWallet(assetId, walletContext.walletId);
    }

    // Kick off an immediate refresh so polling fallback can recover quickly
    // after startup races without waiting for the first periodic tick.
    unawaited(() async {
      final balance = await fetchLatestBalance();
      if (balance != null &&
          !controller.isClosed &&
          _isWalletContextCurrentSync(walletContext)) {
        controller.add(balance);
      }
    }());

    final periodicStream = Stream<void>.periodic(_defaultPollingInterval);
    late final StreamSubscription<BalanceInfo?> subscription;
    subscription = periodicStream
        .asyncMap<BalanceInfo?>((_) => fetchLatestBalance())
        .listen(
          (balance) {
            if (balance != null &&
                !controller.isClosed &&
                _isWalletContextCurrentSync(walletContext)) {
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
            _stopWatchingBalance(assetId, expected: subscription);
            _logger.fine('Balance polling closed for ${assetId.name}');
          },
          cancelOnError: false,
        );

    if (_isWalletContextCurrentSync(walletContext) &&
        identical(_balanceControllers[assetId], controller)) {
      _activeWatchers[assetId] = subscription;
    } else {
      await subscription.cancel();
    }
  }

  /// Stop watching the balance for a specific asset
  void _stopWatchingBalance(
    AssetId assetId, {
    StreamSubscription<dynamic>? expected,
    StreamController<BalanceInfo>? expectedController,
  }) {
    if (expectedController != null &&
        !identical(_balanceControllers[assetId], expectedController)) {
      return;
    }
    final watcher = _activeWatchers[assetId];
    if (expected != null && !identical(watcher, expected)) return;
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
    required WalletOperationContext walletContext,
  }) {
    if (controller.isClosed ||
        !identical(_balanceControllers[assetId], controller) ||
        !_isWalletContextCurrentSync(walletContext)) {
      return;
    }
    // Cancel any existing timer first
    _staleBalanceTimers[assetId]?.cancel();

    _staleBalanceTimers[assetId] = Timer.periodic(_defaultPollingInterval, (
      _,
    ) async {
      if (controller.isClosed || !_isWalletContextCurrentSync(walletContext)) {
        return;
      }
      try {
        final isActive = await _ensureAssetActivated(asset, activateIfNeeded);
        if (!isActive) return;

        final latest = await getBalance(assetId);
        if (!await _isWalletContextCurrent(walletContext)) return;
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
        if (!await _isWalletContextCurrent(walletContext)) return;
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
    required WalletOperationContext walletContext,
  }) {
    final pubkeyManager = _pubkeyManager;
    if (pubkeyManager == null ||
        _isDisposed ||
        controller.isClosed ||
        !identical(_balanceControllers[assetId], controller) ||
        !_isWalletContextCurrentSync(walletContext)) {
      return;
    }

    _pubkeyHintWatchers.remove(assetId)?.cancel();
    final subscription = pubkeyManager
        .watchPubkeys(asset, activateIfNeeded: activateIfNeeded)
        .listen(
          (AssetPubkeys pubkeys) {
            unawaited(
              _handlePubkeyBalanceHint(
                asset: asset,
                assetId: assetId,
                controller: controller,
                pubkeys: pubkeys,
                walletContext: walletContext,
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
    if (_isWalletContextCurrentSync(walletContext) &&
        identical(_balanceControllers[assetId], controller)) {
      _pubkeyHintWatchers[assetId] = subscription;
    } else {
      subscription.cancel();
    }
  }

  void _stopPubkeyHintListener(AssetId assetId) {
    _pubkeyHintWatchers.remove(assetId)?.cancel();
  }

  Future<void> _handlePubkeyBalanceHint({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required AssetPubkeys pubkeys,
    required WalletOperationContext walletContext,
  }) async {
    if (!_isWalletContextCurrentSync(walletContext) ||
        _supportsBalanceStreaming(asset)) {
      return;
    }

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
        walletContext: walletContext,
      ),
    );
  }

  Future<void> _performImmediateBalanceRefresh({
    required Asset asset,
    required AssetId assetId,
    required StreamController<BalanceInfo> controller,
    required WalletOperationContext walletContext,
  }) async {
    if (!_isWalletContextCurrentSync(walletContext)) return;
    if (!_pendingFastRefresh.contains(assetId)) return;

    try {
      final refreshed = await getBalance(assetId);
      if (!await _isWalletContextCurrent(walletContext)) return;
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
      if (_isWalletContextCurrentSync(walletContext)) {
        _pendingFastRefresh.remove(assetId);
      }
    }
  }

  @override
  BalanceInfo? lastKnown(AssetId assetId) {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }
    return _balanceCache[assetId];
  }

  /// Returns a cached balance only when [walletId] owns the active generation.
  BalanceInfo? lastKnownForWallet(AssetId assetId, WalletId walletId) {
    if (_isDisposed) {
      throw StateError('BalanceManager has been disposed');
    }
    final current = _currentWalletId;
    // [isSameStableWallet] is asymmetric: previously accepted identity first,
    // newly observed second. [walletId] is the caller's captured identity and
    // [current] is the latest accepted one, which may since have been enriched
    // with a pubkeyHash. Passing them the other way round read as an
    // enriched -> name-only downgrade and was rejected, so every cached-balance
    // read failed once the wallet identity gained its hash - which is what
    // makes [_BalanceStreamAttachment._attachOnce] skip its replay of the last
    // known balance and leave a freshly subscribed widget blank until a full
    // RPC round trip lands.
    // This matches [_isWalletContextCurrentSync]'s ordering.
    if (current == null || !isSameStableWallet(walletId, current)) {
      return null;
    }
    return _balanceCache[assetId];
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _walletGeneration++;
    _pendingFastRefresh.clear();

    for (final timer in _watcherTeardownTimers.values) {
      timer.cancel();
    }
    _watcherTeardownTimers.clear();
    _cancelWatcherStartRetries();

    // Dispose is the one terminal condition for a `watchBalance` stream, so
    // close the subscriber-facing controllers rather than leaving listeners
    // waiting on a stream that can no longer produce anything.
    final List<_BalanceStreamAttachment> attachments = _streamAttachments
        .toList();
    _streamAttachments.clear();
    for (final attachment in attachments) {
      attachment.close();
    }

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
        List<StreamSubscription<AssetPubkeys>>.from(_pubkeyHintWatchers.values);
    _pubkeyHintWatchers.clear();
    final List<Future<void>> hintCancelFutures = <Future<void>>[];
    for (final StreamSubscription<AssetPubkeys> sub in pubkeyHintSubs) {
      hintCancelFutures.add(
        sub.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling pubkey hint watcher', e, s);
        }),
      );
    }
    if (hintCancelFutures.isNotEmpty) {
      await Future.wait(hintCancelFutures);
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

    final WalletOperationContext walletContext;
    try {
      walletContext = await _captureWalletContext();
    } on AuthException {
      return;
    }

    // Retry logic to handle timing issues after activation
    const maxRetries = 3;
    const baseDelay = Duration(milliseconds: 200);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final balance = await _pubkeyManager!
            .getPubkeys(asset)
            .then<BalanceInfo>((pubkeys) => pubkeys.balance);
        if (!await _isWalletContextCurrent(walletContext)) return;
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
          if (!await _isWalletContextCurrent(walletContext)) return;
          continue;
        }

        // Either not a timing issue or final attempt - fail silently
        _logger.fine('Failed to pre-cache balance for ${asset.id.name}: $e');
        return;
      }
    }
  }
}

/// One caller's resilient, re-listenable view of an asset's balance stream.
///
/// [BalanceManager.watchBalance] used to be an `async*` generator, which gave
/// its result two properties nothing in its contract advertised.
///
/// It was single-subscription, so a caller could not hold one stream across a
/// `StreamBuilder` that unmounts and remounts - the second listen threw
/// `Bad state: Stream has already been listened to`. Creating a fresh stream
/// per build avoided that but flapped the shared per-asset controller 1->0->1,
/// restarting the KDF watcher on every rebuild.
///
/// And every transient failure in its preamble was permanent, because a
/// generator that throws ends the stream for good:
///
/// * [BalanceManager._captureWalletContext] throws [AuthException] when it runs
///   before the SDK has observed the signed-in user - reachable on the ordinary
///   login path, since rows render before the auth read resolves;
/// * [BalanceManager._requireWalletContextCurrent] throws
///   [WalletChangedDisconnectException] when the wallet generation moves under
///   it;
/// * [BalanceManager._resetState] pushes that same error into every cached
///   controller and closes it on any wallet change.
///
/// None of those are permanent conditions, but each one left the caller holding
/// a dead stream: a blank balance for the rest of the session.
///
/// This re-runs that preamble - capture the wallet context, replay the last
/// known balance, attach to the asset's shared controller - whenever the
/// attachment breaks, with a bounded backoff, and exposes the result as a
/// broadcast stream. Errors are still forwarded before recovery, so callers
/// keep their existing transient-error handling.
class _BalanceStreamAttachment {
  _BalanceStreamAttachment({
    required BalanceManager manager,
    required AssetId assetId,
    required bool activateIfNeeded,
  }) : _manager = manager,
       _assetId = assetId,
       _activateIfNeeded = activateIfNeeded {
    _controller = StreamController<BalanceInfo>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  /// Initial delay before re-attaching after the attachment breaks.
  static const Duration _retryDelay = Duration(milliseconds: 250);

  /// Upper bound on the re-attach backoff.
  static const Duration _maxRetryDelay = Duration(seconds: 5);

  final BalanceManager _manager;
  final AssetId _assetId;
  final bool _activateIfNeeded;

  late final StreamController<BalanceInfo> _controller;
  StreamSubscription<BalanceInfo>? _subscription;
  Timer? _retryTimer;
  int _consecutiveFailures = 0;

  /// Whether a listener is currently attached. Not a latch: a broadcast
  /// controller goes 1 -> 0 -> 1 whenever the consuming `StreamBuilder` is
  /// unmounted and remounted, and the upstream should be torn down while
  /// nobody is watching and re-established when somebody returns.
  bool _hasListener = false;

  /// An [_attach] run is in flight. Guards against a second run being started
  /// by a re-listen during the first one's `await`.
  bool _isAttaching = false;

  /// Stood down because the asset's watcher start gave up for this wallet
  /// generation. Only [wakeIfDormant] clears this.
  bool _isDormant = false;

  bool _isClosed = false;

  Stream<BalanceInfo> get stream => _controller.stream;

  void _onListen() {
    _hasListener = true;
    _isDormant = false;
    _consecutiveFailures = 0;
    _manager._streamAttachments.add(this);
    unawaited(_attach());
  }

  void _onCancel() {
    // Fires on every 1 -> 0 listener transition, not only on final teardown.
    _hasListener = false;
    _isDormant = false;
    _consecutiveFailures = 0;
    _manager._streamAttachments.remove(this);
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancelSubscription();
  }

  /// Re-attaches an attachment that stood down on a watcher-start give-up.
  ///
  /// Called by [BalanceManager._resetState] once the give-up latch is cleared.
  /// A non-dormant attachment is left alone: it either has a live subscription
  /// that is about to see the closed controller's `done` and recover on its
  /// own, or a retry already pending.
  void wakeIfDormant() {
    if (_isClosed || !_hasListener || !_isDormant) return;
    _isDormant = false;
    _consecutiveFailures = 0;
    unawaited(_attach());
  }

  void close() {
    _isClosed = true;
    _hasListener = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    // A listener that arrives after the manager is disposed re-registers this
    // attachment before discovering it has nothing to attach to, so unregister
    // here rather than relying only on [BalanceManager.dispose]'s sweep.
    _manager._streamAttachments.remove(this);
    _cancelSubscription();
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  void _cancelSubscription() {
    final subscription = _subscription;
    _subscription = null;
    // Cancelling drops any events the old subscription had already queued,
    // including the `done` from a controller closed by a state reset - which
    // is what stops a late teardown from knocking over a fresh attachment.
    unawaited(subscription?.cancel());
  }

  bool get _isStale => _isClosed || !_hasListener || _manager._isDisposed;

  Future<void> _attach() async {
    if (_isAttaching) return;
    _isAttaching = true;
    try {
      await _attachOnce();
    } finally {
      _isAttaching = false;
    }
  }

  Future<void> _attachOnce() async {
    _retryTimer?.cancel();
    _retryTimer = null;

    // Checked before [_isStale], which subsumes it: dispose is the one
    // terminal condition, and a listener that arrives after it must be told
    // rather than left waiting on a stream that can never produce again.
    if (_manager._isDisposed) {
      close();
      return;
    }
    if (_isStale) return;

    final WalletOperationContext walletContext;
    try {
      walletContext = await _manager._captureWalletContext();
    } catch (e, s) {
      _onAttachFailed(e, s, forwardError: true);
      return;
    }
    if (_isStale) return;

    // Replay the last known balance so a caller that subscribes (or
    // re-subscribes) sees a value immediately instead of a blank cell until
    // the first RPC round trip lands.
    final lastKnownBalance = _manager.lastKnownForWallet(
      _assetId,
      walletContext.walletId,
    );
    if (lastKnownBalance != null && !_controller.isClosed) {
      _controller.add(lastKnownBalance);
    }

    if (!_manager._isWalletContextCurrentSync(walletContext)) {
      _onAttachFailed(
        const WalletChangedDisconnectException(
          'Wallet changed while attaching balance stream',
        ),
        StackTrace.current,
        forwardError: true,
      );
      return;
    }

    _cancelSubscription();
    final source = _manager._controllerFor(
      _assetId,
      _activateIfNeeded,
      walletContext,
    );
    _subscription = source.stream.listen(
      (balance) {
        // A value proves the attachment is healthy again.
        _consecutiveFailures = 0;
        if (!_controller.isClosed) _controller.add(balance);
      },
      onError: (Object error, StackTrace stackTrace) {
        _onAttachFailed(error, stackTrace, forwardError: true);
      },
      // A close is a recoverable termination too: `_resetState` recycles these
      // controllers on every wallet change rather than completing them for
      // good.
      onDone: () => _onAttachFailed(
        const WalletChangedDisconnectException(
          'Balance stream closed; reconnecting',
        ),
        StackTrace.current,
      ),
      cancelOnError: true,
    );
  }

  void _onAttachFailed(
    Object error,
    StackTrace stackTrace, {
    bool forwardError = false,
  }) {
    _cancelSubscription();
    // Forwarded before recovery so callers keep their existing transient-error
    // handling (falling back to the last known balance, retry counters).
    if (forwardError && !_controller.isClosed) {
      _controller.addError(error, stackTrace);
    }
    if (_isStale) return;

    if (_manager._watcherStartGaveUp.contains(_assetId)) {
      // The watcher start has exhausted its own budget for this wallet
      // generation. Re-attaching would drive the asset's controller through
      // another 0 -> 1 listener transition and hand it a fresh one, which is
      // how two independently bounded retry layers compose into an unbounded
      // one. Stand down until [BalanceManager._resetState] clears the latch.
      BalanceManager._logger.fine(
        'Balance attachment for ${_assetId.name} standing down: watcher start '
        'gave up for this wallet generation',
      );
      _isDormant = true;
      return;
    }

    _scheduleRetry();
  }

  void _scheduleRetry() {
    _consecutiveFailures += 1;
    // Exponential, clamped. Shifting by >30 would overflow on web's 32-bit
    // ints, and the value is clamped to _maxRetryDelay long before then.
    final shift = (_consecutiveFailures - 1).clamp(0, 30);
    final delay = Duration(
      microseconds: (_retryDelay.inMicroseconds * (1 << shift)).clamp(
        _retryDelay.inMicroseconds,
        _maxRetryDelay.inMicroseconds,
      ),
    );

    BalanceManager._logger.fine(
      'Balance stream for ${_assetId.name} terminated; re-attaching in '
      '${delay.inMilliseconds}ms (attempt $_consecutiveFailures)',
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_isStale || _isDormant) return;
      unawaited(_attach());
    });
  }
}
