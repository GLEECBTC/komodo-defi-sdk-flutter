// CoreFoundation exists only on Apple platforms. macOS shares iOS's CFURL
// implementation of the flag, so these calls are the ones iOS makes.
@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/native/backup_exclusion_native.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory root;
  late List<LogRecord> warnings;
  late StreamSubscription<LogRecord> logs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_exclusion_');
    warnings = [];
    logs = Logger.root.onRecord
        .where((record) => record.level >= Level.WARNING)
        .listen(warnings.add);
  });
  tearDown(() async {
    await logs.cancel();
    await root.delete(recursive: true);
  });

  test('marks a directory excluded, as a new reader sees it', () {
    final exclusion = CoreFoundationBackupExclusion();
    expect(exclusion.isExcluded(root.path), isFalse);

    exclusion.exclude(root.path);

    expect(CoreFoundationBackupExclusion().isExcluded(root.path), isTrue);
    expect(warnings, isEmpty);
  });

  test('can mark the same directory again', () {
    final exclusion = CoreFoundationBackupExclusion()
      ..exclude(root.path)
      ..exclude(root.path);

    expect(exclusion.isExcluded(root.path), isTrue);
    expect(warnings, isEmpty);
  });

  test('encodes a non-ASCII path as the file system expects', () {
    final directory = Directory(path.join(root.path, 'Données 名前 🔐'))
      ..createSync();

    final exclusion = CoreFoundationBackupExclusion()..exclude(directory.path);

    expect(exclusion.isExcluded(directory.path), isTrue);
    expect(exclusion.isExcluded(root.path), isFalse);
    expect(warnings, isEmpty);
  });

  test('logs a missing directory instead of throwing', () {
    final missing = path.join(root.path, 'missing');

    expect(
      () => CoreFoundationBackupExclusion().exclude(missing),
      returnsNormally,
    );

    expect(warnings, hasLength(1));
    expect(warnings.single.message, contains(missing));
    expect(warnings.single.message, contains('BackupExclusionException'));
  });

  test('logs an empty path instead of throwing', () {
    expect(() => CoreFoundationBackupExclusion().exclude(''), returnsNormally);

    expect(warnings, hasLength(1));
  });
}
