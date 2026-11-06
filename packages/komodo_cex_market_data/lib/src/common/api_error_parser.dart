import 'dart:convert';

/// API Error Parser for Safe Error Handling
///
/// This module provides secure error parsing utilities that prevent sensitive
/// information from being exposed in logs or error messages. It is specifically
/// designed to handle API responses from cryptocurrency data providers without
/// leaking:
///
/// - Raw API response bodies
/// - API keys or authentication tokens
/// - User-specific data or identifiers
/// - Internal server details or stack traces
///
/// ## Security Features
///
/// 1. **No Raw Response Logging**: Never includes raw HTTP response bodies
///    in error messages or logs.
///
/// 2. **Sanitized Error Messages**: Provides clean, user-friendly error
///    messages that don't expose sensitive API details.
///
/// 3. **Rate Limit Handling**: Specifically handles 429 and 402 status codes
///    which are common in cryptocurrency API services with plan limitations.
///
/// 4. **Pattern Recognition**: Identifies specific error patterns (like
///    CoinPaprika's plan limitation messages) without exposing the full text.
///
/// ## Usage
///
/// ```dart
/// // Instead of:
/// throw Exception('API Error: ${response.statusCode} ${response.body}');
///
/// // Use:
/// final apiError = ApiErrorParser.parseCoinPaprikaError(
///   response.statusCode,
///   response.body,
/// );
/// logger.warning(ApiErrorParser.createSafeErrorMessage(
///   operation: 'price fetch',
///   service: 'CoinPaprika',
///   statusCode: response.statusCode,
/// ));
/// throw Exception(apiError.message);
/// ```

/// Represents a parsed API error with safe, loggable information.
class ApiError {
  const ApiError({
    required this.statusCode,
    required this.message,
    this.errorType,
    this.retryAfter,
    this.isRateLimitError = false,
    this.isPaymentRequiredError = false,
    this.isQuotaExceededError = false,
  });

  /// HTTP status code
  final int statusCode;

  /// Safe, parsed error message
  final String message;

  /// Type/category of the error (e.g., 'rate_limit', 'quota_exceeded')
  final String? errorType;

  /// Retry-After header value in seconds (for rate limit errors)
  final int? retryAfter;

  /// Whether this is a rate limiting error (429)
  final bool isRateLimitError;

  /// Whether this is a payment required error (402)
  final bool isPaymentRequiredError;

  /// Whether this is a quota exceeded error
  final bool isQuotaExceededError;

  @override
  String toString() {
    final buffer = StringBuffer('API Error $statusCode: $message');
    if (errorType != null) {
      buffer.write(' (type: $errorType)');
    }
    if (retryAfter != null) {
      buffer.write(' (retry after: ${retryAfter}s)');
    }
    return buffer.toString();
  }
}

/// An HTTP error from a market data API, classified by [ApiErrorParser].
class MarketDataApiException implements Exception {
  const MarketDataApiException(this.error, {required this.service});

  /// The parsed error, which never includes the raw response body.
  final ApiError error;

  /// The API that answered, e.g. `CoinPaprika`.
  final String service;

  /// Whether the API refuses further requests for now.
  bool get isRateLimited => error.isRateLimitError;

  @override
  String toString() => '$service $error';
}

/// Utility class for parsing API error responses without exposing raw response bodies.
class ApiErrorParser {
  /// Parses CoinPaprika API error responses.
  static ApiError parseCoinPaprikaError(int statusCode, String? responseBody) {
    // CoinPaprika once sent this as 400 and now sends it as 402.
    if ((statusCode == 400 || statusCode == 402) &&
        (responseBody?.contains('is not allowed in this plan') ?? false)) {
      return ApiError(
        statusCode: statusCode,
        message:
            'Historical data access denied for current plan. '
            'Please request more recent data or upgrade your plan.',
        errorType: 'plan_limitation',
        isQuotaExceededError: true,
      );
    }

    switch (statusCode) {
      case 429:
        return ApiError(
          statusCode: statusCode,
          message: 'Rate limit exceeded. Please reduce request frequency.',
          errorType: 'rate_limit',
          isRateLimitError: true,
          retryAfter: _parseRetryAfter(responseBody) ?? 60,
        );

      // The free plan answers 402 to every endpoint once its hourly or
      // monthly quota is used up, until the block expires.
      case 402:
        return ApiError(
          statusCode: statusCode,
          message:
              'Rate limit exceeded: CoinPaprika refuses requests until the '
              'plan quota resets.',
          errorType: 'payment_required',
          isRateLimitError: true,
          isPaymentRequiredError: true,
        );

      case 400:
        if (responseBody != null && responseBody.contains('Invalid')) {
          return ApiError(
            statusCode: statusCode,
            message: 'Invalid request parameters.',
            errorType: 'invalid_request',
          );
        }

        return ApiError(
          statusCode: statusCode,
          message: 'Bad request. Please check your request parameters.',
          errorType: 'bad_request',
        );

      case 401:
        return ApiError(
          statusCode: statusCode,
          message: 'Unauthorized. Please check your API key.',
          errorType: 'unauthorized',
        );

      case 403:
        return ApiError(
          statusCode: statusCode,
          message: 'Forbidden. Access denied for this resource.',
          errorType: 'forbidden',
        );

      case 404:
        return ApiError(
          statusCode: statusCode,
          message: 'Resource not found. Please verify the coin ID.',
          errorType: 'not_found',
        );

      case 500:
      case 502:
      case 503:
      case 504:
        return ApiError(
          statusCode: statusCode,
          message: 'CoinPaprika server error. Please try again later.',
          errorType: 'server_error',
        );

      default:
        return ApiError(
          statusCode: statusCode,
          message: 'Unexpected error occurred.',
          errorType: 'unknown',
        );
    }
  }

