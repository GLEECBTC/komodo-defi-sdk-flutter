import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// A top-level MMRPC error from a `routed_swap::*` or `task::routed_swap::*`
/// method.
///
/// Parsed before the global error registry, deliberately: several routed
/// error names are shared with unrelated methods (`NoRouteFound` is also a
/// Lightning payment error, `InvalidConfig` a token-activation one), and a
/// registry lookup by name alone types them into the wrong domain and loses
/// their payload.
///
/// Distinct from a terminal task `Error` *result*, which arrives as a normal
/// `task::routed_swap::status` response rather than as a thrown exception.
sealed class RoutedSwapRpcException implements Exception {
  const RoutedSwapRpcException({
    required this.errorType,
    required this.message,
    this.errorData,
  });

  /// Parses a top-level error envelope, or returns null when it is not one.
  static RoutedSwapRpcException? tryParse(JsonMap json) {
    final envelope =
        json.valueOrNull<JsonMap>('result', 'details') ??
        json.valueOrNull<JsonMap>('message') ??
        json;
    final errorType = envelope.valueOrNull<String>('error_type');
    if (errorType == null) return null;

    final message = envelope.valueOrNull<String>('error') ?? errorType;
    final raw = envelope['error_data'];
    final data = raw is Map ? convertToJsonMap(raw) : const <String, dynamic>{};
    String req(String key) => data.valueOrNull<String>(key) ?? '';
    String? opt(String key) => data.valueOrNull<String>(key);
    // Status reports NoSuchTask's task id as a bare number; cancel reports it
    // as `{"task_id": N}`.
    final taskId = raw is int ? raw : data.valueOrNull<int>('task_id');

    return switch (errorType) {
      'CoinNotActive' => RoutedSwapCoinNotActiveException(
        coin: req('coin'),
        message: message,
        errorData: raw,
      ),
      'PairNotSupported' => RoutedSwapPairNotSupportedException(
        from: req('from'),
        to: req('to'),
        reason: req('reason'),
        message: message,
        errorData: raw,
      ),
      'InvalidParam' => RoutedSwapInvalidParamException(
        param: req('param'),
        reason: req('reason'),
        message: message,
        errorData: raw,
      ),
      'AmountOutOfBounds' => RoutedSwapAmountOutOfBoundsException(
        param: req('param'),
        value: req('value'),
        min: req('min'),
        max: req('max'),
        message: message,
        errorData: raw,
      ),
      'MyAddressError' => RoutedSwapMyAddressException(
        coin: req('coin'),
        detail: req('message'),
        message: message,
        errorData: raw,
      ),
      'InvalidConfig' => RoutedSwapInvalidConfigException(
        detail: req('message'),
        message: message,
        errorData: raw,
      ),
      'NoRouteFound' => RoutedSwapNoRouteException(
        reasons: [
          for (final reason
              in data.valueOrNull<List<dynamic>>('reasons') ?? const [])
            if (reason is String) reason,
        ],
        providerRequestId: opt('provider_request_id'),
        message: message,
        errorData: raw,
      ),
      'RateLimited' => RoutedSwapRateLimitedException(
        providerRequestId: opt('provider_request_id'),
        message: message,
        errorData: raw,
      ),
      'ProviderApiError' => RoutedSwapProviderException(
        detail: req('message'),
        providerRequestId: opt('provider_request_id'),
        message: message,
        errorData: raw,
      ),
      'TransportError' => RoutedSwapTransportException(
        detail: req('message'),
        message: message,
        errorData: raw,
      ),
      'InternalError' => RoutedSwapInternalException(
        detail: raw is String ? raw : req('message'),
        message: message,
        errorData: raw,
      ),
      'NoSuchTask' => RoutedSwapNoSuchTaskException(
        taskId: taskId,
        message: message,
        errorData: raw,
      ),
      'TaskFinished' => RoutedSwapTaskFinishedException(
        taskId: taskId,
        message: message,
        errorData: raw,
      ),
      'TaskAlreadyBroadcast' => RoutedSwapTaskAlreadyBroadcastException(
        taskId: taskId,
        message: message,
        errorData: raw,
      ),
      _ => RoutedSwapUnknownRpcException(
        errorType: errorType,
        message: message,
        errorData: raw,
      ),
    };
  }

  /// The wire `error_type`.
  final String errorType;

  /// KDF's human-readable error text. Diagnostic; not localized.
  final String message;

  /// The raw `error_data`, for logs and support.
  final Object? errorData;

  /// The provider's support-correlation id, on provider-originated errors.
  String? get providerRequestId => null;

  /// Whether retrying the same request later may succeed.
  bool get isTransient => false;

  @override
  String toString() => 'RoutedSwapRpcException($errorType): $message';
}

/// A coin in the request is not activated.
final class RoutedSwapCoinNotActiveException extends RoutedSwapRpcException {
  const RoutedSwapCoinNotActiveException({
    required this.coin,
    required super.message,
    super.errorData,
  }) : super(errorType: 'CoinNotActive');

  /// The inactive ticker.
  final String coin;
}

/// The pair is not eligible to quote for the selected provider.
final class RoutedSwapPairNotSupportedException extends RoutedSwapRpcException {
  const RoutedSwapPairNotSupportedException({
    required this.from,
    required this.to,
    required this.reason,
    required super.message,
    super.errorData,
  }) : super(errorType: 'PairNotSupported');

  /// Source ticker.
  final String from;

  /// Destination ticker.
  final String to;

