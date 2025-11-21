import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// SIA-specific `withdraw` request.
///
/// This wraps the standard v2 `withdraw` RPC but expects a SIA protocol coin
/// and parses the response into [SiaWithdrawResponse], which exposes the
/// SIA-specific `tx_json` needed for broadcasting.
class SiaWithdrawRequest
    extends BaseRequest<SiaWithdrawResponse, GeneralErrorResponse> {
  SiaWithdrawRequest({
    required super.rpcPass,
    required this.coin,
    required this.to,
    this.amount,
    this.fee,
    this.from,
    this.max = false,
  }) : assert(amount != null || max, 'Specify amount or set max=true'),
       super(method: 'withdraw', mmrpc: RpcVersion.v2_0);

  final String coin;
  final String to;
  final Decimal? amount;
  final FeeInfo? fee;
  final WithdrawalSource? from;
  final bool max;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': {
      'coin': coin,
      'to': to,
      if (!max && amount != null) 'amount': amount!.toString(),
      if (max) 'max': true,
      if (fee != null) 'fee': fee!.toJson(),
      if (from != null) 'from': from!.toRpcParams(),
    },
  };

  @override
  SiaWithdrawResponse parse(Map<String, dynamic> json) =>
      SiaWithdrawResponse.parse(json);
}

/// Response for SIA protocol withdrawals.
///
/// Mirrors the SIA examples in the v2 `withdraw` documentation and includes:
/// - [txJson]: raw SIA transaction JSON, to be passed to `send_raw_transaction`
/// - high-level accounting fields such as [totalAmount], [spentByMe],
///   [receivedByMe] and [myBalanceChange]
/// - on-chain metadata like [blockHeight], [timestamp] and [feeDetails]
/// - context fields [coin], [internalId], [transactionType] and optional [memo]
class SiaWithdrawResponse extends BaseResponse {
  SiaWithdrawResponse({
    required super.mmrpc,
    required this.txJson,
    required this.txHash,
    required this.from,
    required this.to,
    required this.totalAmount,
    required this.spentByMe,
    required this.receivedByMe,
    required this.myBalanceChange,
    required this.blockHeight,
    required this.timestamp,
    required this.feeDetails,
    required this.coin,
    required this.internalId,
    required this.transactionType,
    this.memo,
  });

  factory SiaWithdrawResponse.parse(Map<String, dynamic> json) {
    final result = json.value<JsonMap>('result');
    return SiaWithdrawResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      txJson: result.value<JsonMap>('tx_json'),
      txHash: result.value<String>('tx_hash'),
      from: result.value<JsonList>('from').cast<String>(),
      to: result.value<JsonList>('to').cast<String>(),
      totalAmount: result.value<String>('total_amount'),
      spentByMe: result.value<String>('spent_by_me'),
      receivedByMe: result.value<String>('received_by_me'),
      myBalanceChange: result.value<String>('my_balance_change'),
      blockHeight: result.value<int>('block_height'),
      timestamp: result.value<int>('timestamp'),
      feeDetails: FeeInfo.fromJson(result.value<JsonMap>('fee_details')),
      coin: result.value<String>('coin'),
      internalId: result.value<String>('internal_id'),
      transactionType: result.value<String>('transaction_type'),
      memo: result.valueOrNull<String>('memo'),
    );
  }

  /// Raw SIA transaction JSON payload to be passed to send_raw_transaction
  final JsonMap txJson;
  final String txHash;
  final List<String> from;
  final List<String> to;
  final String totalAmount;
  final String spentByMe;
  final String receivedByMe;
  final String myBalanceChange;
  final int blockHeight;
  final int timestamp;
  final FeeInfo feeDetails;
  final String coin;
  final String internalId;
  final String transactionType;
  final String? memo;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'tx_json': txJson,
      'tx_hash': txHash,
      'from': from,
      'to': to,
      'total_amount': totalAmount,
      'spent_by_me': spentByMe,
      'received_by_me': receivedByMe,
      'my_balance_change': myBalanceChange,
      'block_height': blockHeight,
      'timestamp': timestamp,
      'fee_details': feeDetails.toJson(),
      'coin': coin,
      'internal_id': internalId,
      'transaction_type': transactionType,
      if (memo != null) 'memo': memo,
    },
  };
}
