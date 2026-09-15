import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
// HiveInterface has no getter for its initialized directory. Keep this pinned
// implementation dependency inside the native ownership adapter.
// ignore: implementation_imports
import 'package:hive_ce/src/hive_impl.dart';
import 'package:meta/meta.dart';

/// Owns the cache before secure-key access or Hive corruption recovery.
///
/// POSIX advisory locks are process-scoped. The name-server guard also excludes
/// competing isolates before they can open or close the process's lock file.
/// A crashed isolate leaves a conservative guard until process restart; other
/// consumers use bounded memory rather than guessing that ownership expired.
class HistoryCacheLease {
  HistoryCacheLease._(this._name, this._port, this._file, this.lockFilePath);

  final String _name;
  final ReceivePort _port;
  final RandomAccessFile _file;
  Future<void>? _released;

  /// The held OS lock, exposed only for native contention regression tests.
  @visibleForTesting
  final String lockFilePath;

  /// Acquires ownership before loading a key or opening the cache.
  static Future<HistoryCacheLease> acquire(String cacheName) async {
    // Ownership must use the same directory as the initialized Hive instance.
    // ignore: invalid_use_of_visible_for_testing_member
    final path = (Hive as HiveImpl).homePath;
    if (path == null) throw StateError('Hive must be initialized before use');
    final directory = await Directory(path).create(recursive: true);
    final canonicalPath = await directory.resolveSymbolicLinks();
    final identity = sha256.convert(
      utf8.encode('$canonicalPath\u0000$cacheName'),
    );
    final name = 'komodo-history-cache:$identity';
    final port = ReceivePort();
    if (!ui.IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      port.close();
      throw StateError(
        'Transaction history cache is in use by another isolate',
      );
    }
    RandomAccessFile? file;
    try {
      final lockPath = '$canonicalPath/.komodo-history-cache-$identity.lock';
      file = await File(lockPath).open(mode: FileMode.append);
      await file.lock();
      return HistoryCacheLease._(name, port, file, lockPath);
    } on Object {
      try {
        await file?.close();
      } finally {
        ui.IsolateNameServer.removePortNameMapping(name);
        port.close();
      }
      rethrow;
    }
  }

  /// Releases ownership; repeating release is harmless.
  Future<void> release() => _released ??= _release();

  Future<void> _release() async {
    try {
      await _file.unlock();
    } finally {
      try {
        await _file.close();
      } finally {
        // Never delete an advisory lock inode: another process may already be
        // waiting on it, and replacing it would create two independent locks.
        ui.IsolateNameServer.removePortNameMapping(_name);
        _port.close();
      }
    }
  }
}
