import 'package:dragon_logs/src/storage/platform_instance/log_storage_web_platform.dart'
    if (dart.library.io) 'package:dragon_logs/src/storage/platform_instance/log_storage_native_platform.dart'
    if (dart.tool.dart2wasm) 'package:dragon_logs/src/storage/platform_instance/log_storage_wasm_platform.dart';

abstract class LogStorage {
  Future<void> init();
  // Future<Map<DateTime, File>> getLogFiles();
  Future<void> appendLog(DateTime date, String text);
  Future<void> closeLogFile();
  // Future<List<File>> exportLogs();
  Stream<String> exportLogsStream();

  Future<void> exportLogsToDownload();

  Future<void> deleteExportedFiles();

  /// Returns the total size of all logs in bytes.
  Future<int> getLogFolderSize();

  /// Deletes oldest logs until the total size of the log folder is less than
  /// or equal to [size] in bytes.
  Future<void> deleteOldLogs(int size);

  factory LogStorage() => getLogStorageInstance();
}
