import 'dart:convert';

import 'package:decimal/decimal.dart' show Decimal;
import 'package:http/http.dart' as http;
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:logging/logging.dart';

/// Interface for fetching data from CoinGecko API.
///
/// This interface provides methods to interact with the CoinGecko cryptocurrency
/// data API, including fetching coin lists, market data, charts, and historical data.
/// All methods are asynchronous and return Future objects.
abstract class ICoinGeckoProvider {
  /// Fetches a list of available coins from CoinGecko.
  ///
  /// [includePlatforms] - Whether to include platform information for each coin.
  ///                       When true, returns additional blockchain platform details.
  ///
  /// Returns a list of [CexCoin] objects representing available cryptocurrencies.
  ///
  /// Throws an exception if the API request fails or the response cannot be parsed.
  Future<List<CexCoin>> fetchCoinList({bool includePlatforms = false});

  /// Fetches the list of supported vs (versus) currencies.
  ///
  /// Returns a list of currency codes (e.g., 'usd', 'eur', 'btc') that can be
  /// used as the base currency for price comparisons and market data.
  ///
  /// Throws an exception if the API request fails or the response cannot be parsed.
  Future<List<String>> fetchSupportedVsCurrencies();

  /// Fetches market data for coins with various filtering and pagination options.
  ///
  /// [vsCurrency] - The target currency for price data (default: 'usd').
  /// [ids] - Optional list of coin IDs to filter results. If null, returns all coins.
  /// [category] - Optional category filter (e.g., 'decentralized_finance_defi').
  /// [order] - Sort order for results (default: 'market_cap_asc').
  ///           Options: 'market_cap_asc', 'market_cap_desc', 'volume_asc', 'volume_desc',
  ///                    'id_asc', 'id_desc', 'gecko_asc', 'gecko_desc'.
  /// [perPage] - Number of results per page (default: 100, max: 250).
  /// [page] - Page number for pagination (default: 1).
  /// [sparkline] - Whether to include sparkline data (default: false).
  /// [priceChangePercentage] - Optional time period for price change percentage.
  ///                           Options: '1h', '24h', '7d', '14d', '30d', '200d', '1y'.
  /// [locale] - Language for localization (default: 'en').
  /// [precision] - Optional precision for price data.
  ///
  /// Returns a list of [CoinMarketData] objects containing market information.
  ///
  /// Throws an exception if the API request fails or the response cannot be parsed.
  Future<List<CoinMarketData>> fetchCoinMarketData({
    String vsCurrency = 'usd',
    List<String>? ids,
    String? category,
    String order = 'market_cap_asc',
    int perPage = 100,
    int page = 1,
    bool sparkline = false,
    String? priceChangePercentage,
    String locale = 'en',
    String? precision,
  });

  /// Fetches historical market chart data for a specific coin.
  ///
  /// [id] - The CoinGecko ID of the coin (e.g., 'bitcoin').
  /// [vsCurrency] - The target currency for price data (e.g., 'usd').
  /// [fromUnixTimestamp] - Start time as Unix timestamp (seconds since epoch).
  /// [toUnixTimestamp] - End time as Unix timestamp (seconds since epoch).
  /// [precision] - Optional precision for price data.
  ///
  /// Returns a [CoinMarketChart] object containing price, market cap, and volume data
  /// for the specified time period.
  ///
  /// Throws an exception if the API request fails or the response cannot be parsed.
  Future<CoinMarketChart> fetchCoinMarketChart({
    required String id,
    required String vsCurrency,
    required int fromUnixTimestamp,
    required int toUnixTimestamp,
    String? precision,
  });

  /// Fetches OHLC (Open, High, Low, Close) price data for a specific coin.
  ///
  /// [id] - The CoinGecko ID of the coin (e.g., 'bitcoin').
  /// [vsCurrency] - The target currency for price data (e.g., 'usd').
  /// [days] - Number of days of data to retrieve.
  /// [precision] - Optional precision for price data.
  ///
  /// Returns a [CoinOhlc] object containing OHLC price data for the specified period.
  ///
  /// Throws an exception if the API request fails or the response cannot be parsed.
  Future<CoinOhlc> fetchCoinOhlc(
    String id,
    String vsCurrency,
    int days, {
    int? precision,
  });

