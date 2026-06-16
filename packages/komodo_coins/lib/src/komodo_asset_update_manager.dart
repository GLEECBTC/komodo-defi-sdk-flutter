import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/src/asset_filter.dart';
import 'package:komodo_coins/src/asset_management/_asset_management_index.dart';
import 'package:komodo_coins/src/config/custom_coins_config.dart';
import 'package:komodo_coins/src/update_management/_update_management_index.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Contract for interacting with Komodo coins configuration and updates.
abstract class AssetsUpdateManager {
  /// Initializes internal managers and storage.
  @mustCallSuper
  Future<void> init({Set<String> defaultPriorityTickers = const {}});

  /// Whether this instance has been initialized.
  bool get isInitialized;

  /// All available assets keyed by [AssetId].
  Map<AssetId, Asset> get all;

  /// Fetches assets (same as [all], maintained for backward compatibility).
  Future<Map<AssetId, Asset>> fetchAssets();

  /// Returns the currently active coins commit hash (cached on cold start).
  Future<String?> getCurrentCommitHash();

  /// Returns the latest commit hash from the configured remote.
  Future<String?> getLatestCommitHash();

  /// Checks if an update is available.
  Future<bool> isUpdateAvailable();

  /// Performs an immediate update using the configured [UpdateStrategy].
  Future<UpdateResult> updateNow();

  /// Stream of update results for monitoring.
  Stream<UpdateResult> get updateStream;

  /// Returns the assets filtered using the provided [strategy].
  Map<AssetId, Asset> filteredAssets(AssetFilterStrategy strategy);

  /// Finds an asset by ticker and subclass.
  Asset? findByTicker(String ticker, CoinSubClass subClass);

  /// Finds all variants of a coin by ticker.
  Set<Asset> findVariantsOfCoin(String ticker);

  /// Finds child assets of a parent asset.
  Set<Asset> findChildAssets(AssetId parentId);

  /// Disposes resources and stops background updates.
  Future<void> dispose();
}

/// A high-level library that provides a simple way to access Komodo Platform
/// coin data and seed nodes.
class KomodoAssetsUpdateManager implements AssetsUpdateManager {
  KomodoAssetsUpdateManager({
    AssetRuntimeUpdateConfigRepository? configRepository,
    CoinConfigTransformer? transformer,
    CoinConfigDataFactory? dataFactory,
    LoadingStrategy? loadingStrategy,
    UpdateStrategy? updateStrategy,
    this.enableAutoUpdate = true,
    this.appStoragePath,
    this.appName,
    CustomTokenStore? customTokenStorage,
  }) : _configRepository =
           configRepository ?? AssetRuntimeUpdateConfigRepository(),
       _transformer = transformer ?? const CoinConfigTransformer(),
       _dataFactory = dataFactory ?? const DefaultCoinConfigDataFactory(),
       _loadingStrategy = loadingStrategy ?? StorageFirstLoadingStrategy(),
       _updateStrategy = updateStrategy ?? const BackgroundUpdateStrategy(),
       _customTokenStorage = customTokenStorage;

  static final Logger _log = Logger('KomodoAssetsUpdateManager');

  /// Whether to automatically update coin configurations from remote sources.
  /// When false, only reads from existing storage or local asset bundle.
  final bool enableAutoUpdate;

  /// Optional base path for storage (native platforms).
  final String? appStoragePath;

  /// Optional app name used as a subfolder (native) or path (web).
  final String? appName;

  final AssetRuntimeUpdateConfigRepository _configRepository;
  final CoinConfigTransformer _transformer;
  final CoinConfigDataFactory _dataFactory;
  final LoadingStrategy _loadingStrategy;
  final UpdateStrategy _updateStrategy;
  final CustomTokenStore? _customTokenStorage;

  // Internal managers using strategy pattern
  CoinConfigManager? _assetsManager;
  CoinUpdateManager? _updatesManager;
  AssetRuntimeUpdateConfig? _runtimeConfig;
  // Init coordination
  Future<void>? _initFuture;
  bool _initialized = false;

  /// Provides access to asset management operations
  CoinConfigManager get assets {
    if (_assetsManager == null) {
      throw StateError(
        'KomodoAssetsUpdateManager has not been initialized. Call init() first',
      );
    }
    return _assetsManager!;
  }

