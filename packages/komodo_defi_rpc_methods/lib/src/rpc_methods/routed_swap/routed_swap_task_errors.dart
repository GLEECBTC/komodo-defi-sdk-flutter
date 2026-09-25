part of 'routed_swap_models.dart';

/// The typed `error_data` of a terminal routed-swap `Error`.
///
/// One variant per row of the contract's terminal-error table, plus the two
/// outcomes reachable only through history (`TaskCancelled`,
/// `AbortedOnRestart`) and an [RoutedSwapUnknownTaskError] fallback that keeps
/// the raw payload so a newer engine never crashes an older app.
sealed class RoutedSwapTaskError extends Equatable {
  const RoutedSwapTaskError();

  /// Parses [data] for [errorType].
  factory RoutedSwapTaskError.parse(String errorType, JsonMap data) {
    String? str(String key) => data.valueOrNull<String>(key);
    String req(String key) => data.valueOrNull<String>(key) ?? '';
    return switch (errorType) {
      'QuoteWorsened' => RoutedSwapQuoteWorsenedError(
        freshRoute: data.valueOrNull<JsonMap>('fresh_route') == null
            ? null
            : RoutedSwapRoute.fromJson(data.value<JsonMap>('fresh_route')),
      ),
      'InsufficientBalance' => RoutedSwapInsufficientBalanceError(
        coin: req('coin'),
        available: req('available'),
        required: req('required'),
      ),
      'ApprovalFailed' => RoutedSwapApprovalFailedError(
        reason: RoutedSwapApprovalFailureReason.parse(str('reason')),
      ),
      'SwapTxFailed' => RoutedSwapTxFailedError(
        sourceTxHash: str('source_tx_hash') ?? str('tx_hash'),
        reason: RoutedSwapTxFailureReason.parse(str('reason')),
      ),
      'SigningRejected' => RoutedSwapSigningRejectedError(
        reason: RoutedSwapSigningRejectionReason.parse(str('reason')),
      ),
      'BridgeFailed' => RoutedSwapBridgeFailedError(
        sourceTxHash: str('source_tx_hash') ?? str('tx_hash'),
        substatus: str('substatus'),
        substatusMessage: str('substatus_message'),
        providerExplorerUrl: str('provider_explorer_url'),
        providerRequestId: str('provider_request_id'),
      ),
      'PreflightRejected' => RoutedSwapPreflightRejectedError(
        check: RoutedSwapPreflightCheck.parse(str('check')),
      ),
      'NoRouteFound' => RoutedSwapNoRouteTaskError(
        reasons: _strings(data, 'reasons'),
        providerRequestId: str('provider_request_id'),
      ),
      'RateLimited' => RoutedSwapRateLimitedTaskError(
        providerRequestId: str('provider_request_id'),
      ),
      'ProviderApiError' => RoutedSwapProviderTaskError(
        message: req('message'),
        providerRequestId: str('provider_request_id'),
      ),
      'AmountOutOfBounds' => RoutedSwapAmountOutOfBoundsTaskError(
        param: req('param'),
        value: req('value'),
        min: req('min'),
        max: req('max'),
      ),
      'AbortedOnRestart' => const RoutedSwapAbortedOnRestartError(),
      'TaskCancelled' => const RoutedSwapTaskCancelledError(),
      'InternalError' => RoutedSwapInternalTaskError(message: req('message')),
      'TransportError' => RoutedSwapTransportTaskError(message: req('message')),
      _ => RoutedSwapUnknownTaskError(errorType: errorType, data: data),
    };
  }

  /// The wire `error_type`.
  String get errorType;

  /// The provider's support-correlation id, on provider-originated errors.
  String? get providerRequestId => null;

  /// Whether the contract says this error happened before anything could be
  /// broadcast — for the swap itself. An approval may still have confirmed
  /// earlier; check the approval evidence separately.
  ///
  /// Conservative: an error the contract does not pin as pre-broadcast
  /// answers false.
  bool get isPreBroadcast => false;
}

/// The fresh route came in below the accepted minimum. Nothing was sent.
final class RoutedSwapQuoteWorsenedError extends RoutedSwapTaskError {
  const RoutedSwapQuoteWorsenedError({this.freshRoute});

  /// The re-priced route, to show old versus new and retry `init` with its
  /// minimum.
  final RoutedSwapRoute? freshRoute;

  @override
  String get errorType => 'QuoteWorsened';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [freshRoute];
}

/// Not enough balance on the source chain, including routed execution gas and
/// any required approval gas.
final class RoutedSwapInsufficientBalanceError extends RoutedSwapTaskError {
  const RoutedSwapInsufficientBalanceError({
    required this.coin,
    required this.available,
    required this.required,
  });

  /// The coin that ran short.
  final String coin;

  /// What was available, in coin units.
  final String available;

  /// What was required, in coin units.
  final String required;

  @override
  String get errorType => 'InsufficientBalance';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [coin, available, required];
}

/// The approval failed. Nothing was swapped, but approval gas may be spent.
final class RoutedSwapApprovalFailedError extends RoutedSwapTaskError {
  const RoutedSwapApprovalFailedError({required this.reason});

  /// Why.
  final RoutedSwapApprovalFailureReason reason;

  @override
  String get errorType => 'ApprovalFailed';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [reason];
}

/// The source transaction failed.
final class RoutedSwapTxFailedError extends RoutedSwapTaskError {
  const RoutedSwapTxFailedError({required this.reason, this.sourceTxHash});

  /// The source transaction.
  final String? sourceTxHash;

  /// Reverted, or not confirmed in time.
  final RoutedSwapTxFailureReason reason;

  /// Whether the transaction may still confirm, so the funds may yet move.
  bool get mayStillConfirm =>
      reason != RoutedSwapTxFailureReason.sourceTransactionReverted;

