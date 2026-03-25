import 'package:collection/collection.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

const _coinGeckoFallbackIds = <String, String>{
  'TRX': 'tron',
  'TRX-BEP20': 'tron',
};

const _coinPaprikaFallbackIds = <String, String>{
  'TRX': 'trx-tron',
  'TRX-BEP20': 'trx-tron',
};

String? _fallbackIdForAsset(AssetId assetId, Map<String, String> aliases) {
  return {assetId.id.toUpperCase(), assetId.symbol.configSymbol.toUpperCase()}
      .map((key) => aliases[key])
      .firstWhereOrNull((alias) => alias?.isNotEmpty ?? false);
}

/// Strategy for resolving platform-specific asset identifiers
///
/// Exceptions:
/// - [ArgumentError]: Thrown by [resolveTradingSymbol] when an asset cannot be
///   resolved for a given platform (i.e., no usable identifiers are available).
abstract class IdResolutionStrategy {
  /// Checks if this strategy can resolve a trading symbol for the given asset
  bool canResolve(AssetId assetId);

  /// Resolves the trading symbol for the given asset
  ///
  /// Throws:
  /// - [ArgumentError] if the asset cannot be resolved using this strategy.
  String resolveTradingSymbol(AssetId assetId);

  /// Returns the priority order for ID resolution (filtered to non-null, non-empty values)
  List<String> getIdPriority(AssetId assetId);

  /// Platform identifier for logging/debugging
  String get platformName;
}

/// Binance-specific ID resolution strategy
class BinanceIdResolutionStrategy implements IdResolutionStrategy {
  static final Logger _logger = Logger('BinanceIdResolutionStrategy');

  @override
  String get platformName => 'Binance';

  @override
  List<String> getIdPriority(AssetId assetId) {
    final binanceId = assetId.symbol.binanceId;
    final configSymbol = assetId.symbol.configSymbol;

    if (binanceId == null || binanceId.isEmpty) {
      _logger.fine(
        'Missing binanceId for asset ${assetId.symbol.configSymbol}, '
        'falling back to configSymbol. This may cause API issues.',
      );
    }

    return [
      binanceId,
      configSymbol,
    ].where((id) => id != null && id.isNotEmpty).cast<String>().toList();
  }

  @override
  bool canResolve(AssetId assetId) {
    return getIdPriority(assetId).isNotEmpty;
  }

  @override
  String resolveTradingSymbol(AssetId assetId) {
    final ids = getIdPriority(assetId);
    if (ids.isEmpty) {
      // Thrown when the asset lacks a Binance identifier and no suitable
      // fallback exists in [getIdPriority]. Callers should catch this in
      // feature-detection paths (e.g., supports()).
      throw ArgumentError(
        'Cannot resolve trading symbol for asset ${assetId.id} on $platformName',
      );
    }

    final resolvedSymbol = ids.first;
    _logger.finest(
      'Resolved trading symbol for ${assetId.symbol.configSymbol}: $resolvedSymbol '
      '(priority: ${ids.join(', ')})',
    );

    return resolvedSymbol;
  }
}

/// CoinGecko-specific ID resolution strategy
class CoinGeckoIdResolutionStrategy implements IdResolutionStrategy {
  static final Logger _logger = Logger('CoinGeckoIdResolutionStrategy');

  @override
  String get platformName => 'CoinGecko';

  /// Only uses the coinGeckoId, as CoinGecko API does not support or map
  /// to configSymbol. If coinGeckoId is null, then the CoinGecko API cannot
  /// be used and an error is thrown in [resolveTradingSymbol].
  @override
  List<String> getIdPriority(AssetId assetId) {
    final coinGeckoId =
        assetId.symbol.coinGeckoId ??
        _fallbackIdForAsset(assetId, _coinGeckoFallbackIds);

    if (coinGeckoId == null || coinGeckoId.isEmpty) {
      _logger.fine(
        'Missing coinGeckoId for asset ${assetId.symbol.configSymbol}. '
        'CoinGecko API cannot be used for this asset.',
      );
    }

    return [
      coinGeckoId,
    ].where((id) => id != null && id.isNotEmpty).cast<String>().toList();
  }

