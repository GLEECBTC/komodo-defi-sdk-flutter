import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class SiaMethodsNamespace extends BaseRpcMethodNamespace {
  SiaMethodsNamespace(super.client);

  Future<NewTaskResponse> enableSiaInit({
    required String ticker,
    required SiaActivationParams params,
  }) {
    return execute(
      TaskEnableSiaInit(
        rpcPass: rpcPass ?? '',
        ticker: ticker,
        params: params,
      ),
    );
  }

  Future<TaskStatusResponse> enableSiaStatus(
    int taskId, {
    bool forgetIfFinished = true,
  }) {
    return execute(
      TaskEnableSiaStatus(
        taskId: taskId,
        forgetIfFinished: forgetIfFinished,
        rpcPass: rpcPass,
      ),
    );
  }

  Future<BaseResponse> enableSiaCancel({required int taskId}) {
    return execute(
      TaskEnableSiaCancel(taskId: taskId, rpcPass: rpcPass),
    );
  }
}

