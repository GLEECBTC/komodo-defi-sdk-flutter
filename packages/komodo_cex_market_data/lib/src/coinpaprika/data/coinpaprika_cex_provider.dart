import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_cex_market_data/src/coinpaprika/constants/coinpaprika_intervals.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_api_plan.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_coin.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_market.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_ticker.dart';
import 'package:komodo_cex_market_data/src/common/api_error_parser.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:logging/logging.dart';

/// Configuration constants for CoinPaprika API.
class CoinPaprikaConfig {
  /// Base URL for CoinPaprika API
  static const String baseUrl = 'https://api.coinpaprika.com/v1';

  /// Request timeout duration
  static const Duration timeout = Duration(seconds: 30);

  /// Maximum number of retries for failed requests
  static const int maxRetries = 3;
}

/// Abstract interface for CoinPaprika data provider.
abstract class ICoinPaprikaProvider {
  /// Fetches the list of all available coins.
  Future<List<CoinPaprikaCoin>> fetchCoinList();

  /// List of supported quote currencies for CoinPaprika integration.
  /// This is a hard-coded superset of currencies supported by the SDK.
  List<QuoteCurrency> get supportedQuoteCurrencies;

  /// Fetches historical OHLC data for a specific coin.
  ///
  /// [coinId]: The CoinPaprika coin identifier (e.g., "btc-bitcoin")
  /// [startDate]: Start date for historical data
  /// [endDate]: End date for historical data (optional)
  /// [quote]: Quote currency (default: USD)
  /// [interval]: Data interval (default: 24h)
  Future<List<Ohlc>> fetchHistoricalOhlc({
    required String coinId,
    required DateTime startDate,
    DateTime? endDate,
    QuoteCurrency quote,
    String interval = CoinPaprikaIntervals.defaultInterval,
  });

  /// Fetches current market data for a specific coin.
  ///
  /// [coinId]: The CoinPaprika coin identifier (e.g., "btc-bitcoin")
  /// [quotes]: List of quote currencies
  Future<List<CoinPaprikaMarket>> fetchCoinMarkets({
    required String coinId,
    List<QuoteCurrency> quotes,
  });

  /// Fetches ticker data for a specific coin.
  ///
  /// [coinId]: The CoinPaprika coin identifier (e.g., "btc-bitcoin")
  /// [quotes]: List of quote currencies
  ///
  /// The ticker's quotes are keyed by each quote's `coinPaprikaQuoteCurrency`
  /// symbol in upper case, so a USDT quote is keyed `USD`.
  Future<CoinPaprikaTicker> fetchCoinTicker({
    required String coinId,
    List<QuoteCurrency> quotes,
  });

  /// The current API plan with its limitations and features.
  CoinPaprikaApiPlan get apiPlan;

  /// Releases any resources held by the provider.
  void dispose();
}

/// Implementation of CoinPaprika data provider using HTTP requests.
class CoinPaprikaProvider implements ICoinPaprikaProvider {
  /// Creates a new CoinPaprika provider instance.
  CoinPaprikaProvider({
    String? apiKey,
    this.baseUrl = 'api.coinpaprika.com',
    this.apiVersion = '/v1',
    this.apiPlan = const CoinPaprikaApiPlan.free(),
    http.Client? httpClient,
  }) : _apiKey = apiKey,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  /// The base URL for the CoinPaprika API.
  final String baseUrl;

  /// The API version for the CoinPaprika API.
  final String apiVersion;

  /// The current API plan with its limitations and features.
  @override
  final CoinPaprikaApiPlan apiPlan;

  /// The API key for the CoinPaprika API.
  final String? _apiKey;

  /// The HTTP client for the CoinPaprika API.
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  static final Logger _logger = Logger('CoinPaprikaProvider');

  @override
  List<QuoteCurrency> get supportedQuoteCurrencies =>
      List.unmodifiable(_supported);

  @override
  Future<List<CoinPaprikaCoin>> fetchCoinList() async {
    final uri = Uri.https(baseUrl, '$apiVersion/coins');

    final response = await _httpClient
        .get(uri, headers: _createRequestHeaderMap())
        .timeout(CoinPaprikaConfig.timeout);

    if (response.statusCode != 200) {
      _throwApiErrorOrException(response, 'ALL', 'coin list fetch');
    }

    final coins = jsonDecode(response.body) as List<dynamic>;
    final result = coins
        .cast<Map<String, dynamic>>()
        .map(CoinPaprikaCoin.fromJson)
        .toList();

    return result;
  }

