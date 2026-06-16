/// Komodo Coins Library
///
/// High-level library that provides access to Komodo Platform coin data and configurations
/// using strategy patterns for loading and updating coin configurations.
library komodo_coins;

export 'package:komodo_coin_updates/komodo_coin_updates.dart'
    show CustomCoinsFile, FileCoinConfigProvider;

export 'src/asset_filter.dart';
export 'src/asset_management/coin_config_manager.dart'
    show CoinConfigManager, StrategicCoinConfigManager;
export 'src/config/custom_coins_store.dart' show CustomCoinsStore;
export 'src/komodo_asset_update_manager.dart'
    show AssetsUpdateManager, KomodoAssetsUpdateManager;
export 'src/startup/startup_coins_provider.dart' show StartupCoinsProvider;
