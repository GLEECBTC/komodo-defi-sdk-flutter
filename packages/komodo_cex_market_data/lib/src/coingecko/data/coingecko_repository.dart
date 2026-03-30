import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/cex_repository.dart';
import 'package:komodo_cex_market_data/src/coingecko/_coingecko_index.dart';
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

  /// Populated only after a successful fetch; failures do not poison retries.
  List<CexCoin>? _cachedCoinList;
  Future<List<CexCoin>>? _coinListInFlight;
  Set<String>? _cachedFiatCurrencies;

  /// Tracks when the last coin list fetch failed, to prevent API request spam.
  /// When a fetch fails (e.g. due to rate limiting), we avoid retrying until
  /// the cooldown period has elapsed.
  DateTime? _lastCoinListFailure;
  static const _coinListFailureCooldown = Duration(minutes: 5);

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
    if (_cachedCoinList != null) {
      return _cachedCoinList!;
    }

    // Prevent API spam: don't retry if we recently failed.
    // Without this guard, every price request triggers supports() which calls
    // getCoinList(), and each failed call immediately retries the API — causing
    // a request storm that exhausts rate limits.
    if (_lastCoinListFailure != null) {
      final elapsed = DateTime.now().difference(_lastCoinListFailure!);
      if (elapsed < _coinListFailureCooldown) {
        throw StateError(
          'CoinGecko coin list fetch is in cooldown after a recent failure '
          '(${(_coinListFailureCooldown - elapsed).inSeconds}s remaining)',
        );
      }
      _lastCoinListFailure = null;
    }

    if (_coinListInFlight != null) {
      return _coinListInFlight!;
    }
    _coinListInFlight = _fetchCoinListInternal()
        .then((list) {
          _cachedCoinList = list;
          _lastCoinListFailure = null;
          return list;
        })
        .catchError((Object error, StackTrace stackTrace) {
          _lastCoinListFailure = DateTime.now();
          Error.throwWithStackTrace(error, stackTrace);
        })
        .whenComplete(() {
          _coinListInFlight = null;
        });
    return _coinListInFlight!;
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

    dates.sort();

    if (dates.isEmpty) {
      return {};
    }

    final startDate = dates.first.add(const Duration(days: -2));
    final endDate = dates.last.add(const Duration(days: 2));
    final daysDiff = endDate.difference(startDate).inDays;

    final result = <DateTime, Decimal>{};

    // Process in batches to avoid overwhelming the API and stay within API plan limits
    final maxDaysAllowed = _getMaxDaysForDailyData();
    for (var i = 0; i <= daysDiff; i += maxDaysAllowed) {
      final batchStartDate = startDate.add(Duration(days: i));
      final batchEndDate = i + maxDaysAllowed > daysDiff
          ? endDate
          : startDate.add(Duration(days: i + maxDaysAllowed));

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

      // Add a small delay between batch requests to avoid rate limiting
      if (i + maxDaysAllowed <= daysDiff) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    return result;
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
