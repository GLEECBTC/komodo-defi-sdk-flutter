import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class MyBalanceRequest
    extends BaseRequest<MyBalanceResponse, GeneralErrorResponse> {
  MyBalanceRequest({required String rpcPass, required this.coin})
    : super(method: 'my_balance', rpcPass: rpcPass, mmrpc: null);

  final String coin;

  @override
  Map<String, dynamic> toJson() {
    return super.toJson().deepMerge({'coin': coin});
  }

  @override
  MyBalanceResponse parse(Map<String, dynamic> json) =>
      MyBalanceResponse.parse(json);
}

class MyBalanceResponse extends BaseResponse {
  MyBalanceResponse({
    required super.mmrpc,
    required this.address,
    required this.balance,
    required this.coin,
    this.gasfreeAddress,
  });

  factory MyBalanceResponse.parse(Map<String, dynamic> json) {
    return MyBalanceResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      address: json.value<String>('address'),
      balance: BalanceInfo.fromJson(json),
      coin: json.value<String>('coin'),
      gasfreeAddress: json.valueOrNull<String>('gasfree_address'),
    );
  }

  final String address;
  final String? gasfreeAddress;
  final BalanceInfo balance;
  final String coin;

  @override
  Map<String, dynamic> toJson() {
    return {
      'mmrpc': mmrpc,
      'address': address,
      if (gasfreeAddress != null) 'gasfree_address': gasfreeAddress,
      'balance': balance.total,
      'unspendable_balance': balance.unspendable,
      'coin': coin,
    };
  }
}
