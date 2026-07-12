import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Interface defining the contract for pubkey management operations
abstract class IPubkeyManager {
  /// Get pubkeys for a given asset, handling HD/non-HD differences internally
  Future<AssetPubkeys> getPubkeys(Asset asset);

  /// Watch pubkeys for a given asset, emitting the initial state if available
  /// and polling for updates at a fixed interval. Optionally activates asset.
  Stream<AssetPubkeys> watchPubkeys(
    Asset asset, {
    bool activateIfNeeded = true,
  });

  /// Get the last known pubkeys for an asset without triggering a refresh.
  /// Returns null if no pubkeys have been fetched yet.
  AssetPubkeys? lastKnown(AssetId assetId);

  /// Create a new pubkey for an asset if supported
  Future<PubkeyInfo> createNewPubkey(Asset asset);

  /// Streamed version of [createNewPubkey]
  Stream<NewAddressState> watchCreateNewPubkey(Asset asset);

  /// Unban pubkeys according to [unbanBy] criteria
  Future<UnbanPubkeysResult> unbanPubkeys(UnbanBy unbanBy);

  /// Pre-caches pubkeys for an asset to warm the cache and notify listeners
  Future<void> precachePubkeys(Asset asset);

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
  }) : _storage = storage ?? HivePubkeysStorage() {
    _authSubscription = _auth.authStateChanges.listen(_handleAuthStateChanged);
    _logger.fine('Initialized');
  }
  static final Logger _logger = Logger('PubkeyManager');

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final SharedActivationCoordinator _activationCoordinator;
  final PubkeysStorage _storage;

  // Internal state for watching pubkeys per asset
  final Map<AssetId, AssetPubkeys> _pubkeysCache = {};

  /// Addresses ever observed holding funds, per asset. Feeds the TRON gasless
  /// phantom-address filter (see [filterGaslessPhantomAddresses]) and is
  /// persisted with the pubkeys so used-then-emptied addresses stay visible
  /// across restarts.
  final Map<AssetId, Set<String>> _everFundedAddresses = {};
  final Map<AssetId, StreamSubscription<dynamic>> _activeWatchers = {};
  final Map<AssetId, StreamController<AssetPubkeys>> _pubkeysControllers = {};
  // Track the Asset for each AssetId that has an associated controller so that
  // we can restart watchers after auth changes without requiring new listeners
  final Map<AssetId, Asset> _watchedAssets = {};
  // Deduplicate concurrent getPubkeys requests per asset
  final Map<AssetId, Future<AssetPubkeys>> _inFlightPubkeyRequests = {};
  final Map<String, DateTime> _hdAddressScanRetryAfter = {};
  static const Duration _hdAddressScanRetryCooldown = Duration(minutes: 2);

  StreamSubscription<KdfUser?>? _authSubscription;
  WalletId? _currentWalletId;
  bool _isDisposed = false;
  final Duration _defaultPollingInterval = const Duration(seconds: 30);

  /// Get pubkeys for a given asset, handling HD/non-HD differences internally
  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async {
    // Serve from in-memory cache if available
    final cached = _pubkeysCache[asset.id];
    if (cached != null) {
      return cached;
    }

    // If a network fetch for this asset is already in flight, await it
    final existing = _inFlightPubkeyRequests[asset.id];
    if (existing != null) {
      return existing;
    }

    // Capture wallet id at start to avoid cross-wallet persistence
    final currentUser = await _auth.currentUser;
    if (currentUser == null) {
      throw AuthException.notSignedIn();
    }
    final WalletId walletId = currentUser.walletId;

    // Try to hydrate from persisted storage first for instant response
    final hydrated = await _hydrateFromStorageForWallet(walletId, asset);
    if (hydrated != null) {
      _pubkeysCache[asset.id] = hydrated;
      // Fire-and-forget fresh refresh; deduped if one is already running
      final refreshFuture = _fetchFreshPubkeys(asset, walletId)
          .then((fresh) {
            final controller = _pubkeysControllers[asset.id];
            if (controller != null &&
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
    return _fetchFreshPubkeys(asset, walletId);
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
    return asset.pubkeyStrategy(kdfUser: currentUser);
  }

  // Perform a fresh network fetch for pubkeys, deduplicated per asset
  Future<AssetPubkeys> _fetchFreshPubkeys(
    Asset asset,
    WalletId walletId,
  ) async {
    final existing = _inFlightPubkeyRequests[asset.id];
    if (existing != null) return existing;

    final future = () async {
      final retained =
          _pubkeysCache[asset.id] ??
          await _hydrateFromStorageForWallet(walletId, asset);
      await retry(() => _activationCoordinator.activateAsset(asset));
      final strategy = await _resolvePubkeyStrategy(asset);
      await _scanForNewHdAddressesIfNeeded(
        walletId: walletId,
        asset: asset,
        strategy: strategy,
      );
      final raw = await strategy.getPubkeys(asset.id, _client);
      final everFunded = _observeFundedAddresses(asset.id, raw.keys);
      final pubkeys = _retainPrimaryGasfreeAddress(
        asset,
        filterGaslessPhantomAddresses(asset, raw, everFunded: everFunded),
        retained,
      );
      _pubkeysCache[asset.id] = pubkeys;
      // `savePubkeys` replaces the record wholesale, so persisting the
      // filtered list also purges previously-cached phantom addresses.
      _persistPubkeysForWallet(walletId, asset, pubkeys, everFunded).ignore();
      return pubkeys;
    }();

    _inFlightPubkeyRequests[asset.id] = future;
    try {
      return await future;
    } finally {
      _inFlightPubkeyRequests.remove(asset.id);
    }
  }

  AssetPubkeys _retainPrimaryGasfreeAddress(
    Asset asset,
    AssetPubkeys fresh,
    AssetPubkeys? retained,
  ) {
    if (asset.protocol is! Trc20Protocol ||
        fresh.keys.isEmpty ||
        retained == null ||
        retained.keys.isEmpty) {
      return fresh;
    }
    final freshPrimary = _canonicalGasfreePrimary(fresh.keys);
    final retainedPrimary = _canonicalGasfreePrimary(retained.keys);
    if (freshPrimary == null || retainedPrimary == null) return fresh;
    final custody = retainedPrimary.gasfreeAddress?.trim();
    if (custody == null ||
        custody.isEmpty ||
        freshPrimary.address != retainedPrimary.address ||
        (freshPrimary.gasfreeAddress?.isNotEmpty ?? false)) {
      return fresh;
    }
    return AssetPubkeys(
      assetId: fresh.assetId,
      keys: [
        for (final key in fresh.keys)
          PubkeyInfo(
            address: key.address,
            derivationPath: key.derivationPath,
            chain: key.chain,
            balance: key.balance,
            coinTicker: asset.id.id,
            gasfreeAddress: key.address == freshPrimary.address
                ? custody
                : null,
            name: key.name,
          ),
      ],
      availableAddressesCount: fresh.availableAddressesCount,
      syncStatus: fresh.syncStatus,
    );
  }

  PubkeyInfo? _canonicalGasfreePrimary(List<PubkeyInfo> keys) {
    final hdPrimary = keys
        .where(
          (key) =>
              key.derivationPath ==
              GaslessCapabilityRegistry.canonicalPrimaryDerivationPath,
        )
        .toList(growable: false);
    if (hdPrimary.length == 1) return hdPrimary.single;
    if (keys.length == 1 &&
        (keys.single.derivationPath == null ||
            keys.single.derivationPath!.isEmpty)) {
      return keys.single;
    }
    return null;
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

    // Emit last known pubkeys immediately if available
    final lastKnown = _pubkeysCache[asset.id];
    if (lastKnown != null) {
      yield lastKnown;
    }

    final controller = _pubkeysControllers.putIfAbsent(
      asset.id,
      () => StreamController<AssetPubkeys>.broadcast(
        onListen: () {
          _logger.fine(
            'onListen: ${asset.id.name}, activateIfNeeded: $activateIfNeeded',
          );
          _startWatchingPubkeys(asset, activateIfNeeded);
        },
        onCancel: () {
          _logger.fine('onCancel: ${asset.id.name}');
          _stopWatchingPubkeys(asset.id);
          _watchedAssets.remove(asset.id);
        },
      ),
    );
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
    WalletId walletId,
    Asset asset,
    AssetPubkeys pubkeys, [
    Set<String> everFundedAddresses = const {},
  ]) async {
    try {
      await _storage.savePubkeys(
        walletId,
        asset.id.id,
        pubkeys,
        everFundedAddresses: everFundedAddresses,
      );
    } catch (_) {
      // best-effort persistence
    }
  }

  Future<AssetPubkeys?> _hydrateFromStorageForWallet(
    WalletId walletId,
    Asset asset,
  ) async {
    try {
      final map = await _storage.listForWallet(walletId);
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

      final everFunded = _everFundedAddresses.putIfAbsent(asset.id, () => {})
        ..addAll(storedEverFunded);
      _observeFundedAddresses(asset.id, keys);

      return filterGaslessPhantomAddresses(
        asset,
        AssetPubkeys(
          assetId: asset.id,
          keys: keys,
          availableAddressesCount: available,
          syncStatus: sync,
        ),
        everFunded: everFunded,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _startWatchingPubkeys(Asset asset, bool activateIfNeeded) async {
    final controller = _pubkeysControllers[asset.id];
    if (controller == null || _isDisposed) return;

    // Cancel any existing watcher for this asset
    await _activeWatchers[asset.id]?.cancel();
    _activeWatchers.remove(asset.id);

    // Ensure user is authenticated
    final user = await _auth.currentUser;
    if (user == null) {
      // Do not emit an error; wait for authentication changes
      _logger.fine(
        'Delaying watcher start for ${asset.id.name}: unauthenticated',
      );
      return;
    }
    _currentWalletId = user.walletId;
    _logger.fine('Starting watcher for ${asset.id.name}');

    try {
      // Ensure activation if requested, otherwise only proceed if already active
      bool isActive = await _activationCoordinator.isAssetActive(asset.id);
      if (!isActive && activateIfNeeded) {
        final activationResult = await _activationCoordinator.activateAsset(
          asset,
        );
        isActive = activationResult.isSuccess;
      }

      if (isActive) {
        // Try hydrate from persisted cache first for faster cold start
        final walletId = _currentWalletId!;
        final hydrated = await _hydrateFromStorageForWallet(walletId, asset);
        if (hydrated != null) {
          _pubkeysCache[asset.id] = hydrated;
          if (!controller.isClosed) controller.add(hydrated);
        }

        final first = await _fetchFreshPubkeys(asset, walletId);
        _pubkeysCache[asset.id] = first;
        if (!controller.isClosed && (hydrated == null || first != hydrated)) {
          controller.add(first);
        }
        _logger.fine('Emitted initial pubkeys for ${asset.id.name}');
      }

      // Periodic polling for pubkeys updates
      final periodicStream = Stream<void>.periodic(_defaultPollingInterval);
      _activeWatchers[asset.id] = periodicStream
          .asyncMap<AssetPubkeys?>((_) async {
            if (_isDisposed) return null;

            // Check that user is still authenticated and wallet hasn't changed
            final currentUser = await _auth.currentUser;
            if (currentUser == null ||
                currentUser.walletId != _currentWalletId) {
              return null;
            }

            try {
              bool active = await _activationCoordinator.isAssetActive(
                asset.id,
              );
              if (!active && activateIfNeeded) {
                final activationResult = await _activationCoordinator
                    .activateAsset(asset);
                active = activationResult.isSuccess;
              }
              if (active) {
                final pubkeys = await _fetchFreshPubkeys(
                  asset,
                  currentUser.walletId,
                );
                _pubkeysCache[asset.id] = pubkeys;
                return pubkeys;
              }
            } catch (_) {
              // Swallow transient errors; continue with last known state
            }
            return _pubkeysCache[asset.id];
          })
          .listen(
            (AssetPubkeys? pubkeys) {
              if (pubkeys != null && !controller.isClosed) {
                controller.add(pubkeys);
              }
            },
            onError: (Object error) {
              if (!controller.isClosed) controller.addError(error);
            },
            onDone: () => _stopWatchingPubkeys(asset.id),
            cancelOnError: false,
          );
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

  void _stopWatchingPubkeys(AssetId assetId) {
    final watcher = _activeWatchers[assetId];
    if (watcher != null) {
      watcher.cancel();
      _activeWatchers.remove(assetId);
      _logger.fine('Stopped watcher for ${assetId.name}');
    }
  }

  @override
  Future<void> precachePubkeys(Asset asset) async {
    if (_isDisposed) return;

    final user = await _auth.currentUser;
    if (user == null) return;

    try {
      final pubkeys = await getPubkeys(asset);
      _pubkeysCache[asset.id] = pubkeys;

      final controller = _pubkeysControllers[asset.id];
      if (controller != null && !controller.isClosed) {
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
    if (_currentWalletId != newWalletId) {
      await _resetState();
      _currentWalletId = newWalletId;
    }
  }

  Future<void> _scanForNewHdAddressesIfNeeded({
    required WalletId walletId,
    required Asset asset,
    required PubkeyStrategy strategy,
  }) async {
    if (!strategy.supportsMultipleAddresses) {
      return;
    }

    final scanKey = '${walletId.name}:${asset.id.id}';
    final retryAfter = _hdAddressScanRetryAfter[scanKey];
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return;
    }

    try {
      await strategy.scanForNewAddresses(asset.id, _client);
      _hdAddressScanRetryAfter.remove(scanKey);
    } catch (error, stackTrace) {
      _hdAddressScanRetryAfter[scanKey] = DateTime.now().add(
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

    // Cancel all active watchers concurrently
    final List<StreamSubscription<dynamic>> watcherSubs = _activeWatchers.values
        .toList();
    _activeWatchers.clear();

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
    final List<StreamController<AssetPubkeys>> controllers = _pubkeysControllers
        .values
        .toList();
    _pubkeysControllers.clear();

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

    // Clear caches
    _pubkeysCache.clear();
    _everFundedAddresses.clear();
    _inFlightPubkeyRequests.clear();
    _hdAddressScanRetryAfter.clear();

    stopwatch.stop();
    _logger.fine(
      'State reset completed in ${stopwatch.elapsedMilliseconds}ms '
      '(subscriptions: ${watcherSubs.length}, controllers: ${controllers.length})',
    );
  }

  /// Dispose of any resources
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

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

    _pubkeysCache.clear();
    _everFundedAddresses.clear();
    _hdAddressScanRetryAfter.clear();
    _watchedAssets.clear();
    _currentWalletId = null;
    _logger.fine('Disposed');
  }
}

/// Drops never-used phantom addresses for TRON gasless assets.
///
/// Gasless assets are single-address by design: the custody model (headline
/// balance, `gasless::account_status`, gasless sends) only covers the enabled
/// (first-derived) address, and KDF's persistent HD storage keeps re-reporting
/// every address ever created via `get_new_address` — including never-used
/// ones from before the wallet gated address creation. Filtering at this
/// choke point keeps every consumer coherent (receive list, withdraw sources,
/// transaction-history address groups, stranded-funds notice).
///
/// Kept: the enabled address (always), any address currently holding funds
/// (stranded balances stay visible and consolidatable), and any address in
/// [everFunded] — ever observed funded, persisted with the pubkeys — so a
/// used-then-emptied address keeps its transaction history reachable. Only
/// addresses with no observed use are dropped; they are seed-derivable and
/// reappear on the next fetch if they ever receive funds (KDF keeps
/// reporting them; the filter re-admits them on balance).
///
/// Applied to both fresh fetches and cache hydration; `savePubkeys` replaces
/// records wholesale, so the persisted cache self-purges on the first
/// filtered fetch. Note for SDK consumers: an address created via
/// `get_new_address` for a gasless asset is hidden until funded — this
/// wallet gates TRON address creation in the UI for exactly that reason.
AssetPubkeys filterGaslessPhantomAddresses(
  Asset asset,
  AssetPubkeys pubkeys, {
  Set<String> everFunded = const {},
}) {
  final protocol = asset.protocol;
  if (protocol is! TrxProtocol && protocol is! Trc20Protocol) return pubkeys;
  if (pubkeys.keys.length <= 1) return pubkeys;
  // gasfreeAddress is only populated when a gasless provider is configured;
  // without one, TRON multi-address behaves like any other HD asset.
  final isGasless = pubkeys.keys.any(
    (key) => (key.gasfreeAddress ?? '').isNotEmpty,
  );
  if (!isGasless) return pubkeys;

  final canonical = pubkeys.keys
      .where(
        (key) =>
            key.derivationPath ==
            GaslessCapabilityRegistry.canonicalPrimaryDerivationPath,
      )
      .singleOrNull;
  if (canonical == null) {
    // Ambiguous legacy metadata must not expose a custody receive address.
    return AssetPubkeys(
      assetId: pubkeys.assetId,
      keys: [
        for (final key in pubkeys.keys)
          PubkeyInfo(
            address: key.address,
            derivationPath: key.derivationPath,
            chain: key.chain,
            balance: key.balance,
            coinTicker: asset.id.id,
            gasfreeAddress: null,
            name: key.name,
          ),
      ],
      availableAddressesCount: pubkeys.availableAddressesCount,
      syncStatus: pubkeys.syncStatus,
    );
  }
  final keys = [
    for (final key in pubkeys.keys)
      if (key.address == canonical.address ||
          key.balance.hasValue ||
          everFunded.contains(key.address))
        PubkeyInfo(
          address: key.address,
          derivationPath: key.derivationPath,
          chain: key.chain,
          balance: key.balance,
          coinTicker: asset.id.id,
          // Only the canonical primary may advertise a GasFree custody
          // receive address. Retained secondary keys are Standard/recovery
          // sources even if a legacy KDF cache attached a derived value.
          gasfreeAddress: key.address == canonical.address
              ? key.gasfreeAddress
              : null,
          name: key.name,
        ),
  ];
  final secondaryCustodyWasRemoved = pubkeys.keys.any(
    (key) =>
        key.address != canonical.address &&
        (key.gasfreeAddress ?? '').isNotEmpty,
  );
  if (keys.length == pubkeys.keys.length && !secondaryCustodyWasRemoved) {
    return pubkeys;
  }

  return AssetPubkeys(
    assetId: pubkeys.assetId,
    keys: keys,
    availableAddressesCount: pubkeys.availableAddressesCount,
    syncStatus: pubkeys.syncStatus,
  );
}
