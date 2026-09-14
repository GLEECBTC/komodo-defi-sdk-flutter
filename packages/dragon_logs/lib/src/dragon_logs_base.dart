import 'dart:async';
import 'dart:convert';

import 'package:dragon_logs/src/logger/persisted_logger.dart';
// import 'package:dragon_logs/src/performance/performance_metrics.dart';

/// The main logging class for DragonLogs.
class DragonLogs {
  DragonLogs._();

  static final _instance = DragonLogs._();

  // 100 MB
  static final int _maxLogStorageSize = 100 * 1024 * 1024; // 100 MB

  Map<String, dynamic>? _metadata = {};

  static final _logger = PersistedLogger();
  static Future<void>? _initialization;

  /// Initializes the DragonLogs system.
  ///
  /// This method should be called before any logging operation. It sets up
  /// the logger and ensures any old logs that exceed the maximum storage size
  /// are deleted.
  static Future<void> init({
    String? storageNamespace,
    bool purgeLegacy = false,
  }) {
    final result = () async {
      await _logger.init(
        storageNamespace: storageNamespace,
        purgeLegacy: purgeLegacy,
      );
      await _logger.logStorage.deleteOldLogs(_maxLogStorageSize);
    }();
    _initialization = result;
    return result;
  }

  static Future<void> _requireReady() async {
    final initialization = _initialization;
    if (initialization == null) throw StateError('Log storage is not ready');
    await initialization;
  }

  /// Writes one caller-sanitized JSON object without legacy message or metadata
  /// decoration. The caller is responsible for the record's privacy schema.
  static Future<void> writeRecord(String record) async {
    await _requireReady();
    if (record.contains('\n') || record.contains('\r')) {
      throw ArgumentError('A log record must occupy one line');
    }
    try {
      if (jsonDecode(record) is! Map<String, dynamic>) {
        throw const FormatException();
      }
    } on FormatException {
      throw ArgumentError('A log record must be a JSON object');
    }
    await _logger.writeRecord(record);
  }

  /// Stops background flushing and closes storage before another namespace can
  /// be selected. Pending records stay in their original namespace.
  static Future<void> dispose() async {
    try {
      await _logger.dispose();
    } finally {
      _initialization = null;
      _instance._metadata = null;
    }
  }

  /// Sets the session metadata for the logger.
  ///
  /// Session metadata is attached to logs and can be used to provide additional
  /// context to log entries.
  ///
  /// - Parameter [metadata]: The metadata to be attached to log entries.
  static void setSessionMetadata(Map<String, dynamic> metadata) {
    _instance._metadata = metadata;

    log('Session metadata set: $metadata');
  }

  static Map<String, dynamic>? get sessionMetadata => _instance._metadata;

  /// Exports the logs as a stream of strings.
  ///
  /// - Returns: A stream emitting each a non-uniform chunk of the logs. The
  ///  stream is closed when all logs have been emitted.
  static Stream<String> exportLogsStream() async* {
    await _requireReady();
    yield* _logger.exportLogsStream();
  }

  /// Exports all logs as a single concatenated string.
  ///
  /// - Returns: A future that completes with the concatenated log entries as a string.
  ///
  /// **Note**: This method is not recommended for large log files as it will
  /// load the entire log file into memory.
  static Future<String> exportLogsString() async {
    final buffer = StringBuffer();

    await for (final log in exportLogsStream()) {
      buffer.write(log);
    }

    return buffer.toString();
  }

  /// Exports the stored logs for download.
  ///
  /// Depending on the platform, this might trigger a save-as/share or store
  /// the logs in a specific directory (e.g. default downloads directory)
  ///
  /// - Returns: A future that completes once the user has saved the logs.
  static Future<void> exportLogsToDownload() async {
    await _requireReady();
    await _logger.logStorage.exportLogsToDownload();
  }

  /// Gets the size of the log storage folder.
  ///
  /// - Returns: A future that completes with the size in bytes.
  static Future<int> getLogFolderSize() async {
    await _requireReady();
    return _logger.logStorage.getLogFolderSize();
  }

  /// Clears the session metadata.
  ///
  /// After this method is called, logs will no longer have the previously set metadata attached.
  static void clearSessionMetadata() {
    _instance._metadata = null;
  }

  /// Clears all logs.
  static Future<void> clearLogs() async {
    await _requireReady();
    await _logger.logStorage.deleteOldLogs(0);
    await _logger.logStorage.deleteExportedFiles();
  }

  /// A summary of the logger's performance metrics.
  ///
  /// This provides insights into the performance of the DragonLogs system.
  // static String get perfomanceMetricsSummary => LogPerformanceMetrics.summary;
}

/// Logs a message with an optional key.
///
/// - Parameter [message]: The message to be logged.
/// - Parameter [key]: An optional key to categorize the log. Defaults to 'LOG'.
void log(String message, [String key = 'LOG']) {
  unawaited(
    DragonLogs._logger
        .log(key, message, metadata: DragonLogs._instance._metadata)
        .catchError((Object _) {}),
  );
}
