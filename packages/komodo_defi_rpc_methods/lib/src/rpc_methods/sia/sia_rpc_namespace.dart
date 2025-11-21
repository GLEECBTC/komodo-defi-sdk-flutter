import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// High-level namespace for SIA-specific RPC methods.
///
/// Provides typed helpers over the raw `task::enable_sia::*` APIs.
class SiaMethodsNamespace extends BaseRpcMethodNamespace {
  SiaMethodsNamespace(super.client);

  /// Initialize SIA activation using `task::enable_sia::init`.
  ///
  /// Returns a [NewTaskResponse] with the activation task ID.
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

  /// Get activation status using `task::enable_sia::status`.
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

  /// Cancel an activation task using `task::enable_sia::cancel`.
  ///
  /// Returns a [SiaCancelResponse] that indicates success or failure.
  Future<SiaCancelResponse> enableSiaCancel({required int taskId}) {
    return execute(
      TaskEnableSiaCancel(taskId: taskId, rpcPass: rpcPass),
    );
  }

  /// Provide user interaction for SIA activation via `task::enable_sia::user_action`.
  ///
  /// Typically used to pass Trezor PIN or passphrase when required.
  Future<UserActionResponse> enableSiaUserAction({
    required int taskId,
    required String actionType,
    String? pin,
    String? passphrase,
  }) {
    return execute(
      TaskEnableSiaUserAction(
        taskId: taskId,
        actionType: actionType,
        pin: pin,
        passphrase: passphrase,
        rpcPass: rpcPass,
      ),
    );
  }
}

