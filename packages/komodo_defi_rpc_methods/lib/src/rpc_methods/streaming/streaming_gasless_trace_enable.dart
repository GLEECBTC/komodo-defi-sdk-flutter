import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Enables the coin-scoped GasFree trace event stream.
///
/// KDF emits successful updates as `GASLESS_TRACE:<coin>` and stream errors
/// as `ERROR:GASLESS_TRACE:<coin>`.
class StreamGaslessTraceEnableRequest
    extends
        BaseRequest<
          StreamEnableResponse<GaslessTraceEvent>,
          GaslessTraceStreamingRequestException
        > {
  StreamGaslessTraceEnableRequest({
    required super.rpcPass,
    required this.coin,
    this.clientId,
  }) : super(method: 'stream::gasless_trace::enable', mmrpc: RpcVersion.v2_0);

  final String coin;
  final int? clientId;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {'coin': coin, if (clientId != null) 'client_id': clientId},
  };

  @override
  StreamEnableResponse<GaslessTraceEvent> parse(JsonMap json) =>
      StreamEnableResponse<GaslessTraceEvent>.parse(json);

  @override
  GaslessTraceStreamingRequestException? parseCustomErrorResponse(
    JsonMap json,
  ) => GaslessTraceStreamingRequestException.tryParse(json);
}
