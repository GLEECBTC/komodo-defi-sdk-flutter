import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Interface defining the contract for pubkey management operations
abstract class IPubkeyManager {
  /// Get pubkeys for a given asset, handling HD/non-HD differences internally
  Future<AssetPubkeys> getPubkeys(Asset asset);

  /// Fetch pubkeys directly from KDF without reading or updating local caches.
  ///
  /// This is intended for security-sensitive ownership checks that must not
  /// trust a persisted or in-memory address snapshot.
  Future<AssetPubkeys> getFreshPubkeys(Asset asset);

  /// Fetch pubkeys from KDF, bypassing the in-memory cache, and store the
  /// result as the new cached value.
  ///
  /// [getPubkeys] returns `_pubkeysCache[asset.id]` verbatim whenever it is
  /// populated, and that cache has no TTL - it is written by a fresh fetch or
  /// by hydration and cleared only on wallet reset or dispose. So a caller that
  /// polls `getPubkeys` in order to *observe a change* observes nothing, for
  /// the rest of the session, with no error surfaced. This is the method such
  /// callers want.
  ///
  /// Distinct from [getFreshPubkeys], which deliberately neither reads nor
  /// writes the caches and does not join in-flight requests. This one does
  /// both, so a refresh and a concurrent [getPubkeys] miss share one round trip
  /// and agree on the result.
  Future<AssetPubkeys> refreshPubkeys(Asset asset);

  /// Watch pubkeys for a given asset, emitting the initial state if available
  /// and polling for updates at a fixed interval. Optionally activates asset.
  Stream<AssetPubkeys> watchPubkeys(
    Asset asset, {
    bool activateIfNeeded = true,
  });

  /// Get the last known pubkeys for an asset without triggering a refresh.
  /// Returns null if no pubkeys have been fetched yet.
  AssetPubkeys? lastKnown(AssetId assetId);

  /// Persisted pubkeys for [asset] without any network round trip.
  ///
  /// Reads the in-memory entry if present, otherwise hydrates from the
  /// wallet-scoped store. Unlike [getPubkeys] this **never** falls through to a
  /// fresh fetch and never activates the asset, so it is safe on paths that
  /// must not block - including inside the activation critical section, where
  /// [getPubkeys] would re-enter the coordinator and self-join.
  ///
  /// Returns null when nothing is stored, or when the store or the auth read is
  /// not usable yet. Callers treat that as "nothing to paint", not an error.
  Future<AssetPubkeys?> hydratedPubkeys(Asset asset);

  /// Create a new pubkey for an asset if supported
  Future<PubkeyInfo> createNewPubkey(Asset asset);

  /// Streamed version of [createNewPubkey]
  Stream<NewAddressState> watchCreateNewPubkey(Asset asset);

  /// Unban pubkeys according to [unbanBy] criteria
  Future<UnbanPubkeysResult> unbanPubkeys(UnbanBy unbanBy);

  /// Pre-caches pubkeys for an asset to warm the cache and notify listeners
  Future<void> precachePubkeys(Asset asset);

  /// Deletes every cached pubkey belonging to [walletId].
  ///
  /// Called when a wallet is deleted, so its derived addresses do not outlive
  /// it on disk.
  Future<void> purgeWallet(WalletId walletId);

  /// Dispose of any resources
  Future<void> dispose();
}

/// Manager responsible for handling pubkey operations across different assets
class PubkeyManager implements IPubkeyManager {
  PubkeyManager(
    this._client,
    this._auth,
    this._activationCoordinator, {
    PubkeysStorage? storage,
    DateTime Function()? now,
  }) : _storage = storage ?? HivePubkeysStorage(),
       _now = now ?? DateTime.now {
    _authSubscription = _auth.authStateChanges.listen(_handleAuthStateChanged);
    _logger.fine('Initialized');
  }
  static final Logger _logger = Logger('PubkeyManager');

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final SharedActivationCoordinator _activationCoordinator;
  final PubkeysStorage _storage;

  /// Wall clock, injectable so the scan interval below is testable.
  ///
  /// `fakeAsync` fakes timers and microtasks but not `DateTime.now()`, so a
  /// test that elapses six hours of timer time still sees no wall-clock
  /// movement - and a guard keyed on wall time would look permanent.
  final DateTime Function() _now;

  // Internal state for watching pubkeys per asset
  final Map<AssetId, AssetPubkeys> _pubkeysCache = {};

  /// Addresses ever observed holding funds, per asset. Persisted for backward
  /// compatibility with the existing wallet-scoped pubkey cache schema.
  final Map<AssetId, Set<String>> _everFundedAddresses = {};
  final Map<AssetId, StreamSubscription<dynamic>> _activeWatchers = {};
  final Map<AssetId, StreamController<AssetPubkeys>> _pubkeysControllers = {};
  // Track the Asset for each AssetId that has an associated controller so that
  // we can restart watchers after auth changes without requiring new listeners
  final Map<AssetId, Asset> _watchedAssets = {};
  // Deduplicate concurrent getPubkeys requests within one wallet generation.
  final Map<(AssetId, int), Future<AssetPubkeys>> _inFlightPubkeyRequests = {};
  final Map<String, DateTime> _hdAddressScanRetryAfter = {};
  static const Duration _hdAddressScanRetryCooldown = Duration(minutes: 2);

