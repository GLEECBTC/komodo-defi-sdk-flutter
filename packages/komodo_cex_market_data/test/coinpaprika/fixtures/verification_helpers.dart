/// Verification helpers for common test assertions and patterns
library;

import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'mock_helpers.dart';
import 'test_constants.dart';

/// Helper class for common verification patterns in tests
class VerificationHelpers {
  VerificationHelpers._();

  /// Verifies that an HTTP GET request was made to the expected URI
  static void verifyHttpGetCall(
    MockHttpClient mockHttpClient,
    String expectedUrl,
  ) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;
    expect(capturedUri.toString(), equals(expectedUrl));
  }

  /// Verifies that an HTTP GET request was made with specific path and query parameters
  static void verifyHttpGetCallWithParams(
    MockHttpClient mockHttpClient, {
    String? expectedHost,
    String? expectedPath,
    Map<String, String>? expectedQueryParams,
  }) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    if (expectedHost != null) {
      expect(capturedUri.host, equals(expectedHost));
    }

    if (expectedPath != null) {
      expect(capturedUri.path, equals(expectedPath));
    }

    if (expectedQueryParams != null) {
      expect(capturedUri.queryParameters, equals(expectedQueryParams));
    }
  }

  /// Verifies that HTTP GET was called with URI containing specific elements
  static void verifyHttpGetCallContains(
    MockHttpClient mockHttpClient, {
    String? hostContains,
    String? pathContains,
    String? queryContains,
  }) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    if (hostContains != null) {
      expect(capturedUri.host, contains(hostContains));
    }

    if (pathContains != null) {
      expect(capturedUri.path, contains(pathContains));
    }

    if (queryContains != null) {
      expect(capturedUri.query, contains(queryContains));
    }
  }

  /// Performs multiple verifications on the same captured URI to avoid double-verification issues
  static void verifyHttpGetCallMultiple(
    MockHttpClient mockHttpClient, {
    String? expectedUrl,
    String? expectedHost,
    String? expectedPath,
    Map<String, String>? expectedQueryParams,
    List<String>? expectedQueryParamKeys,
    List<String>? excludedParams,
    String? hostContains,
    String? pathContains,
    String? queryContains,
  }) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    if (expectedUrl != null) {
      expect(capturedUri.toString(), equals(expectedUrl));
    }

    if (expectedHost != null) {
      expect(capturedUri.host, equals(expectedHost));
    }

    if (expectedPath != null) {
      expect(capturedUri.path, equals(expectedPath));
    }

    if (expectedQueryParams != null) {
      expect(capturedUri.queryParameters, equals(expectedQueryParams));
    }

    if (expectedQueryParamKeys != null) {
      expect(
        capturedUri.queryParameters.keys.toSet(),
        equals(expectedQueryParamKeys.toSet()),
        reason: 'Only expected query parameters should be present',
      );
    }

    if (excludedParams != null) {
      for (final param in excludedParams) {
        expect(
          capturedUri.queryParameters.containsKey(param),
          isFalse,
          reason: '$param parameter should not be included',
        );
      }
    }

    if (hostContains != null) {
      expect(capturedUri.host, contains(hostContains));
    }

    if (pathContains != null) {
      expect(capturedUri.path, contains(pathContains));
    }

    if (queryContains != null) {
      expect(capturedUri.query, contains(queryContains));
    }
  }

  /// Verifies that fetchHistoricalOhlc was called with expected parameters
  static void verifyFetchHistoricalOhlc(
    MockCoinPaprikaProvider mockProvider, {
    String? expectedCoinId,
    DateTime? expectedStartDate,
    DateTime? expectedEndDate,
    QuoteCurrency? expectedQuote,
    String? expectedInterval,
    int? expectedCallCount,
  }) {
    final verification = verify(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: expectedCoinId ?? any(named: 'coinId'),
        startDate: expectedStartDate ?? any(named: 'startDate'),
        endDate: expectedEndDate ?? any(named: 'endDate'),
        quote: expectedQuote ?? any(named: 'quote'),
        interval: expectedInterval ?? any(named: 'interval'),
      ),
    );

    if (expectedCallCount != null) {
      verification.called(expectedCallCount);
    } else {
      verification.called(1);
    }
  }

  /// Verifies that fetchTickers was called with expected parameters
  static void verifyFetchTickers(
    MockCoinPaprikaProvider mockProvider, {
    List<QuoteCurrency>? expectedQuotes,
    int? expectedCallCount,
  }) {
    final verification = verify(
      () => mockProvider.fetchTickers(
        quotes: expectedQuotes ?? any(named: 'quotes'),
      ),
    );

    if (expectedCallCount != null) {
      verification.called(expectedCallCount);
    } else {
      verification.called(1);
    }
  }

  /// Verifies that fetchCoinMarkets was called with expected parameters
  static void verifyFetchCoinMarkets(
    MockCoinPaprikaProvider mockProvider, {
    String? expectedCoinId,
    List<QuoteCurrency>? expectedQuotes,
    int? expectedCallCount,
  }) {
    final verification = verify(
      () => mockProvider.fetchCoinMarkets(
        coinId: expectedCoinId ?? any(named: 'coinId'),
        quotes: expectedQuotes ?? any(named: 'quotes'),
      ),
    );

    if (expectedCallCount != null) {
      verification.called(expectedCallCount);
    } else {
      verification.called(1);
    }
  }

  /// Verifies that fetchCoinList was called the expected number of times
  static void verifyFetchCoinList(
    MockCoinPaprikaProvider mockProvider, {
    int? expectedCallCount,
  }) {
    final verification = verify(() => mockProvider.fetchCoinList());

    if (expectedCallCount != null) {
      verification.called(expectedCallCount);
    } else {
      verification.called(1);
    }
  }

  /// Verifies that no calls were made to fetchHistoricalOhlc
  static void verifyNoFetchHistoricalOhlcCalls(
    MockCoinPaprikaProvider mockProvider,
  ) {
    verifyNever(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    );
  }

  /// Verifies URL format for historical OHLC endpoint
  static void verifyHistoricalOhlcUrl(
    MockHttpClient mockHttpClient,
    String expectedCoinId, {
    String? expectedStartDate,
    String? expectedInterval,
    List<String>? excludedParams,
  }) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    // Verify URL structure
    expect(capturedUri.host, equals(TestConstants.baseUrl));
    expect(
      capturedUri.path,
      equals('${TestConstants.apiVersion}/tickers/$expectedCoinId/historical'),
    );

    // Verify required query parameters
    if (expectedStartDate != null) {
      expect(capturedUri.queryParameters['start'], equals(expectedStartDate));
    }

    if (expectedInterval != null) {
      expect(capturedUri.queryParameters['interval'], equals(expectedInterval));
    }

    // Verify excluded parameters are not present
    if (excludedParams != null) {
      for (final param in excludedParams) {
        expect(
          capturedUri.queryParameters.containsKey(param),
          isFalse,
          reason: '$param parameter should not be included',
        );
      }
    }
  }

  /// Verifies URL format for ticker endpoint
  static void verifyTickerUrl(
    MockHttpClient mockHttpClient,
    String expectedCoinId, {
    String? expectedQuotes,
  }) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    // Verify URL structure
    expect(capturedUri.host, equals(TestConstants.baseUrl));
    expect(
      capturedUri.path,
      equals('${TestConstants.apiVersion}/tickers/$expectedCoinId'),
    );

    // Verify quotes parameter
    if (expectedQuotes != null) {
      expect(capturedUri.queryParameters['quotes'], equals(expectedQuotes));
    }
  }

  /// Verifies URL format for markets endpoint
  static void verifyMarketsUrl(
    MockHttpClient mockHttpClient,
    String expectedCoinId, {
    String? expectedQuotes,
  }) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    // Verify URL structure
    expect(capturedUri.host, equals(TestConstants.baseUrl));
    expect(
      capturedUri.path,
      equals('${TestConstants.apiVersion}/coins/$expectedCoinId/markets'),
    );

    // Verify quotes parameter
    if (expectedQuotes != null) {
      expect(capturedUri.queryParameters['quotes'], equals(expectedQuotes));
    }
  }

  /// Verifies that a date range is within expected bounds
  static void verifyDateRange(
    DateTime actualStart,
    DateTime actualEnd, {
    DateTime? expectedStart,
    DateTime? expectedEnd,
    Duration? maxDuration,
    Duration? tolerance,
  }) {
    final defaultTolerance = tolerance ?? const Duration(minutes: 5);

    if (expectedStart != null) {
      final startDiff = actualStart.difference(expectedStart).abs();
      expect(
        startDiff,
        lessThan(defaultTolerance),
        reason: 'Start date should be close to expected date',
      );
    }

    if (expectedEnd != null) {
      final endDiff = actualEnd.difference(expectedEnd).abs();
      expect(
        endDiff,
        lessThan(defaultTolerance),
        reason: 'End date should be close to expected date',
      );
    }

    if (maxDuration != null) {
      final actualDuration = actualEnd.difference(actualStart);
      expect(
        actualDuration,
        lessThanOrEqualTo(maxDuration),
        reason: 'Duration should not exceed maximum allowed',
      );
    }
  }

  /// Verifies that batch requests don't exceed safe duration limits
  static void verifyBatchDurations(
    MockCoinPaprikaProvider mockProvider, {
    Duration? maxBatchDuration,
    int? minBatchCount,
  }) {
    final capturedCalls = verify(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: captureAny(named: 'startDate'),
        endDate: captureAny(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    ).captured;

    // Extract start and end dates from captured calls
    final batches = <Duration>[];
    for (int i = 0; i < capturedCalls.length; i += 2) {
      final startDate = capturedCalls[i] as DateTime;
      final endDate = capturedCalls[i + 1] as DateTime;
      batches.add(endDate.difference(startDate));
    }

    if (minBatchCount != null) {
      expect(
        batches.length,
        greaterThanOrEqualTo(minBatchCount),
        reason: 'Should have at least $minBatchCount batches',
      );
    }

    if (maxBatchDuration != null) {
      for (final duration in batches) {
        expect(
          duration,
          lessThanOrEqualTo(maxBatchDuration),
          reason: 'Batch duration should not exceed safe limit',
        );
      }
    }
  }

  /// Verifies that interval conversion was applied correctly
  static void verifyIntervalConversion(
    MockHttpClient mockHttpClient,
    String inputInterval,
    String expectedApiInterval,
  ) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    expect(
      capturedUri.queryParameters['interval'],
      equals(expectedApiInterval),
      reason:
          'Interval $inputInterval should be converted to $expectedApiInterval',
    );
  }

  /// Verifies that quote currency mapping was applied correctly
  static void verifyQuoteCurrencyMapping(
    MockCoinPaprikaProvider mockProvider,
    List<QuoteCurrency> inputQuotes,
    List<QuoteCurrency> expectedQuotes,
  ) {
    verify(
      () => mockProvider.fetchCoinTicker(
        coinId: any(named: 'coinId'),
        quotes: expectedQuotes,
      ),
    ).called(1);
  }

  /// Verifies that date formatting follows the expected pattern
  static void verifyDateFormatting(
    MockHttpClient mockHttpClient,
    DateTime inputDate,
    String expectedFormattedDate,
  ) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    expect(
      capturedUri.queryParameters['start'],
      equals(expectedFormattedDate),
      reason: 'Date should be formatted as YYYY-MM-DD',
    );
  }

  /// Verifies that no quote parameter is included in URL (for historical OHLC)
  static void verifyNoQuoteParameter(MockHttpClient mockHttpClient) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    expect(
      capturedUri.queryParameters.containsKey('quote'),
      isFalse,
      reason:
          'Quote parameter should not be included in historical OHLC requests',
    );
  }

  /// Verifies that only expected query parameters are present
  static void verifyOnlyExpectedQueryParams(
    MockHttpClient mockHttpClient,
    List<String> expectedParams,
  ) {
    final capturedUri =
        verify(() => mockHttpClient.get(captureAny())).captured.single as Uri;

    expect(
      capturedUri.queryParameters.keys.toSet(),
      equals(expectedParams.toSet()),
      reason: 'Only expected query parameters should be present',
    );
  }

  /// Verifies that multiple provider calls were made for batching
  static void verifyMultipleProviderCalls(
    MockCoinPaprikaProvider mockProvider,
    int expectedMinCalls,
  ) {
    verify(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    ).called(greaterThan(expectedMinCalls));
  }

  /// Verifies that UTC time was used in date calculations
  static void verifyUtcTimeUsage(MockCoinPaprikaProvider mockProvider) {
    final capturedCalls = verify(
      () => mockProvider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: captureAny(named: 'startDate'),
        endDate: captureAny(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    ).captured;

    // Verify that captured dates are in UTC
    for (int i = 0; i < capturedCalls.length; i += 2) {
      final startDate = capturedCalls[i] as DateTime;
      final endDate = capturedCalls[i + 1] as DateTime;

      expect(startDate.isUtc, isTrue, reason: 'Start date should be in UTC');
      expect(endDate.isUtc, isTrue, reason: 'End date should be in UTC');
    }
  }
}
