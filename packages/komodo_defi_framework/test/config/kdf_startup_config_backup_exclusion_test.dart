import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/native/backup_exclusion.dart';
import 'package:komodo_defi_framework/src/native/backup_exclusion_native.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory home;
  late BackupExclusion platformDefault;
  // Each request, and whether the directory existed at that moment.
  late List<(String, bool)> requests;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('kdf_backup_exclusion_');
    platformDefault = KdfStartupConfig.backupExclusion;
    requests = [];
    KdfStartupConfig.backupExclusion = (directoryPath) =>
        requests.add((directoryPath, Directory(directoryPath).existsSync()));
  });
  tearDown(() async {
    KdfStartupConfig.backupExclusion = platformDefault;
    await home.delete(recursive: true);
  });

  Future<KdfStartupConfig> start(String dbDir) =>
      KdfStartupConfig.generateWithDefaults(
        walletName: 'wallet',
        walletPassword: 'wallet-secret',
        enableHd: true,
        rpcPassword: 'rpc-secret',
        coinsPath: 'coins',
        userHome: home.path,
        dbDir: dbDir,
        seedNodes: const ['seed01.kmdefi.net'],
      );

  test('excludes the data directory KDF is given, once it exists', () async {
    final dbDir = path.join(home.path, 'db');

    final config = await start(dbDir);

    expect(config.encodeStartParams()['dbdir'], dbDir);
    expect(requests, [(dbDir, true)]);
  });

  test('excludes it again at every start', () async {
    final dbDir = path.join(home.path, 'db');

    await start(dbDir);
    await start(dbDir);

    expect(requests, [(dbDir, true), (dbDir, true)]);
  });

  test('only iOS excludes; desktop and Android keep their backups', () {
    expect(Platform.isIOS, isFalse, reason: 'tests run on a desktop host');
    expect(platformBackupExclusion(), same(keepInBackups));
  });
}