  /// Why. Display text.
  final String reason;
}

/// A request parameter is invalid: an unknown provider or order, or an amount
/// with more decimals than the source coin supports.
final class RoutedSwapInvalidParamException extends RoutedSwapRpcException {
  const RoutedSwapInvalidParamException({
    required this.param,
    required this.reason,
    required super.message,
    super.errorData,
  }) : super(errorType: 'InvalidParam');

  /// The offending parameter.
  final String param;

  /// Why. Display text.
  final String reason;
}

/// The amount is outside the accepted bounds.
final class RoutedSwapAmountOutOfBoundsException
    extends RoutedSwapRpcException {
  const RoutedSwapAmountOutOfBoundsException({
    required this.param,
    required this.value,
    required this.min,
    required this.max,
    required super.message,
    super.errorData,
  }) : super(errorType: 'AmountOutOfBounds');

  /// The offending parameter.
  final String param;

  /// Its value.
  final String value;

  /// Lower bound, in coin units.
  final String min;

  /// Upper bound, in coin units.
  final String max;
}

/// The source coin has no single enabled EVM address.
final class RoutedSwapMyAddressException extends RoutedSwapRpcException {
  const RoutedSwapMyAddressException({
    required this.coin,
    required this.detail,
    required super.message,
    super.errorData,
  }) : super(errorType: 'MyAddressError');

  /// The source ticker.
  final String coin;

  /// The wallet-mode detail. Diagnostic.
  final String detail;
}

/// The node's provider configuration is invalid. Operator-side; not
/// retryable.
final class RoutedSwapInvalidConfigException extends RoutedSwapRpcException {
  const RoutedSwapInvalidConfigException({
    required this.detail,
    required super.message,
    super.errorData,
  }) : super(errorType: 'InvalidConfig');

  /// Diagnostic text.
  final String detail;
}

/// No route exists right now.
final class RoutedSwapNoRouteException extends RoutedSwapRpcException {
  const RoutedSwapNoRouteException({
    required super.message,
    this.reasons = const [],
    this.providerRequestId,
    super.errorData,
  }) : super(errorType: 'NoRouteFound');

  /// Display strings with no stable format — the provider's summary first,
  /// then failed-route tool errors, then filtered-out candidates. Never parse
  /// them.
  final List<String> reasons;

  @override
  final String? providerRequestId;
}

/// The provider's quota is exhausted. Slow re-quoting and retry after a pause.
final class RoutedSwapRateLimitedException extends RoutedSwapRpcException {
  const RoutedSwapRateLimitedException({
    required super.message,
    this.providerRequestId,
    super.errorData,
  }) : super(errorType: 'RateLimited');

  @override
  final String? providerRequestId;

  @override
  bool get isTransient => true;
}

/// The selected provider returned an error.
final class RoutedSwapProviderException extends RoutedSwapRpcException {
  const RoutedSwapProviderException({
    required this.detail,
    required super.message,
    this.providerRequestId,
    super.errorData,
  }) : super(errorType: 'ProviderApiError');

  /// Sanitized provider text. Diagnostic.
  final String detail;

  @override
  final String? providerRequestId;

  @override
  bool get isTransient => true;
}

/// KDF could not reach the provider.
final class RoutedSwapTransportException extends RoutedSwapRpcException {
  const RoutedSwapTransportException({
    required this.detail,
    required super.message,
    super.errorData,
  }) : super(errorType: 'TransportError');

  /// Diagnostic text.
  final String detail;

  @override
  bool get isTransient => true;
}

/// An internal KDF failure.
final class RoutedSwapInternalException extends RoutedSwapRpcException {
  const RoutedSwapInternalException({
    required this.detail,
    required super.message,
    super.errorData,
  }) : super(errorType: 'InternalError');

  /// Diagnostic text.
  final String detail;

  @override
  bool get isTransient => true;
}

/// No task has that id: it was forgotten, cancelled, or lost to a restart.
///
/// Not an error state for the swap itself — resolve it through
/// `routed_swap::history` by uuid.
final class RoutedSwapNoSuchTaskException extends RoutedSwapRpcException {
  const RoutedSwapNoSuchTaskException({
    required super.message,
    this.taskId,
    super.errorData,
  }) : super(errorType: 'NoSuchTask');

  /// The task id, when reported.
  final int? taskId;
}

/// Cancel refused: the task has ended and its result is waiting to be read.
final class RoutedSwapTaskFinishedException extends RoutedSwapRpcException {
  const RoutedSwapTaskFinishedException({
    required super.message,
    this.taskId,
    super.errorData,
  }) : super(errorType: 'TaskFinished');

  /// The task id, when reported.
  final int? taskId;
}

/// Cancel refused: the irreversible broadcast handoff has begun, and tracking
/// continues.
final class RoutedSwapTaskAlreadyBroadcastException
    extends RoutedSwapRpcException {
  const RoutedSwapTaskAlreadyBroadcastException({
    required super.message,
    this.taskId,
    super.errorData,
  }) : super(errorType: 'TaskAlreadyBroadcast');

  /// The task id, when reported.
  final int? taskId;
}

/// An `error_type` this build does not know.
final class RoutedSwapUnknownRpcException extends RoutedSwapRpcException {
  const RoutedSwapUnknownRpcException({
    required super.errorType,
    required super.message,
    super.errorData,
  });

  @override
  String? get providerRequestId {
    final data = errorData;
    return data is Map ? data['provider_request_id'] as String? : null;
  }
}
