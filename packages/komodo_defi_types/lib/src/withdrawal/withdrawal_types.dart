import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Relay type tag for Tron gas-free (gasless) transfers.
const String _tronGasfreeRelayType = 'tron_gasfree';

/// Keys that make up the Tron gas-free relay payload, sent verbatim as
/// `tx_json` to `send_raw_transaction`. Matches the KDF `TronGasfreeRelayPayload`
/// struct, which rejects unknown fields — so the payload must be exactly these.
const List<String> _tronGasfreeRelayPayloadKeys = [
  'relay_type',
  'request_id',
  'chain_id',
  'coin',
  'hd_from',
  'from_address',
  'gasfree_address',
  'verifying_contract',
  'signed_authorization',
  'authorization_fingerprint',
  'created_at',
];

/// Extracts the gas-free relay payload subset from a withdraw result so it can
/// be broadcast via `send_raw_transaction`.
JsonMap _extractTronGasfreeRelayPayload(JsonMap json) {
  final payload = <String, dynamic>{};
  for (final key in _tronGasfreeRelayPayloadKeys) {
    final value = json[key];
    if (value != null) payload[key] = value;
  }
  const requiredKeys = <String>{
    'relay_type',
    'chain_id',
    'coin',
    'from_address',
    'gasfree_address',
    'verifying_contract',
    'signed_authorization',
    'created_at',
  };
  final missing = requiredKeys.where(
    (key) => payload[key] == null || payload[key].toString().isEmpty,
  );
  if (missing.isNotEmpty) {
    throw FormatException(
      'GasFree relay payload is missing required fields: '
      '${missing.join(', ')}',
    );
  }
  final hasRequestId = payload['request_id']?.toString().isNotEmpty ?? false;
  final hasFingerprint =
      payload['authorization_fingerprint']?.toString().isNotEmpty ?? false;
  if (hasRequestId != hasFingerprint) {
    throw const FormatException(
      'GasFree relay payload has partial binding context',
    );
  }
  return payload;
}

/// Raw API response for a withdrawal operation
class WithdrawResult {
  WithdrawResult({
    this.txHex,
    this.txJson,
    required this.txHash,
    required this.from,
    required this.to,
    required this.balanceChanges,
    required this.blockHeight,
    required this.timestamp,
    required this.fee,
    required this.coin,
    this.internalId,
    this.kmdRewards,
    this.memo,
  }) {
    if (txHex == null && txJson == null) {
      throw ArgumentError('Either txHex or txJson must be provided');
    }
  }

  factory WithdrawResult.fromJson(JsonMap json) {
    // A gas-free (gasless) relay result carries the relay payload (at the top
    // level, or already nested under `tx_json`) instead of a signed tx_hex, and
    // has no on-chain tx hash yet — the hash is only known once the relay
    // confirms (via `gasless::trace_status`).
    final nestedTxJson = json.valueOrNull<JsonMap>('tx_json');
    final relaySource = nestedTxJson ?? json;
    final isGaslessRelay =
        relaySource.valueOrNull<String>('relay_type') == _tronGasfreeRelayType;
    final txJson = isGaslessRelay
        ? _extractTronGasfreeRelayPayload(relaySource)
        : nestedTxJson;
    final signedAuthorization = txJson?.valueOrNull<JsonMap>(
      'signed_authorization',
    );

    // The relaxed (nullable) parsing below only applies to a gasless relay
    // result, which legitimately has no on-chain tx hash / from / to / block /
    // timestamp yet. For a standard withdrawal these fields are always present,
    // so keep strict parsing — otherwise a malformed standard response would
    // produce a phantom "complete" with an empty hash, or an empty `to` that
    // later throws a RangeError at the broadcast call sites.
    return WithdrawResult(
      txHex: json.valueOrNull<String>('tx_hex'),
      txJson: txJson,
      txHash: isGaslessRelay
          ? json.valueOrNull<String>('tx_hash')
          : json.value<String>('tx_hash'),
      from: isGaslessRelay
          ? List<String>.from(
              json.valueOrNull('from') ?? [txJson!['from_address']],
            )
          : List<String>.from(json.value('from')),
      to: isGaslessRelay
          ? List<String>.from(
              json.valueOrNull('to') ?? [signedAuthorization!['receiver']],
            )
          : List<String>.from(json.value('to')),
      balanceChanges: BalanceChanges.fromJson(json),
      blockHeight: isGaslessRelay
          ? (json.valueOrNull<int>('block_height') ?? 0)
          : json.value<int>('block_height'),
      timestamp: isGaslessRelay
          ? (json.valueOrNull<int>('timestamp') ?? 0)
          : json.value<int>('timestamp'),
      fee: FeeInfo.fromJson(json.value<JsonMap>('fee_details')),
      coin: json.value<String>('coin'),
      internalId: json.valueOrNull<String>('internal_id'),
      kmdRewards: json.containsKey('kmd_rewards')
          ? KmdRewards.fromJson(json.value<JsonMap>('kmd_rewards'))
          : null,
      memo: json.valueOrNull<String>('memo'),
    );
  }

