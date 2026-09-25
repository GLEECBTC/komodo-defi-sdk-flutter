part of 'routed_swap_models.dart';

/// The `{status, details}` payload of `task::routed_swap::status`, and the
/// `swap` object of a `routed_swap::history` entry — one shape for a running
/// swap and a stored one.
///
/// Every variant carries [uuid] and [provider]: the uuid is the only durable
/// handle on a swap, since `task_id` is in-memory and dies on restart,
/// cancellation or a `forget_if_finished` read. [executedRoute] is present on
/// every payload after `FetchingQuote` completes: the fresh, internally
/// fetched route actually being executed, which may differ from the route
/// shown before `init`.
sealed class RoutedSwapStatus extends Equatable {
  const RoutedSwapStatus({
    required this.uuid,
    required this.provider,
    this.executedRoute,
  });

  /// Parses the `details` object for a given task [status].
  factory RoutedSwapStatus.parse(String status, JsonMap details) {
    final uuid = details.value<String>('uuid');
    final provider = details.valueOrNull<String>('provider') ?? 'lifi';
    final route = details.valueOrNull<JsonMap>('executed_route');
    final executedRoute = route == null
        ? null
        : RoutedSwapRoute.fromJson(route);

    switch (status) {
      case 'Ok':
        return RoutedSwapFinished(
          uuid: uuid,
          provider: provider,
          executedRoute: executedRoute,
          outcome: RoutedSwapOutcome.parse(details.value<String>('outcome')),
          partialReason: details.valueOrNull<String>('partial_reason') == null
              ? null
              : RoutedSwapPartialReason.parse(
                  details.valueOrNull<String>('partial_reason'),
                ),
          received: RoutedSwapAmount.fromJson(
            details.value<JsonMap>('received'),
          ),
          sourceTxHash: details.valueOrNull<String>('source_tx_hash'),
          destTxHash: details.valueOrNull<String>('dest_tx_hash'),
          providerExplorerUrl: details.valueOrNull<String>(
            'provider_explorer_url',
          ),
        );
      case 'Error':
        final errorType = details.valueOrNull<String>('error_type') ?? '';
        final data = details['error_data'];
        return RoutedSwapErrored(
          uuid: uuid,
          provider: provider,
          executedRoute: executedRoute,
          errorType: errorType,
          message: details.valueOrNull<String>('error') ?? errorType,
          error: RoutedSwapTaskError.parse(
            errorType,
            data is Map ? convertToJsonMap(data) : const {},
          ),
        );
      default:
        final rawStage = details.valueOrNull<String>('stage');
        return RoutedSwapInProgress(
          uuid: uuid,
          provider: provider,
          executedRoute: executedRoute,
          state: RoutedSwapState.parse(details.value<String>('state')),
          rawState: details.value<String>('state'),
          approveTxHash: details.valueOrNull<String>('approve_tx_hash'),
          // `tx_hash` was the pre-release name of this field; reading it as a
          // fallback keeps an older engine from losing the source hash.
          sourceTxHash:
              details.valueOrNull<String>('source_tx_hash') ??
              details.valueOrNull<String>('tx_hash'),
          stage: rawStage == null
              ? null
              : RoutedSwapBridgeStage.parse(rawStage),
          rawStage: rawStage,
          substatus: details.valueOrNull<String>('substatus'),
          substatusMessage: details.valueOrNull<String>('substatus_message'),
          providerExplorerUrl: details.valueOrNull<String>(
            'provider_explorer_url',
          ),
          executionDurationS: details.valueOrNull<int>('execution_duration_s'),
          actionUrl: details.valueOrNull<String>('action_url'),
        );
    }
  }

  /// The persistent swap id. Survives restart; recoverable via history.
  final String uuid;

  /// Echoed provider.
  final String provider;

  /// The route actually being executed, once `FetchingQuote` has completed.
  final RoutedSwapRoute? executedRoute;

