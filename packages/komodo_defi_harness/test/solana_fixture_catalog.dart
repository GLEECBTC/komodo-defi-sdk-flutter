import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The Solana fixture's two assets as an injected SDK catalog.
///
/// Fixed catalog injection exercises the production registry and storage path
/// without modifying bundled production assets or making update HTTP calls.
/// KDF's start-up coins come from the same catalog, so a real engine knows
/// both tickers too.
class SolanaFixtureCatalog
    implements CoinConfigProvider, CoinConfigDataFactory {
  List<Asset> get assets => const AssetParser().parseAssetsFromConfig({
    SolanaWalletFixture.platform: SolanaWalletFixture.platformConfig(),
    SolanaWalletFixture.token: SolanaWalletFixture.tokenConfig(),
  });

  @override
  Future<List<Asset>> getAssets({String? branch}) async => assets;

  @override
  Future<List<Asset>> getAssetsForCommit(String commit) async => assets;

  @override
  Future<String> getLatestCommit({
    String? branch,
    String? apiBaseUrl,
    String? githubToken,
  }) async => 'solana-fixture-immutable';

  @override
  CoinConfigProvider createLocalProvider(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  ) => this;

  @override
  CoinConfigRepository createRepository(
    AssetRuntimeUpdateConfig config,
    CoinConfigTransformer transformer,
  ) => CoinConfigRepository(coinConfigProvider: this);
}

/// An SDK limited to [SolanaFixtureCatalog], with nothing pre-activated.
///
/// [storageNamespace] keeps its cached catalog and custom tokens apart from
/// production storage and selects the bundled-only loading strategy.
KomodoDefiSdkConfig solanaFixtureSdkConfig({
  required String storageNamespace,
  bool enabled = true,
}) => KomodoDefiSdkConfig(
  defaultAssets: const {},
  preActivateDefaultAssets: false,
  preActivateHistoricalAssets: false,
  preActivateCustomTokenAssets: false,
  assetsAutoUpdate: false,
  assetsStorageNamespace: storageNamespace,
  assetsDataFactory: SolanaFixtureCatalog(),
  solanaCapabilities: SolanaCapabilities(enabled: enabled),
);
