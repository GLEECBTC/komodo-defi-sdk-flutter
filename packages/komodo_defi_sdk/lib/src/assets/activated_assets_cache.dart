import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Cache for the activated assets list with a configurable TTL.
///
/// This cache reduces repeated `get_enabled_coins` RPC calls by memoizing the
/// activated assets for a short duration. It automatically invalidates when
/// the signed-in wallet changes or when explicitly cleared.
class ActivatedAssetsCache {
  /// Creates a new cache instance.
  ActivatedAssetsCache({
    required ApiClient client,
    required KomodoDefiLocalAuth auth,
    required IAssetLookup assetLookup,
    Duration ttl = const Duration(seconds: 2),
    DateTime Function() clock = DateTime.now,
  }) : _client = client,
       _auth = auth,
       _assetLookup = assetLookup,
       _ttl = ttl,
       _clock = clock {
    _authSubscription = _auth.authStateChanges.listen((_) => invalidate());
  }

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final IAssetLookup _assetLookup;
  final Duration _ttl;
  final DateTime Function() _clock;

  List<Asset>? _cache;
  DateTime? _lastFetchAt;
  Completer<List<Asset>>? _pendingCompleter;
  StreamSubscription<KdfUser?>? _authSubscription;
  bool _isDisposed = false;

  // Generation counter to invalidate in-flight fetches
  int _generation = 0;

  /// Returns the cached activated assets, refreshing when the TTL has expired
  /// or when [forceRefresh] is true.
  Future<List<Asset>> getActivatedAssets({bool forceRefresh = false}) async {
    _assertNotDisposed();

    if (forceRefresh) {
      invalidate();
    }

    if (_hasValidCache) {
      return _cache!;
    }

    // If a fetch is already in progress, return its future
    if (_pendingCompleter != null) {
      return _pendingCompleter!.future;
    }

    // Capture the current generation to detect if we're invalidated
    final generation = _generation;
    final fetchStart = _clock(); // Capture timestamp at fetch start
    final completer = Completer<List<Asset>>();
    _pendingCompleter = completer;

    try {
      final assets = await _fetchActivatedAssets();

      // Only update cache if we haven't been invalidated while fetching
      if (_generation == generation) {
        _cache = assets;
        _lastFetchAt = fetchStart; // Use start time for accurate TTL
      }

      completer.complete(assets);
      return assets;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingCompleter = null;
    }
  }

  /// Returns the activated [AssetId] set, refreshing as needed.
  Future<Set<AssetId>> getActivatedAssetIds({bool forceRefresh = false}) async {
    final assets = await getActivatedAssets(forceRefresh: forceRefresh);
    return assets.map((asset) => asset.id).toSet();
  }

  /// Clears the current cache forcing the next lookup to hit the network.
  ///
  /// If a fetch is currently in progress, it will be allowed to complete for
  /// callers who are awaiting it, but its result will not update the cache.
  /// This is achieved using a generation counter that is incremented on each
  /// invalidation, preventing stale in-flight fetches from populating the cache.
  void invalidate() {
    _cache = null;
    _lastFetchAt = null;
    _pendingCompleter = null;

    // Increment generation to mark any in-flight fetches as stale
    _generation++;
  }

  /// Disposes the cache, cancelling auth subscriptions and clearing state.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _authSubscription?.cancel();
    invalidate();
  }

  Future<List<Asset>> _fetchActivatedAssets() async {
    if (!await _auth.isSignedIn()) return const [];

    final response = await _client.rpc.generalActivation.getEnabledCoins();

    final assets = <Asset>[];
    final seen = <AssetId>{};

    void addAsset(Asset asset) {
      if (seen.add(asset.id)) {
        assets.add(asset);
      }
    }

    for (final coin in response.result) {
      for (final asset in _assetLookup.findAssetsByConfigId(coin.ticker)) {
        addAsset(asset);

        // A token can only be enabled in KDF if its platform coin is already
        // active. KDF may omit the platform from `get_enabled_coins` for some
        // protocols (observed for the TRON TRX platform), so derive it from the
        // token's parent to keep the activated set — and thus `isAssetActive` —
        // consistent for platform coins.
        final parentId = asset.id.parentId;
        if (parentId != null) {
          final parent = _assetLookup.fromId(parentId);
          if (parent != null) {
            addAsset(parent);
          }
        }
      }
    }

    return assets;
  }

  bool get _hasValidCache {
    if (_ttl == Duration.zero) return false;
    if (_cache == null || _lastFetchAt == null) return false;
    return _clock().difference(_lastFetchAt!) <= _ttl;
  }

  void _assertNotDisposed() {
    if (_isDisposed) {
      throw StateError('ActivatedAssetsCache has been disposed');
    }
  }
}
