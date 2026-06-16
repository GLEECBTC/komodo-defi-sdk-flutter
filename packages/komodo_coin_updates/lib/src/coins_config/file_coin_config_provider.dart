import 'dart:convert';

import 'package:komodo_coin_updates/src/coins_config/asset_parser.dart';
import 'package:komodo_coin_updates/src/coins_config/coin_config_provider.dart';
import 'package:komodo_coin_updates/src/coins_config/config_transform.dart';
import 'package:komodo_coin_updates/src/coins_config/custom_coins_file.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// A [CoinConfigProvider] that loads the enriched coins configuration
/// (`coins_config.json`-shaped map) from a user-supplied [CustomCoinsFile]
/// snapshot instead of the bundled app asset.
///
/// The parsing pipeline mirrors [LocalAssetCoinConfigProvider] so the resulting
/// [Asset]s are identical in shape to the bundled configuration.
class FileCoinConfigProvider implements CoinConfigProvider {
  /// Creates a provider backed by the [file] snapshot.
  ///
  /// [commit] is reported by [getLatestCommit]; it defaults to a sentinel that
  /// marks the configuration as a local custom override.
  FileCoinConfigProvider(
    this.file, {
    CoinConfigTransformer? transformer,
    String commit = customCoinsCommit,
  }) : _transformer = transformer ?? const CoinConfigTransformer(),
       _commit = commit;

  /// Sentinel commit hash used to identify a locally-overridden config.
  static const String customCoinsCommit = 'custom-local';

  static final Logger _log = Logger('FileCoinConfigProvider');

  /// The coins-config file snapshot backing this provider.
  final CustomCoinsFile file;

  final CoinConfigTransformer _transformer;
  final String _commit;

  @override
  Future<List<Asset>> getAssetsForCommit(String commit) => _loadAssets();

  @override
  Future<List<Asset>> getAssets({String? branch}) => _loadAssets();

  @override
  Future<String> getLatestCommit({
    String? branch,
    String? apiBaseUrl,
    String? githubToken,
  }) async => _commit;

  Future<List<Asset>> _loadAssets() async {
    _log.info('Loading custom coins config from ${file.displayLabel}');

    final decoded = jsonDecode(file.content);
    if (decoded is! Map) {
      throw FormatException(
        'Custom coins config must be a JSON object mapping coin tickers to '
        'their configuration (got ${decoded.runtimeType}).',
      );
    }
    final items = Map<String, dynamic>.from(decoded);
    _log.info('Loaded ${items.length} coin configurations from custom file');

    // Skip structurally-invalid entries rather than failing the whole file.
    // This mirrors the per-coin tolerance of [AssetParser] (which skips coins
    // with missing/invalid protocol fields), so one malformed entry among the
    // 700+ coins does not break loading the valid ones.
    final transformedItems = <String, Map<String, dynamic>>{};
    var skipped = 0;
    for (final entry in items.entries) {
      final value = entry.value;
      if (value is! Map) {
        _log.warning(
          'Skipping coin "${entry.key}": expected a JSON object but got '
          '${value.runtimeType}.',
        );
        skipped++;
        continue;
      }
      transformedItems[entry.key] = _transformer.apply(
        Map<String, dynamic>.from(value),
      );
    }
    if (skipped > 0) {
      _log.warning(
        'Skipped $skipped malformed coin '
        '${skipped == 1 ? 'entry' : 'entries'} in custom coins config.',
      );
    }

    const parser = AssetParser(loggerName: 'FileCoinConfigProvider');

    return parser.parseAssetsFromConfig(
      transformedItems,
      shouldFilterCoin: (coinData) => const CoinFilter().shouldFilter(coinData),
      logContext: 'from custom file',
    );
  }
}
