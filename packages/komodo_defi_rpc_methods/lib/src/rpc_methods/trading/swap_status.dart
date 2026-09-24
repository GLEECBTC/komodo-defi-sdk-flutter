import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get swap status
class SwapStatusRequest
    extends BaseRequest<SwapStatusResponse, GeneralErrorResponse> {
  SwapStatusRequest({
    required String rpcPass,
    required this.uuid,
  }) : super(
         method: 'my_swap_status',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  final String uuid;

  @override
  Map<String, dynamic> toJson() {
    return super.toJson().deepMerge({
      'params': {
        'uuid': uuid,
      },
    });
  }

  @override
  SwapStatusResponse parse(Map<String, dynamic> json) =>
      SwapStatusResponse.parse(json);
}

/// Response containing swap status
class SwapStatusResponse extends BaseResponse {
  SwapStatusResponse({
    required super.mmrpc,
    required this.swapInfo,
  });

  factory SwapStatusResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    // The v2 `my_swap_status` wraps the saved swap as
    // `{swap_type, swap_data}`; the legacy method returns it bare.
    final swapData = result.valueOrNull<JsonMap>('swap_data') ?? result;

    return SwapStatusResponse(
      mmrpc: json.value<String>('mmrpc'),
      swapInfo: SwapInfo.fromJson(swapData),
    );
  }

  final SwapInfo swapInfo;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': swapInfo.toJson(),
  };
}