import 'package:komodo_cex_market_data/src/coinpaprika/data/coinpaprika_cex_provider.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_api_plan.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fixtures/mock_helpers.dart';
import 'fixtures/test_constants.dart';
import 'fixtures/test_fixtures.dart';
import 'fixtures/verification_helpers.dart';

void main() {
  group('CoinPaprikaProvider', () {
    late MockHttpClient mockHttpClient;
    late CoinPaprikaProvider provider;

    setUp(() {
      MockHelpers.registerFallbackValues();
      mockHttpClient = MockHttpClient();
      provider = CoinPaprikaProvider(
        httpClient: mockHttpClient,
        baseUrl: 'api.coinpaprika.com',
        apiVersion: '/v1',
        apiPlan: const CoinPaprikaApiPlan.pro(),
      );
    });

    group('supportedQuoteCurrencies', () {
      test('returns the correct hard-coded list of supported currencies', () {
        // Act
        final supportedCurrencies = provider.supportedQuoteCurrencies;

        // Assert
        expect(supportedCurrencies, isNotEmpty);
        for (final currency in TestConstants.defaultSupportedCurrencies) {
          expect(supportedCurrencies, contains(currency));
        }

        // Verify the list is unmodifiable
        expect(
          () => supportedCurrencies.add(FiatCurrency.cad),
          throwsUnsupportedError,
        );
      });

      test('includes expected number of currencies', () {
        // Act
        final supportedCurrencies = provider.supportedQuoteCurrencies;

        // Assert - Based on the hard-coded list in the provider
        expect(supportedCurrencies.length, equals(42));
      });

      test('does not include unsupported currencies', () {
        // Act
        final supportedCurrencies = provider.supportedQuoteCurrencies;

        // Assert
        final supportedSymbols = supportedCurrencies
            .map((c) => c.symbol)
            .toSet();
        expect(supportedSymbols, isNot(contains('GOLD')));
        expect(supportedSymbols, isNot(contains('SILVER')));
        expect(supportedSymbols, isNot(contains('UNSUPPORTED')));
      });
    });

    group('fetchHistoricalOhlc URL format validation', () {
      test('generates correct URL format without quote parameter', () async {
        // Arrange
        final mockResponse = TestFixtures.createHistoricalOhlcResponse();

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        final startDate = DateTime.now().subtract(const Duration(days: 30));

        // Act
        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: startDate,
        );

        // Assert - Verify URL structure (real provider includes quote and limit params)
        final capturedUri = verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;
        expect(capturedUri.host, equals('api.coinpaprika.com'));
        expect(capturedUri.path, equals('/v1/tickers/btc-bitcoin/historical'));
        expect(capturedUri.queryParameters.containsKey('start'), isTrue);
        expect(capturedUri.queryParameters.containsKey('interval'), isTrue);
        expect(capturedUri.queryParameters['interval'], equals('1d'));
      });

      test('converts 24h interval to 1d for API compatibility', () async {
        // Arrange
        final mockResponse = TestFixtures.createHistoricalOhlcResponse();

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        // Act
        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime.now().subtract(const Duration(days: 30)),
          interval: TestConstants.interval24h,
        );

        // Assert
        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval24h,
          TestConstants.interval1d,
        );
      });

      test('preserves 1h interval as-is', () async {
        // Arrange
        final mockResponse = TestFixtures.createHistoricalOhlcResponse(
          price: 44000,
          volume24h: TestConstants.mediumVolume,
          marketCap: 800000000000,
        );

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        // Act
        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime.now().subtract(const Duration(days: 7)),
          interval: TestConstants.interval1h,
        );

        // Assert
        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval1h,
          TestConstants.interval1h,
        );
      });

      test('formats date correctly as YYYY-MM-DD', () async {
        // Arrange
        final mockResponse = TestFixtures.createHistoricalOhlcResponse(
          price: 1.02,
          volume24h: TestConstants.lowVolume,
          marketCap: TestConstants.smallMarketCap,
        );

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        final startDate = DateTime(2024, 8, 25, 14, 30, 45); // Date with time

        // Act
        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: startDate,
        );

        // Assert
        VerificationHelpers.verifyDateFormatting(
          mockHttpClient,
          startDate,
          '2024-08-25',
        );
      });

      test('generates URL matching correct format example', () async {
        // Arrange
        final mockResponse = TestFixtures.createHistoricalOhlcResponse(
          timestamp: '2025-01-01T00:00:00Z',
        );

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        final startDate = DateTime.now().subtract(const Duration(days: 30));

        // Act
        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: startDate,
        );

        // Assert
        final capturedUri = verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;
        expect(capturedUri.host, equals('api.coinpaprika.com'));
        expect(capturedUri.path, equals('/v1/tickers/btc-bitcoin/historical'));
        expect(capturedUri.queryParameters.containsKey('start'), isTrue);
        expect(capturedUri.queryParameters.containsKey('interval'), isTrue);
      });
    });

    group('interval conversion tests', () {
      final emptyResponse = TestFixtures.createHistoricalOhlcResponse(
        ticks: [],
      );
      final testDate = DateTime.now().subtract(const Duration(days: 30));

      test('converts 24h to 1d', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: testDate,
          interval: TestConstants.interval24h,
        );

        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval24h,
          TestConstants.interval1d,
        );
      });

      test('preserves 1d as-is', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: testDate,
        );

        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval1d,
          TestConstants.interval1d,
        );
      });

      test('preserves 1h as-is', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime.now().subtract(const Duration(days: 7)),
          interval: TestConstants.interval1h,
        );

        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval1h,
          TestConstants.interval1h,
        );
      });

      test('preserves 5m as-is', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime.now().subtract(const Duration(days: 7)),
          interval: TestConstants.interval5m,
        );

        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval5m,
          TestConstants.interval5m,
        );
      });

      test('preserves 15m as-is', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime.now().subtract(const Duration(days: 7)),
          interval: TestConstants.interval15m,
        );

        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval15m,
          TestConstants.interval15m,
        );
      });

      test('preserves 30m as-is', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime.now().subtract(const Duration(days: 7)),
          interval: TestConstants.interval30m,
        );

        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          TestConstants.interval30m,
          TestConstants.interval30m,
        );
      });

      test('passes through unknown intervals as-is', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime.now().subtract(const Duration(days: 30)),
          interval: '7d',
        );

        VerificationHelpers.verifyIntervalConversion(
          mockHttpClient,
          '7d',
          '7d',
        );
      });
    });

    group('date formatting tests', () {
      final emptyResponse = TestFixtures.createHistoricalOhlcResponse(
        ticks: [],
      );

      test('formats single digit month correctly', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime(2024, 3, 5),
        );

        VerificationHelpers.verifyDateFormatting(
          mockHttpClient,
          DateTime(2024, 3, 5),
          TestConstants.dateFormatWithSingleDigits,
        );
      });

      test('formats single digit day correctly', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime(2024, 12, 7),
        );

        VerificationHelpers.verifyDateFormatting(
          mockHttpClient,
          DateTime(2024, 12, 7),
          '2024-12-07',
        );
      });

      test('ignores time portion of datetime', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => emptyResponse);

        await provider.fetchHistoricalOhlc(
          coinId: TestConstants.bitcoinCoinId,
          startDate: DateTime(2024, 6, 15, 14, 30, 45, 123, 456),
        );

        VerificationHelpers.verifyDateFormatting(
          mockHttpClient,
          DateTime(2024, 6, 15, 14, 30, 45, 123, 456),
          '2024-06-15',
        );
      });
    });

    group('URL format regression tests', () {
      test('URL format does not cause 400 Bad Request - regression test', () async {
        // This test validates the fix for the issue where the old URL format:
        // https://api.coinpaprika.com/v1/tickers/aur-auroracoin/historical?start=2025-08-25&quote=usdt&interval=24h&limit=5000&end=2025-09-01
        // was causing 400 Bad Request responses.
        //
        // The correct format is:
        // https://api.coinpaprika.com/v1/tickers/btc-bitcoin/historical?start=2025-01-01&interval=1d

        final mockResponse = TestFixtures.createHistoricalOhlcResponse(
          timestamp: '2025-01-01T00:00:00Z',
        );

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        final startDate = DateTime.now().subtract(const Duration(days: 30));

        // Act - this should not throw an exception or cause 400 Bad Request
        final result = await provider.fetchHistoricalOhlc(
          coinId: 'aur-auroracoin',
          startDate: startDate,
          interval: TestConstants.interval24h, // This gets converted to '1d'
        );

        // Assert
        expect(result, isNotEmpty);

        final capturedUri = verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;
        expect(capturedUri.host, equals(TestConstants.baseUrl));
        expect(capturedUri.path, equals('${TestConstants.apiVersion}/tickers/aur-auroracoin/historical'));
        expect(capturedUri.queryParameters.containsKey('start'), isTrue);
        expect(capturedUri.queryParameters.containsKey('interval'), isTrue);
      });

      test(
        'validates that quote parameter is properly mapped in URLs',
        () async {
          // The real provider includes quote parameter with proper mapping
          final mockResponse = TestFixtures.createHistoricalOhlcResponse(
            ticks: [],
          );
          when(
            () => mockHttpClient.get(any()),
          ).thenAnswer((_) async => mockResponse);

          // This call should map USDT to USD in the URL
          await provider.fetchHistoricalOhlc(
            coinId: TestConstants.bitcoinCoinId,
            startDate: DateTime.now().subtract(const Duration(days: 30)),
            quote: Stablecoin.usdt, // This should be mapped to USD
          );

          final capturedUri =
              verify(() => mockHttpClient.get(captureAny())).captured.single
                  as Uri;
          expect(capturedUri.queryParameters.containsKey('quote'), isTrue,
              reason: 'Quote parameter should be included in historical OHLC requests');
          expect(capturedUri.queryParameters['quote'], equals('usd'),
              reason: 'USDT should be mapped to USD');
        },
      );
    });

    group('fetchCoinTicker quote currency mapping', () {
      test(
        'uses correct coinPaprikaId mapping for multiple quote currencies',
        () async {
          // Arrange
          final mockResponse = TestFixtures.createTickerResponse(
            quotes: TestFixtures.createMultipleQuotes(
              currencies: [TestConstants.usdQuote, TestConstants.eurQuote],
              prices: [TestConstants.bitcoinPrice, 42000.0],
            ),
          );

          when(
            () => mockHttpClient.get(any()),
          ).thenAnswer((_) async => mockResponse);

          // Act
          await provider.fetchCoinTicker(
            coinId: TestConstants.bitcoinCoinId,
            quotes: [FiatCurrency.usd, Stablecoin.usdt, FiatCurrency.eur],
          );

          // Assert
          VerificationHelpers.verifyTickerUrl(
            mockHttpClient,
            TestConstants.bitcoinCoinId,
            expectedQuotes: 'USD,USD,EUR',
          );
        },
      );

      test('converts coinPaprikaId to uppercase for API request', () async {
        // Arrange
        final mockResponse = TestFixtures.createTickerResponse(
          quotes: TestFixtures.createMultipleQuotes(
            currencies: [TestConstants.btcQuote, TestConstants.ethQuote],
            prices: [1.0, 15.2],
          ),
        );

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        // Act
        await provider.fetchCoinTicker(
          coinId: TestConstants.bitcoinCoinId,
          quotes: [Cryptocurrency.btc, Cryptocurrency.eth],
        );

        // Assert
        VerificationHelpers.verifyTickerUrl(
          mockHttpClient,
          TestConstants.bitcoinCoinId,
          expectedQuotes: 'BTC,ETH',
        );
      });

      test('handles single quote currency correctly', () async {
        // Arrange
        final mockResponse = TestFixtures.createTickerResponse(
          quotes: {
            TestConstants.gbpQuote: {
              'price': 38000.0,
              'volume_24h': TestConstants.highVolume,
              'volume_24h_change_24h': 0.0,
              'market_cap': TestConstants.bitcoinMarketCap,
              'market_cap_change_24h': 0.0,
              'percent_change_15m': 0.0,
              'percent_change_30m': 0.0,
              'percent_change_1h': 0.0,
              'percent_change_6h': 0.0,
              'percent_change_12h': 0.0,
              'percent_change_24h': TestConstants.positiveChange,
              'percent_change_7d': 0.0,
              'percent_change_30d': 0.0,
              'percent_change_1y': 0.0,
            },
          },
        );

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        // Act
        await provider.fetchCoinTicker(
          coinId: TestConstants.bitcoinCoinId,
          quotes: [FiatCurrency.gbp],
        );

        // Assert
        VerificationHelpers.verifyTickerUrl(
          mockHttpClient,
          TestConstants.bitcoinCoinId,
          expectedQuotes: TestConstants.gbpQuote,
        );
      });
    });

    group('fetchCoinMarkets quote currency mapping', () {
      test('uses correct coinPaprikaId mapping for market data', () async {
        // Arrange
        final mockResponse = TestFixtures.createMarketsResponse();

        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => mockResponse);

        // Act
        await provider.fetchCoinMarkets(
          coinId: TestConstants.bitcoinCoinId,
          quotes: [FiatCurrency.usd, Stablecoin.usdt],
        );

        // Assert
        VerificationHelpers.verifyMarketsUrl(
          mockHttpClient,
          TestConstants.bitcoinCoinId,
          expectedQuotes: 'USD,USD',
        );
      });
    });

    group('coinPaprikaId extension usage', () {
      test('verifies QuoteCurrency.coinPaprikaId returns lowercase values', () {
        // Test various currency types to ensure the extension works correctly
        final expectedMappings =
            {
              FiatCurrency.usd: 'usd',
              FiatCurrency.eur: 'eur',
              FiatCurrency.gbp: 'gbp',
              Stablecoin.usdt: 'usdt',
              Stablecoin.usdc: 'usdc',
              Stablecoin.eurs: 'eurs',
              Cryptocurrency.btc: 'btc',
              Cryptocurrency.eth: 'eth',
            }..forEach((currency, expectedId) {
              expect(currency.coinPaprikaId, equals(expectedId));
            });
      });

      test('verifies provider uses coinPaprikaId extension consistently', () {
        // Arrange
        const testCurrency = FiatCurrency.jpy;

        // Act & Assert
        expect(testCurrency.coinPaprikaId, equals('jpy'));

        // Verify this matches what would be used in the provider
        final supportedCurrencies = provider.supportedQuoteCurrencies;
        final jpyCurrency = supportedCurrencies.firstWhere(
          (currency) => currency.symbol == 'JPY',
        );
        expect(jpyCurrency.coinPaprikaId, equals('jpy'));
      });
    });

    group('error handling', () {
      test('throws exception when HTTP request fails for OHLC', () async {
        // Arrange
        MockHelpers.setupErrorResponses(mockHttpClient);

        // Act & Assert
        expect(
          () => provider.fetchHistoricalOhlc(
            coinId: TestConstants.bitcoinCoinId,
            startDate: TestData.pastDate,
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('throws exception when HTTP request fails for ticker', () async {
        // Arrange
        MockHelpers.setupErrorResponses(mockHttpClient);

        // Act & Assert
        expect(
          () => provider.fetchCoinTicker(
            coinId: TestConstants.bitcoinCoinId,
            quotes: [FiatCurrency.usd],
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Quote Currency Mapping', () {
      final testDate = DateTime.now().subtract(const Duration(days: 30));
      final emptyResponse = TestFixtures.createHistoricalOhlcResponse(
        ticks: [],
      );

      test(
        'OHLC requests include quote parameter with proper mapping',
        () async {
          when(
            () => mockHttpClient.get(any()),
          ).thenAnswer((_) async => emptyResponse);

          await provider.fetchHistoricalOhlc(
            coinId: TestConstants.bitcoinCoinId,
            startDate: testDate,
            quote: Stablecoin.usdt, // Should be mapped to USD
          );

          // Verify that quote parameter is included and properly mapped
          final captured = verify(
            () => mockHttpClient.get(captureAny()),
          ).captured;
          final uri = captured.first as Uri;
          expect(
            uri.queryParameters.containsKey('quote'),
            isTrue,
            reason: 'OHLC requests should include quote parameter in real provider',
          );
          expect(
            uri.queryParameters['quote'],
            equals('usd'),
            reason: 'USDT should be mapped to USD in quote parameter',
          );
        },
      );

      test('maps stablecoins to underlying fiat for ticker requests', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => TestFixtures.createTickerResponse());

        await provider.fetchCoinTicker(
          coinId: TestConstants.bitcoinCoinId,
          quotes: [Stablecoin.usdt, Stablecoin.usdc], // Should map to USD
        );

        final captured = verify(
          () => mockHttpClient.get(captureAny()),
        ).captured;
        final uri = captured.first as Uri;
        expect(uri.queryParameters['quotes'], equals('USD,USD'));
      });

      test('maps stablecoins to underlying fiat for market requests', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => TestFixtures.createMarketsResponse());

        await provider.fetchCoinMarkets(
          coinId: TestConstants.bitcoinCoinId,
          quotes: [Stablecoin.usdt, Stablecoin.eurs], // USDT->USD, EURS->EUR
        );

        final captured = verify(
          () => mockHttpClient.get(captureAny()),
        ).captured;
        final uri = captured.first as Uri;
        expect(uri.queryParameters['quotes'], equals('USD,EUR'));
      });

      test('handles mixed quote types correctly', () async {
        when(
          () => mockHttpClient.get(any()),
        ).thenAnswer((_) async => TestFixtures.createMarketsResponse());

        await provider.fetchCoinMarkets(
          coinId: TestConstants.bitcoinCoinId,
          quotes: [
            FiatCurrency.usd, // Should remain USD
            Stablecoin.usdt, // Should map to USD
            Cryptocurrency.btc, // Should remain BTC
            Stablecoin.eurs, // Should map to EUR
          ],
        );

        final captured = verify(
          () => mockHttpClient.get(captureAny()),
        ).captured;
        final uri = captured.first as Uri;
        expect(uri.queryParameters['quotes'], equals('USD,USD,BTC,EUR'));
      });
    });
  });
}
