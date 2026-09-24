import 'dart:async';

mixin QueueMixin {
  List<String> _logQueue = [];
  Completer<void>? _flushCompleter;
  bool _isQueueEnabled = false;

  void initQueueFlusher() {
    if (_isQueueEnabled) return;

    _isQueueEnabled = true;

    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      await flushQueue().catchError((e) {
        print('Error flushing log queue: $e');
      });
      return _isQueueEnabled;
    }).ignore();
  }

  bool get isFlushing => _flushCompleter != null;

  void enqueue(String log) {
    _logQueue.add(log);
  }

  Future<void> startFlush() async {
    // assert(_flushCompleter == null, 'Flush already in progress');

    while (isFlushing) {
      await (_flushCompleter?.future ?? Future.delayed(Duration(seconds: 1)));
    }

    _flushCompleter ??= Completer<void>();
  }

  void endFlush() {
    _flushCompleter?.complete();
    _flushCompleter = null;
  }

  Future<void> flushQueue() async {
    if (_logQueue.isEmpty) return;

    startFlush();

    // This way of re-assigning the queue instead of mutating it helps reduce
    // memory use and CPU to copy the object. It should be safe from race
    // conditions, but if issues arrise, pay attention to these lines.
    final List<String> toWrite = _logQueue;

    _logQueue = [];

    try {
      final logConcat = StringBuffer();

      logConcat.writeAll(toWrite, '\n');

      final bufferWritten = logConcat.toString();

      await writeToTextFile(bufferWritten);
    } catch (e) {
      _logQueue.add('FAILED TO WRITE LOGS: $e');
      _logQueue.insertAll(0, toWrite);
    } finally {
      endFlush();
    }
  }

  Future<void> appendLog(DateTime date, String text) async {
    enqueue(text);
  }

  /// Writes a String to the log text file for today.
  Future<void> writeToTextFile(String logs);
}