  /// When the address gap was last walked, per `wallet:asset`.
  ///
  /// This is the guard on the *repeat*, and it is the only thing standing
  /// between the app and a full gap walk every [_defaultPollingInterval] for
  /// the life of the session. See [_hdAddressScanInterval].
  ///
  /// Keyed exactly like [_hdAddressScanRetryAfter] so the existing bulk clears
  /// in [_resetState] and [dispose] already cover it - a wallet switch must not
  /// leak one wallet's suppression into the next.
  final Map<String, DateTime> _hdAddressScanCompletedAt = {};

  /// `wallet:asset` keys that have consumed their one post-activation skip.
  ///
  /// Separate from [_hdAddressScanCompletedAt] because the two mean different
  /// things: this records "we chose not to scan because activation was
  /// supposed to", which is not evidence that a gap was actually walked.
  final Set<String> _hdAddressScanCredit = <String>{};

  /// How long a completed address scan stands before another is worth issuing.
  ///
  /// A scan is `task::scan_for_new_addresses`, which on an empty wallet probes
  /// `gap_limit + 1` candidate addresses (see `HdGapLimit` for how that limit
  /// is chosen per wallet). For EVM each probe costs `1 + 1 + N` node RPCs on
  /// an *unused* address - `eth_getTransactionCount`, `eth_getBalance`, then
  /// one `eth_call balanceOf` per registered ERC-20
  /// (`mm2src/coins/eth/eth_hd_wallet.rs:125-150`, `mm2src/coins/eth.rs:5107`).
  /// The nonce short-circuit only fires on addresses that *are* used, so a gap
  /// walk pays the full price every time. At the full BIP-44 gap, GLEEC with
  /// its six GRC-20 tokens is 21 x 8 = 168 requests per scan; at one scan per
  /// 30s tick that was ~336 requests a minute against an endpoint measured at
  /// ~20 req/s, forever.
  ///
  /// An HD address set cannot change without an on-chain transaction to an
  /// address this wallet has not derived yet, which in practice means the seed
  /// being used somewhere else at the same time. Six hours bounds the discovery
  /// latency for that while making the steady-state cost negligible. It is
  /// deliberately not "once per session": a session can outlive a day.
  static const Duration _hdAddressScanInterval = Duration(hours: 6);

  StreamSubscription<KdfUser?>? _authSubscription;
  WalletId? _currentWalletId;
  int _walletGeneration = 0;
  bool _isDisposed = false;
  final Duration _defaultPollingInterval = const Duration(seconds: 30);

  /// Get pubkeys for a given asset, handling HD/non-HD differences internally
  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async {
    if (_isDisposed) {
      throw StateError('PubkeyManager has been disposed');
    }

    // Authenticate before looking at wallet-owned caches. Auth stream delivery
    // can lag behind currentUser during a wallet switch.
    final walletContext = await _captureWalletContext();

    // Serve from in-memory cache if available
    final cached = _pubkeysCache[asset.id];
    if (cached != null) {
      await _requireWalletContextCurrent(walletContext);
      return cached;
    }

    // If a network fetch for this asset and wallet generation is already in
    // flight, await it. A previous wallet's future must never be reused.
    final inFlightKey = (asset.id, walletContext.generation);
    final existing = _inFlightPubkeyRequests[inFlightKey];
    if (existing != null) {
      final pubkeys = await existing;
      await _requireWalletContextCurrent(walletContext);
      return pubkeys;
    }

    // Try to hydrate from persisted storage first for instant response
    final hydrated = await _hydrateFromStorageForWallet(walletContext, asset);
    await _requireWalletContextCurrent(walletContext);
    if (hydrated != null) {
      _pubkeysCache[asset.id] = hydrated;
      // Fire-and-forget fresh refresh; deduped if one is already running
      final refreshFuture = _fetchFreshPubkeys(asset, walletContext)
          .then((fresh) {
            final controller = _pubkeysControllers[asset.id];
            if (_isWalletContextCurrentSync(walletContext) &&
                controller != null &&
                !controller.isClosed &&
                fresh != hydrated) {
              controller.add(fresh);
            }
          })
          .catchError((_) {
            // best-effort background refresh
          });
      refreshFuture.ignore();
      return hydrated;
    }

    // No hydration available, fetch fresh
    final pubkeys = await _fetchFreshPubkeys(asset, walletContext);
    await _requireWalletContextCurrent(walletContext);
    return pubkeys;
  }

