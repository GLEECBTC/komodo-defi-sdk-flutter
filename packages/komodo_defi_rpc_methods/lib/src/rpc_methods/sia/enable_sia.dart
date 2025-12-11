import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request for the `task::enable_sia::init` RPC.
///
/// Starts a task-managed activation flow for a SIA protocol coin and returns
/// a [NewTaskResponse] containing the activation task ID.
class TaskEnableSiaInit
    extends BaseRequest<NewTaskResponse, GeneralErrorResponse> {
  TaskEnableSiaInit({required this.ticker, required this.params, super.rpcPass})
    : super(method: 'task::enable_sia::init', mmrpc: RpcVersion.v2_0);

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
    'params': {'ticker': ticker, 'activation_params': params.toRpcParams()},
  };

  @override
  NewTaskResponse parse(Map<String, dynamic> json) {
    return NewTaskResponse.parse(json);
  }
}

/// Request for the `task::enable_sia::status` RPC.
///
/// Polls the status of an ongoing SIA activation task.
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

/// Request for the `task::enable_sia::cancel` RPC.
///
/// Cancels an ongoing SIA activation task and returns a [SiaCancelResponse]
/// indicating whether the cancel operation was successful.
class TaskEnableSiaCancel
    extends BaseRequest<SiaCancelResponse, GeneralErrorResponse> {
  TaskEnableSiaCancel({required this.taskId, super.rpcPass})
    : super(method: 'task::enable_sia::cancel', mmrpc: RpcVersion.v2_0);

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
  SiaCancelResponse parse(Map<String, dynamic> json) =>
      SiaCancelResponse.parse(json);
}

/// Request for the `task::enable_sia::user_action` RPC.
///
/// Used when the SIA activation flow requires user interaction, such as
/// providing a hardware-wallet PIN or passphrase.
class TaskEnableSiaUserAction
    extends BaseRequest<UserActionResponse, GeneralErrorResponse> {
  TaskEnableSiaUserAction({
    required this.taskId,
    required this.actionType,
    this.pin,
    this.passphrase,
    super.rpcPass,
  }) : super(method: 'task::enable_sia::user_action', mmrpc: RpcVersion.v2_0);

  final int taskId;
  final String actionType;
  final String? pin;
  final String? passphrase;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'userpass': rpcPass,
    'mmrpc': mmrpc,
    'method': method,
    'params': {
      'task_id': taskId,
      'user_action': {
        'action_type': actionType,
        if (pin != null) 'pin': pin,
        if (passphrase != null) 'passphrase': passphrase,
      },
    },
  };

  @override
  UserActionResponse parse(Map<String, dynamic> json) =>
      UserActionResponse.parse(JsonMap.of(json));
}

/// Response returned by the `task::enable_sia::cancel` RPC.
///
/// Wraps a simple [result] string, which is `"success"` on success.
class SiaCancelResponse extends BaseResponse {
  SiaCancelResponse({required super.mmrpc, required this.result});

  factory SiaCancelResponse.parse(Map<String, dynamic> json) {
    return SiaCancelResponse(
      mmrpc: json.value<String>('mmrpc'),
      result: json.value<String>('result'),
    );
  }

  final String result;

  @override
  Map<String, dynamic> toJson() => {'mmrpc': mmrpc, 'result': result};
}
