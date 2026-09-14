import 'dart:async';

/// Serializes queue drains and storage snapshots within one logger instance.
mixin QueueMixin {
  List<String> _logQueue = [];
  Future<void> _operations = Future<void>.value();
  Timer? _flushTimer;
  bool _acceptingLogs = false;

  void initQueueFlusher() {
    if (_acceptingLogs) return;
    _acceptingLogs = true;
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Retain failed batches for a later flush. Never log the exception: it
      // may contain the record whose persistence failed.
      flushQueue().catchError((Object _) {});
    });
  }

  void stopQueueFlusher() {
    _acceptingLogs = false;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  void discardQueuedLogs() => _logQueue = [];

  void enqueue(String log) {
    if (!_acceptingLogs) throw StateError('Log storage is not ready');
    _logQueue.add(log);
  }

  Future<T> serializeStorage<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _flushQueuedLogs() async {
    if (_logQueue.isEmpty) return;
    final batch = _logQueue;
    _logQueue = [];
    try {
      await writeToTextFile(batch.join('\n'));
    } catch (_) {
      _logQueue.insertAll(0, batch);
      rethrow;
    }
  }

  Future<void> flushQueue() => serializeStorage(_flushQueuedLogs);

  /// The queue is drained and the operation finishes before another local
  /// flush, export, or retention operation can run.
  Future<T> withFlushedQueue<T>(Future<T> Function() operation) =>
      serializeStorage(() async {
        await _flushQueuedLogs();
        return operation();
      });

  Future<void> appendLog(DateTime date, String text) async => enqueue(text);

  Future<void> writeToTextFile(String logs);
}