  /// Provides access to update management operations
  CoinUpdateManager get updates {
    if (_updatesManager == null) {
      throw StateError(
        'KomodoAssetsUpdateManager has not been initialized. Call init() first',
      );
    }
    return _updatesManager!;
  }

  @override
  Future<void> init({Set<String> defaultPriorityTickers = const {}}) async {
    if (_initialized) return;
    if (_initFuture != null) {
      return _initFuture!;
    }
    _log.fine('Initializing KomodoAssetsUpdateManager with strategy pattern');
    final completer = Completer<void>();
    _initFuture = completer.future;
    try {
      // Initialize hive first before registering adapters or repositories.
      await _initializeHiveStorage();

      // Ensure any persisted custom coins-config override is loaded before
      // building the config sources below.
      await CustomCoinsConfig.instance.load(
        appStoragePath: appStoragePath,
        appName: appName,
      );

      // A custom coins-config override is authoritative: skip remote/background
      // updates so they cannot overwrite or shadow the user-selected config.
      final effectiveAutoUpdate =
          enableAutoUpdate &&
          !CustomCoinsConfig.instance.hasCoinsConfigOverride;

      final runtimeConfig = await _getRuntimeConfig();
      final configProviders = await _createConfigSources(runtimeConfig);
      final newAssetsManager = StrategicCoinConfigManager(
        configSources: configProviders,
        loadingStrategy: _loadingStrategy,
        defaultPriorityTickers: defaultPriorityTickers,
        customTokenStorage: _customTokenStorage ?? CustomTokenStorage(),
      );

      // Initialize update manager
      final repository = _dataFactory.createRepository(
        runtimeConfig,
        _transformer,
      );
      final localProvider = _dataFactory.createLocalProvider(runtimeConfig);
      final newUpdatesManager = StrategicCoinUpdateManager(
        repository: repository,
        updateStrategy: effectiveAutoUpdate
            ? _updateStrategy
            : NoUpdateStrategy(),
        fallbackProvider: localProvider,
      );

      // Initialize both managers
      await Future.wait([newAssetsManager.init(), newUpdatesManager.init()]);

      // Publish only after successful initialization to avoid half-ready state
      _assetsManager = newAssetsManager;
      _updatesManager = newUpdatesManager;
      _initialized = true;

      // Start background updates if enabled
      if (effectiveAutoUpdate) {
        _updatesManager!.startBackgroundUpdates();
      }
      _log.fine('KomodoAssetsUpdateManager initialized successfully');
      completer.complete();
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _initFuture = null;
    }
  }

  /// Initialize Hive storage for coin updates
  Future<void> _initializeHiveStorage() async {
    try {
      final resolvedAppName = appName ?? 'komodo_coins';
      String storagePath;
      if (kIsWeb) {
        // Web: appName is used as the storage path
        storagePath = resolvedAppName;
        _log.fine('Using web storage path: $storagePath');
      } else {
        // Native: join base path and app name
        final basePath =
            appStoragePath ?? (await getApplicationDocumentsDirectory()).path;
        storagePath = p.join(basePath, resolvedAppName);
        _log.fine('Using native storage path: $storagePath');
      }

      await KomodoCoinUpdater.ensureInitialized(storagePath);
      _log.fine('Hive storage initialized successfully');
    } catch (e, stackTrace) {
      _log.shout(
        'Failed to initialize Hive storage, coin updates may not work: $e',
        e,
        stackTrace,
      );
      // Don't rethrow - we want the app to continue working even if Hive fails
    }
  }

  @override
  bool get isInitialized => _initialized;

  /// Convenience getter for backward compatibility
  @override
  Map<AssetId, Asset> get all => assets.all;

  Future<AssetRuntimeUpdateConfig> _getRuntimeConfig() async {
    if (_runtimeConfig != null) return _runtimeConfig!;
    _log.fine('Loading runtime update config');
    _runtimeConfig =
        await _configRepository.tryLoad() ?? const AssetRuntimeUpdateConfig();
    return _runtimeConfig!;
  }

