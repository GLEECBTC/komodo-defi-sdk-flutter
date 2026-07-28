import 'dart:async';
import 'dart:collection';

import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/src/asset_filter.dart';
import 'package:komodo_coins/src/asset_management/coin_config_fallback_mixin.dart';
import 'package:komodo_coins/src/asset_management/loading_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Interface defining the contract for coin configuration management operations
abstract class CoinConfigManager {
  /// Initializes the coin config manager.
  ///
  /// This method should be called before any other methods are called.
  /// It is responsible for loading the initial assets and setting up the
  /// manager.
  ///
  /// Performs the following steps:
  /// 1. Validates the sources
  /// 2. Loads the initial assets
  /// 3. Sets the manager to initialized
  ///
  /// Subsequent calls are ignored if already initialized.
  Future<void> init();

  /// Gets all available assets.
  ///
  /// This method returns a map of all available assets.
  /// The map is keyed by the asset id.
  Map<AssetId, Asset> get all;

  /// Gets the current commit hash for the loaded coin configuration.
  /// This represents the commit hash of the currently active coin list.
  Future<String?> getCurrentCommitHash();

  /// Refreshes assets from sources
  Future<void> refreshAssets();

  /// Returns filtered assets using the provided strategy
  Map<AssetId, Asset> filteredAssets(AssetFilterStrategy strategy);

  /// Finds an asset by ticker and subclass
  Asset? findByTicker(String ticker, CoinSubClass subClass);

  /// Finds all variants of a coin by ticker
  Set<Asset> findVariantsOfCoin(String ticker);

  /// Finds child assets of a parent asset
  Set<Asset> findChildAssets(AssetId parentId);

  /// Checks if the manager is initialized
  bool get isInitialized;

  /// Disposes of all resources
  Future<void> dispose();

  /// Stores a custom token
  Future<void> storeCustomToken(Asset asset);

  /// Deletes a custom token
  Future<void> deleteCustomToken(AssetId assetId);
}

