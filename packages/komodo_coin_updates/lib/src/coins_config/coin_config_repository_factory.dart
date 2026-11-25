// Abstract factory for creating data-layer collaborators used by KomodoCoins.
import 'package:komodo_coin_updates/src/coins_config/_coins_config_index.dart';
import 'package:komodo_coin_updates/src/komodo_coin_updater.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetRuntimeUpdateConfig;

/// Abstract factory for creating data-layer collaborators used by KomodoCoins.
abstract class CoinConfigDataFactory {
  /// Creates a repository wired to the given [config] and [transformer].
  CoinConfigRepository createRepository(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  );

  /// Creates a local asset-backed provider using [config] and [transformer].
  CoinConfigProvider createLocalProvider(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  );
}

/// Default production implementation.
class DefaultCoinConfigDataFactory implements CoinConfigDataFactory {
  /// Creates a default coin config data factory.
  const DefaultCoinConfigDataFactory({this.storageNamespace});

  /// Explicit database namespace, including for Hive's pathless web backend.
  /// Null retains the build's configured namespace and production defaults.
  final String? storageNamespace;

  @override
  CoinConfigRepository createRepository(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  ) {
    return CoinConfigRepository.withDefaults(
      config,
      transformer: transformer,
      assetsBoxName: storageNamespace == null
          ? null
          : KomodoCoinUpdater.storageBoxName(
              'assets',
              namespace: storageNamespace!,
            ),
      settingsBoxName: storageNamespace == null
          ? null
          : KomodoCoinUpdater.storageBoxName(
              'coins_settings',
              namespace: storageNamespace!,
            ),
    );
  }

  @override
  CoinConfigProvider createLocalProvider(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  ) {
    return LocalAssetCoinConfigProvider.fromConfig(
      config,
      transformer: transformer,
    );
  }
}
