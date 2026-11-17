import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/cex_repository.dart';
import 'package:komodo_cex_market_data/src/coingecko/_coingecko_index.dart';
import 'package:komodo_cex_market_data/src/common/shared_fetch.dart';
import 'package:komodo_cex_market_data/src/id_resolution_strategy.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:komodo_cex_market_data/src/repository_selection_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The number of seconds in a day.
const int secondsInDay = 86400;

/// A repository class for interacting with the CoinGecko API.
class CoinGeckoRepository implements CexRepository {
  /// Creates a new instance of [CoinGeckoRepository].
  CoinGeckoRepository({
    required this.coinGeckoProvider,
    this.apiPlan = const CoingeckoApiPlan.demo(),
    bool enableMemoization = true,
  }) : _idResolutionStrategy = CoinGeckoIdResolutionStrategy(),
       _enableMemoization = enableMemoization;

  /// The CoinGecko provider to use for fetching data.
  final ICoinGeckoProvider coinGeckoProvider;

  /// The API plan defining rate limits and historical data access.
  final CoingeckoApiPlan apiPlan;

  final IdResolutionStrategy _idResolutionStrategy;
  final bool _enableMemoization;

  /// Keeps only a successful fetch. After a failure (e.g. rate limiting) the
  /// fetch is not repeated until a cooldown has passed: every price request
  /// runs supports(), which calls getCoinList(), so retrying each time would
  /// be a request storm that exhausts the rate limit.
  final _coinList = RetryingMemoizer<List<CexCoin>>(
    name: 'CoinGecko coin list',
  );
  Set<String>? _cachedFiatCurrencies;

  /// Fetches the CoinGecko market data.
  ///
  /// Returns a list of [CoinMarketData] objects containing the market data.
  ///
  /// Throws an [Exception] if the API request fails.
  ///
  /// Example usage:
  /// ```dart
  /// final List<CoinMarketData> marketData = await getCoinGeckoMarketData();
  /// ```
  Future<List<CoinMarketData>> getCoinGeckoMarketData() async {
    return coinGeckoProvider.fetchCoinMarketData();
  }

  @override
  Future<List<CexCoin>> getCoinList() async {
    if (!_enableMemoization) {
      // Warning: Direct API calls without memoization can lead to API rate limiting
      // and unnecessary network requests. Use this mode sparingly.
      return _fetchCoinListInternal();
    }
    return _coinList.runOnce(_fetchCoinListInternal);
  }

