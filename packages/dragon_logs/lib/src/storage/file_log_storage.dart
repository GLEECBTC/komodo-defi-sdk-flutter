import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dragon_logs/src/storage/input_output_mixin.dart';
import 'package:dragon_logs/src/storage/log_storage.dart';
import 'package:dragon_logs/src/storage/queue_mixin.dart';
import 'package:dragon_logs/src/storage/storage_lifecycle.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileLogStorage
    with QueueMixin, LogStorageLifecycle, CommonLogStorageOperations
    implements LogStorage {
  FileLogStorage() : _documentsOverride = null, _shareFileOverride = null;

  @visibleForTesting
  FileLogStorage.forDirectory(
    Directory directory, {
    Future<void> Function(String path)? shareFile,
  }) : _documentsOverride = directory,
       _shareFileOverride = shareFile;

  final Directory? _documentsOverride;
  final Future<void> Function(String path)? _shareFileOverride;
  static final Map<String, Future<void>> _processLocks = {};
  static String? _lastLogFolderPath;
  Directory? _documentsDirectory;
  Directory? _logDirectory;

  /// Entries under `log_export` that a running export still reads or shares.
  /// Export bodies deliberately run outside the storage queue, so a concurrent
  /// clear has to skip these rather than delete them while they are in use.
  /// Canonical paths share ownership across instances in this isolate, even
  /// after an owning instance is disposed. This is not a cross-process lease.
  static final Set<String> _retainedExports = {};

  @override
  Future<void> init({String? storageNamespace, bool purgeLegacy = false}) {
    final configuration = LogStorageConfiguration(
      storageNamespace: storageNamespace,
      purgeLegacy: purgeLegacy,
    );
    return initializeStorage(configuration, () async {
      final documents =
          _documentsOverride ?? await getApplicationDocumentsDirectory();
      await documents.create(recursive: true);
      _documentsDirectory = Directory(await documents.resolveSymbolicLinks());
      await _withDiskLock(() async {
        final active = Directory(
          p.join(_documentsDirectory!.path, configuration.namespace),
        );
        // The new directory is the durable migration marker. Never create it
        // before removing legacy records and cached exports successfully.
        final activeType = await FileSystemEntity.type(
          active.path,
          followLinks: false,
        );
        if (activeType != FileSystemEntityType.notFound &&
            activeType != FileSystemEntityType.directory) {
          throw StateError('Invalid log storage directory');
        }
        if (activeType == FileSystemEntityType.notFound) {
          if (configuration.purgeLegacy) {
            final legacy = Directory(
              p.join(
                _documentsDirectory!.path,
                LogStorageConfiguration.legacyNamespace,
              ),
            );
            switch (await FileSystemEntity.type(
              legacy.path,
              followLinks: false,
            )) {
              case FileSystemEntityType.directory:
                await legacy.delete(recursive: true);
              case FileSystemEntityType.file:
                await File(legacy.path).delete();
              case FileSystemEntityType.link:
                await Link(legacy.path).delete();
              case FileSystemEntityType.notFound:
                break;
              default:
                throw StateError('Invalid legacy log storage');
            }
          }
          await active.create();
        }
        _logDirectory = active;
        _lastLogFolderPath = active.path;
      });
    });
  }

  /// Serializes instances in this isolate and cooperating native processes.
  /// Handles close after each transaction, including failed operations.
  Future<T> _withDiskLock<T>(Future<T> Function() operation) {
    final documents = _documentsDirectory;
    if (documents == null) throw StateError('Log storage is not ready');
    return _withDirectoryLock(documents.path, operation);
  }

  static Future<T> _withDirectoryLock<T>(
    String documentsPath,
    Future<T> Function() operation,
  ) {
    final lockPath = p.join(documentsPath, '.dragon_logs_storage.lock');
    final previous = _processLocks[lockPath] ?? Future<void>.value();
    final result = previous.then((_) async {
      final handle = await File(lockPath).open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.blockingExclusive);
        return await operation();
      } finally {
        await handle.close();
      }
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _processLocks[lockPath] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_processLocks[lockPath], tail)) {
          _processLocks.remove(lockPath);
        }
      }),
    );
    return result;
  }

  @override
  Future<void> appendLog(DateTime date, String text) async {
    await requireStorageReady();
    enqueue(text);
  }

  @override
  Future<void> writeToTextFile(String logs, {bool batchWrite = true}) =>
      _withDiskLock(() async {
        final directory = _logDirectory;
        if (directory == null) throw StateError('Log storage is not ready');
        final file = File(
          p.join(directory.path, logFileNameOfDate(DateTime.now())),
        );
        final handle = await file.open(mode: FileMode.append);
        try {
          await handle.writeString('$logs\n');
          await handle.flush();
        } finally {
          await handle.close();
        }
      });

  @override
  Future<void> deleteOldLogs(int size) async {
    if (size < 0) throw ArgumentError.value(size, 'size');
    await requireStorageReady();
    await withFlushedQueue(
      () => _withDiskLock(() async {
        final files = await _listLogFiles();
        var total = 0;
        for (final file in files) {
          total += await file.length();
        }
        for (final file in files) {
          if (total <= size) break;
          final length = await file.length();
          await file.delete();
          total -= length;
        }
      }),
    );
  }

  @override
  Future<int> getLogFolderSize() async {
    await requireStorageReady();
    return withFlushedQueue(
      () => _withDiskLock(() async {
        var total = 0;
        for (final file in await _listLogFiles()) {
          total += await file.length();
        }
        return total;
      }),
    );
  }

  @override
  Stream<String> exportLogsStream() async* {
    await requireStorageReady();
    final documentsPath = _documentsDirectory!.path;
    Directory? retainedDirectory;
    try {
      final snapshot = await withFlushedQueue(
        () => _withDiskLock(() async {
          final cache = await Directory(
            p.join(logFolderPath, 'log_export'),
          ).create();
          final directory = await cache.createTemp('snapshot_');
          retainedDirectory = directory;
          _retainedExports.add(directory.path);
          final result = File(p.join(directory.path, 'records.txt'));
          final output = await result.open(mode: FileMode.writeOnly);
          try {
            for (final file in await _listLogFiles()) {
              final input = await file.open();
              try {
                while (true) {
                  final bytes = await input.read(64 * 1024);
                  if (bytes.isEmpty) break;
                  await output.writeFrom(bytes);
                }
              } finally {
                await input.close();
              }
            }
          } finally {
            await output.close();
          }
          return result;
        }),
      );
      // Copy in bounded chunks while locked, then stream an independent
      // snapshot. Consumer pauses never retain a disk or queue lock.
      yield* snapshot.openRead().transform(utf8.decoder);
    } finally {
      // This also covers failed creation or closing its disk-lock handle.
      // Use captured paths after disposal or namespace changes, keeping
      // ownership until cleanup finishes even when the lock cannot be acquired.
      final directory = retainedDirectory;
      if (directory != null) {
        try {
          await _withDirectoryLock(documentsPath, () async {
            if (await directory.exists()) {
              await directory.delete(recursive: true);
            }
          });
        } finally {
          _retainedExports.remove(directory.path);
        }
      }
    }
  }

  @override
  Future<void> closeLogFile() => flushQueue();

  @override
  Future<void> dispose() async {
    try {
      await disposeStorage();
    } finally {
      _logDirectory = null;
      _documentsDirectory = null;
    }
  }

  @override
  Future<void> deleteExportedFiles() async {
    await requireStorageReady();
    await serializeStorage(
      () => _withDiskLock(() async {
        final directory = Directory(p.join(logFolderPath, 'log_export'));
        if (!await directory.exists()) return;
        var retained = false;
        // Materialize before deleting: mutating a directory while its own
        // listing is still open can skip entries.
        final entries = await directory.list(followLinks: false).toList();
        for (final entity in entries) {
          if (_retainedExports.contains(entity.path)) {
            retained = true;
            continue;
          }
          await entity.delete(recursive: true);
        }
        // A retained artefact is removed by the export that owns it, or by the
        // next clear once that export has finished.
        if (!retained) await directory.delete(recursive: true);
      }),
    );
  }

  File getLogFile(DateTime date) =>
      File(p.join(logFolderPath, logFileNameOfDate(date)));

  Future<List<File>> _listLogFiles() async {
    final directory = _logDirectory;
    if (directory == null) throw StateError('Log storage is not ready');
    final files = await directory
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File &&
              CommonLogStorageOperations.isLogFileNameValid(
                p.basename(entity.path),
              ),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<LinkedHashMap<DateTime, File>> getLogFiles() async {
    await requireStorageReady();
    return withFlushedQueue(
      () => _withDiskLock(
        () async => LinkedHashMap.fromEntries(
          (await _listLogFiles()).map(
            (file) => MapEntry(
              CommonLogStorageOperations.parseLogFileDate(
                p.basename(file.path),
              ),
              file,
            ),
          ),
        ),
      ),
    );
  }

  String get logFolderPath {
    final directory = _logDirectory;
    if (directory == null) throw StateError('Log storage is not ready');
    return directory.path;
  }

  @override
  Future<void> exportLogsToDownload() async {
    await requireStorageReady();
    final formatter = DateFormat('yyyyMMdd_HHmmss');
    final now = DateTime.now();
    final filename =
        'export_${formatter.format(now)}_${now.microsecondsSinceEpoch}.log';
    Directory? retainedDirectory;
    try {
      final file = await serializeStorage(
        () => _withDiskLock(() async {
          final cache = await Directory(
            p.join(logFolderPath, 'log_export'),
          ).create();
          // Each concurrent share owns a unique directory, even if their
          // timestamp-based display filenames happen to match.
          final directory = await cache.createTemp('share_');
          retainedDirectory = directory;
          _retainedExports.add(directory.path);
          return File(p.join(directory.path, filename));
        }),
      );
      final handle = await file.open(mode: FileMode.writeOnly);
      try {
        await for (final record in exportLogsStream()) {
          await handle.writeString(record);
        }
        await handle.flush();
      } finally {
        await handle.close();
      }
      final shareFile = _shareFileOverride;
      if (shareFile != null) {
        await shareFile(file.path);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/plain')],
            text: 'App log file export',
          ),
        );
      }
    } finally {
      final directory = retainedDirectory;
      if (directory != null) _retainedExports.remove(directory.path);
    }
  }

  static Future<String> getLogFolderPath() async =>
      _lastLogFolderPath ??
      p.join((await getApplicationDocumentsDirectory()).path, 'dragon_logs');
}
