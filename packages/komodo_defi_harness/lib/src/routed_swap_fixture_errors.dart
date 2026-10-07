part of 'routed_swap_fixture.dart';

/// A top-level MMRPC error from `routed_swap::quote`, `task::routed_swap::init`
/// or `routed_swap::history` — `RoutedSwapRpcError`.
class RoutedSwapQuoteError {
  RoutedSwapQuoteError._(this.errorType, this.errorData, this.message);

  /// `CoinNotActive`.
  factory RoutedSwapQuoteError.coinNotActive(String coin) =>
      RoutedSwapQuoteError._('CoinNotActive', {
        'coin': coin,
      }, 'Coin $coin is not active');

  /// `PairNotSupported`.
  factory RoutedSwapQuoteError.pairNotSupported(
    String from,
    String to,
    String reason,
  ) => RoutedSwapQuoteError._('PairNotSupported', {
    'from': from,
    'to': to,
    'reason': reason,
  }, 'Pair $from/$to is not supported: $reason');

  /// `InvalidParam`.
  factory RoutedSwapQuoteError.invalidParam(String param, String reason) =>
      RoutedSwapQuoteError._('InvalidParam', {
        'param': param,
        'reason': reason,
      }, 'Invalid parameter $param: $reason');

  /// `AmountOutOfBounds`; the engine always reports both bounds.
  factory RoutedSwapQuoteError.amountOutOfBounds({
    required String param,
    required String value,
    required String min,
    required String max,
  }) => RoutedSwapQuoteError._(
    'AmountOutOfBounds',
    {'param': param, 'value': value, 'min': min, 'max': max},
    'Parameter $param out of bounds, value: $value, min: $min max: $max',
  );

  /// `MyAddressError`.
  factory RoutedSwapQuoteError.myAddressError(String coin, String message) =>
      RoutedSwapQuoteError._('MyAddressError', {
        'coin': coin,
        'message': message,
      }, 'Cannot use $coin source address: $message');

  /// `InvalidConfig`.
  factory RoutedSwapQuoteError.invalidConfig(String message) =>
      RoutedSwapQuoteError._('InvalidConfig', {'message': message}, message);

  /// `NoRouteFound`. The engine always sends at least one reason, falling
  /// back to "No route found".
  factory RoutedSwapQuoteError.noRouteFound({
    List<String> reasons = const ['No route found'],
    String? providerRequestId,
  }) {
    if (reasons.isEmpty) {
      throw ArgumentError('The engine never sends an empty reasons list.');
    }
    return RoutedSwapQuoteError._('NoRouteFound', {
      'reasons': reasons,
      'provider_request_id': ?providerRequestId,
    }, 'No route found');
  }

  /// `RateLimited`.
  factory RoutedSwapQuoteError.rateLimited({String? providerRequestId}) =>
      RoutedSwapQuoteError._('RateLimited', {
        'provider_request_id': ?providerRequestId,
      }, 'Routed swap provider rate limit exceeded');

  /// `ProviderApiError`.
  factory RoutedSwapQuoteError.providerApiError(
    String message, {
    String? providerRequestId,
  }) => RoutedSwapQuoteError._('ProviderApiError', {
    'message': message,
    'provider_request_id': ?providerRequestId,
  }, message);

  /// `TransportError`.
  factory RoutedSwapQuoteError.transportError(String message) =>
      RoutedSwapQuoteError._('TransportError', {'message': message}, message);

  /// `InternalError`.
  factory RoutedSwapQuoteError.internalError(String message) =>
      RoutedSwapQuoteError._('InternalError', {'message': message}, message);

  /// The `error_type`.
  final String errorType;

  /// The `error_data`.
  final Map<String, dynamic> errorData;

  /// The `error` display text.
  final String message;
}

/// A terminal task `Error` — `RoutedSwapTaskError`.
///
/// Where it can be raised is checked against the run's ladder: an error the
/// engine cannot produce at that point throws [ArgumentError].
class RoutedSwapRunError {
  RoutedSwapRunError._(
    this.errorType, {
    Map<String, dynamic> data = const {},
    String? message,
    this.freshRoute,
    this.reason,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
  }) : _data = data,
       _message = message;

  /// `QuoteWorsened`: the fresh route's minimum fell below the accepted one.
  /// Nothing was executed, so there is no `executed_route`.
  factory RoutedSwapRunError.quoteWorsened({
    required RoutedSwapQuote freshRoute,
  }) => RoutedSwapRunError._(
    'QuoteWorsened',
    message: 'Fresh route is below the accepted minimum',
    freshRoute: freshRoute,
  );

  /// `InsufficientBalance`.
  factory RoutedSwapRunError.insufficientBalance({
    required String coin,
    required String available,
    required String requiredAmount,
  }) => RoutedSwapRunError._(
    'InsufficientBalance',
    data: {'coin': coin, 'available': available, 'required': requiredAmount},
    message:
        'Insufficient $coin balance: available $available, required '
        '$requiredAmount',
  );

  /// `ApprovalFailed`: [reason] is `approval_broadcast_failed`,
  /// `approval_transaction_failed`, `allowance_reset_not_confirmed` or
  /// `confirmed_allowance_insufficient`.
  factory RoutedSwapRunError.approvalFailed(String reason) {
    _checkOneOf(reason, 'reason', _approvalFailures);
    return RoutedSwapRunError._(
      'ApprovalFailed',
      data: {'reason': reason},
      message: 'Token approval failed: $reason',
      reason: reason,
    );
  }

  /// `SwapTxFailed`: [reason] is `source_transaction_reverted` or
  /// `source_transaction_not_confirmed`. The source hash is the run's.
  factory RoutedSwapRunError.swapTxFailed(String reason) {
    _checkOneOf(reason, 'reason', _txFailures);
    return RoutedSwapRunError._('SwapTxFailed', reason: reason);
  }