  final String? txHex;
  final JsonMap? txJson;
  final String? txHash;
  final List<String> from;
  final List<String> to;
  final BalanceChanges balanceChanges;
  final int blockHeight;
  final int timestamp;
  final FeeInfo fee;
  final String coin;
  final String? internalId;
  final KmdRewards? kmdRewards;
  final String? memo;

  /// Signed GasFree authorization metadata, when this is a relay preview.
  GaslessAuthorization? get gaslessAuthorization {
    final gaslessFee = fee is FeeInfoTronGasless
        ? fee as FeeInfoTronGasless
        : null;
    if (gaslessFee == null) return null;
    final authorization = txJson?['signed_authorization'];
    final auth = authorization is Map
        ? Map<String, dynamic>.from(authorization)
        : const <String, dynamic>{};
    final maxFee =
        gaslessFee.signedMaxFee ??
        Decimal.tryParse(auth['max_fee']?.toString() ?? '');
    final deadline =
        gaslessFee.authorizationDeadline ??
        int.tryParse(auth['deadline']?.toString() ?? '');
    final fingerprint =
        gaslessFee.authorizationFingerprint ??
        txJson?['authorization_fingerprint']?.toString();
    if (maxFee == null ||
        deadline == null ||
        fingerprint == null ||
        fingerprint.isEmpty) {
      return null;
    }
    return GaslessAuthorization(
      signedMaxFee: maxFee,
      deadline: deadline,
      fingerprint: fingerprint,
      provider:
          gaslessFee.providerAddress ?? auth['service_provider']?.toString(),
      tokenContract: auth['token']?.toString(),
      receiver: auth['receiver']?.toString(),
      nonce: auth['nonce']?.toString(),
      version: auth['version']?.toString(),
    );
  }

  JsonMap toJson() => {
    if (txHex != null) 'tx_hex': txHex,
    if (txJson != null) 'tx_json': txJson,
    if (txHash != null) 'tx_hash': txHash,
    'from': from,
    'to': to,
    ...balanceChanges.toJson(),
    'block_height': blockHeight,
    'timestamp': timestamp,
    'fee_details': fee.toJson(),
    'coin': coin,
    if (internalId != null) 'internal_id': internalId,
    if (kmdRewards != null) 'kmd_rewards': kmdRewards!.toJson(),
    if (memo != null) 'memo': memo,
  };
}

/// Domain model for a successful withdrawal operation
class WithdrawalResult extends Equatable {
  const WithdrawalResult({
    required this.txHash,
    required this.balanceChanges,
    required this.coin,
    required this.toAddress,
    required this.fee,
    this.kmdRewardsEligible = false,
    this.confirmationBlockHeight,
    this.confirmedAt,
  });

