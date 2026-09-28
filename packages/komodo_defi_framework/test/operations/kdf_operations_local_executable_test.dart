@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

void main() {
  late Directory sandbox;
  late LocalConfig config;
  late List<String> logs;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('kdf_local_executable_');
    // Nothing listens on this port, so the RPC probe fails at once instead of
    // reaching a KDF a developer has running on the default port.
    final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    config = LocalConfig(https: false, rpcPassword: 'rpc', port: reserved.port);
    await reserved.close();
    logs = <String>[];
  });

  tearDown(() => sandbox.delete(recursive: true));

  KdfOperationsLocalExecutable operations(
    File? executable, {
    required Directory temporaryDirectory,
  }) {
    final kdf = KdfOperationsLocalExecutable.create(
      logCallback: logs.add,
      config: config,
      executableFinder: _FixedFinder(executable),
      temporaryDirectory: () async => temporaryDirectory,
    );
    addTearDown(kdf.dispose);
    return kdf;
  }

  File script(String body) =>
      File('${sandbox.path}/kdf')..writeAsStringSync('#!/bin/sh\n$body\n');

  Future<void> exitCleanup() async {
    for (var i = 0; i < 100; i++) {
      if (logs.contains('Temporary directory deleted successfully.')) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('KDF exit cleanup did not run');
  }

  group(
    'KdfOperationsLocalExecutable.kdfMain',
    () {
      test(
        'creates a temporary directory that path_provider only names',
        () async {
          // path_provider_foundation 2.6.0 names Library/Caches/<bundle id>
          // in the macOS sandbox without creating it.
          final caches = Directory(
            '${sandbox.path}/Library/Caches/com.example',
          );
          final kdf = script(_copyCoinsThenExit2);

          final result = await operations(
            kdf,
            temporaryDirectory: caches,
          ).kdfMain(_params);

          // Only the executable's own exit status yields configError here.
          expect(result, KdfStartupResult.configError);
          expect(caches.existsSync(), isTrue);
          expect(
            jsonDecode(File('${sandbox.path}/coins.json').readAsStringSync()),
            _params['coins'],
          );
          await exitCleanup();
          expect(caches.listSync(), isEmpty);
        },
      );
    },
    skip: Platform.isWindows ? 'the fake KDF is a POSIX shell script' : null,
  );
}

final _params = <String, dynamic>{
  'coins': <Map<String, dynamic>>[
    {'coin': 'KMD'},
  ],
};

const _copyCoinsThenExit2 = r'''
cp "$MM_COINS_PATH" "$(dirname "$0")/coins.json"
exit 2''';

class _FixedFinder extends KdfExecutableFinder {
  _FixedFinder(this._executable) : super(logCallback: (_) {});

  final File? _executable;

  @override
  Future<File?> findExecutable({String executableName = 'kdf'}) async =>
      _executable;
}
