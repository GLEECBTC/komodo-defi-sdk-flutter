@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_migration.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_record.dart';
import 'package:path/path.dart' as p;

import 'kdf_data_fixture.dart';

void main() {
  late KdfDataSandbox sandbox;

  setUp(() async {
    sandbox = await KdfDataSandbox.create();
    await plant(sandbox.legacy, kdfData());
    await sandbox.run();
  });
  tearDown(() async => sandbox.dispose());

  Future<void> later(Duration duration) async {
    sandbox.now = sandbox.now.add(duration);
    await sandbox.run();
  }

  group('the copy put aside', () {
    test('stays until KDF has started on the new directory', () async {
      await later(const Duration(days: 30));

      expect(await readTree(sandbox.retired), kdfData());
      expect((await sandbox.record())!.cleanedAt, isNull);
    });

    test('stays for the grace period after that start', () async {
      await sandbox.verifyStart();
      await later(const Duration(days: 6, hours: 23));

      expect(await readTree(sandbox.retired), kdfData());
    });

    test('counts the grace period from that start', () async {
      sandbox.now = sandbox.now.add(const Duration(days: 10));
      await sandbox.verifyStart();

      await later(const Duration(days: 5));
      expect(await readTree(sandbox.retired), kdfData());

      await later(const Duration(days: 2));
      expect(await sandbox.retired.exists(), isFalse);
    });

    test('is deleted once both have happened', () async {
      await sandbox.verifyStart();
      await later(const Duration(days: 7));

      expect(await sandbox.retired.exists(), isFalse);
      expect(await topLevel(sandbox.legacy), ['README.txt']);
      expect(await readTree(sandbox.target), kdfData());
      expect((await sandbox.record())!.cleanedAt, sandbox.now);
    });

    test(
      'defers cleanup while a KDF may still be using retired data',
      () async {
        await sandbox.verifyStart();
        sandbox.engineRunning = true;

        await later(const Duration(days: 8));
        expect(await readTree(sandbox.retired), kdfData());
        expect((await sandbox.record())!.cleanedAt, isNull);

        sandbox.engineRunning = false;
        await sandbox.run();
        expect(await sandbox.retired.exists(), isFalse);
        expect(await readTree(sandbox.target), kdfData());
      },
    );

    test('keeps every top-level entry that changed after the move', () async {
      await File(p.join(sandbox.retired.path, 'alpha.json'))
          .writeAsString('written by an older app');
      await File(
        p.join(sandbox.retired.path, seedFolder, 'SWAPS', 'MY', 'new.json'),
      ).writeAsString('{"swap":"started by an older app"}');
      await sandbox.verifyStart();

      await later(const Duration(days: 8));

      expect(
        await topLevel(sandbox.retired),
        unorderedEquals(['alpha.json', seedFolder]),
      );
      expect(
        await readTree(Directory(p.join(sandbox.retired.path, seedFolder))),
        containsPair('SWAPS/MY/new.json', isNotEmpty),
      );
      expect((await sandbox.record())!.cleanedAt, isNotNull);
    });

    test('finishes a cleanup that a crash cut short', () async {
      await File(p.join(sandbox.retired.path, seedFolder, 'MM2.db')).delete();
      await sandbox.verifyStart();

      await later(const Duration(days: 8));

      expect(await sandbox.retired.exists(), isFalse);
    });

    test('a file it cannot read now is retried at the next start', () async {
      final locked = File(p.join(sandbox.retired.path, 'beta.json'));
      await setMode(locked, '000');
      await sandbox.verifyStart();

      await later(const Duration(days: 8));
      expect(await locked.exists(), isTrue);
      expect((await sandbox.record())!.cleanedAt, isNull);

      await setMode(locked, '644');
      await later(const Duration(minutes: 1));
      expect(await sandbox.retired.exists(), isFalse);
    });

    test('is never touched when the record cannot be read', () async {
      await sandbox.verifyStart();
      await sandbox.recordFile.writeAsString('{not json');

      await later(const Duration(days: 30));

      expect(await readTree(sandbox.retired), kdfData());
    });
  });

  group('recording the first start', () {
    test('records only the first one', () async {
      final first = sandbox.now;
      await sandbox.verifyStart();
      sandbox.now = first.add(const Duration(days: 1));
      await sandbox.verifyStart();

      expect((await sandbox.record())!.verifiedAt, first);
    });

    test('ignores directories it did not move', () async {
      final elsewhere = await Directory(
        p.join(sandbox.base.path, 'other', 'kdf'),
      ).create(recursive: true);

      await KdfDataMigration.recordVerifiedStart(elsewhere.path);
      await KdfDataMigration.recordVerifiedStart(sandbox.legacy.path);

      expect(
        await File(p.join(elsewhere.parent.path, KdfDataRecord.fileName))
            .exists(),
        isFalse,
      );
      expect((await sandbox.record())!.verifiedAt, isNull);
    });
  });
}
