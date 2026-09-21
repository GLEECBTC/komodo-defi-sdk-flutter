@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/history_cache_lease_native.dart';
import 'package:test/test.dart';

Future<void> _probeIsolate((String, SendPort) args) async {
  Hive.init(args.$1);
  try {
    final lease = await HistoryCacheLease.acquire('native_lease_test');
    await lease.release();
    args.$2.send('acquired');
  } on Object {
    args.$2.send('busy');
  }
}

Future<String> _isolateResult(String path) async {
  final result = ReceivePort();
  try {
    await Isolate.spawn(_probeIsolate, (path, result.sendPort));
    return await result.first.timeout(const Duration(seconds: 5)) as String;
  } finally {
    result.close();
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('history-lease-test-');
    Hive.init(directory.path);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'exclusive lease rejects another isolate and permits reacquisition',
    () async {
      final owner = await HistoryCacheLease.acquire('native_lease_test');
      try {
        expect(await _isolateResult(directory.path), 'busy');
      } finally {
        await owner.release();
      }
      expect(await _isolateResult(directory.path), 'acquired');
      await owner.release();
    },
  );

  test('independent cache directories do not contend', () async {
    final other = await Directory.systemTemp.createTemp('history-lease-other-');
    final owner = await HistoryCacheLease.acquire('native_lease_test');
    try {
      expect(await _isolateResult(other.path), 'acquired');
    } finally {
      await owner.release();
      await other.delete(recursive: true);
    }
  });

  test(
    'exclusive lease rejects another OS process without deleting its inode',
    () async {
      final owner = await HistoryCacheLease.acquire('native_lease_test');
      // Flutter's test runner lives in cache/artifacts/engine/<platform>.
      final dart = File.fromUri(
        File(
          Platform.resolvedExecutable,
        ).parent.uri.resolve('../../../dart-sdk/bin/dart'),
      );
      expect(dart.existsSync(), isTrue, reason: 'Run with flutter test');
      final probe = File('${directory.path}/probe.dart');
      await probe.writeAsString('''
import 'dart:io';
Future<void> main(List<String> args) async {
  final file = await File(args.single).open(mode: FileMode.append);
  try {
    await file.lock();
    stdout.write('acquired');
    await file.unlock();
  } on FileSystemException {
    stdout.write('busy');
  } finally {
    await file.close();
  }
}
''');
      Future<ProcessResult> runProbe() => Process.run(dart.path, [
        probe.path,
        owner.lockFilePath,
      ]).timeout(const Duration(seconds: 10));
      try {
        final blocked = await runProbe();
        expect(blocked.exitCode, 0, reason: '${blocked.stderr}');
        expect(blocked.stdout, 'busy');
      } finally {
        await owner.release();
      }
      final released = await runProbe();
      expect(released.exitCode, 0, reason: '${released.stderr}');
      expect(released.stdout, 'acquired');
    },
  );
}
