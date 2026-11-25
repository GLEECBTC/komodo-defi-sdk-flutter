import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_desktop_data_location.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory sandbox;
  late KdfDesktopDataResolver platformDefault;
  late List<(KdfDesktopDataDirectory, int)> asked;
  final desktop = KdfDesktopDataDirectory(
    windowsFolder: 'Gleec',
    linuxFolder: 'com.gleec.GleecDEX',
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('kdf_desktop_data_');
    platformDefault = KdfStartupConfig.desktopDataResolver;
    asked = [];
    KdfStartupConfig.desktopDataResolver = (config, rpcPort) async {
      asked.add((config, rpcPort));
      return path.join(sandbox.path, 'Gleec', 'kdf');
    };
  });
  tearDown(() async {
    KdfStartupConfig.desktopDataResolver = platformDefault;
    await sandbox.delete(recursive: true);
  });

  Future<Map<String, dynamic>> startParams({
    String? userHome,
    String? dbDir,
  }) async => (await KdfStartupConfig.generateWithDefaults(
    walletName: 'wallet',
    walletPassword: 'wallet-secret',
    enableHd: true,
    rpcPassword: 'rpc-secret',
    coinsPath: 'coins',
    rpcPort: 7790,
    userHome: userHome,
    dbDir: dbDir,
    seedNodes: const ['seed01.kmdefi.net'],
    desktopDataDirectory: desktop,
  )).encodeStartParams();

  test('KDF gets the directory the desktop resolver picks', () async {
    final dbDir = path.join(sandbox.path, 'Gleec', 'kdf');

    final params = await startParams();

    expect(params['dbdir'], dbDir);
    expect(params['userhome'], path.dirname(dbDir));
    expect(Directory(dbDir).existsSync(), isTrue);
    expect(asked, [(desktop, 7790)]);
  });

  test('a directory the caller names wins over the resolver', () async {
    final dbDir = path.join(sandbox.path, 'explicit');

    final params = await startParams(userHome: sandbox.path, dbDir: dbDir);

    expect(params['dbdir'], dbDir);
    expect(params['userhome'], sandbox.path);
    expect(asked, isEmpty);
  });
}