  /// Internal method to fetch coin list data from the API.
  Future<List<CexCoin>> _fetchCoinListInternal() async {
    try {
      final coins = await coinGeckoProvider.fetchCoinList();
      final supportedCurrencies = await coinGeckoProvider
          .fetchSupportedVsCurrencies();

      final result = coins
          .map(
            (CexCoin e) => e.copyWith(currencies: supportedCurrencies.toSet()),
          )
          .toSet();

      _cachedFiatCurrencies = supportedCurrencies
          .map((s) => s.toUpperCase())
          .toSet();

      return result.toList();
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }
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
    var days = 1;
    if (startAt != null && endAt != null) {
      final timeDelta = endAt.difference(startAt);
      days = (timeDelta.inSeconds.toDouble() / secondsInDay).ceil();

      // Ensure we don't request 0 days
      if (days <= 0) {
        days = 1;
      }
    }

    // Use the same ticker resolution as other methods
    final tradingSymbol = resolveTradingSymbol(assetId);

    // Get the maximum days allowed by the current API plan for daily historical data
    final maxDaysAllowed = _getMaxDaysForDailyData();

    // If the request is within the API plan limit, make a single request
    if (days <= maxDaysAllowed) {
      return coinGeckoProvider.fetchCoinOhlc(
        tradingSymbol,
        quoteCurrency.coinGeckoId,
        days,
      );
    }

    // If the request exceeds the limit, we need startAt and endAt to split requests
    if (startAt == null || endAt == null) {
      throw ArgumentError(
        'startAt and endAt must be provided for requests exceeding $maxDaysAllowed days',
      );
    }

    // Split the request into multiple sequential requests to stay within free tier limits
    final allOhlcData = <Ohlc>[];
    var currentStart = startAt;

    while (currentStart.isBefore(endAt)) {
      final currentEnd = currentStart.add(Duration(days: maxDaysAllowed));
      final batchEndDate = currentEnd.isAfter(endAt) ? endAt : currentEnd;

      final batchDays = batchEndDate.difference(currentStart).inDays;
      if (batchDays <= 0) break;

      final batchOhlc = await coinGeckoProvider.fetchCoinOhlc(
        tradingSymbol,
        quoteCurrency.coinGeckoId,
        batchDays,
      );

      allOhlcData.addAll(batchOhlc.ohlc);
      currentStart = batchEndDate;

      // Add a small delay between batch requests to avoid rate limiting
      if (currentStart.isBefore(endAt)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    return CoinOhlc(ohlc: allOhlcData);
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
    final mappedFiatId = fiatCurrency.coinGeckoId;

    final coinPrice = await coinGeckoProvider.fetchCoinHistoricalMarketData(
      id: tradingSymbol,
      date: priceDate ?? DateTime.now(),
    );

    return _extractPriceFromResponse(coinPrice, mappedFiatId);
  }

  Decimal _extractPriceFromResponse(
    CoinHistoricalData coinPrice,
    String mappedFiatId,
  ) {
    final currentPriceMap = coinPrice.marketData?.currentPrice?.toJson();
    if (currentPriceMap == null) {
      throw Exception(
        'Market data or current price not found in historical data response',
      );
    }

    final price = currentPriceMap[mappedFiatId];
    if (price == null) {
      throw Exception(
        'Price data for $mappedFiatId not found in historical data response',
      );
    }
    return Decimal.parse(price.toString());
  }

  /// Prices for [dates], keyed by UTC day, from a single request.
  ///
  /// Days in the future or older than the plan serves are left out, and no
  /// request is made when none of the days can be served.
  @override
  Future<Map<DateTime, Decimal>> getCoinFiatPrices(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async {
    final tradingSymbol = resolveTradingSymbol(assetId);
    final mappedFiatId = fiatCurrency.coinGeckoId;

    if (tradingSymbol.toUpperCase() == mappedFiatId.toUpperCase()) {
      throw ArgumentError('Coin and fiat coin cannot be the same');
    }

    // `/ohlc?days=N` always counts back from now, so the window is sized by
    // how long ago the earliest wanted day is, not by the span of the dates.
    final now = DateTime.now().toUtc();
    final earliestServed = now.subtract(
      Duration(days: _getMaxDaysForDailyData()),
    );
    final wantedDays = {
      for (final date in dates.map(_utcDay))
        if (!date.isBefore(earliestServed) && !date.isAfter(now)) date,
    };
    if (wantedDays.isEmpty) {
      return {};
    }

    final earliestWanted = wantedDays.reduce((a, b) => a.isBefore(b) ? a : b);
    final daysBack = (now.difference(earliestWanted).inSeconds / secondsInDay)
        .ceil();
    final ohlcData = await coinGeckoProvider.fetchCoinOhlc(
      tradingSymbol,
      mappedFiatId,
      _ohlcWindowDays.firstWhere((days) => days >= daysBack),
    );

    final result = <DateTime, Decimal>{};
    for (final ohlc in ohlcData.ohlc) {
      final day = _utcDay(
        DateTime.fromMillisecondsSinceEpoch(ohlc.closeTimeMs, isUtc: true),
      );
      if (wantedDays.contains(day)) result[day] = ohlc.closeDecimal;
    }
    return result;
  }

  /// The window lengths the OHLC endpoint documents for its `days` parameter.
  static const _ohlcWindowDays = [1, 7, 14, 30, 90, 180, 365];

  static DateTime _utcDay(DateTime date) {
    final utc = date.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  @override
  Future<Decimal> getCoin24hrPriceChange(
    AssetId assetId, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async {
    final tradingSymbol = resolveTradingSymbol(assetId);
    final mappedFiatId = fiatCurrency.coinGeckoId;

    if (tradingSymbol.toUpperCase() == mappedFiatId.toUpperCase()) {
      throw ArgumentError('Coin and fiat coin cannot be the same');
    }

    final priceData = await coinGeckoProvider.fetchCoinMarketData(
      ids: [tradingSymbol],
      vsCurrency: mappedFiatId, // Use mapped fiat currency
    );
    if (priceData.length != 1) {
      throw Exception('Invalid market data for $tradingSymbol');
    }

    final priceChange = priceData.first.priceChangePercentage24h;
    if (priceChange == null) {
      throw Exception('Price change data not available for $tradingSymbol');
    }
    return priceChange;
  }

  @override
  Future<bool> supports(
    AssetId assetId,
    QuoteCurrency fiatCurrency,
    PriceRequestType requestType,
  ) async {
    try {
      final coins = await getCoinList();
      final mappedFiat = fiatCurrency.coinGeckoId;

      // Use the same logic as resolveTradingSymbol to find the coin
      final tradingSymbol = resolveTradingSymbol(assetId);
      final supportsAsset = coins.any(
        (c) => c.id.toLowerCase() == tradingSymbol.toLowerCase(),
      );
      final supportsFiat =
          _cachedFiatCurrencies?.contains(mappedFiat.toUpperCase()) ?? false;
      return supportsAsset && supportsFiat;
    } on ArgumentError {
      // If we cannot resolve a trading symbol, treat as unsupported
      return false;
    } catch (_) {
      // Coin list / network failures: treat as unsupported so fallback repos run
      // without throwing from [DefaultRepositorySelectionStrategy].
      return false;
    }
  }

  /// Gets the maximum number of days allowed for daily historical data requests
  /// based on the current API plan.
  int _getMaxDaysForDailyData() {
    final cutoffDate = apiPlan.getDailyHistoricalDataCutoff();
    if (cutoffDate == null) {
      // No cutoff means unlimited access, but we still need to batch requests
      // Use a reasonable batch size for API efficiency
      return 365;
    }

    final now = DateTime.now().toUtc();
    final daysSinceCutoff = now.difference(cutoffDate).inDays;

    // For demo plan (1 year limit), return 365
    // For paid plans with cutoff from 2013/2018, return a reasonable batch size
    return daysSinceCutoff > 365 ? 365 : daysSinceCutoff;
  }

  @override
  void dispose() {
    // No resources to dispose in this implementation
  }
}
