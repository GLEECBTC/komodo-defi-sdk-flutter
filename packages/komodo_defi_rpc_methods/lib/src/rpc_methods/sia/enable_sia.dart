import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

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

class TaskEnableSiaStatus
    extends BaseRequest<SiaTaskStatusResponse, GeneralErrorResponse> {
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
  SiaTaskStatusResponse parse(Map<String, dynamic> json) {
    return SiaTaskStatusResponse.parse(json);
  }
}

class TaskEnableSiaCancel
    extends BaseRequest<SiaTaskCancelResponse, GeneralErrorResponse> {
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
  SiaTaskCancelResponse parse(Map<String, dynamic> json) =>
      SiaTaskCancelResponse.parse(json);
}

class SiaTaskStatusResponse extends BaseResponse {
  SiaTaskStatusResponse({
    required super.mmrpc,
    required this.status,
    required this.details,
  });

  factory SiaTaskStatusResponse.parse(Map<String, dynamic> json) {
    final result = json.value<JsonMap>('result');
    return SiaTaskStatusResponse(
      mmrpc: json.value<String>('mmrpc'),
      status: result.value<String>('status'),
      details: result['details'],
    );
  }

  final String status;
  final Object? details;

  bool get isCompleted => status == 'Ok';

  String? get detailsAsString {
    final raw = details;
    if (raw == null) {
      return null;
    }
    return raw.toString();
  }

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {'status': status, 'details': details},
  };
}

class SiaTaskCancelResponse extends BaseResponse {
  SiaTaskCancelResponse({required super.mmrpc, required this.result});

  factory SiaTaskCancelResponse.parse(Map<String, dynamic> json) {
    return SiaTaskCancelResponse(
      mmrpc: json.value<String>('mmrpc'),
      result: json.value<String>('result'),
    );
  }

  final String result;

  @override
  Map<String, dynamic> toJson() => {'mmrpc': mmrpc, 'result': result};
}
