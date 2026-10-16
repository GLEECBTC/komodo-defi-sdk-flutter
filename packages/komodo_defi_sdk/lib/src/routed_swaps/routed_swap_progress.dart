part of 'routed_swap_types.dart';

/// A snapshot of a routed swap.
///
/// The same type describes a live swap and one recovered from history, so
/// nothing downstream has to branch on where the data came from. Fields only
/// the durable record carries ([createdAt], [requested], [gasSpent], …) are
/// filled whenever a history read has been made for the swap.
class RoutedSwapProgress with RoutedSwapValue {
  /// Creates a swap snapshot.
  const RoutedSwapProgress({
    required this.uuid,
    required this.phase,
    required this.canCancel,
    this.provider,
    this.rawState,
    this.bridgeStage,
    this.acceptedOffer,
    this.executedOffer,
    this.receipt,
    this.failure,
    this.approvalTxHashes = const [],
    this.sourceTxHash,
    this.destinationTxHash,
    this.explorerUrl,
    this.providerStatusDetail,
    this.estimatedDuration,
    this.actionUrl,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
    this.requested,
    this.minToAmountAccepted,
    this.gasSpent = const [],
    this.totalGasSpent = const [],
    this.delayedSince,
  });

  /// The durable swap id. Valid across restarts.
  final String uuid;

  /// Where the swap has got to.
  final RoutedSwapPhase phase;

  /// Whether cancelling would currently be accepted.
  final bool canCancel;

  /// Echoed provider. Diagnostic.
  final String? provider;

  /// The wire state string, for logs and support escalation.
  final String? rawState;

  /// While bridging: the KDF-owned stage that drives display.
  final rpc.RoutedSwapBridgeStage? bridgeStage;

  /// The offer the user accepted, for a swap started in this session.
  final RoutedSwapOffer? acceptedOffer;

  /// The route actually being executed, once the engine has priced it. May
  /// differ from [acceptedOffer].
  final RoutedSwapOffer? executedOffer;

  /// Set once the swap finishes with a terminal `Ok`.
  final RoutedSwapReceipt? receipt;

  /// Set once the swap fails.
  final RoutedSwapFailure? failure;

  /// Every approval transaction observed, in order. A zero-reset produces two.
  final List<String> approvalTxHashes;

  /// The source-chain transaction.
  final String? sourceTxHash;

  /// The destination-chain transaction.
  final String? destinationTxHash;

  /// A provider explorer link for the route.
  final String? explorerUrl;

  /// Opaque provider progress text.
  ///
  /// In the provider's own language and subject to change without notice.
  /// Suitable for a details disclosure, not for primary copy.
  final String? providerStatusDetail;

  /// Provider estimate for the route.
  final Duration? estimatedDuration;

  /// Where the user must act, when the bridge stage requires it.
  final String? actionUrl;

  /// When the swap was started. Immutable.
  final DateTime? createdAt;

  /// When the durable record last changed.
  final DateTime? updatedAt;

  /// When the swap reached a terminal state.
  final DateTime? finishedAt;

  /// The request side accepted at `init`.
  final RoutedSwapRequest? requested;

  /// The guaranteed minimum accepted at `init`.
  final Decimal? minToAmountAccepted;

  /// Actual gas paid per transaction.
  final List<RoutedSwapGasPaid> gasSpent;

  /// Actual gas paid per native coin.
  final List<RoutedSwapGasPaid> totalGasSpent;

  /// Set while status reads are failing: the last good snapshot is being
  /// shown and may be out of date. A delay is not a failure.
  final DateTime? delayedSince;

  /// Whether the swap has stopped, either way.
  bool get isTerminal =>
      phase == RoutedSwapPhase.finished || phase == RoutedSwapPhase.failed;

  /// Whether the swap finished and delivered what was asked for.
  ///
  /// A partial fill and a refund are both terminal and neither is a success.
  bool get isSuccess => receipt?.isSuccess ?? false;

  /// The most recent approval transaction, when there is one.
  String? get approvalTxHash =>
      approvalTxHashes.isEmpty ? null : approvalTxHashes.last;

  /// The offer that best describes the swap: the executed route once known,
  /// otherwise the accepted one.
  RoutedSwapOffer? get offer => executedOffer ?? acceptedOffer;

