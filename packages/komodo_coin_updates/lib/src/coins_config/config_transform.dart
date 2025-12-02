import 'package:flutter/foundation.dart' show kIsWeb, kIsWasm;
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:logging/logging.dart';

/// Defines a transform that can be applied to a single coin configuration.
///
/// Implementations must indicate whether they need to run for a given
/// configuration and return a transformed copy when applied.
abstract class CoinConfigTransform {
  /// Returns a new configuration with this transform applied.
  ///
  /// Implementations should avoid mutating the original map to preserve
  /// idempotency.
  JsonMap transform(JsonMap config);

  /// Returns true if this transform should be applied to the provided [config].
  bool needsTransform(JsonMap config);
}

/// This class is responsible for doing any necessary fixes to the coin config
/// before it is used by the rest of the library.
/// This should be used only when absolutely necessary and not for transforming
/// the config for easier parsing; that should be encapsulated in the
/// respective classes.
class CoinConfigTransformer {
  /// Creates a new [CoinConfigTransformer] with the provided transforms.
  /// If [transforms] is omitted, a default set is used.
  const CoinConfigTransformer({List<CoinConfigTransform>? transforms})
    : _transforms =
          transforms ??
          const [
            WssWebsocketTransform(),
            SslElectrumTransform(),
            ZhtlcLightWalletTransform(),
            ParentCoinTransform(),
          ];

  final List<CoinConfigTransform> _transforms;

  /// Applies all necessary transforms to the given coin configuration.
  JsonMap apply(JsonMap config) {
    final neededTransforms = _transforms.where((t) => t.needsTransform(config));

    if (neededTransforms.isEmpty) {
      return config;
    }

    return neededTransforms.fold(
      config,

      // Instantiating a new map for each transform is not ideal, given the
      // large size of the config file. However, it is necessary to avoid
      // mutating the original map and for making the transforms idempotent.
      // Use sparingly and ideally only once.
      (config, transform) => transform.transform(JsonMap.of(config)),
    );
  }
}

/// This class is responsible for transforming a list of coin configurations.
/// It applies the necessary transforms to each configuration in the list.
class CoinConfigListTransformer {
  const CoinConfigListTransformer();

  /// Applies all registered transforms to each configuration in [configs].
  /// The input list is cloned before modification to preserve immutability.
  static JsonList applyTransforms(
    JsonList configs, {
    CoinConfigTransformer transformer = const CoinConfigTransformer(),
  }) {
    final result = JsonList.of(configs);

    for (var i = 0; i < result.length; i++) {
      result[i] = transformer.apply(result[i]);
    }

    return result;
  }

  /// Applies transforms to each config in the list and filters out coins that should be excluded.
  static JsonList applyTransformsAndFilter(
    JsonList configs, {
    CoinConfigTransformer transformer = const CoinConfigTransformer(),
  }) {
    final transformedList = applyTransforms(configs, transformer: transformer);
    return transformedList
        .where((config) => !const CoinFilter().shouldFilter(config))
        .toList();
  }
}

extension CoinConfigTransformExtension on JsonMap {
  /// Returns a transformed copy of this configuration by applying all
  /// registered transforms.
  JsonMap applyTransforms({
    CoinConfigTransformer transformer = const CoinConfigTransformer(),
  }) => transformer.apply(this);
}

extension CoinConfigListTransformExtension on JsonList {
  /// Returns a transformed copy of the configurations list by applying all
  /// registered transforms to each item.
  JsonList applyTransforms({
    CoinConfigTransformer transformer = const CoinConfigTransformer(),
  }) =>
      CoinConfigListTransformer.applyTransforms(this, transformer: transformer);

  /// Returns a transformed and filtered copy of the configurations list by
  /// applying transforms and then excluding coins that should be filtered.
  JsonList applyTransformsAndFilter({
    CoinConfigTransformer transformer = const CoinConfigTransformer(),
  }) => CoinConfigListTransformer.applyTransformsAndFilter(
    this,
    transformer: transformer,
  );
}

/// If true, only test coins are allowed when filtering.
const bool _isTestCoinsOnly = false;

/// Filters out coins from runtime configuration based on a set of rules.
class CoinFilter {
  const CoinFilter();

  /// Specific coins (by ticker) to exclude from the runtime list.
  static const _filteredCoins = <String, String>{};

  /// Protocol subtypes to exclude from the runtime list.
  static const _filteredProtocolSubTypes = {'SLP': 'Simple Ledger Protocol'};

  // NFT was previosly filtered out, but it is now required with the NFT v2
  // migration. NFT_<COIN> coins are used to represent NFTs on the chain.
  /// Protocol types to exclude from the runtime list.
  static const _filteredProtocolTypes = <String, String>{};

