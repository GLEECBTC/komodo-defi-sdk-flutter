import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Runtime readiness of the GasFree rail for a specific asset.
enum GaslessCapabilityState {
  initial,
  checking,
  ready,
  temporarilyUnavailable,
  disabled,
  unsupported,
  securityMismatch,
}

/// Authoritative SDK view of whether an asset may use the GasFree rail.
class GaslessCapability extends Equatable {
  const GaslessCapability({required this.assetId, required this.state});

  final AssetId assetId;
  final GaslessCapabilityState state;

  bool get isReady => state == GaslessCapabilityState.ready;

  @override
  List<Object?> get props => [assetId, state];
}

/// Durable lifecycle of a GasFree transfer from signing through settlement.
enum GaslessTransferState {
  preparing,
  rejectedBeforeRelay,
  submittedPending,
  submittedUnknown,
  confirming,
  confirmed,
  failedFinal;

  bool get isTerminal =>
      this == GaslessTransferState.confirmed ||
      this == GaslessTransferState.failedFinal;
}

/// Stable categories for GasFree-specific failures.
enum GaslessTransferErrorKind {
  capabilityNotReady,
  persistenceUnavailable,
  invalidTrace,
  traceUnavailable,
  configuration,
  providerResponse,
  finalFailure,
}

enum GaslessTransferStage {
  capability,
  preview,
  persistence,
  submission,
  status,
  finality,
  recovery,
}

enum GaslessTransferErrorCode {
  capabilityNotReady,
  securePersistenceUnavailable,
  invalidSignedPreview,
  configurationInvalid,
  invalidPayload,
  wrongCoinType,
  runtimeMissing,
  chainIdMismatch,
  verifyingContractMismatch,
  serviceProviderMismatch,
  tokenMismatch,
  invalidAddress,
  custodyAddressMismatch,
  signatureMismatch,
  walletOwnershipMismatch,
  authenticationRejected,
  unsupportedToken,
  authorizationExpired,
  pendingTransfer,
  maxFeeExceeded,
  relayRejected,
  rateLimited,
  providerUnavailable,
  providerTimeout,
  submissionOutcomeUnknown,
  traceInvalid,
  traceUnavailable,
  responseMismatch,
  finalFeeExceeded,
  relayFailedFinal,
  storageMigrationRequired,
}

/// Typed GasFree error that preserves retry and terminal semantics.
class GaslessTransferException extends Equatable implements Exception {
  GaslessTransferException({
    required this.kind,
    required this.message,
    required this.retryable,
    required this.terminal,
    GaslessTransferErrorCode? code,
    GaslessTransferStage? stage,
    String? localizationKey,
    this.traceId,
  }) : code =
           code ??
           switch (kind) {
             GaslessTransferErrorKind.capabilityNotReady =>
               GaslessTransferErrorCode.capabilityNotReady,
             GaslessTransferErrorKind.persistenceUnavailable =>
               GaslessTransferErrorCode.securePersistenceUnavailable,
             GaslessTransferErrorKind.invalidTrace =>
               GaslessTransferErrorCode.traceInvalid,
             GaslessTransferErrorKind.traceUnavailable =>
               GaslessTransferErrorCode.traceUnavailable,
             GaslessTransferErrorKind.configuration =>
               GaslessTransferErrorCode.configurationInvalid,
             GaslessTransferErrorKind.providerResponse =>
               GaslessTransferErrorCode.responseMismatch,
             GaslessTransferErrorKind.finalFailure =>
               GaslessTransferErrorCode.relayFailedFinal,
           },
       stage =
           stage ??
           switch (kind) {
             GaslessTransferErrorKind.capabilityNotReady ||
             GaslessTransferErrorKind.configuration =>
               GaslessTransferStage.capability,
             GaslessTransferErrorKind.persistenceUnavailable =>
               GaslessTransferStage.persistence,
             GaslessTransferErrorKind.invalidTrace ||
             GaslessTransferErrorKind.traceUnavailable =>
               GaslessTransferStage.status,
             GaslessTransferErrorKind.providerResponse =>
               GaslessTransferStage.submission,
             GaslessTransferErrorKind.finalFailure =>
               GaslessTransferStage.finality,
           },
       localizationKey =
           localizationKey ??
           switch (kind) {
             GaslessTransferErrorKind.capabilityNotReady ||
             GaslessTransferErrorKind.configuration =>
               'sdk_errors.gasless_capability_not_ready',
             GaslessTransferErrorKind.persistenceUnavailable ||
             GaslessTransferErrorKind.traceUnavailable =>
               'sdk_errors.gasless_status_unavailable',
             GaslessTransferErrorKind.invalidTrace ||
             GaslessTransferErrorKind.providerResponse =>
               'sdk_errors.gasless_response_invalid',
             GaslessTransferErrorKind.finalFailure =>
               'sdk_errors.gasless_final_failure',
           };

