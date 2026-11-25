// The move runs on the UI isolate at start-up; synchronous I/O would freeze it.
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_record.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_tree.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('KdfDataMigration');

/// Thrown when the folder meant to hold KDF's data can't be created.
class KdfDataRootException implements Exception {
  KdfDataRootException(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() => 'KdfDataRootException: $path: $cause';
}

/// Moves KDF's data out of the user's Documents, before KDF first starts.
///
/// [run] picks the directory KDF uses for the process:
///
/// 1. `kdf` under [root], once it exists.
/// 2. Otherwise the old directory is renamed to `<name>.moved` and a README
///    takes its place, so an older app finds no wallets rather than a stale
///    copy. On Windows the rename also fails while any file in it is open.
/// 3. The data is copied into `kdf.partial`, every copy is read back and
///    compared, and one rename commits it as `kdf`.
/// 4. [gracePeriod] after KDF first comes up on `kdf` with a wallet open, the
///    files in `<name>.moved` that still match the copy are deleted. Anything
///    that changed is kept.
///
/// Before the commit, a failure puts the old directory back and KDF uses it
/// as before; the next start tries again.
final class KdfDataMigration {
  KdfDataMigration({
    required this.root,
    required Future<Directory?> Function() legacyDirectory,
    DateTime Function()? clock,
    Future<bool> Function()? engineRunning,
    this.gracePeriod = const Duration(days: 7),
    this.lockTimeout = const Duration(seconds: 30),
    this.copyFile = copyKdfDataFile,
  }) : _legacyDirectory = legacyDirectory,
       _clock = clock ?? DateTime.now,
       _engineRunning = engineRunning ?? _noEngine;

  /// The data directory's name under [root].
  static const targetName = 'kdf';

  /// Left where the old data directory was, for anyone who looks there.
  static const readmeName = 'README.txt';

  /// The app's data folder, which holds the new data directory.
  final Directory root;

  /// Looks up Documents only when the target still needs to be created.
  final Future<Directory?> Function() _legacyDirectory;

  final Duration gracePeriod;
  final Duration lockTimeout;
  final DateTime Function() _clock;

  /// Whether a KDF already answers, which may be using the old directory.
  final Future<bool> Function() _engineRunning;

  /// Copies one file; tests replace it to produce a bad copy.
  @visibleForTesting
  final Future<void> Function(File source, File destination) copyFile;

  Directory get target => Directory(p.join(root.path, targetName));

  Directory get _staging => Directory(p.join(root.path, '$targetName.partial'));
  File get _recordFile => File(p.join(root.path, KdfDataRecord.fileName));
  File get _lockFile => File(p.join(root.path, '$targetName-migration.lock'));

  static Future<bool> _noEngine() async => false;

  /// Notes that KDF came up on [dataDirectory] with a wallet open. Until then,
  /// nothing left in Documents is deleted.
  static Future<void> recordVerifiedStart(
    String dataDirectory, {
    DateTime Function()? clock,
  }) async {
    if (p.basename(dataDirectory) != targetName) return;
    final file = File(p.join(p.dirname(dataDirectory), KdfDataRecord.fileName));
    final record = await KdfDataRecord.read(file);
    if (record == null || record.verifiedAt != null) return;
    await record.copyWith(verifiedAt: (clock ?? DateTime.now)()).write(file);
  }

  /// Returns the directory KDF uses for this run.
  ///
  /// Throws [KdfDataRootException] if [root] can't be created, and a
  /// [FileSystemException] if Documents or a migration source is a link
  /// to a missing directory, such as a volume that isn't mounted yet.
  Future<Directory> run() async {
    try {
      await root.create(recursive: true);
    } on FileSystemException catch (error) {
      throw KdfDataRootException(root.path, error);
    }
    return _locked(() async {
      if (await target.exists()) {
        await _tidyUp();
        return target;
      }
      final legacy = await _legacyDirectory();
      if (legacy == null) return _createEmptyTarget();
      final retired = Directory('${legacy.path}.moved');
      await _requireReachable(legacy.parent);
      await _requireReachable(legacy);
      final bool legacyHolds;
      try {
        legacyHolds = await _holdsData(legacy);
      } on FileSystemException catch (error) {
        // OneDrive may not be running yet, or Documents may be on a share that
        // is down. KDF would have used the old directory anyway.
        _log.warning('Could not read ${legacy.path}, so KDF uses it: $error');
        return legacy;
      }
      final bool retiredHolds;
      try {
        await _requireReachable(retired);
        retiredHolds = await _holdsData(retired);
      } on FileSystemException catch (error) {
        // An absent legacy folder or one containing only the README cannot
        // stand in for the retired copy while that copy is unavailable.
        if (!legacyHolds) rethrow;
        _log.warning(
          'Could not read ${retired.path}, so KDF uses ${legacy.path}: $error',
        );
        return legacy;
      }
      if (legacyHolds && retiredHolds) {
        _log.warning(
          '${legacy.path} and ${retired.path} both hold data, so KDF keeps '
          'using ${legacy.path}',
        );
        return legacy;
      }
      if (legacyHolds) return _moveLegacy(legacy, retired);
      if (retiredHolds) return _copyRetired(legacy, retired);
      return _createEmptyTarget();
    });
  }

