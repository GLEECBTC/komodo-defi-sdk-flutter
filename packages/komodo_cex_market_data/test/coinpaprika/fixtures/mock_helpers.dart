/// Mock helpers for setting up common mock objects and behaviors
library;

import 'package:http/http.dart' as http;
import 'package:komodo_cex_market_data/src/coinpaprika/_coinpaprika_index.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_constants.dart';
import 'test_fixtures.dart';

/// Mock HTTP client for testing
class MockHttpClient extends Mock implements http.Client {}

/// Mock CoinPaprika provider for testing
class MockCoinPaprikaProvider extends Mock implements ICoinPaprikaProvider {}

/// Helper class for setting up common mock behaviors
class MockHelpers {
  MockHelpers._();

  /// Registers common fallback values for mocktail
  static void registerFallbackValues() {
    registerFallbackValue(Uri());
    registerFallbackValue(FiatCurrency.usd);
    registerFallbackValue(DateTime.now());
  }

  /// Sets up a MockHttpClient with common successful responses
  static void setupMockHttpClient(MockHttpClient mockHttpClient) {
    // Default successful responses for common endpoints
    when(
      () => mockHttpClient.get(any()),
    ).thenAnswer((_) async => TestFixtures.createCoinListResponse());
  }

  /// Sets up a MockCoinPaprikaProvider with common default behaviors
  static void setupMockProvider(MockCoinPaprikaProvider mockProvider) {
    // Default supported quote currencies
    when(
      () => mockProvider.supportedQuoteCurrencies,
    ).thenReturn(TestConstants.defaultSupportedCurrencies);

    // Default API plan
    when(
      () => mockProvider.apiPlan,
    ).thenReturn(const CoinPaprikaApiPlan.free());

    // Default empty OHLC response
    when(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    ).thenAnswer((_) async => <Ohlc>[]);

    // Default coin list response
    when(
      () => mockProvider.fetchCoinList(),
    ).thenAnswer((_) async => TestData.activeCoins);

    // Default bulk tickers: one for each active coin
    when(
      () => mockProvider.fetchTickers(quotes: any(named: 'quotes')),
    ).thenAnswer(
      (_) async => [
        TestFixtures.createMockTicker(),
        TestFixtures.createMockTicker(
          id: TestConstants.ethereumCoinId,
          name: TestConstants.ethereumName,
          symbol: TestConstants.ethereumSymbol,
          rank: 2,
          price: TestConstants.ethereumPrice,
        ),
      ],
    );
  }

  /// Configures MockHttpClient to return specific historical OHLC responses
  static void setupHistoricalOhlcResponse(
    MockHttpClient mockHttpClient, {
    List<Map<String, dynamic>>? ticks,
    int statusCode = 200,
  }) {
    when(
      () => mockHttpClient.get(
        any(
          that: isA<Uri>().having(
            (uri) => uri.path,
            'path',
            contains('/historical'),
          ),
        ),
      ),
    ).thenAnswer(
      (_) async => TestFixtures.createHistoricalOhlcResponse(
        ticks: ticks,
        statusCode: statusCode,
      ),
    );
  }

  /// Configures MockHttpClient to return specific ticker responses
  static void setupTickerResponse(
    MockHttpClient mockHttpClient, {
    String? coinId,
    Map<String, Map<String, dynamic>>? quotes,
    int statusCode = 200,
  }) {
    when(
      () => mockHttpClient.get(
        any(
          that: isA<Uri>().having(
            (uri) => uri.path,
            'path',
            allOf(contains('/tickers/'), isNot(contains('/historical'))),
          ),
        ),
      ),
    ).thenAnswer(
      (_) async => TestFixtures.createTickerResponse(
        coinId: coinId,
        quotes: quotes,
        statusCode: statusCode,
      ),
    );
  }

  /// Configures MockHttpClient to return specific markets responses
  static void setupMarketsResponse(
    MockHttpClient mockHttpClient, {
    List<Map<String, dynamic>>? markets,
    int statusCode = 200,
  }) {
    when(
      () => mockHttpClient.get(
        any(
          that: isA<Uri>().having(
            (uri) => uri.path,
            'path',
            contains('/tickers'),
          ),
        ),
      ),
    ).thenAnswer(
      (_) async => TestFixtures.createMarketsResponse(
        markets: markets,
        statusCode: statusCode,
      ),
    );
  }

  /// Configures MockHttpClient to return error responses for all endpoints
  static void setupErrorResponses(
    MockHttpClient mockHttpClient, {
    int statusCode = 500,
    String? errorMessage,
  }) {
    when(() => mockHttpClient.get(any())).thenAnswer(
      (_) async => TestFixtures.createErrorResponse(
        statusCode: statusCode,
        errorMessage: errorMessage,
      ),
    );
  }

  /// Configures MockCoinPaprikaProvider to return specific OHLC data
  static void setupProviderOhlcResponse(
    MockCoinPaprikaProvider mockProvider, {
    List<Ohlc>? ohlcData,
  }) {
    when(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    ).thenAnswer((_) async => ohlcData ?? TestFixtures.createMockOhlcList());
  }