  @override
  Future<AssetPubkeys?> hydratedPubkeys(Asset asset) async {
    if (_isDisposed) return null;

    try {
      // Capture before touching the cache. This call is what proactively
      // detects a wallet switch the auth stream has not delivered yet, and
      // clears `_pubkeysCache` via `_resetState` when it finds one. Reading the
      // cache first would hand back the *previous* wallet's pubkeys, which
      // `BalanceManager._emitHydratedBalance` then paints as a balance under
      // the new wallet. `getPubkeys` and `watchPubkeys` order it this way for
      // the same reason.
      final walletContext = await _captureWalletContext();

      // Deliberately does not write to `_pubkeysCache`. `getPubkeys` returns a
      // cache hit verbatim and only schedules its background refresh on the
      // *hydration* branch, so seeding the cache here would make a stored value
      // permanently authoritative and stop it ever being refreshed.
      final cached = _pubkeysCache[asset.id];
      if (cached != null) return cached;

      final hydrated = await _hydrateFromStorageForWallet(walletContext, asset);
      if (hydrated == null) return null;
      return _isWalletContextCurrentSync(walletContext) ? hydrated : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AssetPubkeys> getFreshPubkeys(Asset asset) async {
    if (_isDisposed) {
      throw StateError('PubkeyManager has been disposed');
    }

    final walletContext = await _captureWalletContext();
    await _requireWalletContextCurrent(walletContext);
    await retry(() => _activationCoordinator.activateAsset(asset));
    await _requireWalletContextCurrent(walletContext);
    final strategy = await _resolvePubkeyStrategy(asset);
    await _requireWalletContextCurrent(walletContext);
    final pubkeys = await strategy.getPubkeys(asset.id, _client);
    await _requireWalletContextCurrent(walletContext);
    return pubkeys;
  }

  @override
  Future<AssetPubkeys> refreshPubkeys(Asset asset) async {
    if (_isDisposed) {
      throw StateError('PubkeyManager has been disposed');
    }

    // Capture first, exactly as [getPubkeys] does: this is what proactively
    // detects a wallet switch the auth stream has not delivered yet and clears
    // the caches, so the fetch below cannot commit into the wrong wallet.
    final walletContext = await _captureWalletContext();
    final pubkeys = await _fetchFreshPubkeys(asset, walletContext);
    await _requireWalletContextCurrent(walletContext);
    return pubkeys;
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
      // branch in [_handleAuthStateChanged].
      operationWalletId = currentWalletId;
    } else {
      // Auth streams are asynchronous. Invalidate proactively so a caller
      // cannot observe the prior wallet's cache before the event arrives.
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
    // Continues-session, not same-stable: the fresh read can observe the same
    // wallet degraded to name-only while the identity RPC is down, which
    // [_captureWalletContext] deliberately admits - rejecting it here would
    // fail the operation during the exact blip that branch tolerates.
    return currentUser != null &&
        _isWalletContextCurrentSync(context) &&
        walletIdentityContinuesSession(context.walletId, currentUser.walletId);
  }

  Future<void> _requireWalletContextCurrent(
    WalletOperationContext context,
  ) async {
    if (await _isWalletContextCurrent(context)) return;
    throw const WalletChangedDisconnectException(
      'Wallet changed while fetching pubkeys',
    );
  }

  /// Create a new pubkey for an asset if supported
  @override
  Future<PubkeyInfo> createNewPubkey(Asset asset) async {
    await retry(() => _activationCoordinator.activateAsset(asset));
    final strategy = await _resolvePubkeyStrategy(asset);
    if (!strategy.supportsMultipleAddresses) {
      throw UnsupportedError(
        'Asset ${asset.id.name} does not support multiple addresses',
      );
    }
    return strategy.getNewAddress(asset.id, _client);
  }

  /// Streamed version of [createNewPubkey]
  @override
  Stream<NewAddressState> watchCreateNewPubkey(Asset asset) async* {
    await retry(() => _activationCoordinator.activateAsset(asset));
    final strategy = await _resolvePubkeyStrategy(asset);
    if (!strategy.supportsMultipleAddresses) {
      yield NewAddressState.error(
        'Asset ${asset.id.name} does not support multiple addresses',
      );
      return;
    }
    yield* strategy.getNewAddressStream(asset.id, _client);
  }

  /// Unban pubkeys according to [unbanBy] criteria
  @override
  Future<UnbanPubkeysResult> unbanPubkeys(UnbanBy unbanBy) async {
    final response = await _client.rpc.wallet.unbanPubkeys(unbanBy: unbanBy);
    return response.result;
  }

  Future<PubkeyStrategy> _resolvePubkeyStrategy(Asset asset) async {
    final currentUser = await _auth.currentUser;
    if (currentUser == null) {
      throw AuthException.notSignedIn();
    }
    return asset.pubkeyStrategy(
      kdfUser: currentUser,
      scanGapLimit: HdGapLimit.resolve(
        privKeyPolicy: currentUser.walletId.authOptions.privKeyPolicy,
        // Session-scoped, so this is true only on the sign-in that created the
        // wallet. A later sign-in of the same generated wallet gets the normal
        // software gap, because by then it could have received funds at an
        // address this app never derived.
        isNewlyGeneratedFirstSignIn: currentUser.isGeneratedThisSession,
      ),
    );
  }

  // Perform a fresh network fetch for pubkeys, deduplicated per asset
  Future<AssetPubkeys> _fetchFreshPubkeys(
    Asset asset,
    WalletOperationContext walletContext,
  ) async {
    final inFlightKey = (asset.id, walletContext.generation);
    final existing = _inFlightPubkeyRequests[inFlightKey];
    if (existing != null) return existing;

    final future = () async {
      await _requireWalletContextCurrent(walletContext);
      await retry(() => _activationCoordinator.activateAsset(asset));
      await _requireWalletContextCurrent(walletContext);
      final strategy = await _resolvePubkeyStrategy(asset);
      await _requireWalletContextCurrent(walletContext);
      await _scanForNewHdAddressesIfNeeded(
        walletContext: walletContext,
        asset: asset,
        strategy: strategy,
        // A *fresh* activation already made KDF walk the address gap:
        // `UtxoProtocol.defaultActivationParams` sends
        // `scan_policy: scan_if_new_wallet` with `gap_limit: 20`. Asking for
        // `task::scan_for_new_addresses` on top of that is the same walk
        // again, immediately, for nothing.
        //
        // Measured on a real KDF (KMD, HD, fresh wallet): activation took 47s
        // and the scan that followed spent its entire 20s deadline before
        // giving up with `TimeoutException: Timed out scanning for new
        // addresses`, which this method then swallows and continues past. So
        // the second walk contributed 20 of the 89 seconds to first balance
        // and changed nothing about the result.
        alreadyScannedByActivation: _activationAlreadyScanned(asset),
      );
      await _requireWalletContextCurrent(walletContext);
      final raw = await strategy.getPubkeys(asset.id, _client);
      await _requireWalletContextCurrent(walletContext);
      final everFunded = _observeFundedAddresses(asset.id, raw.keys);
      // Preserve KDF's complete typed GasFree-address response in the generic
      // SDK; products may apply a narrower address policy at their boundary.
      _pubkeysCache[asset.id] = raw;
      _persistPubkeysForWallet(walletContext, asset, raw, everFunded).ignore();
      return raw;
    }();

    _inFlightPubkeyRequests[inFlightKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightPubkeyRequests[inFlightKey], future)) {
        _inFlightPubkeyRequests.remove(inFlightKey)?.ignore();
      }
    }
  }

