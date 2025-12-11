import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// A class that helps with executing task-based RPC methods by removing
/// the boilerplate code for watching the status of a task.
class TaskShepherd {
  /// Executes a task-based RPC method and returns a stream that emits the
  /// status of the task until it is complete.
  ///
  /// The [initTask] function should return a [NewTaskResponse] that contains
  /// the task ID.
  ///
  /// The [getTaskStatus] function should return the current status of the task
  /// given the task ID.
  ///
  /// The [checkTaskStatus] function should return true if the task is complete.
  ///
  /// The [cancelTask] function can be used to cancel the task if needed.
  /// If provided, it will be called when the stream is canceled by the
  /// consumer.
  /// It will NOT be called when the task completes naturally.
  /// If not provided, the task cannot be canceled and cancelling the stream
  /// will not cancel the task.
  ///
  /// Note: For event-based task watching, use the `KdfEventStreamingService`
  /// with `taskEventsForId()` method to listen for task updates instead of
  /// polling. This provides real-time updates with lower latency and reduced
  /// RPC calls.
  static Stream<T> executeTask<T extends BaseResponse>({
    required Future<NewTaskResponse> Function() initTask,
    required Future<T> Function(int taskId) getTaskStatus,
    required bool Function(T) checkTaskStatus,
    Future<void> Function(int taskId)? cancelTask,
    Duration pollingInterval = const Duration(seconds: 1),
    Duration Function(T status)? pollingIntervalForStatus,
  }) {
    final controller = StreamController<T>();
    var taskCompletedNaturally = false;

    scheduleMicrotask(() async {
      try {
        final initResponse = await initTask();
        final taskId = initResponse.taskId;

        if (cancelTask != null) {
          controller.onCancel = () async {
            // Only call cancelTask if the task didn't complete naturally
            if (!taskCompletedNaturally) {
              await cancelTask(taskId);
            }
          };
        }

        var isPaused = false;
        controller
          ..onPause = (() => isPaused = true)
          ..onResume = (() => isPaused = false);

        T? lastResult;

        while (!controller.isClosed) {
          if (isPaused) {
            await Future<void>.delayed(pollingInterval);
            continue;
          }

          final status = await getTaskStatus(taskId);

          if (status != lastResult) {
            controller.add(status);
            lastResult = status;
          }

          if (checkTaskStatus(status)) {
            // Mark task as naturally completed before closing the controller
            taskCompletedNaturally = true;
            controller.onCancel = null;
            await controller.close();
            return;
          }

          final nextDelay =
              pollingIntervalForStatus != null ? pollingIntervalForStatus(status) : null;
          await Future<void>.delayed(nextDelay ?? pollingInterval);
        }
      } catch (e, stackTrace) {
        controller.addError(e, stackTrace);
        await controller.close();
      }
    });

    return controller.stream;
  }
}

extension TaskRpcBuddy on NewTaskResponse {
  Stream<T> watch<T extends BaseResponse>({
    required Future<T> Function(int taskId) getTaskStatus,
    required bool Function(T) isTaskComplete,
    Future<void> Function(int taskId)? cancelTask,
    Duration pollingInterval = const Duration(seconds: 1),
    Duration Function(T status)? pollingIntervalForStatus,
  }) {
    return TaskShepherd.executeTask<T>(
      initTask: () async => this,
      getTaskStatus: getTaskStatus,
      checkTaskStatus: isTaskComplete,
      cancelTask: cancelTask,
      pollingInterval: pollingInterval,
      pollingIntervalForStatus: pollingIntervalForStatus,
    );
  }
}

extension TaskRpcBuddyFuture on Future<NewTaskResponse> {
  Stream<T> watch<T extends BaseResponse>({
    required Future<T> Function(int taskId) getTaskStatus,
    required bool Function(T) isTaskComplete,
    Future<void> Function(int taskId)? cancelTask,
    Duration pollingInterval = const Duration(seconds: 1),
    Duration Function(T status)? pollingIntervalForStatus,
  }) {
    return TaskShepherd.executeTask<T>(
      initTask: () async => this,
      getTaskStatus: getTaskStatus,
      checkTaskStatus: isTaskComplete,
      cancelTask: cancelTask,
      pollingInterval: pollingInterval,
      pollingIntervalForStatus: pollingIntervalForStatus,
    );
  }
}