  /// Configures MockCoinPaprikaProvider's bulk tickers to hold only [ticker]
  static void setupProviderTickerResponse(
    MockCoinPaprikaProvider mockProvider, {
    CoinPaprikaTicker? ticker,
  }) {
    when(
      () => mockProvider.fetchTickers(quotes: any(named: 'quotes')),
    ).thenAnswer((_) async => [ticker ?? TestFixtures.createMockTicker()]);
  }

  /// Configures MockCoinPaprikaProvider to return specific markets data
  static void setupProviderMarketsResponse(
    MockCoinPaprikaProvider mockProvider, {
    List<CoinPaprikaMarket>? markets,
  }) {
    when(
      () => mockProvider.fetchCoinMarkets(
        coinId: any(named: 'coinId'),
        quotes: any(named: 'quotes'),
      ),
    ).thenAnswer((_) async => markets ?? [TestFixtures.createMockMarket()]);
  }

  /// Configures MockCoinPaprikaProvider to return specific coin list data
  static void setupProviderCoinListResponse(
    MockCoinPaprikaProvider mockProvider, {
    List<CoinPaprikaCoin>? coins,
  }) {
    when(
      () => mockProvider.fetchCoinList(),
    ).thenAnswer((_) async => coins ?? TestData.activeCoins);
  }

  /// Configures MockCoinPaprikaProvider with extended supported currencies
  static void setupExtendedSupportedCurrencies(
    MockCoinPaprikaProvider mockProvider,
  ) {
    when(
      () => mockProvider.supportedQuoteCurrencies,
    ).thenReturn(TestConstants.extendedSupportedCurrencies);
  }

  /// Configures MockCoinPaprikaProvider with specific API plan
  static void setupApiPlan(
    MockCoinPaprikaProvider mockProvider,
    CoinPaprikaApiPlan apiPlan,
  ) {
    when(() => mockProvider.apiPlan).thenReturn(apiPlan);
  }

  /// Configures MockCoinPaprikaProvider to throw exceptions
  static void setupProviderErrors(
    MockCoinPaprikaProvider mockProvider, {
    Exception? coinListError,
    Exception? ohlcError,
    Exception? tickerError,
    Exception? marketsError,
  }) {
    if (coinListError != null) {
      when(() => mockProvider.fetchCoinList()).thenThrow(coinListError);
    }

    if (ohlcError != null) {
      when(
        () => mockProvider.fetchHistoricalOhlc(
          coinId: any(named: 'coinId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          quote: any(named: 'quote'),
          interval: any(named: 'interval'),
        ),
      ).thenThrow(ohlcError);
    }

    if (tickerError != null) {
      when(
        () => mockProvider.fetchTickers(quotes: any(named: 'quotes')),
      ).thenThrow(tickerError);
    }

    if (marketsError != null) {
      when(
        () => mockProvider.fetchCoinMarkets(
          coinId: any(named: 'coinId'),
          quotes: any(named: 'quotes'),
        ),
      ).thenThrow(marketsError);
    }
  }

  /// Creates a complete mock setup for successful scenarios
  static void setupSuccessfulScenario(
    MockCoinPaprikaProvider mockProvider, {
    List<CoinPaprikaCoin>? coins,
    List<Ohlc>? ohlcData,
    CoinPaprikaTicker? ticker,
    List<CoinPaprikaMarket>? markets,
    CoinPaprikaApiPlan? apiPlan,
  }) {
    setupMockProvider(mockProvider);

    if (coins != null) {
      setupProviderCoinListResponse(mockProvider, coins: coins);
    }

    if (ohlcData != null) {
      setupProviderOhlcResponse(mockProvider, ohlcData: ohlcData);
    }

    if (ticker != null) {
      setupProviderTickerResponse(mockProvider, ticker: ticker);
    }

    if (markets != null) {
      setupProviderMarketsResponse(mockProvider, markets: markets);
    }

    if (apiPlan != null) {
      setupApiPlan(mockProvider, apiPlan);
    }
  }

  /// Creates mock setup for testing batching scenarios
  static void setupBatchingScenario(
    MockCoinPaprikaProvider mockProvider, {
    int batchCount = 2,
    int itemsPerBatch = 10,
    CoinPaprikaApiPlan? apiPlan,
  }) {
    setupMockProvider(mockProvider);

    if (apiPlan != null) {
      setupApiPlan(mockProvider, apiPlan);
    }

    // Mock different responses for each batch request
    final batchData = TestFixtures.createBatchOhlcData(
      batchCount: batchCount,
      itemsPerBatch: itemsPerBatch,
    );

    when(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    ).thenAnswer((_) async => batchData);
  }

  /// Sets up a scenario where provider returns empty ticker quotes
  static void setupEmptyQuotesScenario(MockCoinPaprikaProvider mockProvider) {
    setupMockProvider(mockProvider);
    setupProviderTickerResponse(
      mockProvider,
      ticker: TestFixtures.createEmptyQuotesTicker(),
    );
  }
}
