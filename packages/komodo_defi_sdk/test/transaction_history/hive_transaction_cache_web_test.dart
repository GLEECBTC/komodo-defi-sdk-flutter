@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/history_cache_lease.dart';
import 'package:komodo_defi_sdk/src/transaction_history/hive_transaction_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_cache_policy.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'transaction_fixtures.dart';

Future<JSAny?> _request(web.IDBRequest request) {
  final result = Completer<JSAny?>();
  request
    ..onsuccess = ((web.Event _) => result.complete(request.result)).toJS
    ..onerror = ((web.Event _) => result.completeError(
      StateError('IndexedDB test request failed'),
    )).toJS;
  return result.future;
}

void main() {
  late String name;
  final handles = <HiveTransactionStorage>[];
  final wallet = testWallet();
  final asset = testAssetId();

  HiveTransactionStorage open({
    TransactionHistoryCachePolicy policy =
        const TransactionHistoryCachePolicy(),
  }) {
    final store = HiveTransactionStorage(
      boxName: name,
      policy: policy,
      keyProvider: testHistoryCacheKeys,
    );
    handles.add(store);
    return store;
  }

  setUp(() {
    name = 'history_web_${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    for (final store in handles) {
      await store.close();
    }
    handles.clear();
    await Hive.close();
    await Hive.deleteBoxFromDisk(name);
  });

  test(
    'actual IndexedDB values are encrypted and keys hide transaction metadata',
    () async {
      final original = testTransaction(
        internalId: 'browser-private-id-sentinel',
        txHash: 'browser-private-hash-sentinel',
        from: const ['browser-private-address-sentinel'],
      );
      final store = open();
      await store.storeTransaction(original, wallet);
      expect(store.isDegraded, isFalse);
      final database =
          (await _request(web.window.indexedDB.open(name)))! as web.IDBDatabase;
      try {
        final objectStore = database
            .transaction('box'.toJS, 'readonly')
            .objectStore('box');
        final keysRequest = objectStore.getAllKeys();
        final valuesRequest = objectStore.getAll();
        final keys = (await _request(keysRequest))! as JSArray<JSAny?>;
        final values = (await _request(valuesRequest))! as JSArray<JSAny?>;
        expect(
          keys.toDart.map((key) => key.dartify()),
          everyElement(matches(RegExp(r'^[0-9a-f]{64}$'))),
        );
        expect(values.toDart, hasLength(1));
        final value = values.toDart.single;
        expect(value.isA<JSArrayBuffer>(), isTrue);
        final raw = latin1.decode(
          Uint8List.view((value! as JSArrayBuffer).toDart),
        );
        expect(raw, isNot(contains(original.internalId)));
        expect(raw, isNot(contains(original.txHash)));
        expect(raw, isNot(contains(original.from.single)));
        expect(
          raw,
          isNot(contains(original.timestamp.microsecondsSinceEpoch.toString())),
        );
      } finally {
        database.close();
      }
      await store.close();
      expect(
        (await open().getTransactions(asset, wallet)).transactions.single,
        original,
      );
    },
  );

  test('a competing Web Lock owner gets bounded memory, '
      'and release permits persistence', () async {
    final otherOwner = await HistoryCacheLease.acquire(name);
    addTearDown(otherOwner.release);
    final blocked = open(
      policy: const TransactionHistoryCachePolicy(maxTransactionsPerAsset: 2),
    );
    await blocked.storeTransactions([
      for (var i = 0; i < 4; i++) testTransaction(internalId: 'row-$i'),
    ], wallet);
    expect(blocked.isDegraded, isTrue);
    expect((await blocked.getTransactions(asset, wallet)).cachedCount, 2);
    expect(await Hive.boxExists(name), isFalse);
    await blocked.close();
    await otherOwner.release();
    final persistent = open();
    await persistent.storeTransaction(testTransaction(), wallet);
    expect(persistent.isDegraded, isFalse);
    expect(Hive.isBoxOpen(name), isTrue);
  });

  test('legacy plaintext retirement closes its own database handles', () async {
    final legacy = await Hive.openBox<String>('komodo_tx_history_v1');
    await legacy.put('legacy-id', 'legacy-address');
    await legacy.close();
    await HiveTransactionStorage.retireLegacyCache().timeout(
      const Duration(seconds: 2),
    );
    expect(await Hive.boxExists('komodo_tx_history_v1'), isFalse);
  });

  test('IndexedDB retains bounded rows after eviction and reopen', () async {
    const policy = TransactionHistoryCachePolicy(maxTransactionsPerAsset: 2);
    final first = open(policy: policy);
    await first.storeTransactions([
      for (var i = 0; i < 5; i++)
        testTransaction(
          internalId: 'row-$i',
          timestamp: DateTime.utc(2026, 1, i + 1),
        ),
    ], wallet);
    expect(Hive.lazyBox<String>(name).length, 2);
    await first.close();
    final reopened = open(policy: policy);
    expect(
      (await reopened.getTransactions(
        asset,
        wallet,
      )).transactions.map((row) => row.internalId),
      ['row-4', 'row-3'],
    );
  });
}
