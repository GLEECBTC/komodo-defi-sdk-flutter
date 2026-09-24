import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dragon_logs/src/storage/input_output_mixin.dart';
import 'package:dragon_logs/src/storage/log_storage.dart';
import 'package:dragon_logs/src/storage/opfs_interop.dart';
import 'package:dragon_logs/src/storage/queue_mixin.dart';
import 'package:intl/intl.dart';
import 'package:web/web.dart';

/// WASM-compatible web log storage implementation using OPFS
class WebLogStorageWasm
    with QueueMixin, CommonLogStorageOperations
    implements LogStorage {
  FileSystemDirectoryHandle? _logDirectory;
  FileSystemFileHandle? _currentLogFile;
  FileSystemWritableFileStream? _currentLogStream;
  String _currentLogFileName = "";

  @override
  Future<void> init() async {
    final now = DateTime.now();
    _currentLogFileName = logFileNameOfDate(now);

    // Get the OPFS root directory
    final storageManager = window.navigator.storage;
    final root = await storageManager.getDirectory().toDart;

    // Create or get the dragon_logs directory
    _logDirectory =
        await root
            .getDirectoryHandle(
              "dragon_logs",
              FileSystemGetDirectoryOptions(create: true),
            )
            .toDart;

    initQueueFlusher();
  }

  @override
  Future<void> writeToTextFile(String logs) async {
    if (_currentLogStream == null) {
      await initWriteDate(DateTime.now());
    }

    try {
      await _currentLogStream!.write('$logs\n'.toJS).toDart;
      await closeLogFile();
      await initWriteDate(DateTime.now());
    } catch (e) {
      rethrow;
    }
  }

  Future<void> initWriteDate(DateTime date) async {
    await closeLogFile();

    _currentLogFileName = logFileNameOfDate(date);

    _currentLogFile =
        await _logDirectory!
            .getFileHandle(
              _currentLogFileName,
              FileSystemGetFileOptions(create: true),
            )
            .toDart;

    final file = await _currentLogFile!.getFile().toDart;
    final sizeBytes = file.size.toInt();

    _currentLogStream =
        await _currentLogFile!
            .createWritable(
              FileSystemCreateWritableOptions(keepExistingData: true),
            )
            .toDart;

    await _currentLogStream!.seek(sizeBytes).toDart;
  }

  @override
  Future<void> deleteOldLogs(int size) async {
    await startFlush();

    try {
      while (await getLogFolderSize() > size) {
        final files = await _getLogFiles();

        final sortedFiles =
            files
                .where(
                  (handle) => CommonLogStorageOperations.isLogFileNameValid(
                    handle.name,
                  ),
                )
                .toList()
              ..sort((a, b) {
                final aDate = CommonLogStorageOperations.tryParseLogFileDate(
                  a.name,
                );
                final bDate = CommonLogStorageOperations.tryParseLogFileDate(
                  b.name,
                );

                if (aDate == null || bDate == null) {
                  return 0;
                }

                return aDate.compareTo(bDate);
              });

        if (sortedFiles.isEmpty) {
          break;
        }

        await _logDirectory!
            .removeEntry(
              sortedFiles.first.name,
              FileSystemRemoveOptions(recursive: false),
            )
            .toDart;
      }
    } catch (e) {
      rethrow;
    } finally {
      endFlush();
    }
  }

  @override
  Future<int> getLogFolderSize() async {
    final files = await _getLogFiles();

    int totalSize = 0;
    for (final handle in files) {
      final file = await handle.getFile().toDart;
      totalSize += file.size.toInt();
    }

    return totalSize;
  }

  @override
  Future<void> closeLogFile() async {
    if (_currentLogStream != null) {
      await _currentLogStream!.close().toDart;
      _currentLogStream = null;
    }
  }

  @override
  Stream<String> exportLogsStream() async* {
    final files = await _getLogFiles();

    for (final fileHandle in files) {
      final file = await fileHandle.getFile().toDart;
      final content = await _readFileContent(file);
      yield content;
    }
  }

  /// Returns a list of OPFS file handles for all log files EXCLUDING any
  /// temporary write file (if it exists) identified by the `.crswap` extension.
  Future<List<FileSystemFileHandle>> _getLogFiles() async {
    final files = <FileSystemFileHandle>[];

    // Use the async iterator provided by FileSystemDirectoryHandle.values()
    // via our custom interop extension
    await for (final handle in _logDirectory!.valuesStream()) {
      if (handle.kind == 'file' && !handle.name.endsWith('.crswap')) {
        files.add(handle as FileSystemFileHandle);
      }
    }

    files.sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  Future<String> _readFileContent(File file) async {
    final completer = Completer<String>();
    final reader = FileReader();

    reader.onLoadEnd.listen((event) {
      final result = reader.result;
      if (result != null) {
        completer.complete(result.toString());
      } else {
        completer.complete('');
      }
    });

    reader.readAsText(file);
    return completer.future;
  }

  @override
  Future<void> deleteExportedFiles() async {
    // Since it's a web implementation, we just need to ensure necessary permissions.
    // Note: Real-world applications should handle permissions gracefully, prompting users as needed.
  }

  @override
  Future<void> exportLogsToDownload() async {
    final bytesStream = exportLogsStream().asyncExpand((event) {
      return Stream.fromIterable(event.codeUnits);
    });

    final formatter = DateFormat('yyyyMMdd_HHmmss');
    final filename = 'log_${formatter.format(DateTime.now())}.txt';

    final bytes = await bytesStream.toList();
    final blob = Blob([Uint8List.fromList(bytes).toJS].toJS);
    final url = URL.createObjectURL(blob);

    final anchor =
        HTMLAnchorElement()
          ..href = url
          ..download = filename
          ..style.display = 'none';

    document.body!.appendChild(anchor);
    anchor.click();
    document.body!.removeChild(anchor);
    URL.revokeObjectURL(url);
  }

  void dispose() async {
    await closeLogFile();
  }
}
