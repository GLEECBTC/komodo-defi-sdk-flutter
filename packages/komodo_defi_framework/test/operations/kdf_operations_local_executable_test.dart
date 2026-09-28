@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/exceptions/kdf_exception.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

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
    Future<File?> Function() findExecutable, {
    Directory? temporaryDirectory,
  }) {
    final kdf = KdfOperationsLocalExecutable.create(
      logCallback: logs.add,
      config: config,
      executableFinder: _Finder(findExecutable),
      temporaryDirectory: () async =>
          temporaryDirectory ?? Directory('${sandbox.path}/tmp'),
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

  void expectLaunchFailureLog(Matcher line) {
    final failures = logs.where((l) => l.startsWith('KDF process launch'));
    expect(failures, [line]);
    expect(
      DiagnosticSanitizer.sanitizeMessage(failures.single),
      failures.single,
    );
    expect(logs.join('\n'), isNot(contains(sandbox.path)));
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
            () async => kdf,
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

      test('returns the exit status of a KDF that exits on start', () async {
        final kdf = script('exit 4');

        final result = await operations(() async => kdf).kdfMain(_params);

        expect(result, KdfStartupResult.initError);
        await exitCleanup();
      });

      test('reports a start without a coins list as invalid params', () async {
        final kdf = script('exit 0');

        final result = await operations(
          () async => kdf,
        ).kdfMain(<String, dynamic>{});

        expect(result, KdfStartupResult.invalidParams);
        expect(logs, contains('KDF process startup failed'));
      });
    },
    skip: Platform.isWindows ? 'the fake KDF is a POSIX shell script' : null,
  );

  group(
    'KdfOperationsLocalExecutable.kdfMain when KDF never launched',
    () {
      test('reports a missing executable as a spawn error', () async {
        final result = await operations(() async => null).kdfMain(_params);

        expect(result, KdfStartupResult.spawnError);
        expectLaunchFailureLog(
          equals('KDF process launch failed type=executableNotFound'),
        );
      });

      test('reports an executable it cannot mark runnable', () async {
        final absent = File('${sandbox.path}/absent/kdf');

        final result = await operations(() async => absent).kdfMain(_params);

        expect(result, KdfStartupResult.spawnError);
        expectLaunchFailureLog(
          equals('KDF process launch failed type=permissionError'),
        );
      });

      test('reports a temporary directory it cannot create', () async {
        final kdf = script('exit 0');
        final notADirectory = File('${sandbox.path}/tmp')
          ..writeAsStringSync('');

        final result = await operations(
          () async => kdf,
          temporaryDirectory: Directory(notADirectory.path),
        ).kdfMain(_params);

        expect(result, KdfStartupResult.spawnError);
        expectLaunchFailureLog(
          matches(
            '^KDF process launch failed type=startupFailed '
            r'cause=file_system os_error=\d+$',
          ),
        );
      });

      test('reports an executable the OS refuses to run', () async {
        final directory = Directory('${sandbox.path}/kdf')..createSync();
        final temporary = Directory('${sandbox.path}/tmp');

        final result = await operations(
          () async => File(directory.path),
          temporaryDirectory: temporary,
        ).kdfMain(_params);

        expect(result, KdfStartupResult.spawnError);
        expectLaunchFailureLog(
          matches(
            '^KDF process launch failed type=startupFailed '
            r'cause=process os_error=\d+$',
          ),
        );
        expect(temporary.listSync(), isEmpty);
      });

      test('reports a coins list it cannot read', () async {
        final kdf = script('exit 0');

        final result = await operations(
          () async => kdf,
        ).kdfMain(<String, dynamic>{'coins': 'not-a-list'});

        expect(result, KdfStartupResult.spawnError);
        expectLaunchFailureLog(
          equals('KDF process launch failed type=startupFailed cause=argument'),
        );
      });

      test('reports a failing executable lookup', () async {
        final result = await operations(
          () async => throw FileSystemException('lookup failed', sandbox.path),
        ).kdfMain(_params);

        expect(result, KdfStartupResult.spawnError);
        expectLaunchFailureLog(
          equals(
            'KDF process launch failed type=startupFailed cause=file_system',
          ),
        );
      });

      test('logs only the type of an injected KdfException', () async {
        final result = await operations(
          () async => throw KdfException(
            'lookup failed',
            type: KdfExceptionType.configurationError,
            details: {'reason': sandbox.path},
          ),
        ).kdfMain(_params);

        expect(result, KdfStartupResult.spawnError);
        expectLaunchFailureLog(
          equals('KDF process launch failed type=configurationError'),
        );
      });
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

class _Finder extends KdfExecutableFinder {
  _Finder(this._find) : super(logCallback: (_) {});

  final Future<File?> Function() _find;

  @override
  Future<File?> findExecutable({String executableName = 'kdf'}) => _find();
}
