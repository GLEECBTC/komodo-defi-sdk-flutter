@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:dragon_logs/src/storage/opfs_interop.dart';
import 'package:dragon_logs/src/storage/storage_lifecycle.dart';
import 'package:dragon_logs/src/storage/web_log_storage_wasm.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

const _epoch = 'gleec_diagnostics_test_v1';
const _sentinel = 'SYNTHETIC_OLD_TAB_SECRET';

void main() {
  late FileSystemDirectoryHandle origin;
  late FileSystemDirectoryHandle root;
  late String testDirectory;
  late WebLogStorageWasm storage;

  setUp(() async {
    origin = await window.navigator.storage.getDirectory().toDart;
    testDirectory = 'dragon_logs_test_${DateTime.now().microsecondsSinceEpoch}';
    root = await origin
        .getDirectoryHandle(
          testDirectory,
          FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    storage = WebLogStorageWasm.forTesting(directoryProvider: () async => root);
  });

  tearDown(() async {
    await storage.dispose();
    await origin
        .removeEntry(testDirectory, FileSystemRemoveOptions(recursive: true))
        .toDart;
  });

  Future<void> init() =>
      storage.init(storageNamespace: _epoch, purgeLegacy: true);

  test(
    'OPFS migration removes legacy exports and writes only the new epoch',
    () async {
      final legacy = await root
          .getDirectoryHandle(
            'dragon_logs',
            FileSystemGetDirectoryOptions(create: true),
          )
          .toDart;
      final exports = await legacy
          .getDirectoryHandle(
            'log_export',
            FileSystemGetDirectoryOptions(create: true),
          )
          .toDart;
      await _write(exports, 'old-export.txt', _sentinel);
      await _write(legacy, 'unusual-name.bin', _sentinel);
      await init();
      await expectLater(
        root.getDirectoryHandle('dragon_logs').toDart,
        throwsA(isA<DOMException>()),
      );
      await storage.appendLog(DateTime.now(), '{"event":"safe"}');
      expect(await storage.exportLogsStream().join(), '{"event":"safe"}\n');
    },
  );

  test(
    'unsupported Web Locks fail closed and an explicit initialization retry succeeds',
    () async {
      await storage.dispose();
      var unavailable = true;
      storage = WebLogStorageWasm.forTesting(
        directoryProvider: () async => root,
        lock: (operation) async {
          if (unavailable) throw UnsupportedError('Web Locks unavailable');
          await operation();
        },
      );
      await expectLater(
        init(),
        throwsA(isA<LogStorageInitializationException>()),
      );
      await expectLater(storage.exportLogsStream().join(), throwsStateError);
      await expectLater(
        storage.appendLog(DateTime.now(), _sentinel),
        throwsStateError,
      );
      await expectLater(
        root.getDirectoryHandle(_epoch).toDart,
        throwsA(isA<DOMException>()),
      );
      unavailable = false;
      await init();
      expect(await storage.exportLogsStream().join(), isEmpty);
    },
  );

  test('write and export wait behind the migration barrier', () async {
    await storage.dispose();
    final release = Completer<FileSystemDirectoryHandle>();
    storage = WebLogStorageWasm.forTesting(
      directoryProvider: () => release.future,
    );
    final initializing = init();
    var written = false;
    var exported = false;
    final writing = storage.appendLog(DateTime.now(), '{"event":"after"}').then(
      (_) {
        written = true;
      },
    );
    final exporting = storage.exportLogsStream().join().then((value) {
      exported = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(written, isFalse);
    expect(exported, isFalse);
    release.complete(root);
    await initializing;
    await writing;
    await exporting;
    expect(await storage.exportLogsStream().join(), '{"event":"after"}\n');
  });

  test(
    'concurrent browser instances serialize full append transactions',
    () async {
      final other = WebLogStorageWasm.forTesting(
        directoryProvider: () async => root,
      );
      addTearDown(other.dispose);
      await Future.wait([
        init(),
        other.init(storageNamespace: _epoch, purgeLegacy: true),
      ]);
      await Future.wait(
        List.generate(30, (index) async {
          final target = index.isEven ? storage : other;
          await target.appendLog(DateTime.now(), '{"index":$index}');
          await target.flushQueue();
        }),
      );
      final records = const LineSplitter().convert(
        await storage.exportLogsStream().join(),
      );
      expect(records, hasLength(30));
      expect(
        records.map((record) => (jsonDecode(record) as Map)['index']).toSet(),
        Set<int>.from(List.generate(30, (index) => index)),
      );
    },
  );

  test(
    'old tab recreation is never included in safe exports or restarted epochs',
    () async {
      await init();
      await storage.appendLog(DateTime.now(), '{"event":"safe"}');
      await storage.dispose();
      final legacy = await root
          .getDirectoryHandle(
            'dragon_logs',
            FileSystemGetDirectoryOptions(create: true),
          )
          .toDart;
      await _write(legacy, 'APP-LOGS_2026-09-09.log', _sentinel);
      await init();
      expect(await storage.exportLogsStream().join(), '{"event":"safe"}\n');
    },
  );

  test('clear drains queued records and never revives deleted files', () async {
    await init();
    await storage.appendLog(DateTime.now(), '{"event":"before-clear"}');
    await storage.deleteOldLogs(0);
    await storage.flushQueue();
    expect(await storage.exportLogsStream().join(), isEmpty);
    await storage.appendLog(DateTime.now(), '{"event":"after-clear"}');
    expect(
      await storage.exportLogsStream().join(),
      '{"event":"after-clear"}\n',
    );
  });

  test('paused export does not block another browser writer', () async {
    await init();
    await storage.appendLog(DateTime.now(), '{"event":"first"}');
    final received = Completer<void>();
    late StreamSubscription<String> subscription;
    subscription = storage.exportLogsStream().listen((_) {
      subscription.pause();
      received.complete();
    });
    await received.future;
    final other = WebLogStorageWasm.forTesting(
      directoryProvider: () async => root,
    );
    addTearDown(other.dispose);
    await other.init(storageNamespace: _epoch, purgeLegacy: true);
    await other.appendLog(DateTime.now(), '{"event":"second"}');
    await other.flushQueue().timeout(const Duration(seconds: 3));
    subscription.resume();
    await subscription.cancel();
  });

  test('clearing exports spares a snapshot a running export still reads', () async {
    await init();
    await storage.appendLog(DateTime.now(), '{"event":"retained"}');
    final chunks = <String>[];
    final received = Completer<void>();
    late StreamSubscription<String> subscription;
    subscription = storage.exportLogsStream().listen((chunk) {
      chunks.add(chunk);
      subscription.pause();
      received.complete();
    });
    await received.future;
    final epoch = await root.getDirectoryHandle(_epoch).toDart;
    final cache = await epoch.getDirectoryHandle('log_export').toDart;
    await _write(cache, 'old-export.log', _sentinel);

    await storage.deleteExportedFiles().timeout(const Duration(seconds: 3));

    expect(await cache.keysStream().toList(), hasLength(1));
    final done = subscription.asFuture<void>();
    subscription.resume();
    await done.timeout(const Duration(seconds: 3));
    expect(chunks.join(), contains('retained'));

    await storage.deleteExportedFiles().timeout(const Duration(seconds: 3));
    await expectLater(
      epoch.getDirectoryHandle('log_export').toDart,
      throwsA(isA<DOMException>()),
    );
  });

  test(
    'a real worker lock prevents migration until the worker releases it',
    () async {
      const script = '''
      navigator.locks.request('dragon-logs-storage', async () => {
        postMessage('locked');
        await new Promise(resolve => { onmessage = () => resolve(); });
      }).then(() => postMessage('released'));
    ''';
      final url = URL.createObjectURL(
        Blob(
          [script.toJS].toJS,
          BlobPropertyBag(type: 'application/javascript'),
        ),
      );
      final worker = Worker(url.toJS);
      final locked = Completer<void>();
      final released = Completer<void>();
      worker.onmessage = ((MessageEvent event) {
        final state = (event.data as JSString).toDart;
        if (state == 'locked') locked.complete();
        if (state == 'released') released.complete();
      }).toJS;
      addTearDown(() {
        worker.terminate();
        URL.revokeObjectURL(url);
      });
      await locked.future.timeout(const Duration(seconds: 5));
      var initialized = false;
      final pending = init().then((_) {
        initialized = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(initialized, isFalse);
      worker.postMessage(null);
      await released.future;
      await pending;
      expect(initialized, isTrue);
    },
  );

  test(
    'bounded browser slices preserve a snapshot during another writer commit',
    () async {
      await init();
      final record = 'é' * (128 * 1024);
      await storage.appendLog(DateTime.now(), record);
      final iterator = StreamIterator(storage.exportLogsStream());
      expect(await iterator.moveNext(), isTrue);
      final contents = StringBuffer(iterator.current);
      expect(iterator.current.length, lessThanOrEqualTo(64 * 1024));
      final other = WebLogStorageWasm.forTesting(
        directoryProvider: () async => root,
      );
      addTearDown(other.dispose);
      await other.init(storageNamespace: _epoch, purgeLegacy: true);
      await other.appendLog(DateTime.now(), '{"event":"later"}');
      await other.flushQueue();
      while (await iterator.moveNext()) {
        expect(iterator.current.length, lessThanOrEqualTo(64 * 1024));
        contents.write(iterator.current);
      }
      expect(contents.toString(), '$record\n');
      await iterator.cancel();
    },
  );
}

Future<void> _write(
  FileSystemDirectoryHandle directory,
  String name,
  String content,
) async {
  final file = await directory
      .getFileHandle(name, FileSystemGetFileOptions(create: true))
      .toDart;
  final writer = await file.createWritable().toDart;
  try {
    await writer.write(content.toJS).toDart;
  } finally {
    await writer.close().toDart;
  }
}
