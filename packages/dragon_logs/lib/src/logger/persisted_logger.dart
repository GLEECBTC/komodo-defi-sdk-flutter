import 'dart:async';

import 'package:dragon_logs/src/logger/logger_interface.dart';
import 'package:dragon_logs/src/performance/performance_metrics.dart';
import 'package:dragon_logs/src/storage/log_storage.dart';
import 'package:flutter/foundation.dart';

// TODO: Implement zip export and web-worker export to avoid blocking the UI
// thread when exporting logs on
class PersistedLogger extends LoggerInterface /*with LifecycleManagedMixin*/ {
  final logStorage = LogStorage();

  final _appStartTime = DateTime.now();

  bool isInitialized = false;

  Duration get appRunDuration => DateTime.now().difference(_appStartTime);

  @override
  Future<void> init() async {
    await logStorage.init();

    isInitialized = true;
  }

  @override
  Future<void> log(
    String key,
    String message, {
    Map<String, dynamic>? metadata,
  }) async {
    assert(isInitialized, 'Logger is not initialized');

    final now = DateTime.now();

    final formattedMessage = formatMessage(
      key,
      message,
      now,
      metadata: metadata,
      appRunDuration: appRunDuration,
    );

    final timer = Stopwatch()..start();
    try {
      await logStorage.appendLog(now, formattedMessage);

      timer.stop();
      LogPerformanceMetrics.recordLogTimeWaited(timer.elapsedMicroseconds);
    } catch (e) {
      rethrow;
    } finally {
      timer.stop();
      //
    }

    if (kDebugMode) {
      // TODO: Implement (somewhere else) a way to conditionally print logs
      // to the console for development purposes.
      // scheduleMicrotask(() {
      // print(formattedMessage);
      // });
    }
  }

  @override
  Stream<String> exportLogsStream() {
    return logStorage.exportLogsStream();
  }

  // @override
  // Future<void> appendRawLog(String message) async {
  //   // _logger.appendRawLog(message);
  //   _logStorage.appendLog(DateTime.now(), message);
  // }

  // @override
  // void onDispose() async {
  //   // Any cleanup logic related to PersistedLogger

  //   disposeLifecycleManagement(); // Cleanup lifecycle management from mixin
  // }
}
