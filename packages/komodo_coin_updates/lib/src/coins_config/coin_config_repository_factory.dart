// Abstract factory for creating data-layer collaborators used by KomodoCoins.
import 'package:komodo_coin_updates/src/coins_config/_coins_config_index.dart';
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
  const DefaultCoinConfigDataFactory();

  @override
  CoinConfigRepository createRepository(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  ) {
    return CoinConfigRepository.withDefaults(config, transformer: transformer);
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