  /// Stream of pubkeys per asset. Polls pubkeys (not balances) and emits updates.
  /// Emits the initial known state if available.
  @override
  Stream<AssetPubkeys> watchPubkeys(
    Asset asset, {
    bool activateIfNeeded = true,
  }) async* {
    if (_isDisposed) {
      throw StateError('PubkeyManager has been disposed');
    }

    final walletContext = await _captureWalletContext();

    // Emit last known pubkeys only after confirming who owns the cache.
    final lastKnown = _pubkeysCache[asset.id];
    if (lastKnown != null) {
      await _requireWalletContextCurrent(walletContext);
      yield lastKnown;
      await _requireWalletContextCurrent(walletContext);
    }

    await _requireWalletContextCurrent(walletContext);
    final controller = _pubkeysControllers.putIfAbsent(asset.id, () {
      late final StreamController<AssetPubkeys> createdController;
      createdController = StreamController<AssetPubkeys>.broadcast(
        onListen: () {
          if (!_isWalletContextCurrentSync(walletContext) ||
              !identical(_pubkeysControllers[asset.id], createdController)) {
            return;
          }
          _logger.fine(
            'onListen: ${asset.id.name}, activateIfNeeded: $activateIfNeeded',
          );
          _startWatchingPubkeys(asset, activateIfNeeded);
        },
        onCancel: () {
          _logger.fine('onCancel: ${asset.id.name}');
          if (!identical(_pubkeysControllers[asset.id], createdController)) {
            return;
          }
          _stopWatchingPubkeys(asset.id, expectedController: createdController);
          _watchedAssets.remove(asset.id);
        },
      );
      return createdController;
    });
    // Remember the Asset so we can restart the watcher after a reset
    _watchedAssets[asset.id] = asset;

    yield* controller.stream;
  }

  @override
  AssetPubkeys? lastKnown(AssetId assetId) {
    if (_isDisposed) {
      throw StateError('PubkeyManager has been disposed');
    }
    return _pubkeysCache[assetId];
  }

  /// Returns cached pubkeys only when [walletId] owns the active generation.
  AssetPubkeys? lastKnownForWallet(AssetId assetId, WalletId walletId) {
    if (_isDisposed) {
      throw StateError('PubkeyManager has been disposed');
    }
    final current = _currentWalletId;
    // Asymmetric comparison: caller's captured identity first, latest accepted
    // identity second. See the matching note in `BalanceManager` - reversed,
    // this rejects the legitimate name-only -> pubkeyHash-enriched transition
    // and the cache never hits.
    if (current == null || !isSameStableWallet(walletId, current)) {
      return null;
    }
    return _pubkeysCache[assetId];
  }

  // Removed unused non-wallet-stable helpers to avoid confusion

