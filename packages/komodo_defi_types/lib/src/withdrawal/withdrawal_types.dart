import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

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
  }) : assert(
          txHex != null || txJson != null,
          'Either txHex or txJson must be provided',
        );

  factory WithdrawResult.fromJson(JsonMap json) {
    return WithdrawResult(
      txHex: json.valueOrNull<String>('tx_hex'),
      txJson: json.valueOrNull<JsonMap>('tx_json'),
      txHash: json.value<String>('tx_hash'),
      from: List<String>.from(json.value('from')),
      to: List<String>.from(json.value('to')),
      balanceChanges: BalanceChanges.fromJson(json),
      blockHeight: json.value<int>('block_height'),
      timestamp: json.value<int>('timestamp'),
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
  final String txHash;
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

  JsonMap toJson() => {
        if (txHex != null) 'tx_hex': txHex,
        if (txJson != null) 'tx_json': txJson,
        'tx_hash': txHash,
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
  });

  /// Create a domain model from API response
  factory WithdrawalResult.fromWithdrawResult(WithdrawResult result) {
    return WithdrawalResult(
      txHash: result.txHash,
      balanceChanges: result.balanceChanges,
      coin: result.coin,
      toAddress: result.to.first,
      fee: result.fee,
      kmdRewardsEligible: result.kmdRewards != null &&
          Decimal.parse(result.kmdRewards!.amount) > Decimal.zero,
    );
  }

  final String txHash;
  final BalanceChanges balanceChanges;
  final String coin;
  final String toAddress;
  final FeeInfo fee;
  final bool kmdRewardsEligible;

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
  });

  final WithdrawalStatus status;
  final String message;
  final WithdrawalResult? withdrawalResult;
  final WithdrawalErrorCode? errorCode;
  final String? errorMessage;
  final String? taskId;

  @override
  List<Object?> get props => [
        status,
        message,
        withdrawalResult,
        errorCode,
        errorMessage,
        taskId,
      ];
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
    this.isMax,
  }) : assert(
          amount != null || (isMax ?? false),
          'Amount must be non-null when not using max',
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
  final bool? isMax;

  JsonMap toJson() => {
        'coin': asset,
        'to': toAddress,
        if (fee != null) 'fee': fee!.toJson(),
        if (amount != null) 'amount': amount.toString(),
        if (isMax != null) 'max': isMax,
        if (from != null) 'from': from!.toRpcParams(),
        if (memo != null) 'memo': memo,
        if (ibcTransfer != null) 'ibc_transfer': ibcTransfer,
        if (ibcSourceChannel != null) 'ibc_source_channel': ibcSourceChannel,
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
        isMax,
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
  const WithdrawalSource._({
    required this.type,
    required this.params,
  });

  factory WithdrawalSource.hdWalletId({
    required int accountId,
    required int addressId,
    Bip44Chain chain = Bip44Chain.external,
  }) =>
      WithdrawalSource._(
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
  }) =>
      WithdrawalSource._(
        type: WithdrawalSourceType.hdWallet,
        params: {
          'derivation_path': "m/44'/$coinId'/$accountId'/$chain/$addressId",
        },
      );

  // TODO:
  // factory WithdrawalSource.trezor

  final WithdrawalSourceType type;
  final JsonMap params;

  @override
  JsonMap toRpcParams() => params;

  JsonMap toJson() => {
        'type': type.toString(),
        ...params,
      };

  @override
  List<Object?> get props => [
        type,
        [...params.values, params.keys],
      ];
}

class KmdRewards {
  KmdRewards({
    required this.amount,
    this.claimedByMe,
  });

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
