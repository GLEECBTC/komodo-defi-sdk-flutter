import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Legacy send raw transaction request
class SendRawTransactionLegacyRequest
    extends BaseRequest<SendRawTransactionResponse, GeneralErrorResponse> {
  SendRawTransactionLegacyRequest({
    required super.rpcPass,
    required this.coin,
    this.txHex,
    this.txJson,
  })  : assert(
          txHex != null || txJson != null,
          'Either txHex or txJson must be provided',
        ),
        super(method: 'send_raw_transaction', mmrpc: null);

  final String coin;
  final String? txHex;
  final Map<String, dynamic>? txJson;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'coin': coin,
        if (txHex != null) 'tx_hex': txHex,
        if (txJson != null) 'tx_json': txJson,
      };

  @override
  SendRawTransactionResponse parse(Map<String, dynamic> json) =>
      SendRawTransactionResponse.parse(json);
}

class SendRawTransactionResponse extends BaseResponse {
  SendRawTransactionResponse({required super.mmrpc, required this.txHash});

  factory SendRawTransactionResponse.parse(Map<String, dynamic> json) {
    return SendRawTransactionResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      txHash:
          json.valueOrNull<String>('result', 'tx_hash') ??
          json.value('tx_hash'),
    );
  }

  final String txHash;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {'tx_hash': txHash},
  };
}
