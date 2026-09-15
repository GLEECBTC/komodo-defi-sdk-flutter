@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/src/auth/wallet_catalog_lock.dart';
import 'package:web/web.dart' as web;

// These names are the coordination protocol shared by independent SDK clients.
const _catalogLock = 'gleec-wallet-catalog';
const _recordLock = 'gleec-wallet-records';

web.HTMLIFrameElement _otherContext() {
  final frame = web.HTMLIFrameElement();
  web.document.body!.appendChild(frame);
  // External JS interop methods cannot be torn off.
  // ignore: unnecessary_lambdas
  addTearDown(() => frame.remove());
  return frame;
}

Future<void> _withExternalLock(
  web.HTMLIFrameElement frame,
  String name,
  Future<void> Function() operation,
) async {
  await frame.contentWindow!.navigator.locks
      .request(
        name,
        Zone.current.bindUnaryCallback((web.Lock? lock) {
          expect(lock, isNotNull);
          return Future<void>.sync(operation).toJS;
        }).toJS,
      )
      .toDart;
}

Future<void> _expectQueuedInAnotherContext(String name) async {
  // Requests from separate clients reach the browser lock service
  // asynchronously. Wait for the request to be registered before inspecting it.
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  var snapshot = await web.window.navigator.locks.query().toDart;
  while (!snapshot.pending.toDart.any((lock) => lock.name == name) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    snapshot = await web.window.navigator.locks.query().toDart;
  }
  expect(
    snapshot.pending.toDart.where((lock) => lock.name == name),
    hasLength(1),
  );
  final held = snapshot.held.toDart.where((lock) => lock.name == name).single;
  final pending = snapshot.pending.toDart
      .where((lock) => lock.name == name)
      .single;
  expect(held.mode, 'exclusive');
  expect(pending.mode, 'exclusive');
  // The iframe owns a separate browser client controlled by this test.
  expect(pending.clientId, isNot(held.clientId));
}

String _storageKey() {
  final key = 'wallet-lock-test-${DateTime.now().microsecondsSinceEpoch}';
  addTearDown(() => web.window.localStorage.removeItem(key));
  return key;
}

void main() {
  test(
    'catalog creation sees a collision committed by another context',
    () async {
      final frame = _otherContext();
      final key = _storageKey();
      final acquired = Completer<void>();
      final commit = Completer<void>();
      final externalCreation = _withExternalLock(frame, _catalogLock, () async {
        expect(frame.contentWindow!.localStorage.getItem(key), isNull);
        acquired.complete();
        await commit.future;
        frame.contentWindow!.localStorage.setItem(key, 'original-entry');
      });
      addTearDown(() async {
        if (!commit.isCompleted) commit.complete();
        await externalCreation;
      });
      await acquired.future;

      var checkedName = false;
      final created = withWalletCatalogLock(() async {
        checkedName = true;
        if (web.window.localStorage.getItem(key) != null) return false;
        web.window.localStorage.setItem(key, 'replacement-entry');
        return true;
      });
      await _expectQueuedInAnotherContext(_catalogLock);
      expect(checkedName, isFalse);
      commit.complete();

      await externalCreation;
      expect(await created, isFalse);
      expect(web.window.localStorage.getItem(key), 'original-entry');
    },
  );

  test(
    'catalog deletion retains ownership through cleanup before recreation',
    () async {
      final frame = _otherContext();
      final key = _storageKey();
      web.window.localStorage.setItem(key, 'original-entry');
      final deleted = Completer<void>();
      final finishCleanup = Completer<void>();
      final deletion = withWalletCatalogLock(() async {
        web.window.localStorage.removeItem(key);
        deleted.complete();
        await finishCleanup.future;
        // Cleanup must finish before another client can create the same name.
        web.window.localStorage.removeItem(key);
      });
      addTearDown(() async {
        if (!finishCleanup.isCompleted) finishCleanup.complete();
        await deletion;
      });
      await deleted.future;

      var recreated = false;
      final recreation = _withExternalLock(frame, _catalogLock, () async {
        expect(frame.contentWindow!.localStorage.getItem(key), isNull);
        frame.contentWindow!.localStorage.setItem(key, 'new-entry');
        recreated = true;
      });
      await _expectQueuedInAnotherContext(_catalogLock);
      expect(recreated, isFalse);
      finishCleanup.complete();

      await Future.wait([deletion, recreation]);
      expect(recreated, isTrue);
      expect(web.window.localStorage.getItem(key), 'new-entry');
    },
  );

  test(
    'record transforms merge concurrent metadata and preserve entry identity',
    () async {
      final frame = _otherContext();
      final key = _storageKey();
      web.window.localStorage.setItem(key, jsonEncode({'existing': true}));
      final read = Completer<void>();
      final save = Completer<void>();
      final migration = withWalletCatalogLock(
        () => withWalletRecordLock(() async {
          final record =
              jsonDecode(web.window.localStorage.getItem(key)!)
                  as Map<String, dynamic>;
          read.complete();
          await save.future;
          record[walletEntryIdMetadataKey] = 'stable-entry';
          record['backup'] = true;
          web.window.localStorage.setItem(key, jsonEncode(record));
        }),
      );
      addTearDown(() async {
        if (!save.isCompleted) save.complete();
        await migration;
      });
      await read.future;

      var transformed = false;
      final patch = _withExternalLock(frame, _recordLock, () async {
        final record =
            jsonDecode(frame.contentWindow!.localStorage.getItem(key)!)
                as Map<String, dynamic>;
        record['activated_coins'] = ['BTC'];
        frame.contentWindow!.localStorage.setItem(key, jsonEncode(record));
        transformed = true;
      });
      await _expectQueuedInAnotherContext(_recordLock);
      expect(transformed, isFalse);
      save.complete();

      await Future.wait([migration, patch]);
      expect(jsonDecode(web.window.localStorage.getItem(key)!), {
        'existing': true,
        walletEntryIdMetadataKey: 'stable-entry',
        'backup': true,
        'activated_coins': ['BTC'],
      });
    },
  );

  for (final (name, run) in [
    (_catalogLock, withWalletCatalogLock<int>),
    (_recordLock, withWalletRecordLock<int>),
  ]) {
    test('$name returns results and releases after callback failure', () async {
      final frame = _otherContext();
      expect(await run(() async => 42), 42);
      final failure = StateError('operation failed');
      await expectLater(run(() async => throw failure), throwsA(same(failure)));
      var granted = false;
      await _withExternalLock(
        frame,
        name,
        () async => granted = true,
      ).timeout(const Duration(seconds: 2));
      expect(granted, isTrue);
    });
  }
}
