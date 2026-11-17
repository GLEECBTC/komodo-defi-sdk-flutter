// Using relative imports in this "package" to make it easier to track external
// dependencies when moving or copying this "package" to another project.

// TODO: look into custom exception types or justifying the current approach.
// ignore_for_file: avoid_catches_without_on_clauses

import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_cex_market_data/src/common/shared_fetch.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

// Declaring constants here to make this easier to copy & move around
/// The base URL for the Binance API.
List<String> get binanceApiEndpoint => [
  'https://api.binance.com/api/v3',
  'https://api.binance.us/api/v3',
];

/// A repository class for interacting with the Binance API.
/// This class provides methods to fetch legacy tickers and OHLC candle data.
class BinanceRepository implements CexRepository {
  /// Creates a new [BinanceRepository] instance.
  BinanceRepository({
    required IBinanceProvider binanceProvider,
    bool enableMemoization = true,
    DateTime Function() clock = DateTime.now,
  }) : _binanceProvider = binanceProvider,
       _idResolutionStrategy = BinanceIdResolutionStrategy(),
       _enableMemoization = enableMemoization,
       _coinList = RetryingMemoizer(name: 'Binance coin list', clock: clock);

  final IBinanceProvider _binanceProvider;
  final IdResolutionStrategy _idResolutionStrategy;
  final bool _enableMemoization;

  static final Logger _logger = Logger('BinanceRepository');

  /// Priority order of USD stablecoins for fallback selection
  /// Ordered from most liquid/preferred to least preferred
  static const List<String> _usdStablecoinPriority = [
    'USDT', // Tether - most liquid
    'USDC', // USD Coin - most regulated
    'BUSD', // Binance USD - native to Binance
    'FDUSD', // First Digital USD
    'TUSD', // TrueUSD
    'USDP', // Pax Dollar
    'DAI', // MakerDAO DAI
    'LUSD', // Liquity USD
    'GUSD', // Gemini Dollar
    'SUSD', // Synthetix USD
    'FEI', // Fei USD
  ];

  /// Keeps only a successful fetch, so an app started offline is not left
  /// without Binance for the whole session.
  final RetryingMemoizer<List<CexCoin>> _coinList;

  /// Get the USD stablecoin priority configuration
  /// Returns a list of USD stablecoins ordered by preference for fallback selection
  static List<String> get usdStablecoinPriority =>
      List.unmodifiable(_usdStablecoinPriority);

  @override
  Future<List<CexCoin>> getCoinList() async {
    if (_enableMemoization) {
      return _coinList.runOnce(_fetchCoinListInternal);
    } else {
      // Warning: Direct API calls without memoization can lead to API
      // rate limiting and unnecessary network requests. Use this mode sparingly
      return _fetchCoinListInternal();
    }
  }

