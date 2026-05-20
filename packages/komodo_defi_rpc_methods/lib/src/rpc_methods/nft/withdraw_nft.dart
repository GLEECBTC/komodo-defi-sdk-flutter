import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to build a signed NFT withdrawal transaction.
class WithdrawNftRequest
    extends BaseRequest<WithdrawNftResponse, GeneralErrorResponse> {
  WithdrawNftRequest({
    required String rpcPass,
    required this.type,
    required this.withdrawData,
  }) : super(method: 'withdraw_nft', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  /// NFT withdrawal operation type.
  final NftWithdrawType type;

  /// NFT withdrawal data.
  final WithdrawNftData withdrawData;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {'type': type.rpcValue, 'withdraw_data': withdrawData.toJson()},
  });

  @override
  WithdrawNftResponse parse(Map<String, dynamic> json) =>
      WithdrawNftResponse.parse(json);
}

/// Response from `withdraw_nft`.
class WithdrawNftResponse extends BaseResponse {
  WithdrawNftResponse({required super.mmrpc, required this.result});

  factory WithdrawNftResponse.parse(JsonMap json) {
    return WithdrawNftResponse(
      mmrpc: json.value<String>('mmrpc'),
      result: NftTransactionDetails.fromJson(json.value<JsonMap>('result')),
    );
  }

  /// Signed NFT transaction details.
  final NftTransactionDetails result;

  @override
  Map<String, dynamic> toJson() => {'mmrpc': mmrpc, 'result': result.toJson()};
}
