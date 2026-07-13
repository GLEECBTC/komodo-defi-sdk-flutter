import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Runtime readiness of the GasFree rail for a specific asset.
enum GaslessCapabilityState {
  initial,
  checking,
  ready,
  stale,
  temporarilyUnavailable,
  disabled,
  unsupported,
  securityMismatch,
}

/// Authoritative SDK view of whether an asset may use the GasFree rail.
class GaslessCapability extends Equatable {
  const GaslessCapability({
    required this.assetId,
    required this.state,
    this.reasonCode,
  });

  final AssetId assetId;
  final GaslessCapabilityState state;

  /// Stable, non-sensitive reason for a non-ready capability.
  final String? reasonCode;

  @Deprecated('Use reasonCode')
  String? get reason => reasonCode;

  bool get isReady => state == GaslessCapabilityState.ready;

  @override
  List<Object?> get props => [assetId, state, reasonCode];
}

enum GaslessBalanceProvenance {
  /// Custody limits and balances were confirmed by the provider-backed RPC.
  authoritativeProvider,

  /// Only the custody contract balance could be read; spend limits are stale.
  onChainOnly,

  /// A prior custody snapshot is being retained during a transient outage.
  cached,
}

class GaslessStandardBalance extends Equatable {
  const GaslessStandardBalance({
    required this.address,
    required this.balance,
    this.derivationPath,
  });

  final String address;
  final String? derivationPath;
  final BalanceInfo balance;

  @override
  List<Object?> get props => [address, derivationPath, balance];
}

/// One coherent view of custody and Standard-rail funds owned by a wallet.
class GaslessBalanceSnapshot extends Equatable {
  const GaslessBalanceSnapshot({
    required this.custodyAddress,
    required this.custodyTotal,
    required this.custodySpendable,
    required this.frozenAmount,
    required this.standardBalances,
    required this.totalWalletOwned,
    required this.capturedAt,
    required this.provenance,
    required this.isFresh,
  });

  final String custodyAddress;
  final Decimal custodyTotal;

  /// Null when only the on-chain custody total is available.
  final Decimal? custodySpendable;

  /// Null when the provider cannot authoritatively report pending locks.
  final Decimal? frozenAmount;
  final List<GaslessStandardBalance> standardBalances;
  final Decimal totalWalletOwned;
  final DateTime capturedAt;
  final GaslessBalanceProvenance provenance;
  final bool isFresh;

  BalanceInfo get walletBalance {
    final standard = standardBalances.fold(
      BalanceInfo.zero(),
      (total, item) => total + item.balance,
    );
    final spendable = standard.spendable + (custodySpendable ?? Decimal.zero);
    return BalanceInfo(
      total: totalWalletOwned,
      spendable: spendable,
      unspendable: totalWalletOwned - spendable,
    );
  }

  GaslessBalanceSnapshot asStale() => GaslessBalanceSnapshot(
    custodyAddress: custodyAddress,
    custodyTotal: custodyTotal,
    custodySpendable: custodySpendable,
    frozenAmount: frozenAmount,
    standardBalances: standardBalances,
    totalWalletOwned: totalWalletOwned,
    capturedAt: capturedAt,
    provenance: GaslessBalanceProvenance.cached,
    isFresh: false,
  );

  @override
  List<Object?> get props => [
    custodyAddress,
    custodyTotal,
    custodySpendable,
    frozenAmount,
    standardBalances,
    totalWalletOwned,
    capturedAt,
    provenance,
    isFresh,
  ];
}

/// Non-replayable metadata that identifies a signed GasFree authorization.
class GaslessAuthorization extends Equatable {
  const GaslessAuthorization({
    required this.signedMaxFee,
    required this.deadline,
    required this.fingerprint,
    this.provider,
    this.tokenContract,
    this.receiver,
    this.nonce,
    this.version,
  });

  final Decimal signedMaxFee;

  /// Signed deadline in seconds since Unix epoch.
  final int deadline;

  /// SHA-256 correlation fingerprint. The signature itself is never retained.
  final String fingerprint;
  final String? provider;
  final String? tokenContract;
  final String? receiver;
  final String? nonce;
  final String? version;

  DateTime get expiresAt =>
      DateTime.fromMillisecondsSinceEpoch(deadline * 1000, isUtc: true);

  bool isExpiredAt(DateTime instant) =>
      deadline <= instant.toUtc().millisecondsSinceEpoch ~/ 1000;