  /// Fetches historical OHLC data using the correct CoinPaprika API format.
  ///
  /// [coinId]: The CoinPaprika coin identifier (e.g., "btc-bitcoin")
  /// [startDate]: Start date for historical data
  /// [endDate]: End date for historical data (optional)
  /// [quote]: Quote currency (default: USD)
  /// [interval]: Data interval (default: 24h)
  @override
  Future<List<Ohlc>> fetchHistoricalOhlc({
    required String coinId,
    required DateTime startDate,
    DateTime? endDate,
    QuoteCurrency quote = FiatCurrency.usd,
    String interval = '1d',
  }) async {
    _validateInterval(interval);
    _validateHistoricalDataRequest(startDate: startDate, endDate: endDate);

    // Convert interval format: '24h' -> '1d' for CoinPaprika API compatibility
    final apiInterval = _convertIntervalForApi(interval);

    // Map quote currency: stablecoins -> underlying fiat (e.g., USDT -> USD)
    final mappedQuote = quote.coinPaprikaQuoteCurrency;

    // CoinPaprika API only requires start date and interval for historical data
    final queryParams = <String, String>{
      'start': _formatDateForApi(startDate),
      'interval': apiInterval,
      'quote': mappedQuote.coinPaprikaId.toLowerCase(),
      'limit': '5000',
      if (endDate != null) 'end': _formatDateForApi(endDate),
    };

    final uri = Uri.https(
      baseUrl,
      '$apiVersion/tickers/$coinId/historical',
      queryParams,
    );

    final response = await _httpClient
        .get(uri, headers: _createRequestHeaderMap())
        .timeout(CoinPaprikaConfig.timeout);

    if (response.statusCode != 200) {
      _throwApiErrorOrException(response, coinId, 'OHLC data fetch');
    }

    final ticksData = jsonDecode(response.body) as List<dynamic>;
    final result = ticksData
        .cast<Map<String, dynamic>>()
        .map(_parseTicksToOhlc)
        .toList();

    return result;
  }

  @override
  Future<List<CoinPaprikaMarket>> fetchCoinMarkets({
    required String coinId,
    List<QuoteCurrency> quotes = const [FiatCurrency.usd],
  }) async {
    // Map quote currencies: stablecoins -> underlying fiat
    final mappedQuotes = quotes.map((q) => q.coinPaprikaQuoteCurrency).toList();
    final quotesParam = mappedQuotes
        .map((q) => q.coinPaprikaId.toUpperCase())
        .join(',');

    final queryParams = <String, String>{'quotes': quotesParam};

    final uri = Uri.https(
      baseUrl,
      '$apiVersion/coins/$coinId/markets',
      queryParams,
    );

    final response = await _httpClient
        .get(uri, headers: _createRequestHeaderMap())
        .timeout(CoinPaprikaConfig.timeout);

    if (response.statusCode != 200) {
      _throwApiErrorOrException(response, coinId, 'market data fetch');
    }

    final markets = jsonDecode(response.body) as List<dynamic>;
    final result = markets
        .cast<Map<String, dynamic>>()
        .map(CoinPaprikaMarket.fromJson)
        .toList();

    return result;
  }

  /// Fetches ticker data for a specific coin.
  ///
  /// [coinId]: The CoinPaprika coin identifier (e.g., "btc-bitcoin")
  /// [quotes]: List of quote currencies
  @override
  Future<CoinPaprikaTicker> fetchCoinTicker({
    required String coinId,
    List<QuoteCurrency> quotes = const [FiatCurrency.usd],
  }) async {
    // Map quote currencies: stablecoins -> underlying fiat
    final mappedQuotes = quotes.map((q) => q.coinPaprikaQuoteCurrency).toList();
    final quotesParam = mappedQuotes
        .map((q) => q.coinPaprikaId.toUpperCase())
        .join(',');

    final queryParams = <String, String>{'quotes': quotesParam};

    final uri = Uri.https(baseUrl, '$apiVersion/tickers/$coinId', queryParams);

    final response = await _httpClient
        .get(uri, headers: _createRequestHeaderMap())
        .timeout(CoinPaprikaConfig.timeout);

    if (response.statusCode != 200) {
      _throwApiErrorOrException(response, coinId, 'ticker data fetch');
    }
    final ticker = jsonDecode(response.body) as Map<String, dynamic>;
    final result = CoinPaprikaTicker.fromJson(ticker);
    return result;
  }