  /// Creates configuration sources based on the runtime config.
  ///
  /// When a custom coins-config override is configured it becomes the sole,
  /// authoritative source: storage and the bundled asset are bypassed so the
  /// user-selected file is always used (and a malformed file fails loudly
  /// rather than silently falling back to the bundled config).
  Future<List<CoinConfigSource>> _createConfigSources(
    AssetRuntimeUpdateConfig config,
  ) async {
    final overrideSource = CustomCoinsConfig.instance.coinsConfigSource;
    if (overrideSource != null) {
      _log.info(
        'Using custom coins-config override: '
        '${overrideSource.displayLabel}',
      );
      return <CoinConfigSource>[
        AssetBundleCoinConfigSource(
          provider: FileCoinConfigProvider(
            overrideSource,
            transformer: _transformer,
          ),
        ),
      ];
    }

    final sources = <CoinConfigSource>[];

    // Add storage source
    final repository = _dataFactory.createRepository(config, _transformer);
    sources.add(StorageCoinConfigSource(repository: repository));

    // Add local asset bundle source
    final localProvider = _dataFactory.createLocalProvider(config);
    sources.add(AssetBundleCoinConfigSource(provider: localProvider));

    return sources;
  }

  /// Fetches assets using the asset manager
  ///
  /// This method is kept for backward compatibility but now delegates to the
  /// asset manager's functionality.
  ///
  /// During cold start, returns cached assets to prevent refreshing on
  /// every call.
  /// Call assets.refreshAssets to manually refresh the asset list.
  /// Background updates will update the cache without affecting the
  /// current asset list.
  @override
  Future<Map<AssetId, Asset>> fetchAssets() async {
    if (!isInitialized) {
      await init();
    }

    return assets.all;
  }

  /// Returns the currently active coins commit hash.
  ///
  /// Delegates to the coin config manager for commit information.
  /// During cold start, returns cached commit hash to prevent refreshing
  /// on every call.
  @override
  Future<String?> getCurrentCommitHash() async {
    if (!isInitialized) {
      await init();
    }

    return assets.getCurrentCommitHash();
  }

  /// Returns the latest commit hash available from the configured remote.
  ///
  /// Delegates to the update manager for remote commit information.
  @override
  Future<String?> getLatestCommitHash() async {
    if (!isInitialized) {
      await init();
    }
    return updates.getLatestCommitHash();
  }

  /// Checks if an update is available
  ///
  /// Delegates to the update manager for update checking.
  @override
  Future<bool> isUpdateAvailable() async {
    if (!isInitialized) {
      await init();
    }
    return updates.isUpdateAvailable();
  }

  /// Performs an immediate update
  ///
  /// Delegates to the update manager for update operations.
  @override
  Future<UpdateResult> updateNow() async {
    if (!isInitialized) {
      await init();
    }
    return updates.updateNow();
  }

  /// Stream of update results for monitoring
  ///
  /// Delegates to the update manager for update monitoring.
  @override
  Stream<UpdateResult> get updateStream {
    if (!isInitialized) {
      throw StateError(
        'KomodoAssetsUpdateManager has not been initialized. Call init() first',
      );
    }
    return updates.updateStream;
  }

  /// Returns the assets filtered using the provided [strategy].
  ///
  /// Delegates to the asset manager for filtering operations.
  @override
  Map<AssetId, Asset> filteredAssets(AssetFilterStrategy strategy) =>
      assets.filteredAssets(strategy);

  /// Finds an asset by ticker and subclass
  ///
  /// Delegates to the asset manager for asset lookup.
  @override
  Asset? findByTicker(String ticker, CoinSubClass subClass) =>
      assets.findByTicker(ticker, subClass);

  /// Finds all variants of a coin by ticker
  ///
  /// Delegates to the asset manager for variant lookup.
  @override
  Set<Asset> findVariantsOfCoin(String ticker) =>
      assets.findVariantsOfCoin(ticker);

  /// Finds child assets of a parent asset
  ///
  /// Delegates to the asset manager for child asset lookup.
  @override
  Set<Asset> findChildAssets(AssetId parentId) =>
      assets.findChildAssets(parentId);

  /// Disposes of all resources
  @override
  Future<void> dispose() async {
    await Future.wait([
      if (_assetsManager != null) _assetsManager!.dispose(),
      if (_updatesManager != null) _updatesManager!.dispose(),
    ]);

    _assetsManager = null;
    _updatesManager = null;
    _runtimeConfig = null;
    _initialized = false;

    _log.fine('Disposed KomodoAssetsUpdateManager');
  }
}