  @override
  List<Object?> get props => [
    signedMaxFee,
    deadline,
    fingerprint,
    provider,
    tokenContract,
    receiver,
    nonce,
    version,
  ];
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

/// Strength of the relay response verification available for a transfer.
enum GaslessVerificationMode {
  /// KDF PR #9 does not echo the signed request context. Finality therefore
  /// requires an independent, asset-scoped on-chain history match.
  legacyOnChain,

  /// KDF echoes and validates the request identity and signed authorization.
  boundRelay,
}

/// Evidence permitting a wallet UI to expose a new GasFree receive address.
///
/// This is intentionally independent from [GaslessVerificationMode], which
/// describes how an already-submitted transfer reaches finality.
enum GaslessReceiveEvidence {
  /// No authoritative evidence permits a new custody deposit.
  none,

  /// KDF attested the canonical custody address and exact pinned provider.
  statusAttestedV1,

  /// KDF supports request-bound relay verification in addition to status.
  boundRelayV2,
}

/// Result of independently reconciling a legacy relay with on-chain history.
enum GaslessOnChainVerification {
  /// The expected hash has not propagated to authoritative history yet.
  pending,

  /// Hash, token, custody source, recipient, and amount all match.
  verified,

  /// A transaction with the expected hash exists but its signed context differs.
  mismatch,
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
  const WithdrawalSubmission.onChain({required String txHash})
    : type = WithdrawalSubmissionType.onChain,
      txHash = txHash,
      traceId = null,
      requestId = null;

  const WithdrawalSubmission.gaslessRelay({
    required String traceId,
    required String requestId,
  }) : type = WithdrawalSubmissionType.gaslessRelay,
       txHash = null,
       traceId = traceId,
       requestId = requestId;

  const WithdrawalSubmission.gaslessUnknown({required String requestId})
    : type = WithdrawalSubmissionType.gaslessRelay,
      txHash = null,
      traceId = null,
      requestId = requestId;

  final WithdrawalSubmissionType type;
  final String? txHash;
  final String? traceId;
  final String? requestId;

  @override
  List<Object?> get props => [type, txHash, traceId, requestId];
}

/// Encrypted, wallet-scoped record of a GasFree relay awaiting settlement.
///
/// The signed authorization and its signature are deliberately not persisted.
/// [authorizationFingerprint] is sufficient to correlate diagnostics without
/// retaining replayable authorization material.
class PendingGaslessTransfer extends Equatable {
  const PendingGaslessTransfer({
    required this.traceId,
    required this.requestId,
    required this.assetId,
    required this.network,
    required this.sourceAddress,
    required this.custodyAddress,
    required this.destinationAddress,
    required this.requestedAmount,
    required this.signedMaxFee,
    required this.authorizationDeadline,
    required this.authorizationFingerprint,
    required this.balanceChanges,
    required this.fee,
    required this.acceptedAt,
    required this.updatedAt,
    required this.state,
    this.verificationMode = GaslessVerificationMode.boundRelay,
    this.provider,
    this.tokenContract,
    this.authorizationNonce,
    this.authorizationVersion,
    this.authorizationAmount,
    this.authorizationMaxFee,
  });

  factory PendingGaslessTransfer.fromJson(JsonMap json) {
    return PendingGaslessTransfer(
      traceId: json.valueOrNull<String>('trace_id'),
      requestId:
          json.valueOrNull<String>('request_id') ??
          'legacy:${json.value<String>('trace_id')}',
      provider: json.valueOrNull<String>('provider'),
      tokenContract: json.valueOrNull<String>('token_contract'),
      authorizationNonce: json.valueOrNull<String>('authorization_nonce'),
      authorizationVersion: json.valueOrNull<String>('authorization_version'),
      authorizationAmount: json.valueOrNull<String>('authorization_amount'),
      authorizationMaxFee: json.valueOrNull<String>('authorization_max_fee'),
      assetId: json.value<String>('asset_id'),
      network: json.value<String>('network'),
      sourceAddress: json.value<String>('source_address'),
      custodyAddress: json.value<String>('custody_address'),
      destinationAddress: json.value<String>('destination_address'),
      requestedAmount: Decimal.parse(json.value<String>('requested_amount')),
      signedMaxFee: Decimal.parse(json.value<String>('signed_max_fee')),
      authorizationDeadline: json.value<int>('authorization_deadline'),
      authorizationFingerprint: json.value<String>('authorization_fingerprint'),
      balanceChanges: BalanceChanges.fromJson(
        json.value<JsonMap>('balance_changes'),
      ),
      fee: FeeInfo.fromJson(json.value<JsonMap>('fee')),
      acceptedAt: DateTime.parse(json.value<String>('accepted_at')).toUtc(),
      updatedAt: DateTime.parse(json.value<String>('updated_at')).toUtc(),
      state: GaslessTransferState.values.byName(json.value<String>('state')),
      verificationMode: GaslessVerificationMode.values.byName(
        json.valueOrNull<String>('verification_mode') ??
            GaslessVerificationMode.legacyOnChain.name,
      ),
    );
  }

