@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_migration.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_tree.dart';
import 'package:path/path.dart' as p;

import 'kdf_data_fixture.dart';

void main() {
  late KdfDataSandbox sandbox;

  setUp(() async => sandbox = await KdfDataSandbox.create());
  tearDown(() async => sandbox.dispose());

  Future<void> expectUntouched() async {
    expect(await sandbox.target.exists(), isFalse);
    expect(await Directory('${sandbox.target.path}.partial').exists(), isFalse);
    expect(await sandbox.retired.exists(), isFalse);
    expect(await readTree(sandbox.legacy), kdfData());
  }

  test(
    'creates an empty data directory when there is nothing to move',
    () async {
      final directory = await sandbox.run();

      expect(directory.path, sandbox.target.path);
      expect(await topLevel(sandbox.target), isEmpty);
      expect(await sandbox.record(), isNull);
      expect(await sandbox.legacy.exists(), isFalse);
    },
  );

  test('moves the old data byte for byte and puts it aside', () async {
    await plant(sandbox.legacy, kdfData());

    final directory = await sandbox.run();

    expect(directory.path, sandbox.target.path);
    expect(await readTree(sandbox.target), kdfData());
    expect(
      await Directory(p.join(sandbox.target.path, emptyFolder)).exists(),
      isTrue,
    );
    expect(await readTree(sandbox.retired), kdfData());
    expect(await topLevel(sandbox.legacy), ['README.txt']);
    expect(await Directory('${sandbox.target.path}.partial').exists(), isFalse);

    final record = (await sandbox.record())!;
    expect(record.source, sandbox.retired.path);
    expect(record.copiedAt, sandbox.now);
    expect(record.verifiedAt, isNull);
    expect(record.files.keys, unorderedEquals(kdfData().keys));
    expect(record.files['$seedFolder/MM2.db']!.size, 70000);
  });

  test('leaves KDF only the wallet files it had at the top level', () async {
    await plant(sandbox.legacy, kdfData());

    await sandbox.run();

    final walletFiles = (await topLevel(sandbox.target))
        .where((name) => name.endsWith('.json'));
    expect(walletFiles, ['alpha.json', 'beta.json']);
  });

  test('the README says where the data went', () async {
    await plant(sandbox.legacy, kdfData());

    await sandbox.run();

    final readme = await File(
      p.join(sandbox.legacy.path, KdfDataMigration.readmeName),
    ).readAsString();
    expect(readme, contains(sandbox.target.path));
    expect(readme, contains('On 2026-11-20,'));
    expect(readme, contains('.kdf.moved'));
    expect(readme, contains('recovery phrase'));
  });

  test('a later start uses the moved data and changes nothing', () async {
    await plant(sandbox.legacy, kdfData());
    await sandbox.run();
    final record = await sandbox.recordFile.readAsString();

    final directory = await sandbox.run();

    expect(directory.path, sandbox.target.path);
    expect(await readTree(sandbox.target), kdfData());
    expect(await readTree(sandbox.retired), kdfData());
    expect(await sandbox.recordFile.readAsString(), record);
  });

  test('an interrupted copy is discarded and made again', () async {
    await plant(sandbox.legacy, kdfData());
    await plant(Directory('${sandbox.target.path}.partial'), {
      'alpha.json': 'half a copy'.codeUnits,
      'stray.json': 'from an older attempt'.codeUnits,
    });

    await sandbox.run();

    expect(await readTree(sandbox.target), kdfData());
    expect(await Directory('${sandbox.target.path}.partial').exists(), isFalse);
  });

  test('a copy that cannot finish puts the old data back', () async {
    await plant(sandbox.legacy, kdfData());
    final unreadable = File(p.join(sandbox.legacy.path, 'beta.json'));
    await setMode(unreadable, '000');

    final directory = await sandbox.run();

    expect(directory.path, sandbox.legacy.path);
    await setMode(unreadable, '644');
    await expectUntouched();

    expect((await sandbox.run()).path, sandbox.target.path);
    expect(await readTree(sandbox.target), kdfData());
  });

  test('a copy that does not read back the same is never used', () async {
    await plant(sandbox.legacy, kdfData());
    final migration = sandbox.migration(
      copyFile: (source, destination) async {
        await copyKdfDataFile(source, destination);
        if (p.basename(source.path) == 'MM2.db') {
          await destination.writeAsBytes(
            [1, 2, 3],
            mode: FileMode.append,
            flush: true,
          );
        }
      },
    );

    final directory = await migration.run();

    expect(directory.path, sandbox.legacy.path);
    expect(await sandbox.record(), isNull);
    await expectUntouched();
  });

  test('a start that stopped after putting the data aside finishes', () async {
    await plant(sandbox.legacy, kdfData());
    await sandbox.legacy.rename(sandbox.retired.path);

    expect((await sandbox.run()).path, sandbox.target.path);

    expect(await readTree(sandbox.target), kdfData());
    expect(await topLevel(sandbox.legacy), ['README.txt']);
  });

  test('a README left behind is not data to move', () async {
    await plant(sandbox.legacy, kdfData());
    await sandbox.run();
    await sandbox.target.delete(recursive: true);

    await sandbox.run();

    expect(await readTree(sandbox.target), kdfData());
    expect((await sandbox.record())!.source, sandbox.retired.path);
  });

  test('an old folder that cannot be read stays in use', () async {
    await plant(sandbox.legacy, kdfData());
    await setMode(sandbox.legacy, '000');

    final directory = await sandbox.run();

    expect(directory.path, sandbox.legacy.path);
    await setMode(sandbox.legacy, '755');
    await expectUntouched();
  });

  test('an old folder that cannot be renamed stays in use', () async {
    await plant(sandbox.legacy, kdfData());
    await setMode(sandbox.documents, '555');

    final directory = await sandbox.run();

    expect(directory.path, sandbox.legacy.path);
    await setMode(sandbox.documents, '755');
    await expectUntouched();
  });

  test('a KDF that is running keeps the old data where it is', () async {
    await plant(sandbox.legacy, kdfData());
    sandbox.engineRunning = true;

    expect((await sandbox.run()).path, sandbox.legacy.path);
    await expectUntouched();

    sandbox.engineRunning = false;
    expect((await sandbox.run()).path, sandbox.target.path);
  });

  test('a link inside the old data puts it back', () async {
    await plant(sandbox.legacy, kdfData());
    final outside = await Directory(p.join(sandbox.base.path, 'elsewhere'))
        .create();
    final link = Link(p.join(sandbox.legacy.path, 'linked'));
    await link.create(outside.path);

    final directory = await sandbox.run();

    expect(directory.path, sandbox.legacy.path);
    expect(await sandbox.target.exists(), isFalse);
    expect(await sandbox.retired.exists(), isFalse);
    expect(await link.target(), outside.path);
  });

  test('an old directory that is itself a link stays in use', () async {
    final real = Directory(p.join(sandbox.base.path, 'real-kdf'));
    await plant(real, kdfData());
    await sandbox.documents.create(recursive: true);
    await Link(sandbox.legacy.path).create(real.path);

    final directory = await sandbox.run();

    expect(directory.path, sandbox.legacy.path);
    expect(await sandbox.target.exists(), isFalse);
    expect(await readTree(real), kdfData());
  });

  for (final folder in ['legacy', 'retired']) {
    test(
      'an unavailable $folder link cannot select an empty directory',
      () async {
        final linked = folder == 'legacy' ? sandbox.legacy : sandbox.retired;
        final volume = Directory(p.join(sandbox.base.path, 'offline-volume'));
        await sandbox.documents.create(recursive: true);
        await Link(linked.path).create(volume.path);

        await expectLater(sandbox.run(), throwsA(isA<FileSystemException>()));
        expect(await sandbox.target.exists(), isFalse);

        await plant(volume, kdfData());
        expect((await sandbox.run()).path, linked.path);
        expect(await sandbox.target.exists(), isFalse);
        expect(await readTree(volume), kdfData());
      },
    );
  }

  test('a running KDF keeps retired data where it is', () async {
    await plant(sandbox.retired, kdfData());
    sandbox.engineRunning = true;

    expect((await sandbox.run()).path, sandbox.retired.path);
    expect(await sandbox.target.exists(), isFalse);
    expect(await sandbox.legacy.exists(), isFalse);
    expect(await sandbox.record(), isNull);
    expect(await readTree(sandbox.retired), kdfData());

    sandbox.engineRunning = false;
    expect((await sandbox.run()).path, sandbox.target.path);
    expect(await readTree(sandbox.target), kdfData());
  });

  test('moves a copy another device put aside', () async {
    await plant(sandbox.retired, kdfData());

    final directory = await sandbox.run();

    expect(directory.path, sandbox.target.path);
    expect(await readTree(sandbox.target), kdfData());
    expect(await readTree(sandbox.retired), kdfData());
    expect(await topLevel(sandbox.legacy), ['README.txt']);
    expect((await sandbox.record())!.source, sandbox.retired.path);
  });

  test('unreadable retired data cannot fall back to a README', () async {
    await plant(sandbox.retired, kdfData());
    await sandbox.legacy.create();
    await File(p.join(sandbox.legacy.path, KdfDataMigration.readmeName))
        .writeAsString('Migration in progress');
    await setMode(sandbox.retired, '000');

    await expectLater(sandbox.run(), throwsA(isA<FileSystemException>()));
    expect(await sandbox.target.exists(), isFalse);
    expect(await topLevel(sandbox.legacy), ['README.txt']);
    expect(await sandbox.record(), isNull);

    await setMode(sandbox.retired, '755');
    expect((await sandbox.run()).path, sandbox.target.path);
    expect(await readTree(sandbox.target), kdfData());
  });

  test('unreadable retired data preserves a usable legacy directory', () async {
    await plant(sandbox.retired, kdfData());
    await plant(sandbox.legacy, kdfData());
    await setMode(sandbox.retired, '000');

    expect((await sandbox.run()).path, sandbox.legacy.path);
    expect(await readTree(sandbox.legacy), kdfData());
    expect(await sandbox.target.exists(), isFalse);
  });

  test('leaves two copies alone and keeps using the old one', () async {
    final otherDevice = {'gamma.json': 'from another device'.codeUnits};
    await plant(sandbox.retired, otherDevice);
    await plant(sandbox.legacy, kdfData());

    final directory = await sandbox.run();

    expect(directory.path, sandbox.legacy.path);
    expect(await sandbox.target.exists(), isFalse);
    expect(await readTree(sandbox.legacy), kdfData());
    expect(await readTree(sandbox.retired), otherDevice);
  });

  test('a Documents link to a missing folder is not an empty one', () async {
    await sandbox.base.create(recursive: true);
    await Link(sandbox.documents.path)
        .create(p.join(sandbox.base.path, 'volume-not-mounted'));

    await expectLater(sandbox.run(), throwsA(isA<FileSystemException>()));
    expect(await sandbox.target.exists(), isFalse);
  });

  test('only its owner can open the new directory', () async {
    await plant(sandbox.legacy, kdfData());
    await sandbox.run();

    expect((await sandbox.target.stat()).mode & 0x1FF, 0x1C0);
  });

  test('a fresh data directory is limited to its owner too', () async {
    await sandbox.run();

    expect((await sandbox.target.stat()).mode & 0x1FF, 0x1C0);
  });

  test(
    'throws KdfDataRootException when the app folder cannot exist',
    () async {
      await plant(sandbox.legacy, kdfData());
      await File(p.dirname(sandbox.appData.path)).create(recursive: true);

      await expectLater(sandbox.run(), throwsA(isA<KdfDataRootException>()));
      expect(await readTree(sandbox.legacy), kdfData());
    },
  );
}