  /// A copy with the given fields replaced.
  RoutedSwapProgress copyWith({
    RoutedSwapOffer? acceptedOffer,
    List<String>? approvalTxHashes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? finishedAt,
    RoutedSwapRequest? requested,
    Decimal? minToAmountAccepted,
    List<RoutedSwapGasPaid>? gasSpent,
    List<RoutedSwapGasPaid>? totalGasSpent,
    DateTime? delayedSince,
    bool clearDelayedSince = false,
  }) => RoutedSwapProgress(
    uuid: uuid,
    phase: phase,
    canCancel: canCancel,
    provider: provider,
    rawState: rawState,
    bridgeStage: bridgeStage,
    acceptedOffer: acceptedOffer ?? this.acceptedOffer,
    executedOffer: executedOffer,
    receipt: receipt,
    failure: failure,
    approvalTxHashes: approvalTxHashes ?? this.approvalTxHashes,
    sourceTxHash: sourceTxHash,
    destinationTxHash: destinationTxHash,
    explorerUrl: explorerUrl,
    providerStatusDetail: providerStatusDetail,
    estimatedDuration: estimatedDuration,
    actionUrl: actionUrl,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    requested: requested ?? this.requested,
    minToAmountAccepted: minToAmountAccepted ?? this.minToAmountAccepted,
    gasSpent: gasSpent ?? this.gasSpent,
    totalGasSpent: totalGasSpent ?? this.totalGasSpent,
    delayedSince: clearDelayedSince
        ? null
        : (delayedSince ?? this.delayedSince),
  );

  @override
  List<Object?> get props => [
    uuid,
    phase,
    canCancel,
    provider,
    rawState,
    bridgeStage,
    acceptedOffer,
    executedOffer,
    receipt,
    failure,
    approvalTxHashes,
    sourceTxHash,
    destinationTxHash,
    explorerUrl,
    providerStatusDetail,
    estimatedDuration,
    actionUrl,
    createdAt,
    updatedAt,
    finishedAt,
    requested,
    minToAmountAccepted,
    gasSpent,
    totalGasSpent,
    delayedSince,
  ];
}

/// A page of routed swaps from the durable record.
class RoutedSwapHistoryPage with RoutedSwapValue {
  /// Creates a page.
  const RoutedSwapHistoryPage({
    required this.entries,
    required this.total,
    required this.pageNumber,
    required this.totalPages,
  });

  /// The swaps on this page, newest first.
  final List<RoutedSwapProgress> entries;

  /// Matching swaps across all pages.
  final int total;

  /// This page's 1-based number.
  final int pageNumber;

  /// How many pages match.
  final int totalPages;

  /// Whether a later page exists.
  bool get hasMore => pageNumber < totalPages;

  @override
  List<Object?> get props => [entries, total, pageNumber, totalPages];
}

/// Why a cancel was refused.
enum RoutedSwapCancelRefusal {
  /// The transaction has already been handed to the network. Tracking
  /// continues.
  alreadyBroadcast,

  /// The swap has already ended.
  alreadyFinished,

  /// The swap is only known from the durable record — its task is gone, so
  /// there is nothing addressable to cancel.
  notAddressable,
}

/// Thrown when a swap can no longer be cancelled.
///
/// Cancellation stops being possible the moment KDF hands the transaction to
/// the network, which is a race the caller cannot win by checking first.
class RoutedSwapNotCancellableException implements Exception {
  /// Creates the exception for the swap identified by [uuid].
  const RoutedSwapNotCancellableException(
    this.uuid,
    this.phase, {
    this.refusal = RoutedSwapCancelRefusal.alreadyBroadcast,
  });

  /// The swap that could not be cancelled.
  final String uuid;

  /// The phase it had reached.
  final RoutedSwapPhase phase;

  /// Why.
  final RoutedSwapCancelRefusal refusal;

  @override
  String toString() =>
      'Routed swap $uuid cannot be cancelled (${refusal.name}, '
      'phase ${phase.name}).';
}

/// Thrown when a cancel request's outcome could not be confirmed.
///
/// The swap may or may not have been cancelled; its progress stream keeps
/// reporting the truth.
class RoutedSwapCancelUnconfirmedException implements Exception {
  /// Creates the exception for [uuid].
  const RoutedSwapCancelUnconfirmedException(this.uuid, this.cause);

  /// The swap.
  final String uuid;

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Could not confirm cancelling routed swap $uuid.';
}

/// Thrown when `start` could not confirm whether the swap began.
///
/// The engine may already be running it. Re-arming a start button on this is
/// how one tap becomes two real swaps — check history instead.
class RoutedSwapStartUnconfirmedException implements Exception {
  /// Creates the exception.
  const RoutedSwapStartUnconfirmedException(this.cause, {this.taskId});

  /// What went wrong.
  final Object cause;

  /// The task id, when `init` answered before the failure.
  final int? taskId;

  @override
  String toString() => 'Could not confirm whether the routed swap started.';
}

/// Thrown when a swap cannot be found, live or in history.
class RoutedSwapNotFoundException implements Exception {
  /// Creates the exception for [uuid].
  const RoutedSwapNotFoundException(this.uuid);

  /// The swap that could not be resolved.
  final String uuid;

  @override
  String toString() => 'No routed swap found for $uuid.';
}