/// Implementation of [CoinConfigManager] that uses strategy pattern for loading
class StrategicCoinConfigManager
    with CoinConfigFallbackMixin
    implements CoinConfigManager {
  factory StrategicCoinConfigManager({
    required List<CoinConfigSource> configSources,
    LoadingStrategy? loadingStrategy,
    Set<String> defaultPriorityTickers = const {},
    CustomTokenStore? customTokenStorage,
  }) {
    return StrategicCoinConfigManager._internal(
      configSources: configSources,
      loadingStrategy: loadingStrategy ?? StorageFirstLoadingStrategy(),
      defaultPriorityTickers: defaultPriorityTickers,
      customTokenStorage: customTokenStorage ?? CustomTokenStorage(),
    );
  }

  StrategicCoinConfigManager._internal({
    required List<CoinConfigSource> configSources,
    required LoadingStrategy loadingStrategy,
    required Set<String> defaultPriorityTickers,
    required CustomTokenStore customTokenStorage,
  }) : _configSources = configSources,
       _loadingStrategy = loadingStrategy,
       _defaultPriorityTickers = Set.unmodifiable(defaultPriorityTickers),
       _customTokenStorage = customTokenStorage;

  static final _logger = Logger('StrategicCoinConfigManager');

  final List<CoinConfigSource> _configSources;
  final LoadingStrategy _loadingStrategy;
  final Set<String> _defaultPriorityTickers;
  final CustomTokenStore _customTokenStorage;

  // Required by CoinConfigFallbackMixin
  @override
  List<CoinConfigSource> get configSources => _configSources;

  @override
  LoadingStrategy get loadingStrategy => _loadingStrategy;

  SplayTreeMap<AssetId, Asset>? _assets;
  final Map<String, SplayTreeMap<AssetId, Asset>> _filterCache = {};

  /// Hash-keyed snapshots of [_filterCache], memoised per strategy.
  ///
  /// [_filterCache] holds [SplayTreeMap]s ordered by [_assetIdComparator], so
  /// key lookups on them resolve through that comparator rather than through
  /// `AssetId`'s `==`/`hashCode`. The two disagree: the comparator orders on
  /// `AssetId.toString()`, which includes `parentId` and omits `chainId`,
  /// while equality is defined by `[id, subClass, chainId]`. Handing the tree
  /// itself to callers therefore misses on an [AssetId] that is `==` a stored
  /// key but carries a different `parentId` - e.g. any child-token id parsed
  /// with `knownIds: null`, as `Transaction.fromJson` does.
  ///
  /// Snapshotting into a [LinkedHashMap] restores `==`/`hashCode` lookups
  /// while preserving the tree's ordering. It also makes the returned map a
  /// stable snapshot rather than a live view, so callers may iterate it across
  /// an await without risking [ConcurrentModificationError] when a custom
  /// token is stored or deleted mid-iteration.
  ///
  /// Memoised because [filteredAssets] is on hot paths - every
  /// `AssetManager.available` read and everything built on it. Every mutation
  /// of [_filterCache] must invalidate this alongside it.
  final Map<String, Map<AssetId, Asset>> _filterViewCache = {};

  bool _isDisposed = false;
  bool _isInitialized = false;

  // Cache for commit hash to prevent unnecessary queries
  String? _cachedCommitHash;

  @override
  Future<void> init() async {
    if (_isDisposed) {
      _logger.warning('Attempted to init after dispose');
      throw StateError('Cannot re-initialize a disposed CoinConfigManager');
    }
    if (_isInitialized) {
      _logger.finer('init() called more than once; skipping');
      return;
    }
    _logger.fine('Initializing CoinConfigManager');

    await _validateConfigSources();

    await _loadAssets();
    // Populate commit hash cache before the manager is marked initialized
    await _populateCommitHashCacheFromSources();
    _isInitialized = true;
    _logger.fine('CoinConfigManager initialized successfully');
  }

  Future<void> _validateConfigSources() async {
    for (final source in _configSources) {
      try {
        final isAvailable = await source.isAvailable();
        _logger.finer(
          'Source ${source.displayName} availability: $isAvailable',
        );
      } catch (e, s) {
        _logger.warning(
          'Failed to check availability for source ${source.displayName}',
          e,
          s,
        );
      }
    }
  }

  /// Validates that the manager hasn't been disposed
  void _checkNotDisposed() {
    if (_isDisposed) {
      _logger.warning('Attempted to use manager after dispose');
      throw StateError('CoinConfigManager has been disposed');
    }
  }

  /// Validates that the manager has been initialized
  void _assertInitialized() {
    if (!_isInitialized) {
      _logger.warning('Attempted to use manager before initialization');
      throw StateError('CoinConfigManager must be initialized before use');
    }
  }

  /// Comparator for ordering assets deterministically by their key.
  int _assetIdComparator(AssetId a, AssetId b) {
    final aIsDefault = _defaultPriorityTickers.contains(a.id);
    final bIsDefault = _defaultPriorityTickers.contains(b.id);
    if (aIsDefault != bIsDefault) {
      // Default-priority assets come first
      return aIsDefault ? -1 : 1;
    }
    return a.toString().compareTo(b.toString());
  }

  /// Maps a list of assets to an ordered SplayTreeMap keyed by AssetId
  SplayTreeMap<AssetId, Asset> _mapAssets(List<Asset> assets) {
    final map = SplayTreeMap<AssetId, Asset>(_assetIdComparator);
    for (final asset in assets) {
      map[asset.id] = asset;
    }
    return map;
  }

  /// Loads assets using the fallback mechanism
  Future<void> _loadAssets() async {
    _checkNotDisposed();

    final assets = await trySourcesInOrder(
      LoadingRequestType.initialLoad,
      (source) => source.loadAssets(),
      operationName: 'loadAssets',
    );

    _assets = _mapAssets(assets);
    await _loadAndMergeCustomTokens();
    _logger.info('Loaded ${assets.length} assets');
  }

  /// Populates the commit hash cache by querying available sources.
  ///
  /// This variant is safe to call during initialization, before the manager
  /// is marked as initialized. It does not assert initialization state.
  Future<void> _populateCommitHashCacheFromSources() async {
    if (_cachedCommitHash != null && _cachedCommitHash!.isNotEmpty) {
      _logger.finer('Commit hash already cached: $_cachedCommitHash');
      return;
    }

    for (final source in _configSources) {
      try {
        final commit = await source.getCurrentCommitHash();
        if (commit != null && commit.isNotEmpty) {
          _cachedCommitHash = commit;
          _logger.fine(
            'Cached commit hash from ${source.displayName}: $_cachedCommitHash',
          );
          return;
        }
      } catch (e, s) {
        _logger.fine(
          'Failed to get commit hash from ${source.displayName}',
          e,
          s,
        );
        continue;
      }
    }

    _logger.fine('No commit hash available from any source during init');
  }

  /// Refreshes assets from sources
  @override
  Future<void> refreshAssets() async {
    _checkNotDisposed();
    _assertInitialized();

    final assets = await trySourcesInOrder(
      LoadingRequestType.refreshLoad,
      (source) => source.loadAssets(),
      operationName: 'refreshAssets',
    );

    _assets = _mapAssets(assets);
    await _loadAndMergeCustomTokens();
    _filterCache.clear(); // Clear cache after refresh
    _filterViewCache.clear();

    // Refresh commit hash cache when assets are refreshed
    _cachedCommitHash = null;

    _logger.info('Refreshed ${assets.length} assets');
  }

  @override
  bool get isInitialized => _isInitialized && _assets != null;

  @override
  Map<AssetId, Asset> get all {
    _checkNotDisposed();
    _assertInitialized();
    return _assets!;
  }

  @override
  Future<String?> getCurrentCommitHash() async {
    _checkNotDisposed();
    _assertInitialized();

    // Return cached commit hash if available
    if (_cachedCommitHash != null && _cachedCommitHash!.isNotEmpty) {
      _logger.finer('Returning cached commit hash: $_cachedCommitHash');
      return _cachedCommitHash;
    }

    await _populateCommitHashCacheFromSources();

    return _cachedCommitHash;
  }

  @override
  Map<AssetId, Asset> filteredAssets(AssetFilterStrategy strategy) {
    _checkNotDisposed();
    _assertInitialized();

    final cacheKey = strategy.strategyId;
    final cachedView = _filterViewCache[cacheKey];
    if (cachedView != null) return cachedView;

    var result = _filterCache[cacheKey];
    if (result == null) {
      result = SplayTreeMap<AssetId, Asset>(_assetIdComparator);
      for (final entry in _assets!.entries) {
        final config = entry.value.protocol.config;
        if (strategy.shouldInclude(entry.value, config)) {
          result[entry.key] = entry.value;
        }
      }

      _filterCache[cacheKey] = result;
      _logger.finer(
        'filteredAssets(${strategy.strategyId}): ${result.length} assets',
      );
    }

    // Ordered by the tree, keyed by ==/hashCode. See [_filterViewCache].
    return _filterViewCache[cacheKey] = UnmodifiableMapView(
      LinkedHashMap<AssetId, Asset>.of(result),
    );
  }

  @override
  Asset? findByTicker(String ticker, CoinSubClass subClass) {
    _checkNotDisposed();
    _assertInitialized();

    return all.entries
        .where((e) => e.key.id == ticker && e.key.subClass == subClass)
        .map((e) => e.value)
        .firstOrNull;
  }

  @override
  Set<Asset> findVariantsOfCoin(String ticker) {
    _checkNotDisposed();
    _assertInitialized();

    return all.entries
        .where((e) => e.key.id == ticker)
        .map((e) => e.value)
        .toSet();
  }

  @override
  Set<Asset> findChildAssets(AssetId parentId) {
    _checkNotDisposed();
    _assertInitialized();

    return all.entries
        .where((e) => e.key.isChildAsset && e.key.parentId == parentId)
        .map((e) => e.value)
        .toSet();
  }

  /// Loads custom tokens and merges them directly into _assets
  Future<void> _loadAndMergeCustomTokens() async {
    try {
      final knownIds = _assets!.keys.toSet();
      final customTokens = await _customTokenStorage.getAllCustomTokens(
        knownIds,
      );
      if (customTokens.isEmpty) {
        return;
      }

      // Add custom tokens to _assets, handling conflicts by creating duplicate entries
      for (final customToken in customTokens) {
        _assets![customToken.id] = customToken;
      }

      _logger.fine('Merged ${customTokens.length} custom tokens into assets');
    } catch (e, s) {
      _logger.warning('Failed to load custom tokens', e, s);
    }
  }

  /// Updates filter caches when an asset is added
  void _updateFilterCachesForAddedAsset(Asset asset) {
    // The memoised snapshots are now stale for every strategy this touches.
    _filterViewCache.clear();
    for (final entry in _filterCache.entries) {
      final strategyId = entry.key;
      final cachedAssets = entry.value;

      // Create a strategy instance using the factory method
      final strategy = AssetFilterStrategy.fromStrategyId(strategyId);
      if (strategy != null) {
        final config = asset.protocol.config;
        if (strategy.shouldInclude(asset, config)) {
          cachedAssets[asset.id] = asset;
        }
      }
    }
  }

  /// Updates filter caches when an asset is removed
  void _updateFilterCachesForRemovedAsset(AssetId assetId) {
    _filterViewCache.clear();
    for (final cachedAssets in _filterCache.values) {
      cachedAssets.remove(assetId);
    }
  }

  @override
  Future<void> storeCustomToken(Asset asset) async {
    _checkNotDisposed();
    _assertInitialized();

    await _customTokenStorage.storeCustomToken(asset);
    _assets![asset.id] = asset;
    _updateFilterCachesForAddedAsset(asset);
  }

  @override
  Future<void> deleteCustomToken(AssetId assetId) async {
    _checkNotDisposed();
    _assertInitialized();
    await _customTokenStorage.deleteCustomToken(assetId);
    _assets!.remove(assetId);
    _updateFilterCachesForRemovedAsset(assetId);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      _logger.finer('dispose() called more than once; skipping');
      return;
    }
    _isDisposed = true;
    _isInitialized = false;
    _assets = null;
    _filterCache.clear();
    _filterViewCache.clear();
    _cachedCommitHash = null; // Clear commit hash cache
    await _customTokenStorage.dispose(); // Dispose custom token storage
    clearSourceHealthData(); // Clear mixin data
    _logger.fine('Disposed StrategicCoinConfigManager');
  }
}