  /// Whether the task has reached a terminal state.
  bool get isTerminal => this is! RoutedSwapInProgress;

  @override
  List<Object?> get props => [uuid, provider, executedRoute];
}

/// A swap still running.
final class RoutedSwapInProgress extends RoutedSwapStatus {
  const RoutedSwapInProgress({
    required super.uuid,
    required super.provider,
    required this.state,
    required this.rawState,
    super.executedRoute,
    this.approveTxHash,
    this.sourceTxHash,
    this.stage,
    this.rawStage,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
    this.executionDurationS,
    this.actionUrl,
  });

  /// The parsed state.
  final RoutedSwapState state;

  /// The raw `state` string, kept so an unknown value can still be logged and
  /// reported to support rather than silently flattened.
  final String rawState;

  /// On `Approving`, once the approval transaction has been broadcast.
  final String? approveTxHash;

  /// The source-chain transaction: optional on `Broadcasting` (its presence
  /// does not confirm network acceptance), present from
  /// `WaitingSourceConfirmation` on.
  final String? sourceTxHash;

  /// The bridge stage, on `TrackingBridge`.
  final RoutedSwapBridgeStage? stage;

  /// The raw `stage` string, for logs.
  final String? rawStage;

  /// Opaque provider passthrough. Not localizable — show it in a details
  /// disclosure, never as primary copy.
  final String? substatus;

  /// Opaque provider passthrough, in the provider's own language.
  final String? substatusMessage;

  /// Provider explorer link for the bridge.
  final String? providerExplorerUrl;

  /// Provider duration estimate, when supplied.
  final int? executionDurationS;

  /// Where the user must act, when [stage] is `action_required`.
  final String? actionUrl;

  @override
  List<Object?> get props => [
    ...super.props,
    state,
    rawState,
    approveTxHash,
    sourceTxHash,
    stage,
    rawStage,
    substatus,
    substatusMessage,
    providerExplorerUrl,
    executionDurationS,
    actionUrl,
  ];
}

/// A swap that reached a terminal `Ok`.
///
/// `Ok` is not the same as "succeeded" — check [RoutedSwapOutcome.isSuccess].
final class RoutedSwapFinished extends RoutedSwapStatus {
  const RoutedSwapFinished({
    required super.uuid,
    required super.provider,
    required this.outcome,
    required this.received,
    super.executedRoute,
    this.partialReason,
    this.sourceTxHash,
    this.destTxHash,
    this.providerExplorerUrl,
  });

  /// What actually happened.
  final RoutedSwapOutcome outcome;

  /// Why the outcome is partial. Set only for [RoutedSwapOutcome.partial].
  final RoutedSwapPartialReason? partialReason;

  /// The token and amount the user actually received. For a refund this is the
  /// returned source coin, not the requested destination coin. For a
  /// same-chain swap it is the executed route's quoted `to.amount`.
  final RoutedSwapAmount received;

  /// Source-chain transaction.
  final String? sourceTxHash;

  /// Destination-chain transaction. Absent for refunds and same-chain swaps.
  final String? destTxHash;

  /// Provider explorer link.
  final String? providerExplorerUrl;

  @override
  List<Object?> get props => [
    ...super.props,
    outcome,
    partialReason,
    received,
    sourceTxHash,
    destTxHash,
    providerExplorerUrl,
  ];
}

/// A swap that ended in a terminal `Error`.
final class RoutedSwapErrored extends RoutedSwapStatus {
  const RoutedSwapErrored({
    required super.uuid,
    required super.provider,
    required this.errorType,
    required this.message,
    required this.error,
    super.executedRoute,
  });

  /// The `error_type` discriminator, kept as a string so an unrecognised
  /// variant still renders instead of throwing.
  final String errorType;

  /// KDF's human-readable error text. Diagnostic; not localized.
  final String message;

  /// The typed payload.
  final RoutedSwapTaskError error;