  /// Fetches historical market data for a specific coin on a specific date.
  ///
  /// [id] - The CoinGecko ID of the coin (e.g., 'bitcoin').
  /// [date] - The specific date for which to retrieve historical data.
  /// [vsCurrency] - The target currency for price data (default: 'usd').
  /// [localization] - Whether to include localized data (default: false).
  ///
  /// Returns a [CoinHistoricalData] object containing historical market information
  /// for the specified coin and date.
  ///
  /// Throws an exception if the API request fails or the response cannot be parsed.
  Future<CoinHistoricalData> fetchCoinHistoricalMarketData({
    required String id,
    required DateTime date,
    String vsCurrency = 'usd',
    bool localization = false,
  });

  /// Fetches current prices for multiple coins in specified currencies.
  ///
  /// [coinGeckoIds] - List of CoinGecko IDs for the coins to fetch prices for.
  /// [vsCurrencies] - List of target currencies for price data (default: ['usd']).
  ///
  /// Returns a map where keys are coin IDs and values are [AssetMarketInformation]
  /// objects containing current price data in the specified currencies.
  ///
  /// Throws an exception if the API request fails or the response cannot be parsed.
  Future<Map<String, AssetMarketInformation>> fetchCoinPrices(
    List<String> coinGeckoIds, {
    List<String> vsCurrencies = const <String>['usd'],
  });
}

/// A class for fetching data from CoinGecko API.
class CoinGeckoCexProvider implements ICoinGeckoProvider {
  /// Creates a new instance of [CoinGeckoCexProvider].
  CoinGeckoCexProvider({
    this.baseUrl = 'api.coingecko.com',
    this.apiVersion = '/api/v3',
  });

  /// The base URL for the CoinGecko API.
  final String baseUrl;

  /// The API version for the CoinGecko API.
  final String apiVersion;

  static final Logger _logger = Logger('CoinGeckoCexProvider');

  /// Fetches the list of coins supported by CoinGecko.
  ///
  /// [includePlatforms] Include platform contract addresses.
  @override
  Future<List<CexCoin>> fetchCoinList({bool includePlatforms = false}) async {
    final queryParameters = <String, String>{
      'include_platform': includePlatforms.toString(),
    };
    final uri = Uri.https(baseUrl, '$apiVersion/coins/list', queryParameters);

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      _throwApiErrorOrException(response, 'coin list fetch');
    }

