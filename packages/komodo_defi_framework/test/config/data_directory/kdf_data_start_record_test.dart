import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_desktop_data_location.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:path/path.dart' as path;

class _Operations implements IKdfOperations {
  KdfStartupResult startResult = KdfStartupResult.ok;
  MainStatus status = MainStatus.noRpc;
  String? runningVersion;

  @override
  Future<KdfStartupResult> kdfMain(
    JsonMap startParams, {
    int? logLevel,
  }) async => startResult;

  @override
  Future<MainStatus> kdfMainStatus() async => status;

  @override
  Future<String?> version() async => runningVersion;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory sandbox;
  late KdfDataStartRecorder platformDefault;
  late List<String> recorded;
  late _Operations operations;
  late KomodoDefiFramework framework;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('kdf_start_record_');
    platformDefault = KomodoDefiFramework.dataStartRecorder;
    recorded = [];
    KomodoDefiFramework.dataStartRecorder = (directory) async =>
        recorded.add(directory);
    operations = _Operations();
    framework = KomodoDefiFramework.createWithOperations(
      hostConfig: LocalConfig(https: false, rpcPassword: 'rpc-secret'),
      kdfOperations: operations,
    );
  });
  tearDown(() async {
    KomodoDefiFramework.dataStartRecorder = platformDefault;
    await sandbox.delete(recursive: true);
  });

  String dbDir() => path.join(sandbox.path, 'kdf');

  Future<void> startWallet() async => framework.startKdf(
    await KdfStartupConfig.generateWithDefaults(
      walletName: 'wallet',
      walletPassword: 'wallet-secret',
      enableHd: true,
      rpcPassword: 'rpc-secret',
      coinsPath: 'coins',
      userHome: sandbox.path,
      dbDir: dbDir(),
      seedNodes: const ['seed01.kmdefi.net'],
    ),
  );

  test('records the directory once RPC is up after a wallet start', () async {
    await startWallet();
    await framework.kdfMainStatus();
    expect(recorded, isEmpty, reason: 'RPC is not up yet');

    operations.status = MainStatus.rpcIsUp;
    await framework.kdfMainStatus();
    await framework.kdfMainStatus();

    expect(recorded, [dbDir()]);
  });

  test('a start that failed records nothing', () async {
    operations.startResult = KdfStartupResult.initError;
    await startWallet();

    operations.status = MainStatus.rpcIsUp;
    await framework.kdfMainStatus();

    expect(recorded, isEmpty);
  });

  test('another KDF answering on the port records nothing', () async {
    await startWallet();

    operations
      ..status = MainStatus.notRunning
      ..runningVersion = '2.6.0';
    expect(await framework.kdfMainStatus(), MainStatus.rpcIsUp);

    expect(recorded, isEmpty);
  });
}