  @override
  List<Object?> get props => [...super.props, errorType, message, error];
}

/// Why an approval failed.
enum RoutedSwapApprovalFailureReason {
  /// The approval could not be broadcast.
  approvalBroadcastFailed('approval_broadcast_failed'),

  /// The approval transaction failed or did not confirm in time.
  approvalTransactionFailed('approval_transaction_failed'),

  /// The zero-reset never confirmed.
  allowanceResetNotConfirmed('allowance_reset_not_confirmed'),

  /// The confirmed allowance remained insufficient after recheck.
  confirmedAllowanceInsufficient('confirmed_allowance_insufficient'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapApprovalFailureReason(this.wire);

  /// Parses leniently.
  static RoutedSwapApprovalFailureReason parse(String? value) =>
      values.firstWhere(
        (reason) => reason.wire == value,
        orElse: () => RoutedSwapApprovalFailureReason.unknown,
      );

  /// The wire value.
  final String wire;
}

/// Why the source transaction failed.
enum RoutedSwapTxFailureReason {
  /// The source transaction reverted; funds (minus gas) never left.
  sourceTransactionReverted('source_transaction_reverted'),

  /// Broadcast, but not confirmed within KDF's wait. It may still confirm —
  /// never state that funds did not move.
  sourceTransactionNotConfirmed('source_transaction_not_confirmed'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapTxFailureReason(this.wire);

  /// Parses leniently.
  static RoutedSwapTxFailureReason parse(String? value) => values.firstWhere(
    (reason) => reason.wire == value,
    orElse: () => RoutedSwapTxFailureReason.unknown,
  );

  /// The wire value.
  final String wire;
}

/// Why an external wallet did not sign. Unreachable for local-key coins.
enum RoutedSwapSigningRejectionReason {
  /// The wallet declined.
  userRejected('user_rejected'),

  /// The wallet did not answer before the request expired.
  timeout('timeout'),

  /// The wallet supports neither signing method.
  unsupportedMethod('unsupported_method'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapSigningRejectionReason(this.wire);

  /// Parses leniently.
  static RoutedSwapSigningRejectionReason parse(String? value) =>
      values.firstWhere(
        (reason) => reason.wire == value,
        orElse: () => RoutedSwapSigningRejectionReason.unknown,
      );

  /// The wire value.
  final String wire;
}

/// Which pre-sign safety check rejected a route.
enum RoutedSwapPreflightCheck {
  /// The call simulation failed. A retry is reasonable (often a stale route).
  simulation('simulation'),

  /// The execution target is not allowlisted. Do not retry; report.
  targetAllowlist('target_allowlist'),

  /// The approval spender is not allowlisted. Do not retry; report.
  spenderAllowlist('spender_allowlist'),

  /// The native value breached the exact-value cap. A re-quote may differ.
  valueCap('value_cap'),

  /// The amounts breached safety bounds. A re-quote may differ.
  amountBounds('amount_bounds'),

  /// The gas breached safety bounds. A re-quote may differ.
  gasBounds('gas_bounds'),

  /// A check this build does not know.
  unknown('');

  const RoutedSwapPreflightCheck(this.wire);

  /// Parses leniently.
  static RoutedSwapPreflightCheck parse(String? value) => values.firstWhere(
    (check) => check.wire == value,
    orElse: () => RoutedSwapPreflightCheck.unknown,
  );

  /// The wire value.
  final String wire;

  /// Whether retrying the same swap is a reasonable next step.
  bool get isRetryable => this == RoutedSwapPreflightCheck.simulation;

  /// Whether a fresh quote may produce a route that passes.
  bool get mayPassOnRequote => switch (this) {
    RoutedSwapPreflightCheck.simulation ||
    RoutedSwapPreflightCheck.valueCap ||
    RoutedSwapPreflightCheck.amountBounds ||
    RoutedSwapPreflightCheck.gasBounds => true,
    _ => false,
  };
}
