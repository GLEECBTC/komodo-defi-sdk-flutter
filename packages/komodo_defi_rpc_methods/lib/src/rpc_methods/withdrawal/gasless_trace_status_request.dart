import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Lifecycle state of a gas-free (gasless) transfer, as reported by
/// `gasless::trace_status`.
enum GaslessTraceState {
  pending,
  submitted,
  onChain,
  confirmed,
  failed;

  /// Parse KDF's stable lowercase state contract.
  static GaslessTraceState parse(String value) => switch (value) {
    'pending' => GaslessTraceState.pending,
    'submitted' => GaslessTraceState.submitted,
    'on_chain' => GaslessTraceState.onChain,
    'confirmed' => GaslessTraceState.confirmed,
    'failed' => GaslessTraceState.failed,
    _ => throw const FormatException('Unknown GasFree trace state'),
  };

  String get jsonValue => switch (this) {
    GaslessTraceState.pending => 'pending',
    GaslessTraceState.submitted => 'submitted',
    GaslessTraceState.onChain => 'on_chain',
    GaslessTraceState.confirmed => 'confirmed',
    GaslessTraceState.failed => 'failed',
  };

  /// Whether the transfer has reached a terminal state.
  bool get isTerminal =>
      this == GaslessTraceState.confirmed || this == GaslessTraceState.failed;

  /// Whether the transfer completed successfully.
  bool get isConfirmed => this == GaslessTraceState.confirmed;

  /// Whether the transfer failed.
  bool get isFailed => this == GaslessTraceState.failed;
}

/// Fetches one authoritative GasFree transfer snapshot by trace id.
///
/// Use this once immediately after submission and for restart or stream
/// disconnection recovery. Steady-state updates come from the pre-attached
/// `GASLESS_TRACE:<coin>` stream.
class GaslessTraceStatusRequest
    extends
        BaseRequest<GaslessTraceStatusResponse, GaslessTraceStatusException> {
  GaslessTraceStatusRequest({
    required super.rpcPass,
    required this.coin,
    required this.traceId,
  }) : super(method: 'gasless::trace_status', mmrpc: RpcVersion.v2_0);

  final String coin;
  final String traceId;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': {'coin': coin, 'trace_id': traceId},
  };

  @override
  GaslessTraceStatusResponse parse(Map<String, dynamic> json) =>
      GaslessTraceStatusResponse.parse(json);

  @override
  GaslessTraceStatusException? parseCustomErrorResponse(JsonMap json) =>
      GaslessTraceStatusException.tryParse(json);
}

class GaslessTraceStatusResponse extends BaseResponse {
  GaslessTraceStatusResponse({
    required super.mmrpc,
    required this.state,
    this.txHashOnChain,
    this.blockHeight,
    this.confirmedAt,
    this.finalFee,
    this.failureReason,
  }) {
    if (state == GaslessTraceState.failed && failureReason != 'unknown') {
      throw const FormatException(
        'A failed GasFree trace must have failure_reason "unknown"',
      );
    }
    if (state != GaslessTraceState.failed && failureReason != null) {
      throw const FormatException(
        'Only a failed GasFree trace may include failure_reason',
      );
    }
  }

  factory GaslessTraceStatusResponse.parse(Map<String, dynamic> json) {
    final result = json.valueOrNull<JsonMap>('result');
    if (result == null) {
      throw const FormatException(
        'GasFree trace status requires an MMRPC result envelope',
      );
    }
    const allowedKeys = {
      'state',
      'tx_hash_on_chain',
      'block_height',
      'confirmed_at',
      'final_fee',
      'failure_reason',
    };
    final missingKeys = allowedKeys.where((key) => !result.containsKey(key));
    if (missingKeys.isNotEmpty) {
      throw FormatException(
        'GasFree trace status is missing fields serialized by KDF: '
        '${missingKeys.join(', ')}',
      );
    }
    final unknownKeys = result.keys.where((key) => !allowedKeys.contains(key));
    if (unknownKeys.isNotEmpty) {
      throw FormatException(
        'GasFree trace status contains unknown fields: '
        '${unknownKeys.join(', ')}',
      );
    }
    final finalFeeRaw = result['final_fee'];
    if (finalFeeRaw != null && finalFeeRaw is! String) {
      throw const FormatException(
        'GasFree final_fee must be a numeric string or null',
      );
    }
    final confirmedAt = result.valueOrNull<int>('confirmed_at');
    if (confirmedAt != null && confirmedAt < 0) {
      throw const FormatException(
        'GasFree confirmed_at must be a non-negative integer',
      );
    }
    final blockHeight = result.valueOrNull<int>('block_height');
    if (blockHeight != null && blockHeight < 0) {
      throw const FormatException(
        'GasFree block_height must be a non-negative integer',
      );
    }
    final finalFee = finalFeeRaw == null
        ? null
        : Decimal.parse(finalFeeRaw as String);
    if (finalFee != null && finalFee < Decimal.zero) {
      throw const FormatException(
        'GasFree final_fee must be a non-negative numeric string',
      );
    }
    return GaslessTraceStatusResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      state: GaslessTraceState.parse(result.value<String>('state')),
      txHashOnChain: result.valueOrNull<String>('tx_hash_on_chain'),
      blockHeight: blockHeight,
      confirmedAt: confirmedAt,
      finalFee: finalFee,
      failureReason: result.valueOrNull<String>('failure_reason'),
    );
  }

  final GaslessTraceState state;
  final String? txHashOnChain;
  final int? blockHeight;
  final int? confirmedAt;
  final Decimal? finalFee;
  final String? failureReason;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'state': state.jsonValue,
      'tx_hash_on_chain': txHashOnChain,
      'block_height': blockHeight,
      'confirmed_at': confirmedAt,
      'final_fee': finalFee?.toString(),
      'failure_reason': failureReason,
    },
  };
}