  /// Parses CoinGecko API error responses.
  static ApiError parseCoinGeckoError(int statusCode, String? responseBody) {
    switch (statusCode) {
      case 429:
        return ApiError(
          statusCode: statusCode,
          message: 'Rate limit exceeded. Please reduce request frequency.',
          errorType: 'rate_limit',
          isRateLimitError: true,
          retryAfter: _parseRetryAfter(responseBody) ?? 60,
        );

      case 402:
        return ApiError(
          statusCode: statusCode,
          message: 'Payment required. Please upgrade your CoinGecko plan.',
          errorType: 'payment_required',
          isPaymentRequiredError: true,
        );

      case 400:
        // Check for specific CoinGecko error patterns
        if (responseBody != null &&
            (responseBody.contains('days') || responseBody.contains('365'))) {
          return ApiError(
            statusCode: statusCode,
            message:
                'Historical data request exceeds free tier limits (365 days). '
                'Please request more recent data or upgrade your plan.',
            errorType: 'plan_limitation',
            isQuotaExceededError: true,
          );
        }

        return ApiError(
          statusCode: statusCode,
          message: 'Bad request. Please check your request parameters.',
          errorType: 'bad_request',
        );

      case 401:
        return ApiError(
          statusCode: statusCode,
          message: 'Unauthorized. Please check your API key.',
          errorType: 'unauthorized',
        );

      case 403:
        return ApiError(
          statusCode: statusCode,
          message: 'Forbidden. Access denied for this resource.',
          errorType: 'forbidden',
        );

      case 404:
        return ApiError(
          statusCode: statusCode,
          message: 'Resource not found. Please verify the coin ID.',
          errorType: 'not_found',
        );

      case 500:
      case 502:
      case 503:
      case 504:
        return ApiError(
          statusCode: statusCode,
          message: 'CoinGecko server error. Please try again later.',
          errorType: 'server_error',
        );

      default:
        return ApiError(
          statusCode: statusCode,
          message: 'Unexpected error occurred.',
          errorType: 'unknown',
        );
    }
  }

  /// Attempts to parse Retry-After header from response body or headers.
  static int? _parseRetryAfter(String? responseBody) {
    if (responseBody == null) return null;

    // Try to parse JSON response for retry information
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>?;
      if (json != null) {
        // Common retry fields in API responses
        final retryAfter =
            json['retry_after'] ?? json['retryAfter'] ?? json['retry-after'];
        if (retryAfter is int) return retryAfter;
        if (retryAfter is String) return int.tryParse(retryAfter);
      }
    } catch (_) {
      // Ignore JSON parsing errors
    }

    // Default retry suggestion for rate limits
    return null;
  }

  /// Creates a safe error message for logging purposes.
  static String createSafeErrorMessage({
    required String operation,
    required String service,
    required int statusCode,
    String? coinId,
  }) {
    final buffer = StringBuffer('$service API error during $operation');

    if (coinId != null) {
      buffer.write(' for $coinId');
    }

    buffer.write(' (HTTP $statusCode)');

    // Add contextual information based on status code
    switch (statusCode) {
      case 429:
        buffer.write(' - Rate limit exceeded');
      case 402:
        buffer.write(' - Payment/upgrade required');
      case 401:
        buffer.write(' - Authentication failed');
      case 403:
        buffer.write(' - Access forbidden');
      case 404:
        buffer.write(' - Resource not found');
      case 500:
      case 502:
      case 503:
      case 504:
        buffer.write(' - Server error');
    }

    return buffer.toString();
  }
}