  /// Create a domain model from API response
  factory WithdrawalResult.fromWithdrawResult(WithdrawResult result) {
    return WithdrawalResult(
      txHash: result.txHash,
      balanceChanges: result.balanceChanges,
      coin: result.coin,
      toAddress: result.to.first,
      fee: result.fee,
      kmdRewardsEligible:
          result.kmdRewards != null &&
          Decimal.parse(result.kmdRewards!.amount) > Decimal.zero,
      confirmationBlockHeight: result.blockHeight > 0
          ? result.blockHeight
          : null,
      confirmedAt: result.timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              result.timestamp * 1000,
              isUtc: true,
            )
          : null,
    );
  }

  final String? txHash;
  final BalanceChanges balanceChanges;
  final String coin;
  final String toAddress;
  final FeeInfo fee;
  final bool kmdRewardsEligible;
  final int? confirmationBlockHeight;
  final DateTime? confirmedAt;

  /// Convenience getter for the withdrawal amount (abs of net change)
  Decimal get amount => balanceChanges.netChange.abs();

  @override
  List<Object?> get props => [
    txHash,
    balanceChanges,
    coin,
    toAddress,
    fee,
    kmdRewardsEligible,
    confirmationBlockHeight,
    confirmedAt,
  ];
}

/// Progress tracking for withdrawal operations
class WithdrawalProgress extends Equatable {
  const WithdrawalProgress({
    required this.status,
    required this.message,
    this.withdrawalResult,
    this.errorCode,
    this.errorMessage,
    this.taskId,
    this.sdkError,
    this.gaslessState,
    this.gaslessTransferState,
    this.submission,
  });

  final WithdrawalStatus status;
  final String message;
  final WithdrawalResult? withdrawalResult;
  final WithdrawalErrorCode? errorCode;
  final String? errorMessage;
  final String? taskId;
  final SdkError? sdkError;

  /// Relay lifecycle state for a gas-free (gasless) transfer, so consumers
  /// can render their own (e.g. localized) status copy instead of the English
  /// [message]. Null for standard withdrawals and for gasless progress events
  /// that precede the relay poll.
  final GaslessTraceState? gaslessState;
  final GaslessTransferState? gaslessTransferState;
  final WithdrawalSubmission? submission;

  @override
  List<Object?> get props => [
    status,
    message,
    withdrawalResult,
    errorCode,
    errorMessage,
    taskId,
    sdkError,
    gaslessState,
    gaslessTransferState,
    submission,
  ];
}

/// Preferred fee rail for withdrawals that support alternative fee payment.
///
/// `native` keeps the coin's normal fee behavior; `gasless` routes a TRC20
/// transfer through the GasFree provider with the fee paid in the token.
enum WithdrawalFeeMethod {
  native,
  gasless;

  String get jsonValue => switch (this) {
    WithdrawalFeeMethod.native => 'native',
    WithdrawalFeeMethod.gasless => 'gasless',
  };
}

/// Caller-supplied constraints for gas-free (gasless) TRC20 withdrawals.
///
/// Serializes to the KDF `gasless` withdraw option object.
class GaslessWithdrawalOptions extends Equatable {
  const GaslessWithdrawalOptions({
    this.maxFee,
    this.deadlineSeconds,
    this.fallbackToNative = false,
  });

  /// Maximum provider fee, in the token's own units, the user will accept.
  /// When null, the provider's default cap applies.
  final Decimal? maxFee;

  /// Permit deadline, in seconds from now.
  final int? deadlineSeconds;

  /// Whether to fall back to a native (TRX-funded) transfer when gasless is
  /// unavailable.
  final bool fallbackToNative;

  JsonMap toJson() => {
    if (maxFee != null) 'max_fee': maxFee.toString(),
    if (deadlineSeconds != null) 'deadline_seconds': deadlineSeconds,
    'fallback_to_native': fallbackToNative,
  };

  @override
  List<Object?> get props => [maxFee, deadlineSeconds, fallbackToNative];
}

/// Parameters for initiating a withdrawal
class WithdrawParameters extends Equatable {
  const WithdrawParameters({
    required this.asset,
    required this.toAddress,
    required this.amount,
    this.fee,
    this.feePriority,
    this.from,
    this.memo,
    this.ibcTransfer,
    this.ibcSourceChannel,
    this.expirationSeconds,
    this.isMax,
    this.feeMethod,
    this.gaslessOptions,
  }) : assert(
         amount != null || (isMax ?? false),
         'Amount must be specified when isMax is false',
       ),
       assert(
         amount == null || !(isMax ?? false),
         'Amount must be omitted when isMax is true',
       );

