import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// SIA-specific withdraw request
///
/// Uses the same 'withdraw' RPC but parses SIA-flavored response payload
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
  })  : assert(amount != null || max, 'Specify amount or set max=true'),
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

class SiaWithdrawResponse extends BaseResponse {
  SiaWithdrawResponse({
    required super.mmrpc,
    required this.status,
    required this.spentByMe,
    required this.receivedByMe,
    required this.myBalanceChange,
    this.feeDetails,
    this.details,
  });

  factory SiaWithdrawResponse.parse(Map<String, dynamic> json) {
    final result = json.value<JsonMap>('result');
    return SiaWithdrawResponse(
      mmrpc: json.value<String>('mmrpc'),
      status: result.value<String>('status'),
      spentByMe: result.value<String>('spent_by_me'),
      receivedByMe: result.value<String>('received_by_me'),
      myBalanceChange: result.value<String>('my_balance_change'),
      feeDetails: result.valueOrNull<JsonMap>('fee_details') == null
          ? null
          : FeeInfo.fromJson(result.value<JsonMap>('fee_details')),
      details: result.valueOrNull('details'),
    );
  }

  final String status;
  final String spentByMe;
  final String receivedByMe;
  final String myBalanceChange;
  final FeeInfo? feeDetails;
  final dynamic details;

  @override
  Map<String, dynamic> toJson() => {
        'mmrpc': mmrpc,
        'result': {
          'status': status,
          'spent_by_me': spentByMe,
          'received_by_me': receivedByMe,
          'my_balance_change': myBalanceChange,
          if (feeDetails != null) 'fee_details': feeDetails!.toJson(),
          if (details != null) 'details': details,
        },
      };
}

