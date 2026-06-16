import 'package:flutter/foundation.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/src/asset_management/_asset_management_index.dart';
import 'package:komodo_coins/src/config/custom_coins_store.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show JsonList, JsonMap;
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetRuntimeUpdateConfig;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Provides a minimal, read-only way to obtain the raw coins list needed to
/// start mm2/KDF, without instantiating update managers or starting background
/// processes. It wires a [CoinConfigManager] with only read-capable sources
/// (storage + asset bundle), initializes it, extracts configs, and disposes.
class StartupCoinsProvider {
  static final Logger _log = Logger('StartupCoinsProvider');

  /// Fetches the list of coin configuration maps to be passed to mm2 on start.
  ///
  /// - Uses only read paths and does not attempt to update or persist assets.
  /// - If local storage already contains assets, returns those.
  /// - Otherwise, falls back to the bundled local asset provider.
  /// - Initializes Hive storage minimally to enable storage reads.
  static Future<JsonList> fetchRawCoinsForStartup({
    // Optional overrides, primarily for testing/advanced wiring
    AssetRuntimeUpdateConfigRepository? configRepository,
    CoinConfigTransformer? transformer,
    CoinConfigDataFactory? dataFactory,
    LoadingStrategy? loadingStrategy,
    String? appStoragePath,
    String? appName,
    CustomTokenStore? customTokenStorage,
  }) async {
    final resolvedAppName = appName ?? 'komodo_coins';

    // Ensure any persisted coins-config override is loaded so it can be used
    // as the authoritative source for the coins passed to mm2.
    await CustomCoinsStore.instance.load(
      appStoragePath: appStoragePath,
      appName: resolvedAppName,
    );

    // Ensure Hive is initialized so storage reads can succeed.
    try {
      final storagePath = await _resolveStoragePath(
        appStoragePath: appStoragePath,
        appName: resolvedAppName,
      );
      await KomodoCoinUpdater.ensureInitialized(storagePath);
    } catch (e, s) {
      // Continue even if initialization fails;
      // the asset bundle source will be used.
      _log.shout(
        'Failed to initialize Hive storage for startup coins provider',
        e,
        s,
      );
    }

    CoinConfigManager? manager;
    try {
      // Runtime config and data sources
      final repo = configRepository ?? AssetRuntimeUpdateConfigRepository();
      final runtimeConfig =
          await repo.tryLoad() ?? const AssetRuntimeUpdateConfig();

      final factory = dataFactory ?? const DefaultCoinConfigDataFactory();
      final xform = transformer ?? const CoinConfigTransformer();
      final repository = factory.createRepository(runtimeConfig, xform);
      final localProvider = factory.createLocalProvider(runtimeConfig);

      // When a custom coins-config override is configured, derive the mm2
      // startup coins from that file exclusively so KDF and the SDK asset
      // registry stay consistent.
      final overrideFile = CustomCoinsStore.instance.coinsConfigFile;
      final sources = overrideFile != null
          ? <CoinConfigSource>[
              AssetBundleCoinConfigSource(
                provider: FileCoinConfigProvider(
                  overrideFile,
                  transformer: xform,
                ),
              ),
            ]
          : <CoinConfigSource>[
              StorageCoinConfigSource(repository: repository),
              AssetBundleCoinConfigSource(provider: localProvider),
            ];

      manager = StrategicCoinConfigManager(
        configSources: sources,
        loadingStrategy: loadingStrategy ?? StorageFirstLoadingStrategy(),
        customTokenStorage:
            customTokenStorage ?? const NoOpCustomTokenStorage(),
      );

      await manager.init();

      final assets = manager.all;
      // Sort to avoid random ordering of params that causes segfault on linux
      final configs =
          <JsonMap>[for (final asset in assets.values) asset.protocol.config]
            ..sort((a, b) {
              final aId = a['coin'] as String? ?? '';
              final bId = b['coin'] as String? ?? '';
              return aId.compareTo(bId);
            });

      return JsonList.of(configs);
    } finally {
      try {
        await manager?.dispose();
      } catch (disposeErr, disposeStack) {
        _log.fine(
          'Dispose failed in StartupCoinsProvider',
          disposeErr,
          disposeStack,
        );
      }
    }
  }

  static Future<String> _resolveStoragePath({
    required String appName,
    String? appStoragePath,
  }) async {
    if (kIsWeb) {
      // Web: appName acts as logical storage bucket
      return appName;
    }
    final basePath =
        appStoragePath ?? (await getApplicationDocumentsDirectory()).path;
    return p.join(basePath, appName);
  }
}