  @override
  String get errorType => 'SwapTxFailed';

  @override
  List<Object?> get props => [sourceTxHash, reason];
}

/// An external wallet did not sign. Unreachable for local-key coins.
final class RoutedSwapSigningRejectedError extends RoutedSwapTaskError {
  const RoutedSwapSigningRejectedError({required this.reason});

  /// Why.
  final RoutedSwapSigningRejectionReason reason;

  @override
  String get errorType => 'SigningRejected';

  // A timeout after Broadcasting began may have broadcast without KDF
  // receiving a hash, and a reason this build does not know proves nothing,
  // so only a decline or a wallet that cannot sign at all is pre-broadcast.
  @override
  bool get isPreBroadcast => switch (reason) {
    RoutedSwapSigningRejectionReason.userRejected ||
    RoutedSwapSigningRejectionReason.unsupportedMethod => true,
    RoutedSwapSigningRejectionReason.timeout ||
    RoutedSwapSigningRejectionReason.unknown => false,
  };

  @override
  List<Object?> get props => [reason];
}

/// The provider reported FAILED without refund resolution. Funds left the
/// source chain; direct the user to the explorer link and support.
final class RoutedSwapBridgeFailedError extends RoutedSwapTaskError {
  const RoutedSwapBridgeFailedError({
    this.sourceTxHash,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
    this.providerRequestId,
  });

  /// The source transaction.
  final String? sourceTxHash;

  /// Opaque provider passthrough.
  final String? substatus;

  /// Opaque provider passthrough.
  final String? substatusMessage;

  /// Provider explorer link.
  final String? providerExplorerUrl;

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'BridgeFailed';

  @override
  List<Object?> get props => [
    sourceTxHash,
    substatus,
    substatusMessage,
    providerExplorerUrl,
    providerRequestId,
  ];
}

/// A pre-sign safety check failed. Nothing was sent.
final class RoutedSwapPreflightRejectedError extends RoutedSwapTaskError {
  const RoutedSwapPreflightRejectedError({required this.check});

  /// Which check.
  final RoutedSwapPreflightCheck check;

  @override
  String get errorType => 'PreflightRejected';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [check];
}

/// The internal fresh quote found no route. Nothing was sent.
final class RoutedSwapNoRouteTaskError extends RoutedSwapTaskError {
  const RoutedSwapNoRouteTaskError({
    this.reasons = const [],
    this.providerRequestId,
  });

  /// Display strings with no stable format. Never parse them.
  final List<String> reasons;

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'NoRouteFound';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [reasons, providerRequestId];
}

/// The provider's quota was exhausted during the internal re-quote. Nothing
/// was sent.
final class RoutedSwapRateLimitedTaskError extends RoutedSwapTaskError {
  const RoutedSwapRateLimitedTaskError({this.providerRequestId});

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'RateLimited';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [providerRequestId];
}

/// The provider errored during the internal re-quote. Nothing was sent.
final class RoutedSwapProviderTaskError extends RoutedSwapTaskError {
  const RoutedSwapProviderTaskError({
    required this.message,
    this.providerRequestId,
  });

  /// Sanitized provider failure. Diagnostic.
  final String message;

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'ProviderApiError';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [message, providerRequestId];
}

/// The amount fell outside the fresh route's bounds. Nothing was sent.
final class RoutedSwapAmountOutOfBoundsTaskError extends RoutedSwapTaskError {
  const RoutedSwapAmountOutOfBoundsTaskError({
    required this.param,
    required this.value,
    required this.min,
    required this.max,
  });

  /// The offending parameter.
  final String param;

  /// Its value.
  final String value;

  /// The lower bound.
  final String min;

  /// The upper bound.
  final String max;

  @override
  String get errorType => 'AmountOutOfBounds';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [param, value, min, max];
}

/// KDF restarted before `Broadcasting`. Nothing executed, though an already
/// confirmed exact approval may remain. History only.
final class RoutedSwapAbortedOnRestartError extends RoutedSwapTaskError {
  const RoutedSwapAbortedOnRestartError();

  @override
  String get errorType => 'AbortedOnRestart';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => const [];
}

/// The user cancelled before `Broadcasting`. An approval already confirmed
/// cannot be undone. History only.
final class RoutedSwapTaskCancelledError extends RoutedSwapTaskError {
  const RoutedSwapTaskCancelledError();

  @override
  String get errorType => 'TaskCancelled';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => const [];
}

/// An internal failure. Terminal before `Broadcasting`, except the rare
/// external-wallet handoff failure — so not provably pre-broadcast from the
/// payload alone.
final class RoutedSwapInternalTaskError extends RoutedSwapTaskError {
  const RoutedSwapInternalTaskError({required this.message});

  /// Diagnostic text.
  final String message;

  @override
  String get errorType => 'InternalError';

  @override
  List<Object?> get props => [message];
}

/// A transport failure before `Broadcasting`. After broadcast, transport
/// problems keep the task tracking instead of failing.
final class RoutedSwapTransportTaskError extends RoutedSwapTaskError {
  const RoutedSwapTransportTaskError({required this.message});

  /// Diagnostic text.
  final String message;

  @override
  String get errorType => 'TransportError';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [message];
}

/// An `error_type` this build does not know. Never assumed pre-broadcast.
final class RoutedSwapUnknownTaskError extends RoutedSwapTaskError {
  const RoutedSwapUnknownTaskError({
    required this.errorType,
    this.data = const {},
  });

  @override
  final String errorType;

  /// The raw payload, for logs and support.
  final JsonMap data;

  @override
  String? get providerRequestId =>
      data.valueOrNull<String>('provider_request_id');

  @override
  List<Object?> get props => [errorType, data];
}