  /// Validates if the requested date range is within the current API plan's
  /// limitations.
  ///
  /// Different API plans have different limitations:
  /// - Historical data access cutoff dates
  /// - Available intervals
  ///
  /// Throws [ArgumentError] if the request is invalid.
  void _validateHistoricalDataRequest({
    DateTime? startDate,
    DateTime? endDate,
    String interval = '1d',
  }) {
    // Validate interval support
    if (!apiPlan.isIntervalSupported(interval)) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Interval "$interval" is not supported in the ${apiPlan.planName} plan. '
            'Supported intervals: ${apiPlan.availableIntervals.join(", ")}',
      );
    }

    // If the plan has unlimited OHLC history, no date validation needed
    if (apiPlan.hasUnlimitedOhlcHistory) return;

    // If no dates provided, assume recent data request (valid)
    if (startDate == null && endDate == null) return;

    final cutoffDate = apiPlan.getHistoricalDataCutoff();
    if (cutoffDate == null) return; // No limitations

    // Check if any requested date is before the cutoff
    if (startDate != null && startDate.isBefore(cutoffDate)) {
      throw ArgumentError.value(
        startDate,
        'startDate',
        'Historical data before ${_formatDateForApi(cutoffDate)} is not '
            'available in the ${apiPlan.planName} plan. '
            'Requested start date: ${_formatDateForApi(startDate)}. '
            '${apiPlan.ohlcLimitDescription}. Please request more recent data or '
            'upgrade your plan.',
      );
    }

    if (endDate != null && endDate.isBefore(cutoffDate)) {
      throw ArgumentError.value(
        endDate,
        'endDate',
        'Historical data before ${_formatDateForApi(cutoffDate)} is not '
            'available in the ${apiPlan.planName} plan. '
            'Requested end date: ${_formatDateForApi(endDate)}. '
            '${apiPlan.ohlcLimitDescription}. Please request more recent data or '
            'upgrade your plan.',
      );
    }
  }

  /// Validates if the requested interval is supported by the current API plan.
  ///
  /// Throws [ArgumentError] if the interval is not supported.
  void _validateInterval(String interval) {
    if (!apiPlan.isIntervalSupported(interval)) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Interval "$interval" is not supported in the ${apiPlan.planName} '
            'plan. Supported intervals: ${apiPlan.availableIntervals.join(", ")}. '
            'Please use a supported interval or upgrade to a higher plan.',
      );
    }
  }

  /// Creates HTTP headers for CoinPaprika API requests.
  ///
  /// If an API key is provided, it will be included as a Bearer token
  /// in the Authorization header.
  ///
  /// If [contentType] is provided, it will be included as a Content-Type header
  Map<String, String>? _createRequestHeaderMap({String? contentType}) {
    Map<String, String>? headers;
    if (contentType != null) {
      headers = <String, String>{
        'Content-Type': contentType,
        'Accept': contentType,
      };
    }

    if (_apiKey != null && _apiKey.isNotEmpty) {
      headers ??= <String, String>{};
      headers['Authorization'] = 'Bearer $_apiKey';
    }

    return headers;
  }

  /// Formats a DateTime to the format expected by CoinPaprika API.
  ///
  /// CoinPaprika expects dates in YYYY-MM-DD format, not ISO 8601 with time.
  /// This prevents the "Invalid value provided for the date parameter" error.
  String _formatDateForApi(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Converts internal interval format to CoinPaprika API format.
  ///
  /// Internal format -> API format:
  /// - 24h -> 1d (daily data)
  /// - 1d -> 1d (daily data)
  /// - 1h -> 1h (hourly data)
  /// - 5m -> 5m (5-minute data)
  /// - 15m -> 15m (15-minute data)
  /// - 30m -> 30m (30-minute data)
  String _convertIntervalForApi(String interval) {
    switch (interval) {
      case CoinPaprikaDailyIntervals.twentyFourHours:
      case CoinPaprikaDailyIntervals.oneDay:
        return CoinPaprikaDailyIntervals.oneDay;
      case CoinPaprikaHourlyIntervals.oneHour:
      case CoinPaprikaFiveMinuteIntervals.fiveMinutes:
      case CoinPaprikaFiveMinuteIntervals.fifteenMinutes:
      case CoinPaprikaFiveMinuteIntervals.thirtyMinutes:
        return interval;
      default:
        // For any unrecognized interval, pass it through as-is
        return interval;
    }
  }

  /// Hard-coded list of supported quote currencies for CoinPaprika.
  /// Includes: BTC, ETH, USD, EUR, PLN, KRW, GBP, CAD, JPY, RUB, TRY, NZD, AUD,
  /// CHF, UAH, HKD, SGD, NGN, PHP, MXN, BRL, THB, CLP, CNY, CZK, DKK, HUF, IDR,
  /// ILS, INR, MYR, NOK, PKR, SEK, TWD, ZAR, VND, BOB, COP, PEN, ARS, ISK
  ///
  /// FiatCurrency/other constants are used where available; otherwise ad-hoc
  /// instances created.
  static final List<QuoteCurrency> _supported = [
    Cryptocurrency.btc,
    Cryptocurrency.eth,
    FiatCurrency.usd,
    FiatCurrency.eur,
    FiatCurrency.pln,
    FiatCurrency.krw,
    FiatCurrency.gbp,
    FiatCurrency.cad,
    FiatCurrency.jpy,
    FiatCurrency.rub,
    FiatCurrency.tryLira,
    FiatCurrency.nzd,
    FiatCurrency.aud,
    FiatCurrency.chf,
    FiatCurrency.uah,
    FiatCurrency.hkd,
    FiatCurrency.sgd,
    FiatCurrency.ngn,
    FiatCurrency.php,
    FiatCurrency.mxn,
    FiatCurrency.brl,
    FiatCurrency.thb,
    FiatCurrency.clp,
    FiatCurrency.cny,
    FiatCurrency.czk,
    FiatCurrency.dkk,
    FiatCurrency.huf,
    FiatCurrency.idr,
    FiatCurrency.ils,
    FiatCurrency.inr,
    FiatCurrency.myr,
    FiatCurrency.nok,
    FiatCurrency.pkr,
    FiatCurrency.sek,
    FiatCurrency.twd,
    FiatCurrency.zar,
    FiatCurrency.vnd,
    FiatCurrency.bob,
    FiatCurrency.cop,
    FiatCurrency.pen,
    FiatCurrency.ars,
    FiatCurrency.isk,
  ];

  /// Throws an [ArgumentError] if the response is an API error,
  /// otherwise throws an [Exception].
  ///
  /// [coinId]: The CoinPaprika coin identifier (e.g., "btc-bitcoin")
  /// [operation]: The operation that was performed (e.g., "OHLC data fetch")
  void _throwApiErrorOrException(
    http.Response response,
    String coinId,
    String operation,
  ) {
    final apiError = ApiErrorParser.parseCoinPaprikaError(
      response.statusCode,
      response.body,
    );

    // Check if this is a CoinPaprika API limitation error
    if (response.statusCode == 400 &&
        response.body.contains('is not allowed in this plan')) {
      final cutoffDate = apiPlan.getHistoricalDataCutoff();

      _logger.warning(
        'CoinPaprika API historical data limitation encountered for $coinId. '
        '${apiPlan.planName} plan limitation: ${apiPlan.ohlcLimitDescription} '
        '${cutoffDate != null ? '(since ${_formatDateForApi(cutoffDate)})' : ''}',
      );

      throw ArgumentError.value(
        response.body,
        'apiResponse',
        'Historical data not available: ${apiPlan.ohlcLimitDescription}. '
            'Please request more recent data or upgrade your plan.',
      );
    }

    _logger.warning(
      ApiErrorParser.createSafeErrorMessage(
        operation: operation,
        service: 'CoinPaprika',
        statusCode: response.statusCode,
        coinId: coinId,
      ),
    );

    throw Exception(apiError.message);
  }

  /// Helper method to parse CoinPaprika historical ticks JSON into Ohlc format.
  /// Since ticks only have a single price point, we use it for open, high, low, and close.
  Ohlc _parseTicksToOhlc(Map<String, dynamic> json) {
    final timestampStr = json['timestamp'] as String;
    final timestamp = DateTime.parse(timestampStr).millisecondsSinceEpoch;
    final price = Decimal.parse(json['price'].toString());

    return Ohlc.coinpaprika(
      timeOpen: timestamp,
      timeClose: timestamp,
      open: price,
      high: price,
      low: price,
      close: price,
      volume: json['volume_24h'] != null
          ? Decimal.parse(json['volume_24h'].toString())
          : null,
      marketCap: json['market_cap'] != null
          ? Decimal.parse(json['market_cap'].toString())
          : null,
    );
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}
