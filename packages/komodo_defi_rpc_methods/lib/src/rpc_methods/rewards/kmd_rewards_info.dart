import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to fetch KMD rewards information.
class KmdRewardsInfoRequest
    extends BaseRequest<KmdRewardsInfoResponse, GeneralErrorResponse> {
  KmdRewardsInfoRequest({required String rpcPass})
    : super(method: 'kmd_rewards_info', rpcPass: rpcPass, mmrpc: null);

  @override
  KmdRewardsInfoResponse parse(Map<String, dynamic> json) =>
      KmdRewardsInfoResponse.parse(json);
}

/// Response from `kmd_rewards_info`.
class KmdRewardsInfoResponse extends BaseResponse {
  KmdRewardsInfoResponse({required super.mmrpc, required this.rewards});

  factory KmdRewardsInfoResponse.parse(JsonMap json) {
    final rewardsJson = json.valueOrNull<List<dynamic>>('result') ?? [];
    return KmdRewardsInfoResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      rewards: rewardsJson
          .map((item) => KmdRewardInfo.fromJson(item as JsonMap))
          .toList(),
    );
  }

  /// Rewardable KMD UTXO entries.
  final List<KmdRewardInfo> rewards;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': rewards.map((reward) => reward.toJson()).toList(),
  };
}

/// KMD reward information for one UTXO.
class KmdRewardInfo {
  KmdRewardInfo({
    required this.txHash,
    required this.amount,
    this.height,
    this.outputIndex,
    this.lockTime,
    this.accruedReward,
    this.notAccruedReason,
    this.accrueStartAt,
    this.accrueStopAt,
  });

  factory KmdRewardInfo.fromJson(JsonMap json) {
    final accruedRewards = json.valueOrNull<JsonMap>('accrued_rewards') ?? {};
    return KmdRewardInfo(
      txHash: json.value<String>('tx_hash'),
      amount: json.value<String>('amount'),
      height: json.valueOrNull<int>('height'),
      outputIndex: json.valueOrNull<int>('output_index'),
      lockTime: json.valueOrNull<int>('locktime'),
      accruedReward: accruedRewards.valueOrNull<String>('Accrued'),
      notAccruedReason: accruedRewards.valueOrNull<String>('NotAccruedReason'),
      accrueStartAt: json.valueOrNull<int>('accrue_start_at'),
      accrueStopAt: json.valueOrNull<int>('accrue_stop_at'),
    );
  }

  /// Transaction hash containing the rewardable output.
  final String txHash;

  /// UTXO amount.
  final String amount;

  /// Output block height.
  final int? height;

  /// Output index.
  final int? outputIndex;

  /// UTXO locktime.
  final int? lockTime;

  /// Accrued reward amount, if rewards are available.
  final String? accruedReward;

  /// KDF reason why rewards are not accrued.
  final String? notAccruedReason;

  /// Reward accrual start timestamp.
  final int? accrueStartAt;

  /// Reward accrual stop timestamp.
  final int? accrueStopAt;

  Map<String, dynamic> toJson() => {
    'tx_hash': txHash,
    'amount': amount,
    if (height != null) 'height': height,
    if (outputIndex != null) 'output_index': outputIndex,
    if (lockTime != null) 'locktime': lockTime,
    'accrued_rewards': {
      if (accruedReward != null) 'Accrued': accruedReward,
      if (notAccruedReason != null) 'NotAccruedReason': notAccruedReason,
    },
    if (accrueStartAt != null) 'accrue_start_at': accrueStartAt,
    if (accrueStopAt != null) 'accrue_stop_at': accrueStopAt,
  };
}
