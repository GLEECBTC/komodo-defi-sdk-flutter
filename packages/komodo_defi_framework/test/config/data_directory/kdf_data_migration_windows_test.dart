@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_tree.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_desktop_data_location_native.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:path/path.dart' as p;

import 'kdf_data_fixture.dart';

Future<void> _junction(String link, String target) async {
  final result = await Process.run('cmd', ['/c', 'mklink', '/J', link, target]);
  if (result.exitCode != 0) {
    throw StateError('mklink failed: ${result.stdout}${result.stderr}');
  }
}

void main() {
  late KdfDataSandbox sandbox;

  setUp(() async => sandbox = await KdfDataSandbox.create());
  tearDown(() async => sandbox.dispose());

  test('moves the data on NTFS and leaves a Windows README', () async {
    await plant(sandbox.legacy, kdfData());

    expect((await sandbox.run()).path, sandbox.target.path);

    expect(await readTree(sandbox.target), kdfData());
    expect(await readTree(sandbox.retired), kdfData());
    final readme = await File(p.join(sandbox.legacy.path, 'README.txt'))
        .readAsString();
    expect(readme, contains('\r\n'));
    expect(readme, contains(sandbox.target.path));
  });

  test('records the first start and cleans up on NTFS', () async {
    await plant(sandbox.legacy, kdfData());
    await sandbox.run();
    await sandbox.verifyStart();
    final verified = (await sandbox.record())!.verifiedAt;

    sandbox.now = sandbox.now.add(const Duration(days: 8));
    await sandbox.run();

    expect(verified, isNotNull);
    expect(await sandbox.retired.exists(), isFalse);
    expect(await readTree(sandbox.target), kdfData());
  });

  test('a junction inside the old data puts it back', () async {
    await plant(sandbox.legacy, kdfData());
    final outside = await Directory(p.join(sandbox.base.path, 'elsewhere'))
        .create();
    await _junction(p.join(sandbox.legacy.path, 'linked'), outside.path);

    expect((await sandbox.run()).path, sandbox.legacy.path);
    expect(await sandbox.target.exists(), isFalse);
    expect(await sandbox.retired.exists(), isFalse);
  });

  // App execution aliases are reparse points that are neither junctions nor
  // symbolic links, like OneDrive's placeholders.
  test('a reparse point that is not a link is not refused', () async {
    final aliases = Directory(
      p.join(Platform.environment['LOCALAPPDATA']!, 'Microsoft', 'WindowsApps'),
    );
    final found = await aliases.exists()
        ? await aliases
              .list(followLinks: false)
              .where((entity) => entity is Link && entity.path.endsWith('.exe'))
              .toList()
        : <FileSystemEntity>[];
    if (found.isEmpty) {
      markTestSkipped('No app execution alias on this machine');
      return;
    }

    expect(await isKdfDataLink(found.first.path), isFalse);
  });

  test('an old directory that is a junction stays in use', () async {
    final real = Directory(p.join(sandbox.base.path, 'real-kdf'));
    await plant(real, kdfData());
    await sandbox.documents.create(recursive: true);
    await _junction(sandbox.legacy.path, real.path);

    expect((await sandbox.run()).path, sandbox.legacy.path);
    expect(await sandbox.target.exists(), isFalse);
    expect(await readTree(real), kdfData());
  });

  test(
    'unavailable legacy junction cannot select an empty directory',
    () async {
      final real = Directory(p.join(sandbox.base.path, 'real-kdf'));
      await plant(real, kdfData());
      await sandbox.documents.create(recursive: true);
      await _junction(sandbox.legacy.path, real.path);
      final offline = await real.rename(
        p.join(sandbox.base.path, 'offline-kdf'),
      );

      await expectLater(sandbox.run(), throwsA(isA<FileSystemException>()));
      expect(await sandbox.target.exists(), isFalse);

      await offline.rename(real.path);
      expect((await sandbox.run()).path, sandbox.legacy.path);
      expect(await readTree(real), kdfData());
    },
  );

  test('finds Local AppData through the known-folder API', () async {
    final root = await kdfDesktopDataRoot(
      KdfDesktopDataDirectory(windowsFolder: 'Gleec', linuxFolder: 'unused'),
    );

    final localAppData = Platform.environment['LOCALAPPDATA']!;
    expect(root?.toLowerCase(), p.join(localAppData, 'Gleec').toLowerCase());
  });
}