  final String? traceId;

  /// Required idempotency identity created before relay submission.
  final String requestId;
  final String? provider;
  final String? tokenContract;
  final String? authorizationNonce;
  final String? authorizationVersion;
  final String? authorizationAmount;
  final String? authorizationMaxFee;

  final String assetId;
  final String network;
  final String sourceAddress;
  final String custodyAddress;
  final String destinationAddress;
  final Decimal requestedAmount;
  final Decimal signedMaxFee;

  /// Signed authorization expiry as seconds since Unix epoch.
  final int authorizationDeadline;

  final String authorizationFingerprint;
  final BalanceChanges balanceChanges;
  final FeeInfo fee;
  final DateTime acceptedAt;
  final DateTime updatedAt;
  final GaslessTransferState state;
  final GaslessVerificationMode verificationMode;

  GaslessAuthorization get authorization => GaslessAuthorization(
    signedMaxFee: signedMaxFee,
    deadline: authorizationDeadline,
    fingerprint: authorizationFingerprint,
    provider: provider,
    tokenContract: tokenContract,
    receiver: destinationAddress,
    nonce: authorizationNonce,
    version: authorizationVersion,
  );

  PendingGaslessTransfer copyWith({
    String? traceId,
    GaslessTransferState? state,
    FeeInfo? fee,
    DateTime? updatedAt,
    GaslessVerificationMode? verificationMode,
  }) {
    return PendingGaslessTransfer(
      traceId: traceId ?? this.traceId,
      requestId: requestId,
      provider: provider,
      tokenContract: tokenContract,
      authorizationNonce: authorizationNonce,
      authorizationVersion: authorizationVersion,
      authorizationAmount: authorizationAmount,
      authorizationMaxFee: authorizationMaxFee,
      assetId: assetId,
      network: network,
      sourceAddress: sourceAddress,
      custodyAddress: custodyAddress,
      destinationAddress: destinationAddress,
      requestedAmount: requestedAmount,
      signedMaxFee: signedMaxFee,
      authorizationDeadline: authorizationDeadline,
      authorizationFingerprint: authorizationFingerprint,
      balanceChanges: balanceChanges,
      fee: fee ?? this.fee,
      acceptedAt: acceptedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      state: state ?? this.state,
      verificationMode: verificationMode ?? this.verificationMode,
    );
  }

  JsonMap toJson() => {
    if (traceId != null) 'trace_id': traceId,
    'request_id': requestId,
    if (provider != null) 'provider': provider,
    if (tokenContract != null) 'token_contract': tokenContract,
    if (authorizationNonce != null) 'authorization_nonce': authorizationNonce,
    if (authorizationVersion != null)
      'authorization_version': authorizationVersion,
    if (authorizationAmount != null)
      'authorization_amount': authorizationAmount,
    if (authorizationMaxFee != null)
      'authorization_max_fee': authorizationMaxFee,
    'asset_id': assetId,
    'network': network,
    'source_address': sourceAddress,
    'custody_address': custodyAddress,
    'destination_address': destinationAddress,
    'requested_amount': requestedAmount.toString(),
    'signed_max_fee': signedMaxFee.toString(),
    'authorization_deadline': authorizationDeadline,
    'authorization_fingerprint': authorizationFingerprint,
    'balance_changes': balanceChanges.toJson(),
    'fee': fee.toJson(),
    'accepted_at': acceptedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'state': state.name,
    'verification_mode': verificationMode.name,
  };

  @override
  List<Object?> get props => [
    traceId,
    requestId,
    provider,
    tokenContract,
    authorizationNonce,
    authorizationVersion,
    authorizationAmount,
    authorizationMaxFee,
    assetId,
    network,
    sourceAddress,
    custodyAddress,
    destinationAddress,
    requestedAmount,
    signedMaxFee,
    authorizationDeadline,
    authorizationFingerprint,
    balanceChanges,
    fee,
    acceptedAt,
    updatedAt,
    state,
    verificationMode,
  ];
}