  final GaslessTransferErrorKind kind;
  final String message;
  final bool retryable;
  final bool terminal;
  final GaslessTransferErrorCode code;
  final GaslessTransferStage stage;
  final String localizationKey;
  final String? traceId;

  @override
  String toString() => message;

  @override
  List<Object?> get props => [
    kind,
    code,
    stage,
    localizationKey,
    message,
    retryable,
    terminal,
    traceId,
  ];
}

enum WithdrawalSubmissionType { onChain, gaslessRelay }

/// Identity returned when a withdrawal has been accepted for broadcast.
class WithdrawalSubmission extends Equatable {
  const WithdrawalSubmission.onChain({required this.txHash})
    : type = WithdrawalSubmissionType.onChain,
      traceId = null,
      journalId = null;

  const WithdrawalSubmission.gaslessRelay({
    required this.traceId,
    required this.journalId,
  }) : type = WithdrawalSubmissionType.gaslessRelay,
       txHash = null;

  const WithdrawalSubmission.gaslessUnknown({required this.journalId})
    : type = WithdrawalSubmissionType.gaslessRelay,
      txHash = null,
      traceId = null;

  final WithdrawalSubmissionType type;
  final String? txHash;
  final String? traceId;
  final String? journalId;

  @override
  List<Object?> get props => [type, txHash, traceId, journalId];
}

FeeInfo _parsePersistedFee(JsonMap json) {
  if (json['type'] != 'TronGasless') return FeeInfo.fromJson(json);

  // Older encrypted journal entries copied submission-local echoes into the
  // preview fee. Migrate only the documented preview subset and deliberately
  // discard request ids, fingerprints, provider echoes, and accepted traces.
  return FeeInfo.fromJson({
    'type': 'TronGasless',
    'coin': json['coin'],
    'fee_method': json['fee_method'],
    'provider_name': json['provider_name'],
    'gasfree_address': json['gasfree_address'],
    'transfer_fee': json['transfer_fee'],
    'total_token_fee': json['total_token_fee'],
    if (json['activation_fee'] != null)
      'activation_fee': json['activation_fee'],
    if (json['signed_max_fee'] != null)
      'signed_max_fee': json['signed_max_fee'],
    'trace_id': null,
  });
}

/// Encrypted, wallet-scoped record of a GasFree relay awaiting settlement.
///
/// [journalId] is a local reservation identity and is never sent to KDF. The
/// signed authorization and signature are deliberately not persisted.
class PendingGaslessTransfer extends Equatable {
  const PendingGaslessTransfer({
    required this.journalId,
    required this.assetId,
    required this.network,
    required this.sourceAddress,
    required this.custodyAddress,
    required this.destinationAddress,
    required this.requestedAmount,
    required this.signedMaxFee,
    required this.authorizationDeadline,
    required this.balanceChanges,
    required this.fee,
    required this.acceptedAt,
    required this.updatedAt,
    required this.state,
    this.traceId,
  });

