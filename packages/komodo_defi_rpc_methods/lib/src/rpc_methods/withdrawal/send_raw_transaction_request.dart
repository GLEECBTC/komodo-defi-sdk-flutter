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
  }) : super(method: 'send_raw_transaction', mmrpc: null) {
    if (txHex == null && txJson == null) {
      throw ArgumentError('Either txHex or txJson must be provided');
    }
  }

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
  SendRawTransactionResponse({
    required super.mmrpc,
    this.txHash,
    this.relayType,
    this.requestId,
    this.traceId,
    this.state,
    this.expectedAuthorization,
  });

  factory SendRawTransactionResponse.parse(Map<String, dynamic> json) {
    // A gas-free (gasless) relay broadcast returns a trace handle instead of a
    // signed-tx hash: `{relay_type, trace_id, state}` (optionally wrapped in a
    // `result` envelope for mmrpc:null responses).
    final relayType =
        json.valueOrNull<String>('result', 'relay_type') ??
        json.valueOrNull<String>('relay_type');

    if (relayType != null) {
      final result = json.valueOrNull<JsonMap>('result') ?? json;
      final expectedAuthorization = result.valueOrNull<JsonMap>(
        'expected_authorization',
      );
      return SendRawTransactionResponse(
        mmrpc: json.valueOrNull<String>('mmrpc'),
        relayType: relayType,
        requestId: result.valueOrNull<String>('request_id'),
        traceId: result.value<String>('trace_id'),
        state: result.valueOrNull<String>('state'),
        expectedAuthorization: expectedAuthorization == null
            ? null
            : GaslessExpectedAuthorization.fromJson(expectedAuthorization),
      );
    }

    return SendRawTransactionResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      txHash:
          json.valueOrNull<String>('result', 'tx_hash') ??
          json.value('tx_hash'),
    );
  }

  /// On-chain transaction hash for a standard broadcast. Null for a gas-free
  /// relay broadcast, where the on-chain hash is only known once the relay
  /// confirms (poll [traceId] via `gasless::trace_status`).
  final String? txHash;

  /// Relay type for a gas-free broadcast (`tron_gasfree`). Null for standard.
  final String? relayType;

  /// Wallet-scoped UUID that binds the signed preview to relay acceptance.
  final String? requestId;

  /// Trace handle for polling gas-free transfer status. Null for standard.
  final String? traceId;

  /// Initial relay state (e.g. `WAITING`). Null for standard.
  final String? state;

  /// Echoed signed context validated by KDF before relay acceptance.
  final GaslessExpectedAuthorization? expectedAuthorization;

  /// Whether the relay response supports the hardened bound-response contract.
  bool get hasBoundRelayContext =>
      requestId != null && expectedAuthorization != null;

  /// Whether this is a gas-free relay broadcast (no immediate tx hash).
  bool get isGaslessRelay => relayType == 'tron_gasfree';

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      if (txHash != null) 'tx_hash': txHash,
      if (relayType != null) 'relay_type': relayType,
      if (requestId != null) 'request_id': requestId,
      if (traceId != null) 'trace_id': traceId,
      if (state != null) 'state': state,
      if (expectedAuthorization != null)
        'expected_authorization': expectedAuthorization!.toJson(),
    },
  };
}
