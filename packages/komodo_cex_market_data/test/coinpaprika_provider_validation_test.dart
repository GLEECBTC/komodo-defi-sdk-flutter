import 'package:http/http.dart' as http;
import 'package:komodo_cex_market_data/src/coinpaprika/data/coinpaprika_cex_provider.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_api_plan.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// Mock HTTP client for testing
class MockHttpClient extends Mock implements http.Client {}

/// Test class that extends the provider to test validation logic
class TestCoinPaprikaProvider extends CoinPaprikaProvider {
  TestCoinPaprikaProvider({
    super.apiKey,
    super.apiPlan = const CoinPaprikaApiPlan.free(),
    super.httpClient,
  });

  /// Expose the private date formatting method for testing
  String formatDateForApi(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Test validation by simulating the internal validation logic
  void testValidation({
    DateTime? startDate,
    DateTime? endDate,
    String interval = '24h',
  }) {
    // Validate interval support
    if (!apiPlan.isIntervalSupported(interval)) {
      throw ArgumentError(
        'Interval "$interval" is not supported in the ${apiPlan.planName} plan. '
        'Supported intervals: ${apiPlan.availableIntervals.join(", ")}',
      );
    }

    // If the plan has unlimited OHLC history, no date validation needed
    if (apiPlan.hasUnlimitedOhlcHistory) return;

    // If no dates provided, assume recent data request (valid)
    if (startDate == null && endDate == null) return;

    final cutoffDate = apiPlan.getHistoricalDataCutoff(buffer: Duration.zero);
    if (cutoffDate == null) return; // No limitations

    // The API reads each sent date as that day's 00:00 UTC.
    DateTime dayReadByApi(DateTime date) =>
        DateTime.utc(date.year, date.month, date.day);

    // Check if any requested date is before the cutoff
    if (startDate != null && dayReadByApi(startDate).isBefore(cutoffDate)) {
      throw ArgumentError(
        'Historical data before ${formatDateForApi(cutoffDate)} is not available in the ${apiPlan.planName} plan. '
        'Requested start date: ${formatDateForApi(startDate)}. '
        '${apiPlan.ohlcLimitDescription}. Please request more recent data or upgrade your plan.',
      );
    }

    if (endDate != null && dayReadByApi(endDate).isBefore(cutoffDate)) {
      throw ArgumentError(
        'Historical data before ${formatDateForApi(cutoffDate)} is not available in the ${apiPlan.planName} plan. '
        'Requested end date: ${formatDateForApi(endDate)}. '
        '${apiPlan.ohlcLimitDescription}. Please request more recent data or upgrade your plan.',
      );
    }
  }
}

void main() {
  group('CoinPaprika Provider API Key Tests', () {
    late MockHttpClient mockHttpClient;

    setUp(() {
      mockHttpClient = MockHttpClient();
      registerFallbackValue(Uri());
    });

    test(
      'should not include Authorization header when no API key provided',
      () async {
        // Arrange
        final provider = CoinPaprikaProvider(httpClient: mockHttpClient);

        when(
          () => mockHttpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('[]', 200));

        // Act
        await provider.fetchCoinList();

        // Assert - verify Authorization header is not present
        final capturedHeaders =
            verify(
                  () => mockHttpClient.get(
                    any(),
                    headers: captureAny(named: 'headers'),
                  ),
                ).captured.single
                as Map<String, String>?;

        expect(capturedHeaders, isNot(contains('Authorization')));
      },
    );

    test(
      'should not include Authorization header when API key is empty',
      () async {
        // Arrange
        final provider = CoinPaprikaProvider(
          apiKey: '',
          httpClient: mockHttpClient,
        );

        when(
          () => mockHttpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('[]', 200));

        // Act
        await provider.fetchCoinList();

        // Assert - verify Authorization header is not present
        final capturedHeaders =
            verify(
                  () => mockHttpClient.get(
                    any(),
                    headers: captureAny(named: 'headers'),
                  ),
                ).captured.single
                as Map<String, String>?;

        expect(capturedHeaders, isNot(contains('Authorization')));
      },
    );

    test('should include Bearer token when API key is provided', () async {
      // Arrange
      const testApiKey = 'test-api-key-123';
      final provider = CoinPaprikaProvider(
        apiKey: testApiKey,
        httpClient: mockHttpClient,
      );

      when(
        () => mockHttpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('[]', 200));

      // Act
      await provider.fetchCoinList();

      // Assert - verify Authorization header contains Bearer token
      final capturedHeaders =
          verify(
                () => mockHttpClient.get(
                  any(),
                  headers: captureAny(named: 'headers'),
                ),
              ).captured.single
              as Map<String, String>?;

      expect(capturedHeaders!['Authorization'], equals('Bearer $testApiKey'));
    });

    test('should include Bearer token in all API methods', () async {
      // Arrange
      const testApiKey = 'test-api-key-456';
      final provider = CoinPaprikaProvider(
        apiKey: testApiKey,
        httpClient: mockHttpClient,
      );

      when(
        () => mockHttpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('[]', 200));

      // Act - test multiple API methods
      await provider.fetchCoinList();

      when(
        () => mockHttpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('[]', 200));
      await provider.fetchCoinMarkets(coinId: 'btc-bitcoin');

      when(
        () => mockHttpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('{"quotes":{}}', 200));
      await provider.fetchCoinTicker(coinId: 'btc-bitcoin');

      // Assert - verify all requests include Bearer token
      final capturedHeaders = verify(
        () => mockHttpClient.get(any(), headers: captureAny(named: 'headers')),
      ).captured;

      // Check that all 3 requests had the correct Authorization header
      for (final headers in capturedHeaders) {
        final headerMap = headers as Map<String, String>;
        expect(headerMap['Authorization'], equals('Bearer $testApiKey'));
      }
    });

    test('should include Bearer token in OHLC requests', () async {
      // Arrange
      const testApiKey = 'ohlc-test-key';
      final provider = CoinPaprikaProvider(
        apiKey: testApiKey,
        httpClient: mockHttpClient,
        // Use unlimited plan to avoid date validation
        apiPlan: const CoinPaprikaApiPlan.ultimate(),
      );

      when(
        () => mockHttpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('[]', 200));

      // Act
      await provider.fetchHistoricalOhlc(
        coinId: 'btc-bitcoin',
        startDate: DateTime.now().subtract(const Duration(days: 1)),
      );

      // Assert - verify OHLC request includes Bearer token
      final capturedHeaders =
          verify(
                () => mockHttpClient.get(
                  any(),
                  headers: captureAny(named: 'headers'),
                ),
              ).captured.single
              as Map<String, String>;

      expect(capturedHeaders['Authorization'], equals('Bearer $testApiKey'));
    });
  });

  group('CoinPaprikaProvider free plan start date', () {
    late MockHttpClient mockHttpClient;
    late CoinPaprikaProvider provider;

    setUp(() {
      mockHttpClient = MockHttpClient();
      registerFallbackValue(Uri());
      provider = CoinPaprikaProvider(httpClient: mockHttpClient);
      when(
        () => mockHttpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('[]', 200));
    });

    test('rejects a start on the cutoff day without a request', () async {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 365));
      final cutoffDay = DateTime.utc(cutoff.year, cutoff.month, cutoff.day);

      // Later than the cutoff when it falls before noon, but the API reads
      // the sent date as that day's midnight and refuses it.
      await expectLater(
        provider.fetchHistoricalOhlc(
          coinId: 'btcz-bitcoinz',
          startDate: cutoffDay.add(const Duration(hours: 12)),
        ),
        throwsA(isA<ArgumentError>()),
      );
      verifyNever(
        () => mockHttpClient.get(any(), headers: any(named: 'headers')),
      );
    });

    test('accepts the earliest start date the plan reports', () async {
      final earliest = provider.apiPlan.getEarliestStartDate()!;

      await provider.fetchHistoricalOhlc(
        coinId: 'btcz-bitcoinz',
        startDate: earliest,
      );

      final uri =
          verify(
                () => mockHttpClient.get(
                  captureAny(),
                  headers: any(named: 'headers'),
                ),
              ).captured.single
              as Uri;
      expect(
        uri.queryParameters['start'],
        earliest.toIso8601String().substring(0, 10),
      );
    });
  });

  group('CoinPaprikaProvider Validation Tests', () {
    group('Free Plan Validation', () {
      late TestCoinPaprikaProvider testProvider;

      setUp(() {
        testProvider = TestCoinPaprikaProvider();
      });

      test('should allow recent dates within cutoff', () {
        final now = DateTime.now();
        final recentDate = now.subtract(
          const Duration(days: 200),
        ); // Within 365 days limit for free plan

        expect(
          () => testProvider.testValidation(startDate: recentDate),
          returnsNormally,
        );
      });

      test('should reject dates before the cutoff period', () {
        final now = DateTime.now();
        final oldDate = now.subtract(
          const Duration(days: 400),
        ); // Beyond 365 days limit for free plan

        expect(
          () => testProvider.testValidation(startDate: oldDate),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('Historical data before'),
                contains('Free plan'),
                contains('1 year of OHLC historical data'),
              ]),
            ),
          ),
        );
      });

      test('should allow null dates (current data request)', () {
        expect(() => testProvider.testValidation(), returnsNormally);
      });

      test('should include helpful error message with plan information', () {
        const freePlan = CoinPaprikaApiPlan.free();
        final cutoffDate = freePlan.getHistoricalDataCutoff()!;
        final oldDate = cutoffDate.subtract(const Duration(hours: 1));

        try {
          testProvider.testValidation(startDate: oldDate);
          fail('Should have thrown ArgumentError');
        } catch (e) {
          expect(e, isA<ArgumentError>());
          final error = e as ArgumentError;

          // Check that the error message contains the key information
          expect(error.message, contains('Historical data before'));
          expect(error.message, contains('Free plan'));
          expect(error.message, contains('1 year of OHLC historical data'));
          expect(error.message, contains('upgrade your plan'));
        }
      });
    });

    group('Starter Plan Validation', () {
      late TestCoinPaprikaProvider testProvider;

      setUp(() {
        testProvider = TestCoinPaprikaProvider(
          apiPlan: const CoinPaprikaApiPlan.starter(),
        );
      });

      test('should allow dates within starter plan limit', () {
        final now = DateTime.now();
        final recentDate = now.subtract(
          const Duration(days: 15),
        ); // Within 30 day limit for starter plan

        expect(
          () => testProvider.testValidation(startDate: recentDate),
          returnsNormally,
        );
      });

      test('should reject dates before starter plan cutoff', () {
        final now = DateTime.now();
        final oldDate = now.subtract(
          const Duration(days: 2000),
        ); // Beyond 5 year limit for starter plan

        expect(
          () => testProvider.testValidation(startDate: oldDate),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('Historical data before'),
                contains('Starter plan'),
                contains('5 years of OHLC historical data'),
              ]),
            ),
          ),
        );
      });
    });

    group('Ultimate Plan Validation', () {
      late TestCoinPaprikaProvider testProvider;

      setUp(() {
        testProvider = TestCoinPaprikaProvider(
          apiPlan: const CoinPaprikaApiPlan.ultimate(),
        );
      });

      test('should allow any dates for unlimited plans', () {
        final now = DateTime.now();
        final veryOldDate = now.subtract(
          const Duration(days: 365 * 5),
        ); // 5 years ago

        expect(
          () => testProvider.testValidation(startDate: veryOldDate),
          returnsNormally,
        );
      });
    });

    group('Interval Validation', () {
      test('should reject unsupported intervals for free plan', () {
        final freePlanProvider = TestCoinPaprikaProvider();

        expect(
          () => freePlanProvider.testValidation(interval: '1h'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Interval "1h" is not supported in the Free plan'),
            ),
          ),
        );
      });

      test('should allow supported daily intervals for free plan', () {
        final freePlanProvider = TestCoinPaprikaProvider();

        expect(freePlanProvider.testValidation, returnsNormally);
        expect(
          () => freePlanProvider.testValidation(interval: '1d'),
          returnsNormally,
        );
        expect(
          () => freePlanProvider.testValidation(interval: '7d'),
          returnsNormally,
        );
        expect(
          () => freePlanProvider.testValidation(interval: '30d'),
          returnsNormally,
        );
        expect(
          () => freePlanProvider.testValidation(interval: '90d'),
          returnsNormally,
        );
        expect(
          () => freePlanProvider.testValidation(interval: '365d'),
          returnsNormally,
        );
      });

      test('should reject unsupported hourly intervals for free plan', () {
        final freePlanProvider = TestCoinPaprikaProvider();

        expect(
          () => freePlanProvider.testValidation(interval: '1h'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Interval "1h" is not supported in the Free plan'),
            ),
          ),
        );
        expect(
          () => freePlanProvider.testValidation(interval: '5m'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Interval "5m" is not supported in the Free plan'),
            ),
          ),
        );
      });

      test('should allow supported intervals for business plan', () {
        final businessPlanProvider = TestCoinPaprikaProvider(
          apiPlan: const CoinPaprikaApiPlan.business(),
        );

        expect(
          () => businessPlanProvider.testValidation(interval: '1h'),
          returnsNormally,
        );
        expect(
          () => businessPlanProvider.testValidation(interval: '6h'),
          returnsNormally,
        );
        expect(businessPlanProvider.testValidation, returnsNormally);
      });

      test('should allow all intervals for enterprise plan', () {
        final enterprisePlanProvider = TestCoinPaprikaProvider(
          apiPlan: const CoinPaprikaApiPlan.enterprise(),
        );

        expect(
          () => enterprisePlanProvider.testValidation(interval: '5m'),
          returnsNormally,
        );
        expect(
          () => enterprisePlanProvider.testValidation(interval: '15m'),
          returnsNormally,
        );
        expect(
          () => enterprisePlanProvider.testValidation(interval: '1h'),
          returnsNormally,
        );
      });
    });
  });

  group('API Plan Configuration', () {
    test('free plan should have correct limitations', () {
      const plan = CoinPaprikaApiPlan.free();

      expect(plan.ohlcHistoricalDataLimit?.inDays, equals(365));
      expect(
        plan.availableIntervals,
        equals(['24h', '1d', '7d', '14d', '30d', '90d', '365d']),
      );
      expect(plan.monthlyCallLimit, equals(20000));
      expect(plan.hasUnlimitedOhlcHistory, isFalse);
      expect(plan.planName, equals('Free'));
    });

    test('starter plan should have correct limitations', () {
      const plan = CoinPaprikaApiPlan.starter();

      expect(plan.ohlcHistoricalDataLimit?.inDays, equals(1825)); // 5 years
      expect(
        plan.availableIntervals,
        equals([
          '24h',
          '1d',
          '7d',
          '14d',
          '30d',
          '90d',
          '365d',
          '1h',
          '2h',
          '3h',
          '6h',
          '12h',
          '5m',
          '10m',
          '15m',
          '30m',
          '45m',
        ]),
      );
      expect(plan.monthlyCallLimit, equals(400000));
      expect(plan.hasUnlimitedOhlcHistory, isFalse);
      expect(plan.planName, equals('Starter'));
    });

    test('business plan should have correct limitations', () {
      const plan = CoinPaprikaApiPlan.business();

      expect(plan.ohlcHistoricalDataLimit, isNull); // unlimited
      expect(
        plan.availableIntervals,
        equals([
          '24h',
          '1d',
          '7d',
          '14d',
          '30d',
          '90d',
          '365d',
          '1h',
          '2h',
          '3h',
          '6h',
          '12h',
          '5m',
          '10m',
          '15m',
          '30m',
          '45m',
        ]),
      );
      expect(plan.monthlyCallLimit, equals(5000000));
      expect(plan.hasUnlimitedOhlcHistory, isTrue);
      expect(plan.planName, equals('Business'));
    });

    test('pro plan should have correct limitations', () {
      const plan = CoinPaprikaApiPlan.pro();

      expect(plan.ohlcHistoricalDataLimit, isNull); // unlimited
      expect(
        plan.availableIntervals,
        equals([
          '24h',
          '1d',
          '7d',
          '14d',
          '30d',
          '90d',
          '365d',
          '1h',
          '2h',
          '3h',
          '6h',
          '12h',
          '5m',
          '10m',
          '15m',
          '30m',
          '45m',
        ]),
      );
      expect(plan.monthlyCallLimit, equals(1000000));
      expect(plan.hasUnlimitedOhlcHistory, isTrue);
      expect(plan.planName, equals('Pro'));
    });

    test('ultimate plan should have unlimited OHLC history', () {
      const plan = CoinPaprikaApiPlan.ultimate();

      expect(plan.ohlcHistoricalDataLimit, isNull);
      expect(plan.hasUnlimitedOhlcHistory, isTrue);
      expect(plan.planName, equals('Ultimate'));
    });

    test('enterprise plan should have unlimited features', () {
      const plan = CoinPaprikaApiPlan.enterprise();

      expect(plan.ohlcHistoricalDataLimit, isNull);
      expect(plan.monthlyCallLimit, isNull);
      expect(plan.hasUnlimitedOhlcHistory, isTrue);
      expect(plan.hasUnlimitedCalls, isTrue);
      expect(plan.planName, equals('Enterprise'));
    });
  });

  group('DateTime Utility', () {
    late TestCoinPaprikaProvider testProvider;

    setUp(() {
      testProvider = TestCoinPaprikaProvider();
    });

    test('should format dates correctly for API', () {
      final testDate = DateTime(2025, 8, 31, 15, 30, 45);
      expect(testProvider.formatDateForApi(testDate), equals('2025-08-31'));

      final newYear = DateTime(2025);
      expect(testProvider.formatDateForApi(newYear), equals('2025-01-01'));

      final endOfYear = DateTime(2025, 12, 31);
      expect(testProvider.formatDateForApi(endOfYear), equals('2025-12-31'));

      final singleDigits = DateTime(2025, 5, 3);
      expect(testProvider.formatDateForApi(singleDigits), equals('2025-05-03'));
    });

    test('should handle leap year dates correctly', () {
      final testProvider = TestCoinPaprikaProvider();
      final leapYearDate = DateTime(2024, 2, 29, 12);
      expect(testProvider.formatDateForApi(leapYearDate), equals('2024-02-29'));
    });
  });

  group('Quote Currency Support', () {
    late TestCoinPaprikaProvider testProvider;

    setUp(() {
      testProvider = TestCoinPaprikaProvider();
    });

    test('should support standard quote currencies', () {
      final supportedCurrencies = testProvider.supportedQuoteCurrencies;

      expect(supportedCurrencies, contains(FiatCurrency.usd));
      expect(supportedCurrencies, contains(FiatCurrency.eur));
      expect(supportedCurrencies, contains(Cryptocurrency.btc));
      expect(supportedCurrencies, contains(Cryptocurrency.eth));
    });

    test('should have non-empty supported currencies list', () {
      expect(testProvider.supportedQuoteCurrencies, isNotEmpty);
      expect(testProvider.supportedQuoteCurrencies.length, greaterThan(10));
    });

    test('should support common fiat currencies', () {
      final supportedCurrencies = testProvider.supportedQuoteCurrencies;

      expect(supportedCurrencies, contains(FiatCurrency.gbp));
      expect(supportedCurrencies, contains(FiatCurrency.jpy));
      expect(supportedCurrencies, contains(FiatCurrency.cad));
    });
  });

  group('Plan Description', () {
    test('should provide human-readable descriptions', () {
      const freePlan = CoinPaprikaApiPlan.free();
      expect(freePlan.ohlcLimitDescription, contains('1 year'));

      const starterPlan = CoinPaprikaApiPlan.starter();
      expect(starterPlan.ohlcLimitDescription, contains('5 years'));

      const businessPlan = CoinPaprikaApiPlan.business();
      expect(businessPlan.ohlcLimitDescription, contains('No limit'));

      const ultimatePlan = CoinPaprikaApiPlan.ultimate();
      expect(ultimatePlan.ohlcLimitDescription, contains('No limit'));
    });
  });
}