    final coins = jsonDecode(response.body) as List<dynamic>;
    return coins
        .map(
          (dynamic element) =>
              CexCoin.fromJson(element as Map<String, dynamic>),
        )
        .toList();
  }

  /// Fetches the list of supported vs currencies.
  @override
  Future<List<String>> fetchSupportedVsCurrencies() async {
    final uri = Uri.https(
      baseUrl,
      '$apiVersion/simple/supported_vs_currencies',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      _throwApiErrorOrException(response, 'supported currencies fetch');
    }

    final currencies = jsonDecode(response.body) as List<dynamic>;
    return currencies.map((dynamic currency) => currency as String).toList();
  }

  /// Fetches the market data for a specific currency.
  ///
  /// [vsCurrency] The target currency of market data (usd, eur, jpy, etc.).
  /// [ids] The ids of the coins, comma separated.
  /// [category] The category of the coins.
  /// [order] The order of the coins.
  /// [perPage] Total results per page.
  /// [page] Page through results.
  /// [sparkline] Include sparkline 7 days data.
  /// [priceChangePercentage] Comma-sepa
  /// [locale] The localization of the market data.
  /// [precision] The price's precision.
  @override
  Future<List<CoinMarketData>> fetchCoinMarketData({
    String vsCurrency = 'usd',
    List<String>? ids,
    String? category,
    String order = 'market_cap_asc',
    int perPage = 100,
    int page = 1,
    bool sparkline = false,
    String? priceChangePercentage,
    String locale = 'en',
    String? precision,
  }) {
    final queryParameters = <String, String>{
      'vs_currency': vsCurrency,
      if (ids != null) 'ids': ids.join(','),
      if (category != null) 'category': category,
      'order': order,
      'per_page': perPage.toString(),
      'page': page.toString(),
      'sparkline': sparkline.toString(),
      if (priceChangePercentage != null)
        'price_change_percentage': priceChangePercentage,
      'locale': locale,
      if (precision != null) 'price_change_percentage': precision,
    };
    final uri = Uri.https(
      baseUrl,
      '$apiVersion/coins/markets',
      queryParameters,
    );

    return http.get(uri).then((http.Response response) {
      if (response.statusCode != 200) {
        _throwApiErrorOrException(response, 'market data fetch');
      }
      final coins = jsonDecode(response.body) as List<dynamic>;
      return coins
          .map(
            (dynamic element) =>
                CoinMarketData.fromJson(element as Map<String, dynamic>),
          )
          .toList();
    });
  }

  /// Fetches the market chart data for a specific currency.
  ///
  /// [id] The id of the coin.
  /// [vsCurrency] The target currency of market data (usd, eur, jpy, etc.).
  /// [fromUnixTimestamp] From date in UNIX Timestamp.
  /// [toUnixTimestamp] To date in UNIX Timestamp.
  /// [precision] The price's precision.
  @override
  Future<CoinMarketChart> fetchCoinMarketChart({
    required String id,
    required String vsCurrency,
    required int fromUnixTimestamp,
    required int toUnixTimestamp,
    String? precision,
  }) async {
    // Validate that dates are within CoinGecko's historical data limit
    _validateHistoricalDataAccess(fromUnixTimestamp, toUnixTimestamp);

    const maxDaysPerRequest = 365;
    const secondsPerDay = 86400;
    const maxSecondsPerRequest = maxDaysPerRequest * secondsPerDay;

    final totalDuration = toUnixTimestamp - fromUnixTimestamp;

    // If the range is within 365 days, make a single request
    if (totalDuration <= maxSecondsPerRequest) {
      return _fetchCoinMarketChartSingle(
        id: id,
        vsCurrency: vsCurrency,
        fromUnixTimestamp: fromUnixTimestamp,
        toUnixTimestamp: toUnixTimestamp,
        precision: precision,
      );
    }

    // Split into multiple requests and combine results
    final List<CoinMarketChart> charts = [];
    int currentFrom = fromUnixTimestamp;

    while (currentFrom < toUnixTimestamp) {
      final currentTo = (currentFrom + maxSecondsPerRequest) > toUnixTimestamp
          ? toUnixTimestamp
          : currentFrom + maxSecondsPerRequest;

      final chart = await _fetchCoinMarketChartSingle(
        id: id,
        vsCurrency: vsCurrency,
        fromUnixTimestamp: currentFrom,
        toUnixTimestamp: currentTo,
        precision: precision,
      );

      charts.add(chart);
      currentFrom = currentTo;
    }

    // Combine all charts into one
    return _combineCoinMarketCharts(charts);
  }

  /// Makes a single API request for coin market chart data.
  Future<CoinMarketChart> _fetchCoinMarketChartSingle({
    required String id,
    required String vsCurrency,
    required int fromUnixTimestamp,
    required int toUnixTimestamp,
    String? precision,
  }) {
    final queryParameters = <String, String>{
      'vs_currency': vsCurrency,
      'from': fromUnixTimestamp.toString(),
      'to': toUnixTimestamp.toString(),
      if (precision != null) 'precision': precision,
    };
    final uri = Uri.https(
      baseUrl,
      '$apiVersion/coins/$id/market_chart/range',
      queryParameters,
    );

    return http.get(uri).then((http.Response response) {
      if (response.statusCode != 200) {
        _throwApiErrorOrException(response, 'market chart fetch', coinId: id);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CoinMarketChart.fromJson(data);
    });
  }

  /// Combines multiple CoinMarketChart objects into a single one.
  CoinMarketChart _combineCoinMarketCharts(List<CoinMarketChart> charts) {
    if (charts.isEmpty) {
      throw ArgumentError('Cannot combine empty list of charts');
    }

    if (charts.length == 1) {
      return charts.first;
    }

    final List<List<num>> combinedPrices = [];
    final List<List<num>> combinedMarketCaps = [];
    final List<List<num>> combinedTotalVolumes = [];

    for (final chart in charts) {
      combinedPrices.addAll(chart.prices);
      combinedMarketCaps.addAll(chart.marketCaps);
      combinedTotalVolumes.addAll(chart.totalVolumes);
    }

    // Remove potential duplicate data points at boundaries
    final uniquePrices = _removeDuplicateDataPoints(combinedPrices);
    final uniqueMarketCaps = _removeDuplicateDataPoints(combinedMarketCaps);
    final uniqueTotalVolumes = _removeDuplicateDataPoints(combinedTotalVolumes);

    return CoinMarketChart(
      prices: uniquePrices,
      marketCaps: uniqueMarketCaps,
      totalVolumes: uniqueTotalVolumes,
    );
  }

  /// Removes duplicate data points based on timestamp (first element).
  List<List<num>> _removeDuplicateDataPoints(List<List<num>> dataPoints) {
    if (dataPoints.isEmpty) return dataPoints;

    final Map<num, List<num>> uniquePoints = {};
    for (final point in dataPoints) {
      if (point.isNotEmpty) {
        final timestamp = point[0];
        uniquePoints[timestamp] = point;
      }
    }

    final sortedKeys = uniquePoints.keys.toList()..sort();
    return sortedKeys.map((key) => uniquePoints[key]!).toList();
  }

  /// Validates that the requested time range is within CoinGecko's historical
  /// data limits.
  /// Public API users are limited to querying historical data within the
  /// past 365 days.
  void _validateHistoricalDataAccess(
    int fromUnixTimestamp,
    int toUnixTimestamp,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const maxDaysBack = 365;
    const secondsPerDay = 86400;

    // Check if the from date is more than 365 days in the past
    final daysFromNow = (now - fromUnixTimestamp) / secondsPerDay;
    if (daysFromNow > maxDaysBack) {
      throw ArgumentError(
        'From date cannot be more than 365 days in the past for CoinGecko public API. '
        'From date is ${daysFromNow.ceil()} days ago. Maximum allowed: $maxDaysBack days.',
      );
    }

    // Check if the to date is more than 365 days in the past
    final toDaysFromNow = (now - toUnixTimestamp) / secondsPerDay;
    if (toDaysFromNow > maxDaysBack) {
      throw ArgumentError(
        'To date cannot be more than 365 days in the past for CoinGecko public API. '
        'To date is ${toDaysFromNow.ceil()} days ago. Maximum allowed: $maxDaysBack days.',
      );
    }
  }

  /// Fetches the market chart data for a specific currency.
  ///
  /// [id] The id of the coin.
  /// [vsCurrency] The target currency of market data (usd, eur, jpy, etc.).
  /// [date] The date of the market data to fetch.
  /// [localization] Include all the localized languages in response. Defaults to false.
  @override
  Future<CoinHistoricalData> fetchCoinHistoricalMarketData({
    required String id,
    required DateTime date,
    String vsCurrency = 'usd',
    bool localization = false,
  }) {
    final queryParameters = <String, String>{
      'date': _formatDate(date),
      'localization': localization.toString(),
    };
    final uri = Uri.https(
      baseUrl,
      '$apiVersion/coins/$id/history',
      queryParameters,
    );

    return http.get(uri).then((http.Response response) {
      if (response.statusCode != 200) {
        _throwApiErrorOrException(
          response,
          'historical market data fetch',
          coinId: id,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return CoinHistoricalData.fromJson(data);
    });
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$year-$month-$day';
  }

  /// Fetches prices from CoinGecko API.
  /// The CoinGecko API is used as a fallback when the Komodo API is down.
  ///
  /// The [coinGeckoIds] are the CoinGecko IDs of the coins to fetch prices for.
  /// The [vsCurrencies] is a comma-separated list of currencies to compare to.
  ///
  /// Returns a map of coingecko IDs to their [AssetMarketInformation]s.
  ///
  /// Throws an error if the request fails.
  ///
  /// Example:
  /// ```dart
  /// final prices = await cexPriceProvider.getCoinGeckoPrices(
  ///  ['bitcoin', 'ethereum'],
  /// );
  @override
  Future<Map<String, AssetMarketInformation>> fetchCoinPrices(
    List<String> coinGeckoIds, {
    List<String> vsCurrencies = const <String>['usd'],
  }) async {
    final currencies = vsCurrencies.join(',');
    coinGeckoIds.removeWhere((String id) => id.isEmpty);

    final tickersUrl = Uri.https(baseUrl, '$apiVersion/simple/price', {
      'ids': coinGeckoIds.join(','),
      'vs_currencies': currencies,
    });

    final res = await http.get(tickersUrl);
    final body = res.body;

    // Check for HTTP errors first
    if (res.statusCode != 200) {
      _throwApiErrorOrException(res, 'price data fetch');
    }

    final json = jsonDecode(body) as Map<String, dynamic>?;
    if (json == null) {
      throw Exception('Invalid response from CoinGecko API: empty response');
    }

    final prices = <String, AssetMarketInformation>{};
    json.forEach((String coingeckoId, dynamic pricesData) {
      if (coingeckoId == 'test-coin') {
        return;
      }

      // TODO(Francois): map to multiple currencies, or only allow 1 vs currency
      final price = (pricesData as Map<String, dynamic>)['usd'] as num?;

      // Parse price with explicit error handling
      Decimal parsedPrice;
      final priceString = price?.toString() ?? '';

      if (price == null || priceString.isEmpty) {
        _logger.warning(
          'CoinGecko API returned null or empty price for $coingeckoId',
        );
        throw Exception(
          'Invalid price data for $coingeckoId: received null or empty value',
        );
      }

      final tempPrice = Decimal.tryParse(priceString);
      if (tempPrice == null) {
        _logger.warning(
          'Failed to parse price "$priceString" for $coingeckoId as Decimal',
        );
        throw Exception(
          'Invalid price data for $coingeckoId: could not parse '
          '"$priceString" as decimal',
        );
      }

      parsedPrice = tempPrice;

      prices[coingeckoId] = AssetMarketInformation(
        ticker: coingeckoId,
        lastPrice: parsedPrice,
      );
    });

    return prices;
  }

  /// Fetches the ohlc data for a specific currency.
  ///
  /// [id] The id of the coin.
  /// [vsCurrency] The target currency of market data (usd, eur, jpy, etc.).
  /// [days] Data up to number of days ago.
  /// [precision] The price's precision.
  @override
  Future<CoinOhlc> fetchCoinOhlc(
    String id,
    String vsCurrency,
    int days, {
    int? precision,
  }) {
    // Validate days constraint for CoinGecko public API
    if (days > 365) {
      throw ArgumentError(
        'Days parameter cannot exceed 365 for CoinGecko public API. '
        'Requested: $days days. Maximum allowed: 365 days.',
      );
    }
    // Snap to CoinGecko OHLC-supported day buckets
    final int snappedDays = _normalizeOhlcDaysParam(days);
    if (snappedDays != days) {
      _logger.fine(
        'Snapped OHLC days from $days to $snappedDays to satisfy CoinGecko constraints',
      );
    }
    final queryParameters = <String, String>{
      'id': id,
      'vs_currency': vsCurrency,
      'days': snappedDays.toString(),
      if (precision != null) 'precision': precision.toString(),
    };

    final uri = Uri.https(
      baseUrl,
      '$apiVersion/coins/$id/ohlc',
      queryParameters,
    );

    return http.get(uri).then((http.Response response) {
      if (response.statusCode != 200) {
        _throwApiErrorOrException(response, 'OHLC data fetch', coinId: id);
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      return CoinOhlc.fromJson(data, source: OhlcSource.coingecko);
    });
  }

  /// Normalizes the OHLC `days` parameter to the nearest allowed bucket for CoinGecko:
  /// 1, 7, 14, 30, 90, 180, 365.
  /// Strategy: round up to the next allowed bucket to avoid under-fetching.
  int _normalizeOhlcDaysParam(int requestedDays) {
    if (requestedDays <= 1) return 1;
    const List<int> allowed = <int>[1, 7, 14, 30, 90, 180, 365];
    for (final int value in allowed) {
      if (requestedDays <= value) {
        return value;
      }
    }
    // Fallback safeguard (should be capped earlier)
    return 365;
  }

  /// Throws an [Exception] with a properly formatted error message.
  ///
  /// This method consolidates the error handling logic that was repeated
  /// throughout the class. It parses the API error, logs a warning, and
  /// throws an appropriate exception.
  ///
  /// [response]: The HTTP response containing the error
  /// [operation]: The operation that was performed (e.g., "OHLC data fetch")
  /// [coinId]: Optional coin identifier for more specific error context
  void _throwApiErrorOrException(
    http.Response response,
    String operation, {
    String? coinId,
  }) {
    final apiError = ApiErrorParser.parseCoinGeckoError(
      response.statusCode,
      response.body,
    );

    throw Exception(apiError.message);
  }
}