  factory PendingGaslessTransfer.fromJson(JsonMap json) {
    final traceId = json.valueOrNull<String>('trace_id');
    final journalId =
        json.valueOrNull<String>('journal_id') ??
        // One-way migration from the pre-contract local persistence name.
        json.valueOrNull<String>('request_id') ??
        (traceId == null ? null : 'legacy:$traceId');
    if (journalId == null || journalId.trim().isEmpty) {
      throw const FormatException(
        'Pending GasFree transfer is missing its local journal id',
      );
    }
    final persistedState = GaslessTransferState.values.byName(
      json.value<String>('state'),
    );

    return PendingGaslessTransfer(
      traceId: traceId,
      journalId: journalId,
      assetId: json.value<String>('asset_id'),
      network: json.value<String>('network'),
      sourceAddress: json.value<String>('source_address'),
      custodyAddress: json.value<String>('custody_address'),
      destinationAddress: json.value<String>('destination_address'),
      requestedAmount: Decimal.parse(json.value<String>('requested_amount')),
      signedMaxFee: Decimal.parse(json.value<String>('signed_max_fee')),
      authorizationDeadline: json.value<int>('authorization_deadline'),
      balanceChanges: BalanceChanges.fromJson(
        json.value<JsonMap>('balance_changes'),
      ),
      fee: _parsePersistedFee(json.value<JsonMap>('fee')),
      acceptedAt: DateTime.parse(json.value<String>('accepted_at')).toUtc(),
      updatedAt: DateTime.parse(json.value<String>('updated_at')).toUtc(),
      // A reservation without a KDF trace cannot be proven unsent after a
      // restart. Preserve the no-blind-resubmit invariant.
      state: traceId == null
          ? GaslessTransferState.submittedUnknown
          : persistedState,
    );
  }

  final String? traceId;

  /// Local identity created before relay submission.
  final String journalId;

  final String assetId;
  final String network;
  final String sourceAddress;
  final String custodyAddress;
  final String destinationAddress;
  final Decimal requestedAmount;
  final Decimal signedMaxFee;

  /// Signed authorization expiry as seconds since Unix epoch.
  final int authorizationDeadline;

  final BalanceChanges balanceChanges;
  final FeeInfo fee;
  final DateTime acceptedAt;
  final DateTime updatedAt;
  final GaslessTransferState state;

  PendingGaslessTransfer copyWith({
    String? traceId,
    GaslessTransferState? state,
    FeeInfo? fee,
    DateTime? updatedAt,
  }) {
    return PendingGaslessTransfer(
      traceId: traceId ?? this.traceId,
      journalId: journalId,
      assetId: assetId,
      network: network,
      sourceAddress: sourceAddress,
      custodyAddress: custodyAddress,
      destinationAddress: destinationAddress,
      requestedAmount: requestedAmount,
      signedMaxFee: signedMaxFee,
      authorizationDeadline: authorizationDeadline,
      balanceChanges: balanceChanges,
      fee: fee ?? this.fee,
      acceptedAt: acceptedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      state: state ?? this.state,
    );
  }

  JsonMap toJson() => {
    if (traceId != null) 'trace_id': traceId,
    'journal_id': journalId,
    'asset_id': assetId,
    'network': network,
    'source_address': sourceAddress,
    'custody_address': custodyAddress,
    'destination_address': destinationAddress,
    'requested_amount': requestedAmount.toString(),
    'signed_max_fee': signedMaxFee.toString(),
    'authorization_deadline': authorizationDeadline,
    'balance_changes': balanceChanges.toJson(),
    'fee': fee.toJson(),
    'accepted_at': acceptedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'state': state.name,
  };

  @override
  List<Object?> get props => [
    traceId,
    journalId,
    assetId,
    network,
    sourceAddress,
    custodyAddress,
    destinationAddress,
    requestedAmount,
    signedMaxFee,
    authorizationDeadline,
    balanceChanges,
    fee,
    acceptedAt,
    updatedAt,
    state,
  ];
}
