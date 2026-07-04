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

  /// Parse a snake_case state string from KDF. Unknown / `WAITING` values map
  /// to [pending] (still in flight).
  static GaslessTraceState parse(String value) => switch (value.toLowerCase()) {
    'pending' => GaslessTraceState.pending,
    'submitted' => GaslessTraceState.submitted,
    'on_chain' => GaslessTraceState.onChain,
    'confirmed' => GaslessTraceState.confirmed,
    'failed' => GaslessTraceState.failed,
    _ => GaslessTraceState.pending,
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

/// Polls the status of a gas-free (gasless) transfer by its trace id.
class GaslessTraceStatusRequest
    extends BaseRequest<GaslessTraceStatusResponse, GeneralErrorResponse> {
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
  });

  factory GaslessTraceStatusResponse.parse(Map<String, dynamic> json) {
    final result = json.valueOrNull<JsonMap>('result') ?? json;
    final finalFeeRaw = result.valueOrNull<dynamic>('final_fee');
    return GaslessTraceStatusResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      state: GaslessTraceState.parse(result.value<String>('state')),
      txHashOnChain: result.valueOrNull<String>('tx_hash_on_chain'),
      blockHeight: result.valueOrNull<int>('block_height'),
      confirmedAt: result.valueOrNull<int>('confirmed_at'),
      finalFee: finalFeeRaw == null
          ? null
          : Decimal.parse(finalFeeRaw.toString()),
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
      if (txHashOnChain != null) 'tx_hash_on_chain': txHashOnChain,
      if (blockHeight != null) 'block_height': blockHeight,
      if (confirmedAt != null) 'confirmed_at': confirmedAt,
      if (finalFee != null) 'final_fee': finalFee.toString(),
      if (failureReason != null) 'failure_reason': failureReason,
    },
  };
}
