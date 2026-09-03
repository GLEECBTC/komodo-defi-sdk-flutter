import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Legacy send raw transaction request
class SendRawTransactionLegacyRequest
    extends BaseRequest<SendRawTransactionResponse, GeneralErrorResponse> {
  SendRawTransactionLegacyRequest({
    required super.rpcPass,
    required this.coin,
    this.txHex,
    this.txJson,
    this.gaslessRelayPayload,
  }) : super(method: 'send_raw_transaction', mmrpc: null) {
    final payloadCount = [
      txHex,
      txJson,
      gaslessRelayPayload,
    ].where((payload) => payload != null).length;
    if (payloadCount != 1) {
      throw ArgumentError(
        'Exactly one of txHex, txJson, or gaslessRelayPayload must be provided',
      );
    }
  }

  final String coin;
  final String? txHex;
  final Map<String, dynamic>? txJson;
  final TronGasfreeRelayPayload? gaslessRelayPayload;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'coin': coin,
    if (txHex != null) 'tx_hex': txHex,
    if (txJson != null)
      'tx_json': txJson!.containsKey('relay_type')
          ? TronGasfreeRelayPayload.fromJson(txJson!).toJson()
          : txJson,
    if (gaslessRelayPayload != null) 'tx_json': gaslessRelayPayload!.toJson(),
  };

  @override
  SendRawTransactionResponse parse(Map<String, dynamic> json) =>
      SendRawTransactionResponse.parse(json);
}

/// Provider state returned immediately after a GasFree relay is accepted.
enum GaslessSubmitState {
  waiting('WAITING'),
  inProgress('INPROGRESS'),
  confirming('CONFIRMING'),
  succeed('SUCCEED'),
  failed('FAILED');

  const GaslessSubmitState(this.wireValue);

  final String wireValue;

  static GaslessSubmitState parse(String value) => switch (value) {
    'WAITING' => GaslessSubmitState.waiting,
    'INPROGRESS' => GaslessSubmitState.inProgress,
    'CONFIRMING' => GaslessSubmitState.confirming,
    'SUCCEED' => GaslessSubmitState.succeed,
    'FAILED' => GaslessSubmitState.failed,
    _ => throw const FormatException('Unknown GasFree submit state'),
  };
}

class SendRawTransactionResponse extends BaseResponse {
  SendRawTransactionResponse({
    required super.mmrpc,
    this.txHash,
    this.relayType,
    this.traceId,
    this.state,
  }) {
    final isRelay = relayType != null;
    if (isRelay) {
      final acceptedTraceId = traceId;
      if (relayType != TronGasfreeRelayPayload.relayTypeValue ||
          acceptedTraceId == null ||
          acceptedTraceId.trim().isEmpty ||
          state == null ||
          txHash != null) {
        throw const FormatException(
          'Invalid GasFree send_raw_transaction response shape',
        );
      }
    } else if (txHash == null || traceId != null || state != null) {
      throw const FormatException(
        'Invalid standard send_raw_transaction response shape',
      );
    }
  }

  factory SendRawTransactionResponse.parse(Map<String, dynamic> json) {
    // A gas-free (gasless) relay broadcast returns a trace handle instead of a
    // signed-tx hash: `{relay_type, trace_id, state}` at the response's top
    // level. The pinned KDF legacy endpoint does not wrap this relay response.
    final nestedResult = json.valueOrNull<JsonMap>('result');
    if (nestedResult?.containsKey('relay_type') ?? false) {
      throw const FormatException(
        'GasFree send_raw_transaction response must not be result-wrapped',
      );
    }
    final relayType = json.valueOrNull<String>('relay_type');

    if (relayType != null) {
      final result = json;
      const allowedKeys = {'relay_type', 'trace_id', 'state'};
      final unknownKeys = result.keys.where(
        (key) => !allowedKeys.contains(key),
      );
      if (unknownKeys.isNotEmpty) {
        throw FormatException(
          'GasFree send_raw_transaction response contains unknown fields: '
          '${unknownKeys.join(', ')}',
        );
      }
      return SendRawTransactionResponse(
        mmrpc: json.valueOrNull<String>('mmrpc'),
        relayType: relayType,
        traceId: result.value<String>('trace_id'),
        state: GaslessSubmitState.parse(result.value<String>('state')),
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
  /// confirms through the pre-attached `GASLESS_TRACE:<coin>` stream.
  final String? txHash;

  /// Relay type for a gas-free broadcast (`tron_gasfree`). Null for standard.
  final String? relayType;

  /// Trace handle used to filter streamed updates and perform one-shot
  /// restart or stream-disconnection reconciliation. Null for standard.
  final String? traceId;

  /// Initial provider relay state. Null for standard.
  final GaslessSubmitState? state;

  /// Whether this is a gas-free relay broadcast (no immediate tx hash).
  bool get isGaslessRelay => relayType == 'tron_gasfree';

  @override
  Map<String, dynamic> toJson() => isGaslessRelay
      ? {
          'relay_type': relayType,
          'trace_id': traceId,
          'state': state!.wireValue,
        }
      : {
          'mmrpc': mmrpc,
          'result': {'tx_hash': txHash},
        };
}
