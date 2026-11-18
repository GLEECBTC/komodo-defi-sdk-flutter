import 'package:flutter/foundation.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show JsonList;
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetRuntimeUpdateConfig;

/// The asset catalog KDF's start-up `coins` parameter is read from.
///
/// KDF activates only tickers its start-up coins config lists, and treats a
/// listed ticker sent with a `protocol` as a duplicate custom token. So this
/// must name the same sources as the SDK's runtime asset manager, or KDF
/// refuses assets the SDK offers (`TokenConfigIsNotFound`).
///
/// It does not take the SDK's config transformer: that is application policy
/// for the SDK registry, and KDF has always read the untransformed catalog.
@immutable
final class KdfStartupCatalog {
  /// Each null field keeps the production default.
  const KdfStartupCatalog({
    this.dataFactory,
    this.storageNamespace,
    this.runtimeUpdateConfig,
  });

  /// The bundled catalog under the compile-time `KDF_COINS_STORAGE_NAMESPACE`.
  static const bundled = KdfStartupCatalog();

  /// Catalog sources, such as an isolated fixture catalog.
  final CoinConfigDataFactory? dataFactory;

  /// Storage namespace, which also names the Hive folder, as it does for the
  /// SDK's asset manager. A non-empty value reads the bundled assets only.
  final String? storageNamespace;

  /// Explicit catalog source configuration instead of the bundled one.
  final AssetRuntimeUpdateConfig? runtimeUpdateConfig;

  /// Reads the raw coin configs without starting any catalog updates.
  Future<JsonList> loadCoins() => StartupCoinsProvider.fetchRawCoinsForStartup(
    dataFactory: dataFactory,
    storageNamespace: storageNamespace,
    appName: storageNamespace,
    configRepository: runtimeUpdateConfig == null
        ? null
        : _FixedRuntimeUpdateConfig(runtimeUpdateConfig!),
  );

  @override
  bool operator ==(Object other) =>
      other is KdfStartupCatalog &&
      other.dataFactory == dataFactory &&
      other.storageNamespace == storageNamespace &&
      other.runtimeUpdateConfig == runtimeUpdateConfig;

  @override
  int get hashCode =>
      Object.hash(dataFactory, storageNamespace, runtimeUpdateConfig);
}

final class _FixedRuntimeUpdateConfig
    extends AssetRuntimeUpdateConfigRepository {
  _FixedRuntimeUpdateConfig(this._config);

  final AssetRuntimeUpdateConfig _config;

  @override
  Future<AssetRuntimeUpdateConfig> load() async => _config;
}