  @override
  bool canResolve(AssetId assetId) {
    return getIdPriority(assetId).isNotEmpty;
  }

  @override
  String resolveTradingSymbol(AssetId assetId) {
    final ids = getIdPriority(assetId);
    if (ids.isEmpty) {
      // Thrown when the asset lacks a CoinGecko identifier and no suitable
      // fallback exists in [getIdPriority]. Callers should catch this in
      // feature-detection paths (e.g., supports()).
      throw ArgumentError(
        'Cannot resolve trading symbol for asset ${assetId.id} on $platformName',
      );
    }

    final resolvedSymbol = ids.first;
    _logger.finest(
      'Resolved trading symbol for ${assetId.symbol.configSymbol}: $resolvedSymbol '
      '(priority: ${ids.join(', ')})',
    );

    return resolvedSymbol;
  }
}

/// CoinPaprika-specific ID resolution strategy
class CoinPaprikaIdResolutionStrategy implements IdResolutionStrategy {
  static final Logger _logger = Logger('CoinPaprikaIdResolutionStrategy');

  @override
  String get platformName => 'CoinPaprika';

  /// Only uses the coinPaprikaId, as CoinPaprika API requires specific coin IDs.
  /// If coinPaprikaId is null, then the CoinPaprika API cannot be used and an
  /// error is thrown in [resolveTradingSymbol].
  @override
  List<String> getIdPriority(AssetId assetId) {
    final coinPaprikaId =
        assetId.symbol.coinPaprikaId ??
        _fallbackIdForAsset(assetId, _coinPaprikaFallbackIds);

    if (coinPaprikaId == null || coinPaprikaId.isEmpty) {
      _logger.fine(
        'Missing coinPaprikaId for asset ${assetId.symbol.configSymbol}. '
        'CoinPaprika API cannot be used for this asset.',
      );
    }

    return [
      coinPaprikaId,
    ].where((id) => id != null && id.isNotEmpty).cast<String>().toList();
  }

  @override
  bool canResolve(AssetId assetId) {
    return getIdPriority(assetId).isNotEmpty;
  }

  @override
  String resolveTradingSymbol(AssetId assetId) {
    final ids = getIdPriority(assetId);
    if (ids.isEmpty) {
      // Thrown when the asset lacks a CoinPaprika identifier and no suitable
      // fallback exists in [getIdPriority]. Callers should catch this in
      // feature-detection paths (e.g., supports()).
      throw ArgumentError(
        'Cannot resolve trading symbol for asset ${assetId.id} on $platformName',
      );
    }

    final resolvedSymbol = ids.first;
    _logger.finest(
      'Resolved trading symbol for ${assetId.symbol.configSymbol}: $resolvedSymbol '
      '(priority: ${ids.join(', ')})',
    );

    return resolvedSymbol;
  }
}

/// Komodo-specific ID resolution strategy
class KomodoIdResolutionStrategy implements IdResolutionStrategy {
  @override
  String get platformName => 'Komodo';

  @override
  List<String> getIdPriority(AssetId assetId) {
    return [assetId.symbol.configSymbol].where((id) => id.isNotEmpty).toList();
  }

  @override
  bool canResolve(AssetId assetId) {
    return getIdPriority(assetId).isNotEmpty;
  }

  @override
  String resolveTradingSymbol(AssetId assetId) {
    final ids = getIdPriority(assetId);
    if (ids.isEmpty) {
      // Thrown when the asset lacks a Komodo identifier and no suitable
      // fallback exists in [getIdPriority]. Callers should catch this in
      // feature-detection paths (e.g., supports()).
      throw ArgumentError(
        'Cannot resolve trading symbol for asset ${assetId.id} on $platformName',
      );
    }
    return ids.first;
  }
}