  /// Returns true if the given coin should be filtered out.
  bool shouldFilter(JsonMap config) {
    // Honor an explicit exclusion marker
    if (config.valueOrNull<bool>('excluded') ?? false) {
      return true;
    }

    final coin = config.value<String>('coin');
    final protocolSubClass = config.valueOrNull<String>('type');
    final protocolClass = config.valueOrNull<String>('protocol', 'type');
    final isTestnet = config.valueOrNull<bool>('is_testnet') ?? false;

    return _filteredCoins.containsKey(coin) ||
        _filteredProtocolTypes.containsKey(protocolClass) ||
        _filteredProtocolSubTypes.containsKey(protocolSubClass) ||
        (_isTestCoinsOnly && !isTestnet);
  }
}

/// Filters out non-wss electrum/server URLs from the given coin config for
/// the web platform as only wss connections are supported.
class WssWebsocketTransform implements CoinConfigTransform {
  const WssWebsocketTransform();

  @override
  /// Determines if the transform should run by checking the presence of an
  /// `electrum` list in the configuration.
  bool needsTransform(JsonMap config) {
    final electrum = config.valueOrNull<JsonList>('electrum');
    return electrum != null;
  }

  @override
  /// Filters `electrum` entries based on the platform: WSS-only on web and
  /// non-WSS on native platforms.
  JsonMap transform(JsonMap config) {
    final electrum = JsonList.of(config.value<JsonList>('electrum'));
    // On native, only non-WSS servers are supported. On web, only WSS servers
    // are supported.
    final filteredElectrums = filterElectrums(
      electrum,
      serverType: kIsWeb
          ? ElectrumServerType.wssOnly
          : ElectrumServerType.nonWssOnly,
    );

    return config..['electrum'] = filteredElectrums;
  }

  /// Returns a filtered copy of [electrums] keeping only entries allowed by
  /// [serverType]. For WSS entries, `ws_url` is normalized to match `url`.
  JsonList filterElectrums(
    JsonList electrums, {
    required ElectrumServerType serverType,
  }) {
    final electrumsCopy = JsonList.of(electrums);

    for (final e in electrumsCopy) {
      if (e['protocol'] == 'WSS') {
        e['ws_url'] = e['url'];
      }
    }

    return electrumsCopy..removeWhere(
      (JsonMap e) => serverType == ElectrumServerType.wssOnly
          ? e['ws_url'] == null
          : e['ws_url'] != null,
    );
  }
}

/// Specifies which type of Electrum servers to retain
enum ElectrumServerType { wssOnly, nonWssOnly }

/// Filters out insecure connections on non-web platforms, emulating the
/// filtering applied to the coins_config_ssl.json file in GLEECBTC/coins
/// On non-web platforms, only SSL electrum servers and HTTPS URLs are
/// supported for security.
// TODO: move this to a build-time step via the coins config and/or the
// komodo_wallet_build_transformer package
class SslElectrumTransform implements CoinConfigTransform {
  const SslElectrumTransform();

  static final _log = Logger('SslElectrumTransform');

  @override
  /// Determines if the transform should run by checking if this is a non-web
  /// platform with any of the filterable fields in the configuration.
  bool needsTransform(JsonMap config) {
    // Only run on non-web platforms
    if (kIsWeb || kIsWasm) return false;

    final electrum = config.valueOrNull<List>('electrum');
    final rpcNodes = config.valueOrNull<List>('nodes');
    final lightWalletServers = config.valueOrNull<List>(
      'light_wallet_d_servers',
    );

    return electrum != null || rpcNodes != null || lightWalletServers != null;
  }