  Future<T> _locked<T>(Future<T> Function() body) async {
    // Append never truncates, so opening can't fail while another process
    // holds the lock.
    final handle = await _lockFile.open(mode: FileMode.append);
    try {
      final waited = Stopwatch()..start();
      while (true) {
        try {
          await handle.lock(FileLock.exclusive, 0, 1);
          break;
        } on FileSystemException {
          if (waited.elapsed >= lockTimeout) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      return await body();
    } finally {
      await handle.close();
    }
  }

  Future<void> _requireReachable(Directory directory) async {
    if (!await directory.exists() && await isKdfDataLink(directory.path)) {
      throw FileSystemException(
        'KDF data path is not reachable',
        directory.path,
      );
    }
  }

  Future<bool> _holdsData(Directory directory) async {
    if (!await directory.exists()) return false;
    await for (final entity in directory.list(followLinks: false)) {
      if (p.basename(entity.path) != readmeName) return true;
    }
    return false;
  }

  Future<Directory> _moveLegacy(Directory legacy, Directory retired) async {
    if (await isKdfDataLink(legacy.path)) {
      _log.info('${legacy.path} is a link, so KDF keeps using it');
      return legacy;
    }
    if (await _engineRunning()) {
      _log.info('A KDF is running and may use ${legacy.path}; not moving it');
      return legacy;
    }
    try {
      await legacy.rename(retired.path);
    } on FileSystemException catch (error) {
      _log.warning('${legacy.path} could not be moved, so KDF uses it: $error');
      return legacy;
    }
    await _writeReadme(legacy, retired);
    try {
      await _copy(retired);
      return target;
    } on Object catch (error) {
      _log.warning('Moving ${legacy.path} failed, so it goes back: $error');
      await _discardStagingQuietly();
      return _putBack(legacy, retired);
    }
  }

  /// Copies a directory an earlier start, or another device, put aside.
  Future<Directory> _copyRetired(Directory legacy, Directory retired) async {
    if (await isKdfDataLink(retired.path)) return retired;
    if (await _engineRunning()) {
      _log.info('A KDF is running and may use ${retired.path}; not copying it');
      return retired;
    }
    if (!await legacy.exists()) await _writeReadme(legacy, retired);
    try {
      await _copy(retired);
      return target;
    } on Object catch (error) {
      _log.warning('KDF data stays in ${retired.path} for now: $error');
      await _discardStagingQuietly();
      return retired;
    }
  }

  Future<Directory> _putBack(Directory legacy, Directory retired) async {
    try {
      final readme = File(p.join(legacy.path, readmeName));
      if (await readme.exists()) await readme.delete();
      if (await legacy.exists()) await legacy.delete();
      await retired.rename(legacy.path);
      return legacy;
    } on Object catch (error) {
      _log.warning(
        '${retired.path} stays where it is, and KDF uses it: $error',
      );
      return retired;
    }
  }

  Future<void> _copy(Directory source) async {
    await _discardStaging();
    await _staging.create();
    await _restrictToUser(_staging);
    final files = <String, KdfDataDigest>{};
    for (final entry in await walkKdfData(source)) {
      final destination = kdfDataPath(_staging.path, entry.relativePath);
      if (entry.kind == KdfDataEntryKind.directory) {
        await Directory(destination).create(recursive: true);
        continue;
      }
      final original = await digestKdfDataFile(File(entry.path));
      await copyFile(File(entry.path), File(destination));
      if (await digestKdfDataFile(File(destination)) != original) {
        throw FileSystemException('The copy differs', entry.path);
      }
      files[entry.relativePath] = original;
    }
    await KdfDataRecord(
      source: source.path,
      copiedAt: _clock(),
      files: files,
    ).write(_recordFile);
    await _staging.rename(target.path);
  }

  Future<Directory> _createEmptyTarget() async {
    await _discardStaging();
    await _staging.create();
    await _restrictToUser(_staging);
    await _staging.rename(target.path);
    return target;
  }

  Future<void> _discardStaging() async {
    if (await _staging.exists()) await _staging.delete(recursive: true);
  }

  Future<void> _discardStagingQuietly() async {
    try {
      await _discardStaging();
    } on Object catch (error) {
      _log.warning('Could not remove ${_staging.path}: $error');
    }
  }

  Future<void> _tidyUp() async {
    try {
      final record = await KdfDataRecord.read(_recordFile);
      final verifiedAt = record?.verifiedAt;
      if (record == null || verifiedAt == null || record.cleanedAt != null) {
        return;
      }
      // Counting from the later of the two keeps a clock that was wrong at
      // the copy from ending the grace period at once.
      final since = verifiedAt.isAfter(record.copiedAt)
          ? verifiedAt
          : record.copiedAt;
      if (_clock().difference(since) < gracePeriod) return;
      if (await _engineRunning()) return;
      await _cleanUp(Directory(record.source), record);
      await record.copyWith(cleanedAt: _clock()).write(_recordFile);
    } on Object catch (error) {
      _log.warning('Old KDF data not cleaned up yet: $error');
    }
  }

  /// Deletes each top-level entry of [directory] whose files all match
  /// [record], then [directory] itself if that left it empty.
  Future<void> _cleanUp(Directory directory, KdfDataRecord record) async {
    if (!await directory.exists() || await isKdfDataLink(directory.path)) {
      return;
    }
    var kept = 0;
    for (final entity in await directory.list(followLinks: false).toList()) {
      if (!await _deleteIfCopied(entity, directory, record)) kept++;
    }
    if (kept == 0) {
      await directory.delete();
    } else {
      _log.info(
        'Kept $kept entries in ${directory.path} that differ from the '
        'copy in ${target.path}',
      );
    }
  }

  /// Deletes [entity] if every file under it is one the copy holds,
  /// unchanged. Files already gone, from a cleanup a crash cut short, are
  /// fine.
  Future<bool> _deleteIfCopied(
    FileSystemEntity entity,
    Directory directory,
    KdfDataRecord record,
  ) async {
    final List<KdfDataEntry> entries;
    try {
      entries = await walkKdfDataEntity(entity, root: directory);
    } on KdfDataLinkException {
      return false;
    }
    final files = [
      for (final entry in entries)
        if (entry.kind == KdfDataEntryKind.file) entry,
    ];
    for (final file in files) {
      final expected = record.files[file.relativePath];
      if (expected == null) return false;
      if (await digestKdfDataFile(File(file.path)) != expected) return false;
    }
    // Journals go first, so a cut-short cleanup never leaves a write-ahead
    // log that SQLite could replay into another database.
    files.sort((a, b) => _deleteOrder(a.path) - _deleteOrder(b.path));
    for (final file in files) {
      await File(file.path).delete();
    }
    for (final entry in entries.reversed) {
      if (entry.kind == KdfDataEntryKind.directory) {
        await Directory(entry.path).delete();
      }
    }
    return true;
  }

  static int _deleteOrder(String path) =>
      path.endsWith('-wal') ||
          path.endsWith('-shm') ||
          path.endsWith('-journal')
      ? 0
      : 1;

  Future<void> _writeReadme(Directory legacy, Directory retired) async {
    final date = _clock().toUtc().toIso8601String().substring(0, 10);
    final text = [
      'Wallet data moved',
      '',
      'On $date, the wallet data that was in this folder moved to:',
      '',
      '    ${target.path}',
      '',
      'Documents is often synced to cloud storage, and wallet data',
      'should not be. Unchanged files in ${p.basename(retired.path)} are',
      'removed after a seven-day grace period from the first wallet open',
      'in the new folder. Cleanup waits while a wallet engine is running.',
      '',
      'To back up a wallet, keep its recovery phrase, or export the',
      'wallet file from the app. To restore a wallet, import its',
      'recovery phrase.',
      '',
    ].join(Platform.isWindows ? '\r\n' : '\n');
    try {
      await legacy.create();
      await File(p.join(legacy.path, readmeName))
          .writeAsString(text, flush: true);
    } on Object catch (error) {
      _log.warning('No README in ${legacy.path}: $error');
    }
  }

  // A Windows profile's AppData is already limited to its user.
  Future<void> _restrictToUser(Directory directory) async {
    if (Platform.isWindows) return;
    try {
      final result = await Process.run('chmod', ['700', directory.path]);
      if (result.exitCode != 0) throw Exception(result.stderr);
    } on Object catch (error) {
      _log.warning('Could not limit ${directory.path} to its owner: $error');
    }
  }
}
