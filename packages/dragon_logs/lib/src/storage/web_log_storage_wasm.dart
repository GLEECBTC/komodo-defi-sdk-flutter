import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:dragon_logs/src/storage/input_output_mixin.dart';
import 'package:dragon_logs/src/storage/log_storage.dart';
import 'package:dragon_logs/src/storage/opfs_interop.dart';
import 'package:dragon_logs/src/storage/queue_mixin.dart';
import 'package:dragon_logs/src/storage/storage_lifecycle.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:web/web.dart';

/// Browser and Wasm storage share the same OPFS implementation. The lock covers
/// the entire read/append/commit transaction, including migration and snapshots.
class WebLogStorageWasm
    with QueueMixin, LogStorageLifecycle, CommonLogStorageOperations
    implements LogStorage {
  WebLogStorageWasm() : _directoryProvider = null, _lockOverride = null;

  @visibleForTesting
  WebLogStorageWasm.forTesting({
    required Future<FileSystemDirectoryHandle> Function() directoryProvider,
    Future<void> Function(Future<void> Function())? lock,
  }) : _directoryProvider = directoryProvider,
       _lockOverride = lock;

  static const _lockName = 'dragon-logs-storage';
  final Future<FileSystemDirectoryHandle> Function()? _directoryProvider;
  final Future<void> Function(Future<void> Function())? _lockOverride;
  FileSystemDirectoryHandle? _logDirectory;

  /// Entries under `log_export` that a running export still reads. Export
  /// bodies deliberately run outside the storage queue, so a concurrent clear
  /// has to skip these rather than invalidate a snapshot that is being read.
  final Set<String> _retainedExports = {};

  @override
  Future<void> init({String? storageNamespace, bool purgeLegacy = false}) {
    final configuration = LogStorageConfiguration(
      storageNamespace: storageNamespace,
      purgeLegacy: purgeLegacy,
    );
    return initializeStorage(configuration, () async {
      final root =
          await (_directoryProvider?.call() ??
              window.navigator.storage.getDirectory().toDart);
      await _withStorageLock(() async {
        FileSystemDirectoryHandle? active;
        try {
          active = await root
              .getDirectoryHandle(configuration.namespace)
              .toDart;
        } on DOMException catch (error) {
          if (error.name != 'NotFoundError') rethrow;
        }
        if (active == null) {
          if (configuration.purgeLegacy) {
            try {
              await root
                  .removeEntry(
                    LogStorageConfiguration.legacyNamespace,
                    FileSystemRemoveOptions(recursive: true),
                  )
                  .toDart;
            } on DOMException catch (error) {
              if (error.name != 'NotFoundError') rethrow;
            }
          }
          // Existence marks a successfully completed migration. Do not create
          // this directory after failed legacy deletion, and never import old
          // files. Old clients cannot write into the new namespace.
          active = await root
              .getDirectoryHandle(
                configuration.namespace,
                FileSystemGetDirectoryOptions(create: true),
              )
              .toDart;
        }
        _logDirectory = active;
      });
    });
  }

  Future<T> _withStorageLock<T>(Future<T> Function() operation) async {
    late T result;
    final override = _lockOverride;
    if (override != null) {
      await override(() async {
        result = await operation();
      });
      return result;
    }
    Object? failure;
    StackTrace? failureStack;
    var completed = false;
    // No unlocked fallback: unsupported/failed Web Locks disable persistence
    // and export instead of allowing an unsafe cross-tab race.
    await window.navigator.locks
        .request(
          _lockName,
          ((Lock? _) {
            return Future<T>.sync(operation)
                .then<JSAny?>(
                  (value) {
                    result = value;
                    completed = true;
                    return null;
                  },
                  onError: (Object error, StackTrace stack) {
                    failure = error;
                    failureStack = stack;
                    return null;
                  },
                )
                .toJS;
          }).toJS,
        )
        .toDart;
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    if (!completed) throw StateError('Log storage lock did not complete');
    return result;
  }

  @override
  Future<void> appendLog(DateTime date, String text) async {
    await requireStorageReady();
    enqueue(text);
  }

  @override
  Future<void> writeToTextFile(String logs) => _withStorageLock(() async {
    final directory = _logDirectory;
    if (directory == null) throw StateError('Log storage is not ready');
    final handle = await directory
        .getFileHandle(
          logFileNameOfDate(DateTime.now()),
          FileSystemGetFileOptions(create: true),
        )
        .toDart;
    final size = (await handle.getFile().toDart).size;
    final stream = await handle
        .createWritable(FileSystemCreateWritableOptions(keepExistingData: true))
        .toDart;
    try {
      await stream.seek(size).toDart;
      await stream.write('$logs\n'.toJS).toDart;
      await stream.close().toDart;
    } catch (_) {
      try {
        await stream.abort().toDart;
      } catch (_) {}
      rethrow;
    }
  });

  @override
  Future<void> deleteOldLogs(int size) async {
    if (size < 0) throw ArgumentError.value(size, 'size');
    await requireStorageReady();
    await withFlushedQueue(
      () => _withStorageLock(() async {
        final files = await _getLogFiles();
        var total = 0;
        for (final file in files) {
          total += (await file.getFile().toDart).size;
        }
        for (final file in files) {
          if (total <= size) break;
          final length = (await file.getFile().toDart).size;
          await _logDirectory!.removeEntry(file.name).toDart;
          total -= length;
        }
      }),
    );
  }

  @override
  Future<int> getLogFolderSize() async {
    await requireStorageReady();
    return withFlushedQueue(
      () => _withStorageLock(() async {
        var total = 0;
        for (final file in await _getLogFiles()) {
          total += (await file.getFile().toDart).size;
        }
        return total;
      }),
    );
  }

  @override
  Future<void> closeLogFile() => flushQueue();

  @override
  Stream<String> exportLogsStream() async* {
    final snapshot = await _createSnapshot();
    try {
      yield* _readFileChunks(snapshot.file).transform(utf8.decoder);
    } finally {
      await _deleteSnapshot(snapshot);
    }
  }

  Future<_WebLogSnapshot> _createSnapshot() async {
    await requireStorageReady();
    return withFlushedQueue(
      () => _withStorageLock(() async {
        final cache = await _logDirectory!
            .getDirectoryHandle(
              'log_export',
              FileSystemGetDirectoryOptions(create: true),
            )
            .toDart;
        final random = Random.secure();
        final name =
            'snapshot_${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(0x100000000)}_${random.nextInt(0x100000000)}';
        final directory = await cache
            .getDirectoryHandle(
              name,
              FileSystemGetDirectoryOptions(create: true),
            )
            .toDart;
        _retainedExports.add(name);
        try {
          final handle = await directory
              .getFileHandle(
                'records.txt',
                FileSystemGetFileOptions(create: true),
              )
              .toDart;
          final writer = await handle.createWritable().toDart;
          try {
            for (final source in await _getLogFiles()) {
              final file = await source.getFile().toDart;
              await for (final bytes in _readFileChunks(file)) {
                await writer.write(Uint8List.fromList(bytes).toJS).toDart;
              }
            }
            await writer.close().toDart;
          } catch (_) {
            try {
              await writer.abort().toDart;
            } catch (_) {}
            rethrow;
          }
          // OPFS getFile() objects are invalidated by later commits to their
          // source. Copy first: this private snapshot file is never appended.
          return _WebLogSnapshot(cache, name, await handle.getFile().toDart);
        } catch (_) {
          _retainedExports.remove(name);
          await cache
              .removeEntry(name, FileSystemRemoveOptions(recursive: true))
              .toDart;
          rethrow;
        }
      }),
    );
  }

  Future<void> _deleteSnapshot(_WebLogSnapshot snapshot) =>
      _withStorageLock(() async {
        _retainedExports.remove(snapshot.name);
        try {
          await snapshot.parent
              .removeEntry(
                snapshot.name,
                FileSystemRemoveOptions(recursive: true),
              )
              .toDart;
        } on DOMException catch (error) {
          if (error.name != 'NotFoundError') rethrow;
        }
      });

  Stream<List<int>> _readFileChunks(File file) async* {
    for (var offset = 0; offset < file.size; offset += 64 * 1024) {
      final bytes = await file
          .slice(offset, offset + 64 * 1024)
          .arrayBuffer()
          .toDart;
      yield bytes.toDart.asUint8List();
    }
  }

  Future<List<FileSystemFileHandle>> _getLogFiles() async {
    final directory = _logDirectory;
    if (directory == null) throw StateError('Log storage is not ready');
    final files = <FileSystemFileHandle>[];
    await for (final handle in directory.valuesStream()) {
      if (handle.kind == 'file' &&
          CommonLogStorageOperations.isLogFileNameValid(handle.name)) {
        files.add(handle as FileSystemFileHandle);
      }
    }
    files.sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  @override
  Future<void> deleteExportedFiles() async {
    await requireStorageReady();
    await serializeStorage(
      () => _withStorageLock(() async {
        try {
          final cache = await _logDirectory!
              .getDirectoryHandle('log_export')
              .toDart;
          var retained = false;
          for (final name in await cache.keysStream().toList()) {
            if (_retainedExports.contains(name)) {
              retained = true;
              continue;
            }
            await cache
                .removeEntry(name, FileSystemRemoveOptions(recursive: true))
                .toDart;
          }
          // A retained snapshot is removed by the export that owns it, or by
          // the next clear once that export has finished.
          if (!retained) {
            await _logDirectory!
                .removeEntry(
                  'log_export',
                  FileSystemRemoveOptions(recursive: true),
                )
                .toDart;
          }
        } on DOMException catch (error) {
          if (error.name != 'NotFoundError') rethrow;
        }
      }),
    );
  }

  @override
  Future<void> exportLogsToDownload() async {
    final snapshot = await _createSnapshot();
    late Blob download;
    try {
      // Download blobs must own their bytes before the OPFS snapshot is
      // deleted. Keep conversion chunked; no concatenated full-store string.
      final parts = <JSAny>[];
      await for (final bytes in _readFileChunks(snapshot.file)) {
        parts.add(Uint8List.fromList(bytes).toJS);
      }
      download = Blob(parts.toJS);
    } finally {
      await _deleteSnapshot(snapshot);
    }
    final filename =
        'log_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
    final url = URL.createObjectURL(download);
    final anchor = HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';
    try {
      document.body!.appendChild(anchor);
      anchor.click();
    } finally {
      anchor.remove();
      URL.revokeObjectURL(url);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await disposeStorage();
    } finally {
      _logDirectory = null;
    }
  }
}

class _WebLogSnapshot {
  _WebLogSnapshot(this.parent, this.name, this.file);
  final FileSystemDirectoryHandle parent;
  final String name;
  final File file;
}
