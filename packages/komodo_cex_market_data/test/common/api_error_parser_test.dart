import 'package:komodo_cex_market_data/src/common/api_error_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ApiError', () {
    test('toString includes status code and message', () {
      const error = ApiError(statusCode: 429, message: 'Rate limit exceeded');

      expect(error.toString(), 'API Error 429: Rate limit exceeded');
    });

    test('toString includes error type when provided', () {
      const error = ApiError(
        statusCode: 429,
        message: 'Rate limit exceeded',
        errorType: 'rate_limit',
      );

      expect(
        error.toString(),
        'API Error 429: Rate limit exceeded (type: rate_limit)',
      );
    });

    test('toString includes retry after when provided', () {
      const error = ApiError(
        statusCode: 429,
        message: 'Rate limit exceeded',
        errorType: 'rate_limit',
        retryAfter: 60,
      );

      expect(
        error.toString(),
        'API Error 429: Rate limit exceeded (type: rate_limit) (retry after: 60s)',
      );
    });
  });

  group('MarketDataApiException', () {
    test('names the service and reports the rate limit', () {
      final exception = MarketDataApiException(
        ApiErrorParser.parseCoinPaprikaError(402, null),
        service: 'CoinPaprika',
      );

      expect(exception.isRateLimited, isTrue);
      expect(exception.toString(), startsWith('CoinPaprika API Error 402: '));
    });

    test('is not rate limited for other errors', () {
      final exception = MarketDataApiException(
        ApiErrorParser.parseCoinPaprikaError(500, null),
        service: 'CoinPaprika',
      );

      expect(exception.isRateLimited, isFalse);
    });
  });

  group('ApiErrorParser.parseCoinPaprikaError', () {
    test('parses 429 rate limit error correctly', () {
      const responseBody = '{"error": "Rate limit exceeded"}';
      final error = ApiErrorParser.parseCoinPaprikaError(429, responseBody);

      expect(error.statusCode, 429);
      expect(
        error.message,
        'Rate limit exceeded. Please reduce request frequency.',
      );
      expect(error.errorType, 'rate_limit');
      expect(error.isRateLimitError, true);
      expect(error.isPaymentRequiredError, false);
      expect(error.retryAfter, 60); // Default retry
    });

    test('parses a 402 quota block as a rate limit', () {
      const responseBody = '{"error": "payment_required"}';
      final error = ApiErrorParser.parseCoinPaprikaError(402, responseBody);

      expect(error.statusCode, 402);
      expect(
        error.message,
        'Rate limit exceeded: CoinPaprika refuses requests until the plan '
        'quota resets.',
      );
      expect(error.errorType, 'payment_required');
      expect(error.isPaymentRequiredError, true);
      expect(error.isRateLimitError, true);
    });

    test('parses a 402 history cutoff as a plan limitation', () {
      const responseBody =
          '{"error":"Getting daily historical data before 2025-11-06 '
          '08:44:51.330733739 +0000 UTC is not allowed in this plan. Check '
          'plans on coinpaprika.com/api"}';
      final error = ApiErrorParser.parseCoinPaprikaError(402, responseBody);

      expect(error.statusCode, 402);
      expect(error.errorType, 'plan_limitation');
      expect(error.isQuotaExceededError, true);
      expect(error.isRateLimitError, false);
      expect(error.message, isNot(contains('2025-11-06')));
    });

    test('parses the daily-history wording on a 400 as well', () {
      const responseBody =
          '{"error": "Getting daily historical data before 2024-01-01 is '
          'not allowed in this plan"}';
      final error = ApiErrorParser.parseCoinPaprikaError(400, responseBody);

      expect(error.errorType, 'plan_limitation');
    });

    test('parses 400 plan limitation error correctly', () {
      const responseBody =
          '{"error": "Getting historical OHLCV data before 2024-01-01 is not allowed in this plan"}';
      final error = ApiErrorParser.parseCoinPaprikaError(400, responseBody);

      expect(error.statusCode, 400);
      expect(error.message, contains('Historical data access denied'));
      expect(error.message, contains('upgrade your plan'));
      expect(error.errorType, 'plan_limitation');
      expect(error.isQuotaExceededError, true);
    });

    test('parses generic 400 error correctly', () {
      const responseBody = '{"error": "Bad request"}';
      final error = ApiErrorParser.parseCoinPaprikaError(400, responseBody);

      expect(error.statusCode, 400);
      expect(
        error.message,
        'Bad request. Please check your request parameters.',
      );
      expect(error.errorType, 'bad_request');
    });

    test('parses 401 unauthorized error correctly', () {
      const responseBody = '{"error": "Unauthorized"}';
      final error = ApiErrorParser.parseCoinPaprikaError(401, responseBody);

      expect(error.statusCode, 401);
      expect(error.message, 'Unauthorized. Please check your API key.');
      expect(error.errorType, 'unauthorized');
    });

    test('parses 404 not found error correctly', () {
      const responseBody = '{"error": "Not found"}';
      final error = ApiErrorParser.parseCoinPaprikaError(404, responseBody);

      expect(error.statusCode, 404);
      expect(error.message, 'Resource not found. Please verify the coin ID.');
      expect(error.errorType, 'not_found');
    });

    test('parses 500 server error correctly', () {
      const responseBody = '{"error": "Internal server error"}';
      final error = ApiErrorParser.parseCoinPaprikaError(500, responseBody);

      expect(error.statusCode, 500);
      expect(
        error.message,
        'CoinPaprika server error. Please try again later.',
      );
      expect(error.errorType, 'server_error');
    });

    test('parses unknown error code correctly', () {
      const responseBody = '{"error": "Unknown error"}';
      final error = ApiErrorParser.parseCoinPaprikaError(999, responseBody);

      expect(error.statusCode, 999);
      expect(error.message, 'Unexpected error occurred.');
      expect(error.errorType, 'unknown');
    });

    test('handles null response body safely', () {
      final error = ApiErrorParser.parseCoinPaprikaError(429, null);

      expect(error.statusCode, 429);
      expect(error.message, isNotNull);
      expect(error.isRateLimitError, true);
    });

    test('does not expose raw response body in error message', () {
      const sensitiveData = 'SENSITIVE_API_KEY_12345';
      final responseBody =
          '{"error": "Rate limit", "api_key": "$sensitiveData"}';
      final error = ApiErrorParser.parseCoinPaprikaError(429, responseBody);

      expect(error.message, isNot(contains(sensitiveData)));
      expect(error.toString(), isNot(contains(sensitiveData)));
    });
  });

  group('ApiErrorParser.parseCoinGeckoError', () {
    test('parses 429 rate limit error correctly', () {
      const responseBody = '{"error": "Rate limit exceeded"}';
      final error = ApiErrorParser.parseCoinGeckoError(429, responseBody);

      expect(error.statusCode, 429);
      expect(
        error.message,
        'Rate limit exceeded. Please reduce request frequency.',
      );
      expect(error.errorType, 'rate_limit');
      expect(error.isRateLimitError, true);
    });

    test('parses 402 payment required error correctly', () {
      const responseBody = '{"error": "Payment required"}';
      final error = ApiErrorParser.parseCoinGeckoError(402, responseBody);

      expect(error.statusCode, 402);
      expect(
        error.message,
        'Payment required. Please upgrade your CoinGecko plan.',
      );
      expect(error.errorType, 'payment_required');
      expect(error.isPaymentRequiredError, true);
    });

    test('parses 400 plan limitation error with days limit', () {
      const responseBody = '{"error": "Cannot query more than 365 days"}';
      final error = ApiErrorParser.parseCoinGeckoError(400, responseBody);

      expect(error.statusCode, 400);
      expect(error.message, contains('365 days'));
      expect(error.message, contains('upgrade your plan'));
      expect(error.errorType, 'plan_limitation');
      expect(error.isQuotaExceededError, true);
    });

    test('parses generic 400 error correctly', () {
      const responseBody = '{"error": "Bad request"}';
      final error = ApiErrorParser.parseCoinGeckoError(400, responseBody);

      expect(error.statusCode, 400);
      expect(
        error.message,
        'Bad request. Please check your request parameters.',
      );
      expect(error.errorType, 'bad_request');
    });

    test('does not expose raw response body in error message', () {
      const sensitiveData = 'PRIVATE_TOKEN_XYZ789';
      final responseBody = '{"error": "Forbidden", "token": "$sensitiveData"}';
      final error = ApiErrorParser.parseCoinGeckoError(403, responseBody);

      expect(error.message, isNot(contains(sensitiveData)));
      expect(error.toString(), isNot(contains(sensitiveData)));
    });
  });

  group('ApiErrorParser.createSafeErrorMessage', () {
    test('creates basic error message', () {
      final message = ApiErrorParser.createSafeErrorMessage(
        operation: 'price fetch',
        service: 'CoinGecko',
        statusCode: 404,
      );

      expect(
        message,
        'CoinGecko API error during price fetch (HTTP 404) - Resource not found',
      );
    });

    test('includes coin ID when provided', () {
      final message = ApiErrorParser.createSafeErrorMessage(
        operation: 'OHLC fetch',
        service: 'CoinPaprika',
        statusCode: 429,
        coinId: 'btc-bitcoin',
      );

      expect(
        message,
        'CoinPaprika API error during OHLC fetch for btc-bitcoin (HTTP 429) - Rate limit exceeded',
      );
    });

    test('handles different status codes with appropriate context', () {
      final testCases = [
        (429, 'Rate limit exceeded'),
        (402, 'Payment/upgrade required'),
        (401, 'Authentication failed'),
        (403, 'Access forbidden'),
        (404, 'Resource not found'),
        (500, 'Server error'),
        (502, 'Server error'),
        (503, 'Server error'),
        (504, 'Server error'),
      ];

      for (final (statusCode, expectedContext) in testCases) {
        final message = ApiErrorParser.createSafeErrorMessage(
          operation: 'test operation',
          service: 'TestService',
          statusCode: statusCode,
        );

        expect(message, contains(expectedContext));
        expect(message, contains('HTTP $statusCode'));
      }
    });

    test('does not include context for unrecognized status codes', () {
      final message = ApiErrorParser.createSafeErrorMessage(
        operation: 'test operation',
        service: 'TestService',
        statusCode: 999,
      );

      expect(message, 'TestService API error during test operation (HTTP 999)');
      expect(message, isNot(contains(' - ')));
    });
  });

  group('Security Tests', () {
    test('ensures no sensitive data leaks in error messages', () {
      const sensitivePatterns = [
        'api_key',
        'token',
        'password',
        'secret',
        'private',
        'bearer',
        'authorization',
        'x-api-key',
      ];

      // Test with response body containing sensitive data
      final responseBody = '''
      {
        "error": "Unauthorized",
        "api_key": "sk-1234567890abcdef",
        "token": "bearer_token_xyz",
        "private_data": "sensitive_info",
        "debug_info": {
          "authorization": "Bearer secret_key",
          "x-api-key": "private_key_123"
        }
      }
      ''';

      final coinPaprikaError = ApiErrorParser.parseCoinPaprikaError(
        401,
        responseBody,
      );
      final coinGeckoError = ApiErrorParser.parseCoinGeckoError(
        401,
        responseBody,
      );

      for (final pattern in sensitivePatterns) {
        expect(
          coinPaprikaError.message.toLowerCase(),
          isNot(contains(pattern)),
        );
        expect(
          coinPaprikaError.toString().toLowerCase(),
          isNot(contains(pattern)),
        );
        expect(coinGeckoError.message.toLowerCase(), isNot(contains(pattern)));
        expect(
          coinGeckoError.toString().toLowerCase(),
          isNot(contains(pattern)),
        );
      }
    });

    test('ensures no raw JSON is included in error messages', () {
      const responseBody = '''
      {
        "error": "Rate limit exceeded",
        "details": {
          "limit": 1000,
          "remaining": 0,
          "reset_time": "2024-01-01T00:00:00Z"
        },
        "user_info": {
          "plan": "free",
          "user_id": "12345"
        }
      }
      ''';

      final error = ApiErrorParser.parseCoinPaprikaError(429, responseBody);

      // Should not contain JSON structure characters in the final message
      expect(error.message, isNot(contains('{')));
      expect(error.message, isNot(contains('}')));
      expect(error.message, isNot(contains('"')));
      expect(error.message, isNot(contains('user_id')));
      expect(error.message, isNot(contains('12345')));
    });
  });
}