  /// Records addresses currently holding funds into the per-asset ever-funded
  /// set and returns it.
  Set<String> _observeFundedAddresses(
    AssetId assetId,
    Iterable<PubkeyInfo> keys,
  ) {
    final everFunded = _everFundedAddresses.putIfAbsent(assetId, () => {});
    for (final key in keys) {
      if (key.balance.hasValue) everFunded.add(key.address);
    }
    return everFunded;
  }

  // Wallet-stable variants to avoid cross-wallet contamination during async ops
  Future<void> _persistPubkeysForWallet(
    WalletOperationContext walletContext,
    Asset asset,
    AssetPubkeys pubkeys, [
    Set<String> everFundedAddresses = const {},
  ]) async {
    if (!_isWalletContextCurrentSync(walletContext)) return;
    try {
      await _storage.savePubkeys(
        walletContext.walletId,
        asset.id.id,
        pubkeys,
        everFundedAddresses: everFundedAddresses,
      );
    } catch (_) {
      // best-effort persistence
    }
  }

  Future<AssetPubkeys?> _hydrateFromStorageForWallet(
    WalletOperationContext walletContext,
    Asset asset,
  ) async {
    try {
      final map = await _storage.listForWallet(walletContext.walletId);
      final raw = map[asset.id.id];
      if (raw == null) return null;

      final addresses =
          (raw['addresses'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      final keys = <PubkeyInfo>[];
      final storedEverFunded = <String>{};
      for (final addr in addresses) {
        final bal = BalanceInfo.fromJson(
          (addr['balance'] as Map).cast<String, dynamic>(),
        );
        final address = addr['address'] as String;
        if (addr['ever_funded'] == true) storedEverFunded.add(address);
        keys.add(
          PubkeyInfo(
            address: address,
            derivationPath: addr['derivation_path'] as String?,
            chain: addr['chain'] as String?,
            balance: bal,
            coinTicker: asset.id.id,
            gasfreeAddress:
                addr['gasfree_address'] as String? ??
                addr['gasfreeAddress'] as String?,
          ),
        );
      }

      final available = (raw['available'] as num?)?.toInt() ?? keys.length;
      final syncString = raw['sync'] as String?;
      final sync =
          SyncStatusEnum.tryParse(syncString) ?? SyncStatusEnum.success;

      await _requireWalletContextCurrent(walletContext);
      _everFundedAddresses
          .putIfAbsent(asset.id, () => {})
          .addAll(storedEverFunded);
      _observeFundedAddresses(asset.id, keys);

      return AssetPubkeys(
        assetId: asset.id,
        keys: keys,
        availableAddressesCount: available,
        syncStatus: sync,
      );
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<void> _startWatchingPubkeys(Asset asset, bool activateIfNeeded) async {
    final controller = _pubkeysControllers[asset.id];
    if (controller == null || _isDisposed) return;

    // Cancel any existing watcher for this asset
    final previousWatcher = _activeWatchers.remove(asset.id);
    await previousWatcher?.cancel();

    final WalletOperationContext walletContext;
    try {
      walletContext = await _captureWalletContext();
    } on AuthException {
      _logger.fine(
        'Delaying watcher start for ${asset.id.name}: unauthenticated',
      );
      return;
    }
    if (controller.isClosed || !_isWalletContextCurrentSync(walletContext)) {
      return;
    }
    if (!identical(_pubkeysControllers[asset.id], controller)) return;
    _logger.fine('Starting watcher for ${asset.id.name}');

    // Last value handed to [controller], so the 30s poll below can drop
    // no-op re-emissions. Addresses change rarely; re-emitting an identical
    // snapshot every tick made the app's `CoinAddressesBloc` cycle through its
    // `submitting` state with an empty address list, so the coin page's
    // addresses section blanked to a spinner twice a minute for no reason.
    AssetPubkeys? lastEmitted;

    void emit(AssetPubkeys pubkeys) {
      if (controller.isClosed || !_isWalletContextCurrentSync(walletContext)) {
        return;
      }
      if (lastEmitted == pubkeys) return;
      lastEmitted = pubkeys;
      controller.add(pubkeys);
    }

    try {
      // Ensure activation if requested, otherwise only proceed if already active
      bool isActive = await _activationCoordinator.isAssetActive(asset.id);
      await _requireWalletContextCurrent(walletContext);
      if (!isActive && activateIfNeeded) {
        final activationResult = await _activationCoordinator.activateAsset(
          asset,
        );
        await _requireWalletContextCurrent(walletContext);
        isActive = activationResult.isSuccess;
      }

      if (isActive) {
        // Re-emit this wallet's in-memory state to the shared controller, or
        // hydrate persisted state when the watcher starts cold.
        final hydrated =
            _pubkeysCache[asset.id] ??
            await _hydrateFromStorageForWallet(walletContext, asset);
        await _requireWalletContextCurrent(walletContext);
        if (hydrated != null) {
          _pubkeysCache[asset.id] = hydrated;
          emit(hydrated);
        }

        final first = await _fetchFreshPubkeys(asset, walletContext);
        await _requireWalletContextCurrent(walletContext);
        _pubkeysCache[asset.id] = first;
        emit(first);
        _logger.fine('Emitted initial pubkeys for ${asset.id.name}');
      }

      // Periodic polling for pubkeys updates
      final periodicStream = Stream<void>.periodic(_defaultPollingInterval);
      late final StreamSubscription<dynamic> subscription;
      subscription = periodicStream
          .asyncMap<AssetPubkeys?>((_) async {
            if (!await _isWalletContextCurrent(walletContext)) {
              return null;
            }

            try {
              bool active = await _activationCoordinator.isAssetActive(
                asset.id,
              );
              if (!await _isWalletContextCurrent(walletContext)) return null;
              if (!active && activateIfNeeded) {
                final activationResult = await _activationCoordinator
                    .activateAsset(asset);
                if (!await _isWalletContextCurrent(walletContext)) return null;
                active = activationResult.isSuccess;
              }
              if (active) {
                final pubkeys = await _fetchFreshPubkeys(asset, walletContext);
                if (!await _isWalletContextCurrent(walletContext)) return null;
                _pubkeysCache[asset.id] = pubkeys;
                return pubkeys;
              }
            } catch (_) {
              // Swallow transient errors; continue with last known state
            }
            if (!_isWalletContextCurrentSync(walletContext)) return null;
            return _pubkeysCache[asset.id];
          })
          .listen(
            (AssetPubkeys? pubkeys) {
              if (pubkeys != null) emit(pubkeys);
            },
            onError: (Object error) {
              if (!controller.isClosed &&
                  _isWalletContextCurrentSync(walletContext)) {
                controller.addError(error);
              }
            },
            onDone: () =>
                _stopWatchingPubkeys(asset.id, expected: subscription),
            cancelOnError: false,
          );
      if (_isWalletContextCurrentSync(walletContext) && !controller.isClosed) {
        if (identical(_pubkeysControllers[asset.id], controller)) {
          _activeWatchers[asset.id] = subscription;
        } else {
          await subscription.cancel();
        }
      } else {
        await subscription.cancel();
      }
    } on WalletChangedDisconnectException {
      // The auth-change reset owns disconnection and cleanup.
      return;
    } catch (e) {
      if (!controller.isClosed) {
        if (e is ActivationFailedException) {
          controller.addError(e);
        } else {
          // Wrap other errors in ActivationFailedException for consistency
          controller.addError(
            ActivationFailedException(
              assetId: asset.id,
              message: e.toString(),
              errorCode: 'PUBKEY_ACTIVATION_ERROR',
              originalError: e,
            ),
          );
        }
      }
    }
  }

  void _stopWatchingPubkeys(
    AssetId assetId, {
    StreamSubscription<dynamic>? expected,
    StreamController<AssetPubkeys>? expectedController,
  }) {
    if (expectedController != null &&
        !identical(_pubkeysControllers[assetId], expectedController)) {
      return;
    }
    final watcher = _activeWatchers[assetId];
    if (expected != null && !identical(watcher, expected)) return;
    if (watcher != null) {
      watcher.cancel();
      _activeWatchers.remove(assetId);
      _logger.fine('Stopped watcher for ${assetId.name}');
    }
  }

  @override
  Future<void> precachePubkeys(Asset asset) async {
    if (_isDisposed) return;

    try {
      final walletContext = await _captureWalletContext();
      final pubkeys = await getPubkeys(asset);
      await _requireWalletContextCurrent(walletContext);
      _pubkeysCache[asset.id] = pubkeys;

      final controller = _pubkeysControllers[asset.id];
      if (controller != null &&
          !controller.isClosed &&
          _isWalletContextCurrentSync(walletContext)) {
        controller.add(pubkeys);
      }
    } catch (_) {
      // Fail silently; this is a best-effort cache warm-up
    }
  }

  Future<void> _handleAuthStateChanged(KdfUser? user) async {
    if (_isDisposed) return;
    final newWalletId = user?.walletId;
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

    // Same wallet observed without its pubkeyHash because the identity RPC is
    // temporarily unavailable - not a wallet switch. Resetting here would drop
    // every cached pubkey set for a wallet that never changed, and the RPC is
    // most likely to blip precisely when KDF is saturated with login
    // activations. See [isDegradedWalletIdentity].
    if (currentWalletId != null &&
        newWalletId != null &&
        isDegradedWalletIdentity(currentWalletId, newWalletId)) {
      _logger.warning(
        'Ignoring a degraded wallet identity for ${currentWalletId.name} '
        '(identity RPC unavailable); keeping pubkey state',
      );
      return;
    }

    // Invalidate before awaiting cleanup so an already-completing RPC cannot
    // commit into the next wallet's cache during the reset window.
    _walletGeneration++;
    _currentWalletId = newWalletId;
    await _resetState();
  }

  /// Whether this session's activation of [asset] already walked the address
  /// gap, making the *immediately following* [_scanForNewHdAddressesIfNeeded] a
  /// duplicate of it.
  ///
  /// Both conditions matter. The activation must have actually happened this
  /// session (a warm re-login finds the asset already enabled and scans
  /// nothing), and the protocol's activation params must carry a scanning
  /// policy - `UtxoProtocol` sends `scan_policy: scan_if_new_wallet`.
  ///
  /// The ETH-family params carry no `scan_policy` field, and this deliberately
  /// still returns false for them - but **not** for the reason that used to be
  /// written here. The old comment concluded that ETH-family "HD address
  /// discovery is *not* covered by activation and must still scan". The premise
  /// is true of the Dart; the conclusion is false, and it is what made a gap
  /// walk on every 30-second poll look intentional.
  ///
  /// What KDF actually does: `EthActivationV2Request` carries
  /// `#[serde(flatten)] pub enable_params: EnabledCoinBalanceParams`
  /// (`mm2src/coins/eth/v2_activation.rs:249-250`), so an absent `scan_policy`
  /// takes its serde default, and that default is `ScanIfNewWallet`, not
  /// `DoNotScan` (`mm2src/coins/coin_balance.rs:159-178`). So ETH-family
  /// activation *does* walk the gap - but only down one of two branches:
  ///
  ///  * HD account **absent** from KDF's wallet storage (a first-ever
  ///    activation of this coin for this wallet): `coin_balance.rs:532-535`
  ///    accepts `ScanIfNewWallet` and walks.
  ///  * HD account **present** (every activation after that; accounts persist
  ///    to sqlite/IndexedDB): `coin_balance.rs:577` requires `Scan`, so the
  ///    default does *not* walk.
  ///
  /// The SDK cannot see which branch KDF took, and guessing wrong in the
  /// "already scanned" direction would silently disable address discovery on
  /// every warm re-login. So the redundant post-activation walk on a first-ever
  /// activation is knowingly left in place - it costs one scan, once - and the
  /// repeat is bounded by [_hdAddressScanInterval] instead, which is where
  /// essentially all of the cost was.
  bool _activationAlreadyScanned(Asset asset) {
    if (!_activationCoordinator.wasFreshlyActivated(asset.id)) return false;
    try {
      final policy = asset.protocol.defaultActivationParams().scanPolicy;
      return policy != null && policy != ScanPolicy.doNotScan;
    } catch (_) {
      // A protocol that cannot build default params tells us nothing; scan.
      return false;
    }
  }

  Future<void> _scanForNewHdAddressesIfNeeded({
    required WalletOperationContext walletContext,
    required Asset asset,
    required PubkeyStrategy strategy,
    bool alreadyScannedByActivation = false,
  }) async {
    if (!strategy.supportsMultipleAddresses) {
      return;
    }

    final scanKey = '${walletContext.walletId.compoundId}:${asset.id.id}';
    final now = _now();

    // Skip the walk KDF has just done - once.
    //
    // Deliberately does *not* arm [_hdAddressScanInterval]. This branch only
    // knows that the protocol asked KDF to scan, not that KDF actually walked:
    // `scan_policy: scan_if_new_wallet` walks only when KDF has no stored HD
    // account for the coin (`mm2src/coins/coin_balance.rs:519-535`), so on
    // every launch after the first, activation runs, this credit is granted,
    // and nothing was walked. Arming a six-hour interval off that would delay
    // real address discovery on every warm re-login.
    //
    // So the credit is consumed once and the *next* fetch does a real scan,
    // which is what arms the interval. That is one scan per session rather
    // than one every 30 seconds, and it is bounded from then on.
    if (alreadyScannedByActivation && _hdAddressScanCredit.add(scanKey)) {
      _logger.info(
        'Skipping HD address scan for ${asset.id.id}: activation already '
        'scanned with the same gap limit',
      );
      return;
    }

    // The repeat guard. `watchPubkeys` calls `_fetchFreshPubkeys` on every
    // 30-second tick and nothing else bounds a *successful* scan -
    // `_hdAddressScanRetryAfter` below is a failure-only cooldown and is
    // cleared on success, and `_inFlightPubkeyRequests` only joins concurrent
    // fetches, never sequential ones.
    final completedAt = _hdAddressScanCompletedAt[scanKey];
    if (completedAt != null &&
        now.difference(completedAt) < _hdAddressScanInterval) {
      return;
    }

    final retryAfter = _hdAddressScanRetryAfter[scanKey];
    if (retryAfter != null && now.isBefore(retryAfter)) {
      return;
    }

    try {
      await strategy.scanForNewAddresses(asset.id, _client);
      await _requireWalletContextCurrent(walletContext);
      _hdAddressScanRetryAfter.remove(scanKey);
      // Stamped after the await, not before: a scan that threw must not arm
      // the interval, or one failure would suppress retries for six hours.
      _hdAddressScanCompletedAt[scanKey] = _now();
    } catch (error, stackTrace) {
      if (!await _isWalletContextCurrent(walletContext)) {
        throw const WalletChangedDisconnectException(
          'Wallet changed while scanning for pubkeys',
        );
      }
      _hdAddressScanRetryAfter[scanKey] = _now().add(
        _hdAddressScanRetryCooldown,
      );
      _logger.warning(
        'HD address scan failed for ${asset.id.name}; continuing with '
        'existing pubkeys',
        error,
        stackTrace,
      );
    }
  }

  /// Called when authentication state changes to do the following:
  /// - clear active watchers by canceling all subscriptions
  /// - close all controllers after indicating disconnection with state error
  /// - clear pubkey caches
  ///
  /// Note: This method does NOT restart watchers. New watchers will be created
  /// on-demand when clients call watchPubkeys() again.
  Future<void> _resetState() async {
    _logger.fine('Resetting state');
    final stopwatch = Stopwatch()..start();

    // Clear wallet-owned values before awaiting cancellation. A stale
    // operation keeps its generation token and cannot repopulate these maps.
    _pubkeysCache.clear();
    _everFundedAddresses.clear();
    _inFlightPubkeyRequests.clear();
    _hdAddressScanRetryAfter.clear();
    _hdAddressScanCompletedAt.clear();
    _hdAddressScanCredit.clear();
    _watchedAssets.clear();

    // Cancel all active watchers concurrently
    final List<StreamSubscription<dynamic>> watcherSubs = _activeWatchers.values
        .toList();
    _activeWatchers.clear();

    // Snapshot controllers before the first await. A newer wallet may create
    // its own controllers while the old subscriptions are being cancelled.
    final List<StreamController<AssetPubkeys>> controllers = _pubkeysControllers
        .values
        .toList();
    _pubkeysControllers.clear();

    final List<Future<void>> subscriptionCancelFutures = <Future<void>>[];
    for (final subscription in watcherSubs) {
      subscriptionCancelFutures.add(
        subscription.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling pubkey watcher', e, s);
        }),
      );
    }

    if (subscriptionCancelFutures.isNotEmpty) {
      await Future.wait(subscriptionCancelFutures);
    }

    // Close all controllers concurrently
    final List<Future<void>> controllerCloseFutures = <Future<void>>[];
    for (final controller in controllers) {
      if (!controller.isClosed) {
        // Add error to signal disconnection before closing
        controller.addError(
          const WalletChangedDisconnectException(
            'Wallet changed, reconnecting pubkey watchers',
          ),
        );

        controllerCloseFutures.add(
          controller.close().catchError((Object e, StackTrace s) {
            _logger.warning('Error closing pubkey controller', e, s);
          }),
        );
      }
    }

    if (controllerCloseFutures.isNotEmpty) {
      await Future.wait(controllerCloseFutures);
    }

    stopwatch.stop();
    _logger.fine(
      'State reset completed in ${stopwatch.elapsedMilliseconds}ms '
      '(subscriptions: ${watcherSubs.length}, controllers: ${controllers.length})',
    );
  }

  @override
  Future<void> purgeWallet(WalletId walletId) async {
    await _storage.purgeWallet(walletId);
    // Drop the in-memory view too when the deleted wallet is the one loaded,
    // so nothing can repopulate the box from a cache that outlived it.
    final current = _currentWalletId;
    if (current != null && isSameStableWallet(current, walletId)) {
      await _resetState();
    }
  }

  /// Dispose of any resources
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _walletGeneration++;
    _currentWalletId = null;
    _pubkeysCache.clear();
    _everFundedAddresses.clear();
    _inFlightPubkeyRequests.clear();
    _hdAddressScanRetryAfter.clear();
    _hdAddressScanCompletedAt.clear();
    _hdAddressScanCredit.clear();

    // Collect all async cleanup operations and run them concurrently.
    final List<Future<void>> pending = <Future<void>>[];

    final StreamSubscription<KdfUser?>? authSub = _authSubscription;
    _authSubscription = null;
    if (authSub != null) {
      pending.add(authSub.cancel());
    }

    final List<StreamSubscription<dynamic>> watcherSubs = _activeWatchers.values
        .toList();
    _activeWatchers.clear();
    for (final StreamSubscription<dynamic> subscription in watcherSubs) {
      pending.add(
        subscription.cancel().catchError((Object e, StackTrace s) {
          _logger.warning('Error cancelling pubkey watcher', e, s);
        }),
      );
    }

    final List<StreamController<AssetPubkeys>> controllers = _pubkeysControllers
        .values
        .toList();
    _pubkeysControllers.clear();
    for (final StreamController<AssetPubkeys> controller in controllers) {
      pending.add(
        controller.close().catchError((Object e, StackTrace s) {
          _logger.warning('Error closing pubkey controller', e, s);
        }),
      );
    }

    try {
      if (pending.isNotEmpty) {
        await Future.wait(pending);
      }
    } catch (error, stackTrace) {
      // Swallow errors during disposal to ensure best-effort cleanup
      _logger.warning('Error during PubkeyManager disposal', error, stackTrace);
    }

    _watchedAssets.clear();
    _logger.fine('Disposed');
  }
}
