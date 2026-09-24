import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:hive_ce/hive.dart';
// The lock the deletion hooks run under; not public API.
// ignore: implementation_imports
import 'package:komodo_defi_local_auth/src/auth/wallet_catalog_lock.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/transaction_history/hive_transaction_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_record_codec.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage_key.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'transaction_fixtures.dart';
import 'transaction_storage_conformance.dart';

void main() {
  late Directory directory;
  final open = <HiveTransactionStorage>[];

  Future<HiveTransactionStorage> openStorage() async {
    final storage = HiveTransactionStorage(keyProvider: testHistoryCacheKeys);
    open.add(storage);
    return storage;
  }

  /// Closes the live storage and opens a fresh one over the same directory,
  /// which is the only honest way to prove a row reached disk.
  Future<HiveTransactionStorage> reopenStorage() async {
    for (final storage in open) {
      await storage.close();
    }
    open.clear();
    return openStorage();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tx_history_');
    Hive.init(directory.path);
  });

  tearDown(() async {
    for (final storage in open) {
      await storage.close();
    }
    open.clear();
    await Hive.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  runTransactionStorageConformanceTests(
    name: 'HiveTransactionStorage',
    create: openStorage,
    reopen: reopenStorage,
  );

  group('orphaned wallet sweep', () {
    final kept = testWallet(name: 'kept', pubkeyHash: 'kept-pubkey');
    final deleted = testWallet(name: 'deleted', pubkeyHash: 'deleted-pubkey');
    final asset = testAssetId();

    Future<HiveTransactionStorage> openWithCatalogue(
      Future<Set<String>> Function()? catalogue,
    ) async {
      final storage = HiveTransactionStorage(
        keyProvider: testHistoryCacheKeys,
        knownWalletNamespaces: catalogue,
      );
      open.add(storage);
      return storage;
    }

    Future<void> seedBothWallets() async {
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(assetId: asset, internalId: 'kept-1'),
      ], kept);
      await storage.storeTransactions([
        testTransaction(assetId: asset, internalId: 'deleted-1'),
      ], deleted);
      for (final s in open) {
        await s.close();
      }
      open.clear();
    }

    Future<int> countFor(
      HiveTransactionStorage storage,
      WalletId wallet,
    ) async =>
        (await storage.getTransactions(asset, wallet)).transactions.length;

    /// Opens via getStats, which reads no wallet: a read marks its scope in use
    /// and the sweep spares it.
    Future<void> openAndSweep(HiveTransactionStorage storage) async {
      await storage.getStats();
      await storage.orphanSweep;
    }

    test(
      'drops history for a wallet that is no longer in the catalogue',
      () async {
        // The deletion-time purge is best effort: while the store is degraded it
        // clears only memory and throws, the bootstrap hook logs that, and
        // deleteWallet still reports success. This sweep is what stops the rows
        // surviving that.
        await seedBothWallets();

        final storage = await openWithCatalogue(
          () async => {walletStorageNamespace(kept)},
        );
        await openAndSweep(storage);

        expect(await countFor(storage, deleted), 0);
        expect(
          await countFor(storage, kept),
          1,
          reason: 'a live wallet must be untouched by the sweep',
        );
      },
    );

    test(
      'an empty catalogue means do-not-know, never delete-everything',
      () async {
        await seedBothWallets();

        final storage = await openWithCatalogue(() async => <String>{});
        await openAndSweep(storage);

        expect(await countFor(storage, kept), 1);
        expect(await countFor(storage, deleted), 1);
      },
    );

    test('a throwing catalogue leaves every wallet in place', () async {
      await seedBothWallets();

      final storage = await openWithCatalogue(
        () async => throw StateError('cannot list wallets'),
      );
      await openAndSweep(storage);

      expect(await countFor(storage, kept), 1);
      expect(await countFor(storage, deleted), 1);
    });

    test('no catalogue provider sweeps nothing', () async {
      await seedBothWallets();

      final storage = await openWithCatalogue(null);
      await openAndSweep(storage);

      expect(await countFor(storage, kept), 1);
      expect(await countFor(storage, deleted), 1);
    });

    /// Released at teardown, so an open that regresses into waiting on it
    /// unwinds instead of wedging every later test's open.
    Completer<Set<String>> heldListing() {
      final listing = Completer<Set<String>>();
      addTearDown(() {
        if (!listing.isCompleted) listing.complete(<String>{});
      });
      return listing;
    }

    test('cache operations never wait for the wallet listing', () async {
      await seedBothWallets();
      final listing = heldListing();
      final storage = await openWithCatalogue(() => listing.future);

      await storage.purgeWallet(deleted).timeout(const Duration(seconds: 5));
      await storage.storeTransactions([
        testTransaction(assetId: asset, internalId: 'kept-2'),
      ], kept);
      expect(await countFor(storage, kept), 2);

      listing.complete({walletStorageNamespace(kept)});
      await storage.orphanSweep;
      expect(await countFor(storage, kept), 2);
      expect(await countFor(storage, deleted), 0);
    });

    test('history stored after a stale listing is kept', () async {
      await seedBothWallets();
      final created = testWallet(name: 'created', pubkeyHash: 'created-key');
      final listing = heldListing();
      final storage = await openWithCatalogue(() => listing.future);
      await storage.getStats();

      await storage.storeTransactions([
        testTransaction(assetId: asset, internalId: 'created-1'),
      ], created);
      listing.complete({walletStorageNamespace(kept)});
      await storage.orphanSweep;

      expect(await countFor(storage, created), 1);
      expect(await countFor(storage, kept), 1);
      expect(await countFor(storage, deleted), 0);
    });

    // Timeouts sit inside the lock: the native lock is process-wide, and a
    // regression must release it rather than wedge every later catalog test.
    group('under the wallet catalog lock', () {
      Future<HiveTransactionStorage> openListingThroughCatalog({
        void Function()? onListing,
      }) => openWithCatalogue(() {
        onListing?.call();
        return withWalletCatalogLock(
          () async => {walletStorageNamespace(kept)},
        );
      });

      test('a purge that opens the cache completes', () async {
        await seedBothWallets();
        final storage = await openListingThroughCatalog();

        await withWalletCatalogLock(
          () =>
              storage.purgeWallet(deleted).timeout(const Duration(seconds: 5)),
        );
        await storage.orphanSweep;

        expect(await countFor(storage, deleted), 0);
        expect(await countFor(storage, kept), 1);
      });

      test('a purge completes while another caller opens the cache', () async {
        await seedBothWallets();
        final listingStarted = Completer<void>();
        final storage = await openListingThroughCatalog(
          onListing: listingStarted.complete,
        );
        final catalogHeld = Completer<void>();

        final deletion = withWalletCatalogLock(() async {
          catalogHeld.complete();
          await listingStarted.future;
          await storage
              .purgeWallet(deleted)
              .timeout(const Duration(seconds: 5));
        });
        await catalogHeld.future;
        final read = countFor(storage, kept);

        await Future.wait([
          read,
          deletion,
        ]).timeout(const Duration(seconds: 10));
        await storage.orphanSweep;
        expect(await countFor(storage, deleted), 0);
      });
    });
  });

  group('HiveTransactionStorage persistence', () {
    final wallet = testWallet();
    final asset = testAssetId();

    test('a full transaction survives a reopen by value equality', () async {
      final original = testTransaction(
        internalId: 'tx-0',
        id: 'distinct-id',
        confirmations: 7,
        blockHeight: 900,
        receivedByMe: Decimal.parse('1.25'),
        spentByMe: Decimal.parse('0.5'),
        totalAmount: Decimal.parse('1.75'),
        from: const ['from-a', 'from-b'],
        to: const ['to-a'],
        memo: 'a memo',
        fee: FeeInfo.tendermint(
          coin: 'IRIS',
          amount: Decimal.parse('0.038553'),
          gasLimit: 100000,
        ),
      );

      final storage = await openStorage();
      await storage.storeTransactions([original], wallet);

      final restored = await reopenStorage();
      final page = await restored.getTransactions(asset, wallet);
      expect(page.transactions.single, original);
      expect(page.transactions.single.fee, isA<FeeInfoTendermint>());
    });

    test('rows are scoped to the caller supplied asset id', () async {
      // Scoped decoding hands back the live AssetId, so parentId linkage and
      // the concrete ChainId subtype survive rather than being reconstructed.
      final parent = testAssetId(id: 'TRX', subClass: CoinSubClass.trx);
      final child = testAssetId(parentId: parent);

      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0', assetId: child),
      ], wallet);

      final restored = await reopenStorage();
      final page = await restored.getTransactions(child, wallet);
      expect(identical(page.transactions.single.assetId, child), isTrue);
      expect(page.transactions.single.assetId.parentId, parent);
    });

    test('ordering survives a reopen', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        for (var i = 0; i < 5; i++)
          testTransaction(
            internalId: 'tx-$i',
            timestamp: DateTime.utc(2026, 7, 20).subtract(Duration(days: i)),
          ),
      ], wallet);

      final restored = await reopenStorage();
      final page = await restored.getTransactions(asset, wallet, limit: 10);
      expect(page.transactions.map((tx) => tx.internalId), [
        'tx-0',
        'tx-1',
        'tx-2',
        'tx-3',
        'tx-4',
      ]);
    });

    test('wallets stay isolated across a reopen', () async {
      final first = testWallet(pubkeyHash: 'aaaa');
      final second = testWallet(pubkeyHash: 'bbbb');

      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'first-tx'),
      ], first);
      await storage.storeTransactions([
        testTransaction(internalId: 'second-tx'),
      ], second);

      final restored = await reopenStorage();
      expect(
        (await restored.getTransactions(
          asset,
          first,
        )).transactions.single.internalId,
        'first-tx',
      );
      expect(
        (await restored.getTransactions(
          asset,
          second,
        )).transactions.single.internalId,
        'second-tx',
      );
    });

    test('a renamed wallet keeps its history', () async {
      // walletStorageNamespace keys enriched identities by pubkey hash, so a
      // display-name change must not orphan the cache. This is deliberately
      // different from the in-memory store, which keys on raw WalletId
      // equality, and so is asserted here rather than in the shared suite.
      final before = testWallet(name: 'old name', pubkeyHash: 'abc123');
      final after = testWallet(name: 'new name', pubkeyHash: 'abc123');

      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], before);

      final restored = await reopenStorage();
      expect((await restored.getTransactions(asset, after)).cachedCount, 1);
    });

    test('pubkey hash casing does not fork the history', () async {
      final lower = testWallet(pubkeyHash: 'abcdef');
      final upper = testWallet(pubkeyHash: 'ABCDEF');

      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], lower);

      expect((await storage.getTransactions(asset, upper)).cachedCount, 1);
    });

    test('a name-only identity stays separate from an enriched one', () async {
      final nameOnly = testWallet(pubkeyHash: null);
      final enriched = testWallet(pubkeyHash: 'abc123');

      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'name-only-tx'),
      ], nameOnly);
      await storage.storeTransactions([
        testTransaction(internalId: 'enriched-tx'),
      ], enriched);

      expect(
        (await storage.getTransactions(
          asset,
          nameOnly,
        )).transactions.single.internalId,
        'name-only-tx',
      );
      expect(
        (await storage.getTransactions(
          asset,
          enriched,
        )).transactions.single.internalId,
        'enriched-tx',
      );
    });
  });

  group('HiveTransactionStorage write behaviour', () {
    final wallet = testWallet();
    final asset = testAssetId();

    Future<LazyBox<String>> boxOf() async =>
        Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName);

    test('an injected legacy key is discarded on reopen', () async {
      final storage = await openStorage();
      final confirmed = testTransaction(
        internalId: 'tx-0',
        timestamp: DateTime.utc(2026, 7, 10),
      );
      await storage.storeTransactions([confirmed], wallet);

      // Simulate the crash window in _writeBatch: the replacement row was
      // written, but the displaced pending-timestamp record never deleted.
      final staleKey = TransactionStorageKey.build(
        prefix: TransactionStorageKey.prefix(wallet, asset),
        timestamp: DateTime.utc(1970),
        internalId: 'tx-0',
      );
      await (await boxOf()).put(
        staleKey,
        TransactionRecordCodec.encode(
          confirmed.copyWith(timestamp: DateTime.utc(1970), confirmations: 0),
        ),
      );

      final restored = await reopenStorage();
      final page = await restored.getTransactions(asset, wallet);
      expect(page.cachedCount, 1, reason: 'the duplicate must collapse');
      expect(
        page.transactions.single.timestamp,
        DateTime.utc(2026, 7, 10),
        reason: 'the newest row is the authoritative one',
      );
      expect(
        (await boxOf()).containsKey(staleKey),
        isFalse,
        reason: 'the superseded record is evicted from disk',
      );
    });

    test('re-storing an identical row writes nothing new', () async {
      final storage = await openStorage();
      final transaction = testTransaction(internalId: 'tx-0');
      await storage.storeTransactions([transaction], wallet);

      final box = await boxOf();
      final keysBefore = box.keys.toList();

      // The confirmations refresh re-stores page one every 30 seconds; the
      // overwhelming majority of those rows are byte-identical.
      await storage.storeTransactions([transaction], wallet);

      expect(box.keys.toList(), keysBefore);
      expect((await storage.getTransactions(asset, wallet)).cachedCount, 1);
    });

    test('a pending row confirms under the same opaque key', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(
          internalId: 'tx-0',
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          confirmations: 0,
          blockHeight: 0,
        ),
      ], wallet);

      final box = await boxOf();
      expect(box.keys, hasLength(1));
      final pendingKey = box.keys.single as String;

      await storage.storeTransactions([
        testTransaction(
          internalId: 'tx-0',
          timestamp: DateTime.utc(2026, 7, 10),
          confirmations: 6,
          blockHeight: 900,
        ),
      ], wallet);

      expect(box.keys, hasLength(1), reason: 'the stale key must be deleted');
      expect(
        box.keys.single,
        pendingKey,
        reason: 'opaque identity is independent of timestamp',
      );

      final page = await storage.getTransactions(asset, wallet);
      expect(page.cachedCount, 1);
      expect(page.transactions.single.confirmations, 6);
      expect(page.transactions.single.timestamp, DateTime.utc(2026, 7, 10));
    });

    test('one entry is written per transaction', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        for (var i = 0; i < 12; i++)
          testTransaction(
            internalId: 'tx-$i',
            timestamp: DateTime.utc(2026, 7, 10).add(Duration(minutes: i)),
          ),
      ], wallet);

      expect((await boxOf()).keys, hasLength(12));
    });

    test('clearing deletes the rows from disk', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);
      await storage.clearTransactions(asset, wallet);

      expect((await boxOf()).keys, isEmpty);
    });

    test('purgeWallet removes only that wallet', () async {
      final first = testWallet(pubkeyHash: 'aaaa');
      final second = testWallet(pubkeyHash: 'bbbb');

      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'first-tx'),
      ], first);
      await storage.storeTransactions([
        testTransaction(internalId: 'second-tx'),
      ], second);

      await storage.purgeWallet(first);

      expect((await storage.getTransactions(asset, first)).cachedCount, 0);
      expect((await storage.getTransactions(asset, second)).cachedCount, 1);
      expect((await boxOf()).keys, hasLength(1));
    });

    test('an over-long internal id is stored and read back intact', () async {
      final longId = 'z' * 5000;
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: longId),
      ], wallet);

      final restored = await reopenStorage();
      final page = await restored.getTransactions(asset, wallet);
      expect(page.transactions.single.internalId, longId);
      // The key holds a digest, so this must come from the record body.
      expect(await restored.getLatestTransactionId(asset, wallet), longId);
    });
  });

  group('HiveTransactionStorage recovery', () {
    final wallet = testWallet();
    final asset = testAssetId();

    test('drops a record that is not valid JSON', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'good-0'),
        testTransaction(
          internalId: 'bad',
          timestamp: DateTime.utc(2026, 7, 11),
        ),
        testTransaction(
          internalId: 'good-1',
          timestamp: DateTime.utc(2026, 7, 12),
        ),
      ], wallet);

      final box = Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName);
      String? badKey;
      for (final key in box.keys.cast<String>()) {
        final envelope =
            jsonDecode((await box.get(key))!) as Map<String, dynamic>;
        if (TransactionStorageKey.parse(envelope['key'] as String)!.idToken ==
            'bad') {
          badKey = key;
        }
      }
      expect(badKey, isNotNull);
      await box.put(badKey, '{not json');

      final page = await storage.getTransactions(asset, wallet, limit: 10);
      expect(page.transactions.map((tx) => tx.internalId), [
        'good-1',
        'good-0',
      ]);
    });

    test('drops a record written by a newer schema', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);

      final box = Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName);
      final key = box.keys.single as String;
      final encoded = TransactionRecordCodec.encodeToMap(
        testTransaction(internalId: 'tx-0'),
      );
      encoded['v'] = TransactionRecordCodec.currentVersion + 1;
      final envelope =
          jsonDecode((await box.get(key))!) as Map<String, dynamic>;
      envelope['record'] = jsonEncode(encoded);
      await box.put(key, jsonEncode(envelope));

      // Never throws: a downgrade should cost a refetch, not a broken wallet.
      final page = await storage.getTransactions(asset, wallet);
      expect(page.transactions, isEmpty);
    });

    test('drops unparseable keys at open', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);

      final box = Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName);
      await box.put('a-key-from-nowhere', 'whatever');
      expect(box.keys, hasLength(2));

      final restored = await reopenStorage();
      expect((await restored.getTransactions(asset, wallet)).cachedCount, 1);
      expect(
        Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName).keys,
        hasLength(1),
      );
    });

    test('validation still throws while everything else degrades', () async {
      final storage = await openStorage();
      await expectLater(
        storage.storeTransaction(testTransaction(internalId: ''), wallet),
        throwsA(isA<TransactionStorageException>()),
      );
    });
  });

  group('HiveTransactionStorage unreadable rows', () {
    final wallet = testWallet();
    final asset = testAssetId();

    test('a row that fails to read leaves no phantom in the index', () async {
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);
      expect((await storage.getTransactions(asset, wallet)).cachedCount, 1);

      // Close the box behind the storage's back so every `LazyBox.get`
      // throws the way a corrupt or unreadable backend would.
      await Hive.lazyBox<String>(HiveTransactionStorage.defaultBoxName).close();

      // The failed read is contained and must also drop the key from the
      // index - a key left behind is a phantom the process keeps counting.
      final broken = await storage.getTransactions(asset, wallet);
      expect(broken.transactions, isEmpty);

      final after = await storage.getTransactions(asset, wallet);
      expect(
        after.cachedCount,
        0,
        reason: 'the unreadable key must not be counted',
      );
      expect(await storage.getLatestTransactionId(asset, wallet), isNull);
    });
  });

  group('HiveTransactionStorage shared acquisition', () {
    final wallet = testWallet();
    final asset = testAssetId();

    test('acquire shares one instance and close is refcounted', () async {
      final first = HiveTransactionStorage.acquire(
        keyProvider: testHistoryCacheKeys,
      );
      final second = HiveTransactionStorage.acquire(
        keyProvider: testHistoryCacheKeys,
      );
      // Failure-safe drains: extra closes on a released instance are no-ops.
      addTearDown(first.close);
      addTearDown(second.close);

      expect(
        identical(first, second),
        isTrue,
        reason: 'containers over one box name must share one store and index',
      );

      await first.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);

      // Releasing one acquirer must not close the box under the other.
      await first.close();
      await second.storeTransactions([
        testTransaction(internalId: 'tx-1'),
      ], wallet);
      expect((await second.getTransactions(asset, wallet)).cachedCount, 2);

      // The last release really closes; a later acquire starts fresh over
      // the same persisted data.
      await second.close();
      final third = HiveTransactionStorage.acquire(
        keyProvider: testHistoryCacheKeys,
      );
      addTearDown(third.close);
      expect(identical(third, first), isFalse);
      expect((await third.getTransactions(asset, wallet)).cachedCount, 2);
    });

    test('an acquire during the final close waits for the release', () async {
      final first = HiveTransactionStorage.acquire(
        keyProvider: testHistoryCacheKeys,
      );
      addTearDown(first.close);
      await first.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);

      // Deliberately not awaited: the registry entry is gone but the box is
      // still releasing when the next acquire arrives.
      final closing = first.close();
      final second = HiveTransactionStorage.acquire(
        keyProvider: testHistoryCacheKeys,
      );
      addTearDown(second.close);
      expect(identical(second, first), isFalse);

      // The replacement must not adopt the closing box - its open waits for
      // the release and reopens - so reads and writes keep working instead
      // of landing on a box closed underneath it.
      expect((await second.getTransactions(asset, wallet)).cachedCount, 1);
      await second.storeTransactions([
        testTransaction(internalId: 'tx-1'),
      ], wallet);
      expect((await second.getTransactions(asset, wallet)).cachedCount, 2);
      await closing;
    });
  });

  group('HiveTransactionStorage degraded mode', () {
    final wallet = testWallet();
    final asset = testAssetId();

    /// Occupies the box name with an incompatible value type, so opening it as
    /// `LazyBox<String>` fails the way a corrupt or unreadable box would.
    Future<void> blockTheBox() async {
      await Hive.openBox<int>(HiveTransactionStorage.defaultBoxName);
    }

    test('an unopenable box does not throw and still serves reads', () async {
      await blockTheBox();
      final storage = await openStorage();

      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);

      expect(storage.isDegraded, isTrue);
      final page = await storage.getTransactions(asset, wallet);
      expect(page.transactions.single.internalId, 'tx-0');
    });

    test('every read path degrades rather than throwing', () async {
      await blockTheBox();
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);

      expect(await storage.getLatestTransactionId(asset, wallet), 'tx-0');
      expect((await storage.getTransactionById('tx-0'))?.internalId, 'tx-0');
      expect((await storage.getStats()).totalTransactions, 1);
      await storage.clearTransactions(asset, wallet);
      expect((await storage.getTransactions(asset, wallet)).cachedCount, 0);
    });

    test('validation still throws in degraded mode', () async {
      await blockTheBox();
      final storage = await openStorage();

      await expectLater(
        storage.storeTransaction(testTransaction(internalId: ''), wallet),
        throwsA(isA<TransactionStorageException>()),
      );
    });

    test('degraded rows do not survive a reopen', () async {
      // The point of naming this state is that it is lossy: nothing reached
      // disk, so a restart legitimately starts empty.
      await blockTheBox();
      final storage = await openStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'tx-0'),
      ], wallet);
      expect(storage.isDegraded, isTrue);

      await storage.close();
      await Hive.close();
      Hive.init(directory.path);

      final restored = await openStorage();
      expect(restored.isDegraded, isFalse);
      expect((await restored.getTransactions(asset, wallet)).cachedCount, 0);
    });
  });

  test(
    'cold purge removes only the requested wallet without a catalogue',
    () async {
      final wallet = testWallet();
      final otherWallet = testWallet(pubkeyHash: 'other-pubkey');
      final asset = testAssetId();
      final seeded = await openStorage();
      await seeded.storeTransaction(
        testTransaction(internalId: 'keep'),
        wallet,
      );
      await seeded.storeTransaction(
        testTransaction(internalId: 'remove'),
        otherWallet,
      );
      await seeded.close();
      open.clear();

      final storage = HiveTransactionStorage(keyProvider: testHistoryCacheKeys);
      open.add(storage);
      await storage.purgeWallet(otherWallet);
      expect((await storage.getTransactions(asset, wallet)).cachedCount, 1);
      expect(
        (await storage.getTransactions(asset, otherWallet)).cachedCount,
        0,
      );
    },
  );
}
