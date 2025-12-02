import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class TaskEnableSiaInit
    extends BaseRequest<NewTaskResponse, GeneralErrorResponse> {
  TaskEnableSiaInit({
    required this.ticker,
    required this.params,
    super.rpcPass,
  }) : super(method: 'task::enable_sia::init', mmrpc: RpcVersion.v2_0);

  final String ticker;

  @override
  // ignore: overridden_fields
  final SiaActivationParams params;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'userpass': rpcPass,
        'mmrpc': mmrpc,
        'method': method,
        'params': {
          'ticker': ticker,
          'activation_params': params.toRpcParams(),
        },
      };

  @override
  NewTaskResponse parse(Map<String, dynamic> json) {
    return NewTaskResponse.parse(json);
  }
}

class TaskEnableSiaStatus
    extends BaseRequest<TaskStatusResponse, GeneralErrorResponse> {
  TaskEnableSiaStatus({
    required this.taskId,
    this.forgetIfFinished = true,
    super.rpcPass,
  }) : super(method: 'task::enable_sia::status', mmrpc: RpcVersion.v2_0);

  final int taskId;
  final bool forgetIfFinished;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'userpass': rpcPass,
        'mmrpc': mmrpc,
        'method': method,
        'params': {'task_id': taskId, 'forget_if_finished': forgetIfFinished},
      };

  @override
  TaskStatusResponse parse(Map<String, dynamic> json) {
    return TaskStatusResponse.parse(json);
  }
}

class TaskEnableSiaCancel
    extends BaseRequest<TaskStatusResponse, GeneralErrorResponse> {
  TaskEnableSiaCancel({
    required this.taskId,
    super.rpcPass,
  }) : super(method: 'task::enable_sia::cancel', mmrpc: RpcVersion.v2_0);

  final int taskId;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'userpass': rpcPass,
        'mmrpc': mmrpc,
        'method': method,
        'params': {'task_id': taskId},
      };

  @override
  TaskStatusResponse parse(Map<String, dynamic> json) =>
      TaskStatusResponse.parse(json);
}