  /// `SigningRejected`: [reason] is `user_rejected`, `timeout` or
  /// `unsupported_method`.
  factory RoutedSwapRunError.signingRejected(String reason) {
    _checkOneOf(reason, 'reason', _signingRejections);
    return RoutedSwapRunError._(
      'SigningRejected',
      data: {'reason': reason},
      message: 'Wallet rejected the routed swap transaction: $reason',
      reason: reason,
    );
  }

  /// `BridgeFailed`, from the provider's final `FAILED` status. The engine
  /// never sets `provider_request_id` on it (`bridge_failed()` passes
  /// `None`). A `REFUND_IN_PROGRESS` substatus keeps tracking instead.
  factory RoutedSwapRunError.bridgeFailed({
    String? substatus = 'UNKNOWN_ERROR',
    String? substatusMessage,
    String? providerExplorerUrl,
  }) {
    if (substatus == 'REFUND_IN_PROGRESS') {
      throw ArgumentError(
        'A FAILED status whose refund is in flight keeps tracking; the '
        'engine does not fail the task on it.',
      );
    }
    return RoutedSwapRunError._(
      'BridgeFailed',
      substatus: substatus,
      substatusMessage: substatusMessage,
      providerExplorerUrl: providerExplorerUrl,
    );
  }

  /// `PreflightRejected`: [check] is `simulation`, `target_allowlist`,
  /// `spender_allowlist`, `value_cap`, `amount_bounds` or `gas_bounds`.
  factory RoutedSwapRunError.preflightRejected(String check) {
    _checkOneOf(check, 'check', _preflightChecks);
    return RoutedSwapRunError._(
      'PreflightRejected',
      data: {'check': check},
      message: 'Routed swap preflight rejected by the $check check',
    );
  }

  /// `NoRouteFound` from the internal fresh quote.
  factory RoutedSwapRunError.noRouteFound({
    List<String> reasons = const ['No route found'],
    String? providerRequestId,
  }) {
    if (reasons.isEmpty) {
      throw ArgumentError('The engine never sends an empty reasons list.');
    }
    return RoutedSwapRunError._(
      'NoRouteFound',
      data: {'reasons': reasons, 'provider_request_id': ?providerRequestId},
      message: 'No route found',
    );
  }

  /// `RateLimited` from the internal fresh quote.
  factory RoutedSwapRunError.rateLimited({String? providerRequestId}) =>
      RoutedSwapRunError._(
        'RateLimited',
        data: {'provider_request_id': ?providerRequestId},
        message: 'Routed swap provider rate limit exceeded',
      );

  /// `ProviderApiError` from the internal fresh quote.
  factory RoutedSwapRunError.providerApiError(
    String message, {
    String? providerRequestId,
  }) => RoutedSwapRunError._(
    'ProviderApiError',
    data: {'message': message, 'provider_request_id': ?providerRequestId},
    message: message,
  );

  /// `AmountOutOfBounds` from the internal fresh quote.
  factory RoutedSwapRunError.amountOutOfBounds({
    required String param,
    required String value,
    required String min,
    required String max,
  }) => RoutedSwapRunError._(
    'AmountOutOfBounds',
    data: {'param': param, 'value': value, 'min': min, 'max': max},
    message:
        'Parameter $param out of bounds, value: $value, min: $min max: $max',
  );

  /// `InternalError`. Legal after `Broadcasting` too: an external wallet's
  /// handoff can fail without returning a hash.
  factory RoutedSwapRunError.internalError(String message) =>
      RoutedSwapRunError._(
        'InternalError',
        data: {'message': message},
        message: message,
      );

  /// `TransportError`; terminal only before `Broadcasting`.
  factory RoutedSwapRunError.transportError(String message) =>
      RoutedSwapRunError._(
        'TransportError',
        data: {'message': message},
        message: message,
      );

  /// The `error_type`.
  final String errorType;

  /// For `QuoteWorsened`.
  final RoutedSwapQuote? freshRoute;

  /// The typed reason, when the variant has one.
  final String? reason;

  /// For `BridgeFailed`.
  final String? substatus;

  /// For `BridgeFailed`.
  final String? substatusMessage;

  /// For `BridgeFailed`.
  final String? providerExplorerUrl;

  final Map<String, dynamic> _data;
  final String? _message;

  /// Whether the engine raises this while `FetchingQuote` in the default
  /// ladder: the internal fresh quote failed.
  bool get _raisedByFreshQuote => const {
    'QuoteWorsened',
    'NoRouteFound',
    'RateLimited',
    'ProviderApiError',
    'AmountOutOfBounds',
    'TransportError',
  }.contains(errorType);

  String _messageFor(String sourceTxHash) => switch (errorType) {
    'SwapTxFailed' => 'Routed swap transaction $sourceTxHash failed: $reason',
    'BridgeFailed' => 'Routed swap bridge failed for transaction $sourceTxHash',
    _ => _message!,
  };

  Map<String, dynamic> _dataFor(String sourceTxHash, String amount) =>
      switch (errorType) {
        'QuoteWorsened' => {'fresh_route': freshRoute!.toJson(amount: amount)},
        'SwapTxFailed' => {'source_tx_hash': sourceTxHash, 'reason': reason},
        'BridgeFailed' => {
          'source_tx_hash': sourceTxHash,
          'substatus': ?substatus,
          'substatus_message': ?substatusMessage,
          'provider_explorer_url': ?providerExplorerUrl,
        },
        _ => _data,
      };

  static void _checkOneOf(String value, String name, Set<String> allowed) {
    if (!allowed.contains(value)) {
      throw ArgumentError.value(value, name, 'must be one of $allowed');
    }
  }
}