  @override
  /// Filters entries to keep only secure connections on non-web platforms.
  JsonMap transform(JsonMap config) {
    final result = JsonMap.of(config);
    final coin = config.valueOrNull<String>('coin') ?? 'unknown';
    // Filter electrum servers - keep only SSL protocol
    final electrum = config.valueOrNull<JsonList>('electrum');
    if (electrum != null) {
      final originalCount = electrum.length;
      final filteredElectrums = electrum.where((JsonMap e) {
        final protocol = e.valueOrNull<String>('protocol');
        return protocol == 'SSL';
      }).toList();

      if (filteredElectrums.isEmpty && originalCount > 0) {
        _log.warning(
          'SslElectrumTransform: All $originalCount electrum servers filtered '
          'out for $coin (no SSL servers available)',
        );
      }

      result['electrum'] = filteredElectrums;
    }

    // Filter RPC nodes - keep only HTTPS URLs
    final rpcNodes = config.valueOrNull<JsonList>('nodes');
    if (rpcNodes != null) {
      final originalCount = rpcNodes.length;
      final filteredRpcNodes = rpcNodes.where((JsonMap node) {
        final url = node.valueOrNull<String>('url');
        return url != null && url.startsWith('https://');
      }).toList();

      if (filteredRpcNodes.isEmpty && originalCount > 0) {
        _log.warning(
          'SslElectrumTransform: All $originalCount RPC nodes filtered '
          'out for $coin (no HTTPS nodes available)',
        );
      }

      result['nodes'] = filteredRpcNodes;
    }

    // Filter light wallet servers - keep only HTTPS URLs
    final lightWalletServers = config.valueOrNull<List>(
      'light_wallet_d_servers',
    );
    if (lightWalletServers != null) {
      final originalCount = lightWalletServers.length;
      final filteredLightWalletServers = lightWalletServers.where((
        dynamic server,
      ) {
        return server is String && server.startsWith('https://');
      }).toList();

      if (filteredLightWalletServers.isEmpty && originalCount > 0) {
        _log.warning(
          'SslElectrumTransform: All $originalCount light wallet servers '
          'filtered out for $coin (no HTTPS servers available)',
        );
      }

      result['light_wallet_d_servers'] = filteredLightWalletServers;
    }

    // Mark coin as having insufficient secure servers if all critical servers were filtered
    final hasElectrum = (result['electrum'] as List?)?.isNotEmpty ?? false;
    final hasNodes = (result['nodes'] as List?)?.isNotEmpty ?? false;
    final hasLightWallet =
        (result['light_wallet_d_servers'] as List?)?.isNotEmpty ?? false;

    // If the coin had servers but now has none, mark it
    if (!hasElectrum &&
        !hasNodes &&
        !hasLightWallet &&
        (electrum != null || rpcNodes != null || lightWalletServers != null)) {
      _log.severe(
        'SslElectrumTransform: Coin $coin has no secure servers available '
        'after filtering - coin may not be activatable',
      );
      // Optionally mark the coin for exclusion or special handling
      // result['_ssl_filtered_empty'] = true;
    }

    return result;
  }
}

class ParentCoinTransform implements CoinConfigTransform {
  const ParentCoinTransform();

  @override
  /// Returns true if `parent_coin` exists and requires remapping to a concrete
  /// parent (e.g. `SLP` → `BCH`).
  bool needsTransform(JsonMap config) =>
      config.valueOrNull<String>('parent_coin') != null &&
      _ParentCoinResolver.needsRemapping(config.value('parent_coin'));

  @override
  /// Remaps `parent_coin` to the resolved concrete parent when needed.
  JsonMap transform(JsonMap config) {
    final parentCoin = config.valueOrNull<String>('parent_coin');
    if (parentCoin != null && _ParentCoinResolver.needsRemapping(parentCoin)) {
      return config
        ..['parent_coin'] = _ParentCoinResolver.resolveParentCoin(parentCoin);
    }
    return config;
  }
}

class _ParentCoinResolver {
  const _ParentCoinResolver._();

  static const _parentCoinMappings = {
    'SLP': 'BCH',
    // Add any other mappings here as needed
  };

  /// Resolves the actual parent coin ticker from a given parent coin identifier.
  ///
  /// For example, `SLP` resolves to `BCH` since SLP tokens are BCH tokens.
  static String resolveParentCoin(String parentCoin) =>
      _parentCoinMappings[parentCoin] ?? parentCoin;

  /// Returns true if this parent coin identifier needs remapping.
  static bool needsRemapping(String? parentCoin) =>
      _parentCoinMappings.containsKey(parentCoin);
}

/// Replaces `light_wallet_d_servers` with `light_wallet_d_servers_wss` for ZHTLC coins
/// on web/wasm platforms to ensure WebSocket compatibility.
class ZhtlcLightWalletTransform implements CoinConfigTransform {
  const ZhtlcLightWalletTransform();

  @override
  /// Determines if the transform should run by checking if this is a ZHTLC coin
  /// on a web/wasm platform that has both light_wallet_d_servers and light_wallet_d_servers_wss configured.
  bool needsTransform(JsonMap config) {
    // Only run on web or wasm platforms
    if (!kIsWeb && !kIsWasm) return false;

    // Only run for ZHTLC coin type
    final coinType = config.valueOrNull<String>('type');
    if (coinType != 'ZHTLC') return false;

    final lightWalletServersWss = config.valueOrNull<List>(
      'light_wallet_d_servers_wss',
    );

    return lightWalletServersWss != null && lightWalletServersWss.isNotEmpty;
  }

  @override
  /// Replaces the `light_wallet_d_servers` list with the `light_wallet_d_servers_wss` list
  /// for WebSocket compatibility in web/wasm environments.
  JsonMap transform(JsonMap config) {
    // .value used here since the needsTransform check should only allow this to
    // run if present. No strict type given to checking here since we don't
    // need to perform operations on the individual elements.
    final lightWalletServersWss = config.value<List>(
      'light_wallet_d_servers_wss',
    );

    return config..['light_wallet_d_servers'] = lightWalletServersWss;
  }
}
