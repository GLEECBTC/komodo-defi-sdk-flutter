import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Legacy `send_raw_transaction` request for UTXO/EVM-style coins.
///
/// Sends a pre-built transaction hex ([txHex]) to the network for the given
/// [coin]. For SIA protocol coins, prefer [SiaSendRawTransactionRequest].
class SendRawTransactionLegacyRequest
    extends BaseRequest<SendRawTransactionResponse, GeneralErrorResponse> {
  SendRawTransactionLegacyRequest({
    required super.rpcPass,
    required this.coin,
    this.txHex,
    this.txJson,
  }) : assert(
         txHex != null || txJson != null,
         'Either txHex or txJson must be provided',
       ),
       super(method: 'send_raw_transaction', mmrpc: null);

  final String coin;
  final String? txHex;
  final JsonMap? txJson;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'coin': coin,
    'tx_hex': ?txHex,
    'tx_json': ?txJson,
  };

  @override
  SendRawTransactionResponse parse(Map<String, dynamic> json) =>
      SendRawTransactionResponse.parse(json);
}

/// SIA-specific legacy `send_raw_transaction` request using `tx_json`.
///
/// For SIA protocol withdrawals, the KDF API expects the transaction details
/// as JSON ([txJson]) instead of a hex string. This request mirrors the SIA
/// examples in the KDF documentation.
class SiaSendRawTransactionRequest
    extends BaseRequest<SendRawTransactionResponse, GeneralErrorResponse> {
  SiaSendRawTransactionRequest({
    required super.rpcPass,
    required this.coin,
    required this.txJson,
  }) : super(method: 'send_raw_transaction', mmrpc: null);

  final String coin;
  final JsonMap txJson;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'coin': coin,
    'tx_json': txJson,
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
