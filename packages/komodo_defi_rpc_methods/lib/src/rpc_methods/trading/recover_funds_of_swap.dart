import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to recover funds from a swap that needs manual recovery.
class RecoverFundsOfSwapRequest
    extends BaseRequest<RecoverFundsOfSwapResponse, GeneralErrorResponse> {
  RecoverFundsOfSwapRequest({required String rpcPass, required this.uuid})
    : super(
        method: 'recover_funds_of_swap',
        rpcPass: rpcPass,
        mmrpc: RpcVersion.v2_0,
      );

  /// Swap UUID to recover funds for.
  final String uuid;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {'uuid': uuid},
  });

  @override
  RecoverFundsOfSwapResponse parse(Map<String, dynamic> json) =>
      RecoverFundsOfSwapResponse.parse(json);
}

/// Response returned after a swap recovery transaction is prepared.
class RecoverFundsOfSwapResponse extends BaseResponse {
  RecoverFundsOfSwapResponse({required super.mmrpc, required this.result});

  factory RecoverFundsOfSwapResponse.parse(JsonMap json) {
    return RecoverFundsOfSwapResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      result: RecoverFundsOfSwapResult.fromJson(json.value<JsonMap>('result')),
    );
  }

  /// Recovery transaction details.
  final RecoverFundsOfSwapResult result;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': result.toJson(),
  };
}

/// Details of the recovery action KDF performed or prepared.
class RecoverFundsOfSwapResult {
  RecoverFundsOfSwapResult({
    required this.action,
    required this.coin,
    required this.txHash,
    required this.txHex,
  });

  factory RecoverFundsOfSwapResult.fromJson(JsonMap json) {
    return RecoverFundsOfSwapResult(
      action: json.value<String>('action'),
      coin: json.value<String>('coin'),
      txHash: json.value<String>('tx_hash'),
      txHex: json.value<String>('tx_hex'),
    );
  }

  /// Recovery action, for example `SpentOtherPayment` or `RefundedMyPayment`.
  final String action;

  /// Coin used by the recovery transaction.
  final String coin;

  /// Transaction hash for the recovery transaction.
  final String txHash;

  /// Signed transaction hex returned by KDF.
  final String txHex;

  Map<String, dynamic> toJson() => {
    'action': action,
    'coin': coin,
    'tx_hash': txHash,
    'tx_hex': txHex,
  };
}