  final String asset;
  final String toAddress;
  final Decimal? amount;
  final FeeInfo? fee;
  final WithdrawalFeeLevel? feePriority;
  final WithdrawalSource? from;
  final String? memo;
  final bool? ibcTransfer;
  final int? ibcSourceChannel;
  final int? expirationSeconds;
  final bool? isMax;

  /// Preferred fee rail (e.g. `gasless` for gas-free TRC20 transfers).
  final WithdrawalFeeMethod? feeMethod;

  /// Constraints for a gasless withdrawal. Only used when
  /// [feeMethod] is [WithdrawalFeeMethod.gasless].
  final GaslessWithdrawalOptions? gaslessOptions;

  JsonMap toJson() => {
    'coin': asset,
    'to': toAddress,
    if (fee != null) 'fee': fee!.toJson(),
    if (!(isMax ?? false) && amount != null) 'amount': amount.toString(),
    if (isMax != null) 'max': isMax,
    if (from != null) 'from': from!.toRpcParams(),
    if (memo != null) 'memo': memo,
    if (ibcTransfer != null) 'ibc_transfer': ibcTransfer,
    if (ibcSourceChannel != null) 'ibc_source_channel': ibcSourceChannel,
    if (expirationSeconds != null) 'expiration_seconds': expirationSeconds,
    if (feeMethod != null) 'fee_method': feeMethod!.jsonValue,
    if (gaslessOptions != null) 'gasless': gaslessOptions!.toJson(),
  };

  @override
  List<Object?> get props => [
    asset,
    toAddress,
    amount,
    fee,
    feePriority,
    from,
    memo,
    ibcTransfer,
    ibcSourceChannel,
    expirationSeconds,
    isMax,
    feeMethod,
    gaslessOptions,
  ];
}

/// Preview of a withdrawal operation, using same structure as API response
typedef WithdrawalPreview = WithdrawResult;

enum Bip44Chain {
  external._('External', 'External', 0),
  internal._('Internal', 'Internal', 1);

  const Bip44Chain._(this.value, this.name, this.id);

  final String value;
  final String name;

  final int id;
}

/// Specifies the source of funds for a withdrawal
// TODO: Implement Trezor sourcew
class WithdrawalSource extends Equatable implements RpcRequestParams {
  const WithdrawalSource._({required this.type, required this.params});

  factory WithdrawalSource.hdWalletId({
    required int accountId,
    required int addressId,
    Bip44Chain chain = Bip44Chain.external,
  }) => WithdrawalSource._(
    type: WithdrawalSourceType.hdWallet,
    params: {
      'account_id': accountId,
      'chain': chain.value,
      'address_id': addressId,
    },
  );

  factory WithdrawalSource.hdDerivationPath(String derivationPath) =>
      WithdrawalSource._(
        type: WithdrawalSourceType.hdWallet,
        params: {'derivation_path': derivationPath},
      );

  // E.g. m/44'/COIN_ID'/ACCOUNT_ID'/CHAIN/ADDRESS_ID
  factory WithdrawalSource.hdWalletPath({
    required int coinId,
    required int accountId,
    required String chain,
    required int addressId,
  }) => WithdrawalSource._(
    type: WithdrawalSourceType.hdWallet,
    params: {'derivation_path': "m/44'/$coinId'/$accountId'/$chain/$addressId"},
  );

  // TODO:
  // factory WithdrawalSource.trezor

  final WithdrawalSourceType type;
  final JsonMap params;

  @override
  JsonMap toRpcParams() => params;

  JsonMap toJson() => {'type': type.toString(), ...params};

  @override
  List<Object?> get props => [
    type,
    [...params.values, params.keys],
  ];
}

class KmdRewards {
  KmdRewards({required this.amount, this.claimedByMe});

  factory KmdRewards.fromJson(JsonMap json) {
    return KmdRewards(
      amount: json.value<String>('amount'),
      claimedByMe: json.valueOrNull<bool>('claimed_by_me'),
    );
  }

  final String amount;
  final bool? claimedByMe;

  JsonMap toJson() => {
    'amount': amount,
    if (claimedByMe != null) 'claimed_by_me': claimedByMe,
  };
}