  /// Internal method to fetch coin list data from the API.
  Future<List<CexCoin>> _fetchCoinListInternal() async {
    Exception? lastException;
    // Try primary endpoint first, fallback to secondary on failure
    for (final baseUrl in binanceApiEndpoint) {
      try {
        final exchangeInfo = await _binanceProvider.fetchExchangeInfoReduced(
          baseUrl: baseUrl,
        );
        final coins = _convertSymbolsToCoins(exchangeInfo);
        // A geo-blocked endpoint (HTTP 451) answers with no symbols; the next
        // endpoint may still serve this user.
        if (coins.isEmpty) {
          throw Exception('Binance lists no tradable symbols at $baseUrl');
        }
        return coins;
      } catch (e) {
        _logger.fine('No Binance coin list from $baseUrl: $e');
        lastException = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastException ?? Exception('All endpoints failed');
  }

  CexCoin _binanceCoin(String baseCoinAbbr, String quoteCoinAbbr) {
    return CexCoin(
      id: baseCoinAbbr,
      symbol: baseCoinAbbr,
      name: baseCoinAbbr,
      currencies: <String>{quoteCoinAbbr},
      source: 'binance',
    );
  }

  @override
  Future<CoinOhlc> getCoinOhlc(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    GraphInterval interval, {
    DateTime? startAt,
    DateTime? endAt,
    int? limit,
  }) async {
    final baseTicker = resolveTradingSymbol(assetId);

    // Find the best available quote currency for this coin
    final coins = await getCoinList();
    final coin = coins.firstWhere(
      (c) => c.id.toUpperCase() == baseTicker.toUpperCase(),
      orElse: () =>
          throw ArgumentError.value(baseTicker, 'assetId', 'Asset not found'),
    );

    final effectiveQuote = _getEffectiveQuoteCurrency(coin, quoteCurrency);
    if (effectiveQuote == null) {
      throw ArgumentError(
        'No suitable quote currency available for $baseTicker with '
        'requested ${quoteCurrency.symbol}',
      );
    }

    if (baseTicker.toUpperCase() == effectiveQuote.toUpperCase()) {
      throw ArgumentError.value(
        effectiveQuote,
        'quoteCurrency',
        'Base and rel coin tickers cannot be the same',
      );
    }

    final startUnixTimestamp = startAt?.millisecondsSinceEpoch;
    final endUnixTimestamp = endAt?.millisecondsSinceEpoch;
    final intervalAbbreviation = interval.toAbbreviation();

    // Try primary endpoint first, fallback to secondary on failure
    Exception? lastException;
    for (final baseUrl in binanceApiEndpoint) {
      try {
        final symbolString =
            '${baseTicker.toUpperCase()}${effectiveQuote.toUpperCase()}';
        return await _binanceProvider.fetchKlines(
          symbolString,
          intervalAbbreviation,
          startUnixTimestampMilliseconds: startUnixTimestamp,
          endUnixTimestampMilliseconds: endUnixTimestamp,
          limit: limit,
          baseUrl: baseUrl,
        );
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastException ?? Exception('All endpoints failed');
  }

  @override
  String resolveTradingSymbol(AssetId assetId) {
    return _idResolutionStrategy.resolveTradingSymbol(assetId);
  }

  @override
  bool canHandleAsset(AssetId assetId) {
    return _idResolutionStrategy.canResolve(assetId);
  }

  @override
  Future<Decimal> getCoinFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async {
    final tradingSymbol = resolveTradingSymbol(assetId);

    // Find the best available quote currency for this coin
    final coins = await getCoinList();
    final coin = coins.firstWhere(
      (c) => c.id.toUpperCase() == tradingSymbol.toUpperCase(),
      orElse: () => throw ArgumentError.value(
        tradingSymbol,
        'assetId',
        'Asset not found',
      ),
    );

    final effectiveQuote = _getEffectiveQuoteCurrency(coin, fiatCurrency);
    if (effectiveQuote == null) {
      throw ArgumentError(
        'No suitable quote currency available for $tradingSymbol with '
        'requested ${fiatCurrency.symbol}',
      );
    }

    if (tradingSymbol.toUpperCase() == effectiveQuote.toUpperCase()) {
      throw ArgumentError.value(
        effectiveQuote,
        'fiatCurrency',
        'Coin and fiat coin cannot be the same',
      );
    }

    final endAt = priceDate ?? DateTime.now();
    final startAt = endAt.subtract(const Duration(days: 1));

    final ohlcData = await getCoinOhlc(
      assetId,
      fiatCurrency,
      GraphInterval.oneDay,
      startAt: startAt,
      endAt: endAt,
      limit: 1,
    );
    return ohlcData.ohlc.first.closeDecimal;
  }

  @override
  Future<Map<DateTime, Decimal>> getCoinFiatPrices(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async {
    final tradingSymbol = resolveTradingSymbol(assetId);

    // Find the best available quote currency for this coin
    final coins = await getCoinList();
    final coin = coins.firstWhere(
      (c) => c.id.toUpperCase() == tradingSymbol.toUpperCase(),
      orElse: () => throw ArgumentError.value(
        tradingSymbol,
        'assetId',
        'Asset not found',
      ),
    );

    final effectiveQuote = _getEffectiveQuoteCurrency(coin, fiatCurrency);
    if (effectiveQuote == null) {
      throw ArgumentError(
        'No suitable quote currency available for $tradingSymbol with '
        'requested ${fiatCurrency.symbol}',
      );
    }

    if (tradingSymbol.toLowerCase() == effectiveQuote.toLowerCase()) {
      throw ArgumentError.value(
        effectiveQuote,
        'fiatCurrency',
        'Coin and fiat coin cannot be the same',
      );
    }

    if (dates.isEmpty) {
      return {};
    }

    final sortedDates = List.of(dates)..sort();
    final startDate = sortedDates.first.add(const Duration(days: -2));
    final endDate = sortedDates.last.add(const Duration(days: 2));
    final daysDiff = endDate.difference(startDate).inDays;

    final result = <DateTime, Decimal>{};

    for (var i = 0; i <= daysDiff; i += 500) {
      final batchStartDate = startDate.add(Duration(days: i));
      final batchEndDate = i + 500 > daysDiff
          ? endDate
          : startDate.add(Duration(days: i + 500));

      final ohlcData = await getCoinOhlc(
        assetId,
        fiatCurrency,
        GraphInterval.oneDay,
        startAt: batchStartDate,
        endAt: batchEndDate,
      );

      final batchResult = ohlcData.ohlc.fold<Map<DateTime, Decimal>>({}, (
        map,
        ohlc,
      ) {
        final dateUtc = DateTime.fromMillisecondsSinceEpoch(
          ohlc.closeTimeMs,
          isUtc: true,
        );
        map[DateTime.utc(dateUtc.year, dateUtc.month, dateUtc.day)] =
            ohlc.closeDecimal;
        return map;
      });

      result.addAll(batchResult);
    }

    return result;
  }

  @override
  Future<Decimal> getCoin24hrPriceChange(
    AssetId assetId, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async {
    final tradingSymbol = resolveTradingSymbol(assetId);

    // Find the best available quote currency for this coin
    final coins = await getCoinList();
    final coin = coins.firstWhere(
      (c) => c.id.toUpperCase() == tradingSymbol.toUpperCase(),
      orElse: () => throw ArgumentError.value(
        tradingSymbol,
        'assetId',
        'Asset not found',
      ),
    );

    final effectiveQuote = _getEffectiveQuoteCurrency(coin, fiatCurrency);
    if (effectiveQuote == null) {
      throw ArgumentError(
        'No suitable quote currency available for $tradingSymbol with '
        'requested ${fiatCurrency.symbol}',
      );
    }

    if (tradingSymbol.toUpperCase() == effectiveQuote.toUpperCase()) {
      throw ArgumentError.value(
        effectiveQuote,
        'fiatCurrency',
        'Coin and fiat coin cannot be the same',
      );
    }

    final symbol =
        '${tradingSymbol.toUpperCase()}${effectiveQuote.toUpperCase()}';

    // Try primary endpoint first, fallback to secondary on failure
    Exception? lastException;
    for (final baseUrl in binanceApiEndpoint) {
      try {
        final tickerData = await _binanceProvider.fetch24hrTicker(
          symbol,
          baseUrl: baseUrl,
        );
        return tickerData.priceChangePercent;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastException ?? Exception('All endpoints failed');
  }

  List<CexCoin> _convertSymbolsToCoins(
    BinanceExchangeInfoResponseReduced exchangeInfo,
  ) {
    final coins = <String, CexCoin>{};
    for (final symbol in exchangeInfo.symbols) {
      final baseAsset = symbol.baseAsset;
      final quoteAsset = symbol.quoteAsset;

      // TODO(Anon): Decide if this belongs at the repository level considering
      // that the repository should provide and transform data as required
      // without implementing business logic (or make it an optional parameter).
      if (!symbol.isSpotTradingAllowed) {
        continue;
      }

      if (!coins.containsKey(baseAsset)) {
        coins[baseAsset] = _binanceCoin(baseAsset, quoteAsset);
      } else {
        coins[baseAsset] = coins[baseAsset]!.copyWith(
          currencies: {...coins[baseAsset]!.currencies, quoteAsset},
        );
      }
    }
    return coins.values.toList();
  }

  /// Find the best available USD stablecoin for a specific coin
  /// Returns null if no USD stablecoins are available for this coin
  String? _findBestUsdStablecoinForCoin(CexCoin coin) {
    for (final stablecoin in _usdStablecoinPriority) {
      if (coin.currencies.contains(stablecoin)) {
        return stablecoin;
      }
    }
    return null;
  }

  /// Get the effective quote currency for a coin, with fallback logic
  /// For USD/USDT requests, tries to find the best available USD stablecoin
  String? _getEffectiveQuoteCurrency(
    CexCoin coin,
    QuoteCurrency quoteCurrency,
  ) {
    final originalQuote = quoteCurrency.binanceId.toUpperCase();

    // If the coin directly supports the requested quote currency, use it
    if (coin.currencies.contains(originalQuote)) {
      return originalQuote;
    }

    // Special handling for USD and USD stablecoins
    final isUsdRequest =
        quoteCurrency.symbol.toUpperCase() == 'USD' ||
        (quoteCurrency.isStablecoin &&
            quoteCurrency.maybeWhen(
              stablecoin: (_, __, underlying) =>
                  underlying.symbol.toUpperCase() == 'USD',
              orElse: () => false,
            ));

    if (isUsdRequest) {
      // Try to find any available USD stablecoin for this coin
      return _findBestUsdStablecoinForCoin(coin);
    }

    // For non-USD currencies, no fallback - must have exact match
    return null;
  }

  @override
  Future<bool> supports(
    AssetId assetId,
    QuoteCurrency fiatCurrency,
    PriceRequestType requestType,
  ) async {
    try {
      final coins = await getCoinList();
      // If resolveTradingSymbol throws, treat as unsupported
      final tradingSymbol = resolveTradingSymbol(assetId);

      // Find the specific coin
      final coin = coins.firstWhere(
        (c) => c.id.toUpperCase() == tradingSymbol.toUpperCase(),
        orElse: () => throw ArgumentError.value(
          tradingSymbol,
          'assetId',
          'Asset not found',
        ),
      );

      // Check if we can find an effective quote currency for this coin
      final effectiveQuote = _getEffectiveQuoteCurrency(coin, fiatCurrency);
      return effectiveQuote != null;
    } on ArgumentError {
      return false;
    }
  }

  @override
  void dispose() {
    // No resources to dispose in this implementation
  }
}
