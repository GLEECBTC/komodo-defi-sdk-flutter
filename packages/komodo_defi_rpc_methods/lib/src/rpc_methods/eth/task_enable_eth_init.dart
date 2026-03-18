import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';

class TaskEnableEthInit
    extends BaseRequest<NewTaskResponse, GeneralErrorResponse> {
  TaskEnableEthInit({required this.ticker, required this.params, super.rpcPass})
    : super(method: 'task::enable_eth::init', mmrpc: RpcVersion.v2_0);

  final String ticker;

  @override
  // ignore: overridden_fields
  final ActivationParams params;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'userpass': rpcPass,
    'mmrpc': mmrpc,
    'method': method,
    'params': {'ticker': ticker, ...params.toRpcParams()},
  };

  @override
  NewTaskResponse parse(Map<String, dynamic> json) =>
      NewTaskResponse.parse(json);
}
