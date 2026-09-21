@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/history_cache_key_provider.dart';
import 'package:komodo_defi_sdk/src/transaction_history/hive_transaction_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_cache_policy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';

import 'transaction_fixtures.dart';

class _UnavailableKey implements HistoryCacheKeyProvider {
  @override
  Future<List<int>> loadOrCreate(String cacheName) async =>
      throw StateError('synthetic secret must not appear in diagnostics');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final handles = <HiveTransactionStorage>[];
  final wallet = testWallet();
  final asset = testAssetId();

  HiveTransactionStorage open({
    TransactionHistoryCachePolicy policy =
        const TransactionHistoryCachePolicy(),
    HistoryCacheKeyProvider? keys,
  }) {
    final store = HiveTransactionStorage(
      policy: policy,
      keyProvider: keys ?? testHistoryCacheKeys,
    );
    handles.add(store);
    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('encrypted_history_');
    Hive.init(directory.path);
    FlutterSecureStorage.setMockInitialValues({'wallet-secret': 'keep-me'});
  });

  tearDown(() async {
    for (final handle in handles) {
      await handle.close();
    }
    handles.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'failed purge reports retained encrypted rows instead of success',
    () async {
      final store = open();
      await store.storeTransaction(
        testTransaction(internalId: 'retained'),
        wallet,
      );
      await Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName).close();
      await expectLater(
        store.purgeWallet(wallet),
        throwsA(isA<TransactionStorageException>()),
      );
      await store.close();
      final reopened = open();
      expect((await reopened.getTransactions(asset, wallet)).cachedCount, 1);
      await reopened.purgeWallet(wallet);
      expect((await reopened.getTransactions(asset, wallet)).cachedCount, 0);
    },
  );

  test(
    'queued writes and reads share the same memory fallback after IO failure',
    () async {
      final store = open();
      await store.storeTransaction(testTransaction(internalId: 'seed'), wallet);
      // Simulate the persistent handle becoming unusable while its SDK owner
      // remains alive. Queued operations must observe the backend transition.
      await Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName).close();
      final first = store.storeTransaction(
        testTransaction(internalId: 'first'),
        wallet,
      );
      final second = store.storeTransaction(
        testTransaction(internalId: 'second'),
        wallet,
      );
      final queuedRead = store.getTransactions(asset, wallet);
      await Future.wait([first, second]);
      expect(store.isDegraded, isTrue);
      expect(
        (await queuedRead).transactions.map((row) => row.internalId),
        unorderedEquals(['first', 'second']),
      );
      expect((await store.getStats()).totalTransactions, 2);
      await expectLater(
        store.purgeWallet(wallet),
        throwsA(isA<TransactionStorageException>()),
      );
      expect((await store.getTransactions(asset, wallet)).cachedCount, 0);
    },
  );

  test(
    'disk contains encrypted values and opaque keys, including after reopen',
    () async {
      final row = testTransaction(
        internalId: 'private-transaction-id-sentinel',
        txHash: 'private-chain-hash-sentinel',
        from: const ['private-source-address-sentinel'],
        to: const ['private-destination-address-sentinel'],
        memo: 'private-memo-sentinel',
      );
      final first = open();
      await first.storeTransaction(row, wallet);
      final box = Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName);
      expect(box.keys, everyElement(matches(RegExp(r'^[0-9a-f]{64}$'))));
      final opaqueKeys = box.keys.toList();
      await first.close();
      final raw = latin1.decode(
        await File(
          '${directory.path}/${HiveTransactionStorage.defaultBoxName}.hive',
        ).readAsBytes(),
      );
      for (final marker in [
        row.internalId,
        row.txHash!,
        ...row.from,
        ...row.to,
        row.memo!,
        row.timestamp.microsecondsSinceEpoch.toString(),
        wallet.pubkeyHash!,
      ]) {
        expect(
          raw,
          isNot(contains(marker)),
          reason: 'must not persist $marker in plaintext',
        );
      }
      final reopened = open();
      expect(
        (await reopened.getTransactions(asset, wallet)).transactions.single,
        row,
      );
      expect(
        Hive.lazyBox<String>(
          HiveTransactionStorage.defaultBoxName,
        ).keys.toList(),
        opaqueKeys,
      );
    },
  );

  test(
    'the same transaction id has distinct opaque keys in distinct wallets',
    () async {
      final store = open();
      await store.storeTransaction(testTransaction(), wallet);
      await store.storeTransaction(
        testTransaction(),
        testWallet(pubkeyHash: 'another-wallet'),
      );
      expect(
        Hive.lazyBox<String>(
          HiveTransactionStorage.defaultBoxName,
        ).keys.toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'plaintext cache is retired even when secure storage is unavailable',
    () async {
      final legacy = await Hive.openBox<String>('komodo_tx_history_v1');
      await legacy.put('old-plaintext-id', 'old-plaintext-address');
      await legacy.close();
      final store = open(keys: _UnavailableKey());
      await store.storeTransaction(testTransaction(), wallet);
      expect(store.isDegraded, isTrue);
      expect(await Hive.boxExists('komodo_tx_history_v1'), isFalse);
      expect(
        await Hive.boxExists(HiveTransactionStorage.defaultBoxName),
        isFalse,
      );
      expect((await store.getTransactions(asset, wallet)).cachedCount, 1);
    },
  );

  test(
    'secure provider retains its random key and isolates unrelated secrets',
    () async {
      final provider = SecureHistoryCacheKeyProvider();
      final first = await provider.loadOrCreate('cache-a');
      expect(first, hasLength(32));
      expect(await provider.loadOrCreate('cache-a'), first);
      expect(await provider.loadOrCreate('cache-b'), isNot(first));
      expect(
        await const FlutterSecureStorage().read(key: 'wallet-secret'),
        'keep-me',
      );
    },
  );

  test(
    'lost secure key rebuilds the cache without touching unrelated secrets',
    () async {
      final provider = SecureHistoryCacheKeyProvider();
      final first = open(keys: provider);
      await first.storeTransaction(
        testTransaction(internalId: 'before-key-loss'),
        wallet,
      );
      await first.close();
      const secrets = FlutterSecureStorage();
      final stored = await secrets.readAll();
      final keyName = stored.keys.singleWhere(
        (key) => key.startsWith('komodo_tx_history_key_v2.'),
      );
      await secrets.delete(key: keyName);
      final reopened = open(keys: provider);
      expect(
        (await reopened.getTransactions(asset, wallet)).transactions,
        isEmpty,
      );
      await reopened.storeTransaction(
        testTransaction(internalId: 'after-key-loss'),
        wallet,
      );
      expect(
        (await reopened.getTransactions(
          asset,
          wallet,
        )).transactions.single.internalId,
        'after-key-loss',
      );
      expect(await secrets.read(key: 'wallet-secret'), 'keep-me');
    },
  );

  test(
    'a malformed key degrades without overwriting it or persisting plaintext',
    () async {
      final provider = SecureHistoryCacheKeyProvider();
      await provider.loadOrCreate(HiveTransactionStorage.defaultBoxName);
      const secrets = FlutterSecureStorage();
      final keyName = (await secrets.readAll()).keys.singleWhere(
        (key) => key.startsWith('komodo_tx_history_key_v2.'),
      );
      await secrets.write(key: keyName, value: 'invalid-key-sentinel');
      final store = open(keys: provider);
      await store.storeTransaction(testTransaction(), wallet);
      expect(store.isDegraded, isTrue);
      expect(
        await Hive.boxExists(HiveTransactionStorage.defaultBoxName),
        isFalse,
      );
      expect(await secrets.read(key: keyName), 'invalid-key-sentinel');
    },
  );

  test(
    'an externally opened plaintext box is never adopted for writes',
    () async {
      final external = await Hive.openLazyBox<String>(
        HiveTransactionStorage.defaultBoxName,
      );
      final store = open();
      await store.storeTransaction(testTransaction(), wallet);
      expect(store.isDegraded, isTrue);
      expect(external.keys, isEmpty);
    },
  );

  test(
    'persistent per-asset bounds survive reopen and a smaller policy',
    () async {
      final store = open(
        policy: const TransactionHistoryCachePolicy(maxTransactionsPerAsset: 3),
      );
      await store.storeTransactions([
        for (var i = 0; i < 8; i++)
          testTransaction(
            internalId: 'row-$i',
            timestamp: DateTime.utc(2026, 1, i + 1),
          ),
      ], wallet);
      expect(
        (await store.getTransactions(
          asset,
          wallet,
        )).transactions.map((row) => row.internalId),
        ['row-7', 'row-6', 'row-5'],
      );
      await store.close();
      final smaller = open(
        policy: const TransactionHistoryCachePolicy(maxTransactionsPerAsset: 2),
      );
      expect(
        (await smaller.getTransactions(
          asset,
          wallet,
        )).transactions.map((row) => row.internalId),
        ['row-7', 'row-6'],
      );
      expect(
        Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName).length,
        2,
      );
    },
  );

  for (final persistent in [false, true]) {
    test(
      '${persistent ? 'disk' : 'memory'} evicts the least recently used scope '
      'at the global cap',
      () async {
        const policy = TransactionHistoryCachePolicy(maxTransactions: 3);
        final TransactionStorage store = persistent
            ? open(policy: policy)
            : InMemoryTransactionStorage(policy: policy);
        final other = testWallet(pubkeyHash: 'other');
        await store.storeTransactions([
          testTransaction(internalId: 'a-old'),
          testTransaction(internalId: 'a-new'),
        ], wallet);
        await store.storeTransaction(testTransaction(internalId: 'b'), other);
        await store.getTransactions(asset, wallet);
        await store.storeTransaction(
          testTransaction(internalId: 'a-newest'),
          wallet,
        );
        expect((await store.getTransactions(asset, wallet)).cachedCount, 3);
        expect((await store.getTransactions(asset, other)).cachedCount, 0);
      },
    );

    test('${persistent ? 'disk' : 'memory'} accounts for escaped payload '
        'and index bytes', () async {
      const policy = TransactionHistoryCachePolicy(maxLogicalBytes: 2500);
      final TransactionStorage store = persistent
          ? open(policy: policy)
          : InMemoryTransactionStorage(policy: policy);
      await store.storeTransaction(testTransaction(memo: '"' * 1000), wallet);
      expect((await store.getTransactions(asset, wallet)).cachedCount, 0);
      await store.storeTransaction(testTransaction(), wallet);
      expect((await store.getTransactions(asset, wallet)).cachedCount, 1);
      final bytes = store is HiveTransactionStorage
          ? store.logicalBytes
          : (store as InMemoryTransactionStorage).logicalBytes;
      expect(bytes, lessThanOrEqualTo(policy.maxLogicalBytes));
    });
  }

  test('fallback enforces limits and wallet purge', () async {
    final store = open(
      keys: _UnavailableKey(),
      policy: const TransactionHistoryCachePolicy(maxTransactionsPerAsset: 2),
    );
    await store.storeTransactions([
      for (var i = 0; i < 10; i++) testTransaction(internalId: 'row-$i'),
    ], wallet);
    expect(store.isDegraded, isTrue);
    expect((await store.getTransactions(asset, wallet)).cachedCount, 2);
    await expectLater(
      store.purgeWallet(wallet),
      throwsA(isA<TransactionStorageException>()),
    );
    expect((await store.getTransactions(asset, wallet)).cachedCount, 0);
  });

  test('compaction reclaims superseded encrypted payloads on close', () async {
    final row = testTransaction(memo: 'memo' * 300);
    final first = open();
    await first.storeTransaction(row, wallet);
    await first.close();
    final file = File(
      '${directory.path}/${HiveTransactionStorage.defaultBoxName}.hive',
    );
    final initialBytes = await file.length();
    final updated = open();
    for (var i = 2; i < 100; i++) {
      await updated.storeTransaction(row.copyWith(confirmations: i), wallet);
    }
    await updated.close();
    expect(await file.length(), lessThan(initialBytes * 2));
    expect(
      (await open().getTransactions(
        asset,
        wallet,
      )).transactions.single.confirmations,
      99,
    );
  });

  test('replacing a corrupt record does not delete the new row', () async {
    final store = open();
    await store.storeTransaction(testTransaction(), wallet);
    final box = Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName);
    await box.put(box.keys.single, '{broken');
    await store.storeTransaction(testTransaction(confirmations: 12), wallet);
    expect(
      (await store.getTransactions(
        asset,
        wallet,
      )).transactions.single.confirmations,
      12,
    );
    await store.close();
    expect(
      (await open().getTransactions(
        asset,
        wallet,
      )).transactions.single.confirmations,
      12,
    );
  });
}
