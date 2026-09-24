import 'package:dragon_logs/src/storage/queue_mixin.dart';

class LogStorageConfiguration {
  LogStorageConfiguration({String? storageNamespace, this.purgeLegacy = false})
    : namespace = storageNamespace ?? legacyNamespace {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$').hasMatch(namespace) ||
        (purgeLegacy && namespace == legacyNamespace)) {
      throw ArgumentError('Invalid log storage namespace');
    }
  }

  static const legacyNamespace = 'dragon_logs';
  final String namespace;
  final bool purgeLegacy;

  bool matches(LogStorageConfiguration other) =>
      namespace == other.namespace && purgeLegacy == other.purgeLegacy;
}

/// Safe to report without disclosing paths, record contents, or platform errors.
class LogStorageInitializationException implements Exception {
  const LogStorageInitializationException();

  @override
  String toString() => 'Log storage initialization failed';
}

mixin LogStorageLifecycle on QueueMixin {
  Future<void>? _initialization;
  LogStorageConfiguration? _configuration;
  bool _ready = false;
  bool _disposing = false;

  Future<void> initializeStorage(
    LogStorageConfiguration configuration,
    Future<void> Function() initialize,
  ) {
    if (_disposing) throw StateError('Log storage is closing');
    if (_configuration != null && !_configuration!.matches(configuration)) {
      // Never move a queued record from one privacy epoch into another.
      throw StateError('Close log storage before changing its namespace');
    }
    final pending = _initialization;
    if (pending != null) return pending;
    _configuration = configuration;
    final result = Future<void>.sync(() async {
      try {
        await initialize();
        initQueueFlusher();
        _ready = true;
      } catch (_) {
        stopQueueFlusher();
        discardQueuedLogs();
        _configuration = null;
        _initialization = null;
        throw const LogStorageInitializationException();
      }
    });
    _initialization = result;
    return result;
  }

  Future<void> requireStorageReady() async {
    final initialization = _initialization;
    if (initialization == null || _disposing) {
      throw StateError('Log storage is not ready');
    }
    await initialization;
    if (!_ready || _disposing) throw StateError('Log storage is not ready');
  }

  Future<void> disposeStorage() async {
    if (_disposing) throw StateError('Log storage is closing');
    // Await an in-progress migration before stopping its newly started timer.
    try {
      await _initialization;
    } catch (_) {
      // Failed initialization has no usable storage or accepted queue.
    }
    _disposing = true;
    stopQueueFlusher();
    try {
      // writeToTextFile is an internal drain primitive; it must not require
      // readiness again while disposal is waiting for it.
      if (_ready) await flushQueue();
    } finally {
      discardQueuedLogs();
      _ready = false;
      _initialization = null;
      _configuration = null;
      _disposing = false;
    }
  }
}
