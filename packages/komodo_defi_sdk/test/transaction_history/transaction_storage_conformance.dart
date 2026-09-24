// The `TransactionStorage` contract, run against every implementation.
//
// Deliberately not named `*_test.dart`: it is driven by
// `in_memory_transaction_storage_test.dart` and
// `hive_transaction_storage_test.dart`, which supply the factory.
//
// Only behaviour that every implementation must share belongs here. Wallet
// identity axes that legitimately differ - a persisted store keys through
// `walletStorageNamespace`, which is deliberately tolerant of renames and
// pubkey-hash casing, while the in-memory store keys on raw `WalletId`
// equality - are asserted in the implementation-specific suites instead.
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'transaction_fixtures.dart';

/// Runs the shared contract against the storage produced by [create].
///
/// [reopen] is supplied only by persistent implementations: when non-null, the
/// durability group runs and must return a storage reading the same backing
/// store as the one [create] produced.
void runTransactionStorageConformanceTests({
  required String name,
  required Future<TransactionStorage> Function() create,
  Future<TransactionStorage> Function()? reopen,
}) {
  group('$name conformance', () {
    late TransactionStorage storage;
    final wallet = testWallet();
    final asset = testAssetId();

    setUp(() async {
      storage = await create();
    });

    group('validation', () {
      test('rejects an empty internal id', () async {
        await expectLater(
          storage.storeTransaction(testTransaction(internalId: ''), wallet),
          throwsA(isA<TransactionStorageException>()),
        );
      });

      test('storing an empty batch is a no-op', () async {
        await storage.storeTransactions([], wallet);
        final page = await storage.getTransactions(asset, wallet);
        expect(page.total, 0);
      });
    });

    group('ordering', () {
      test('orders by timestamp descending', () async {
        await storage.storeTransactions([
          testTransaction(
            internalId: 'oldest',
            timestamp: DateTime.utc(2026, 7, 1),
          ),
          testTransaction(
            internalId: 'newest',
            timestamp: DateTime.utc(2026, 7, 20),
          ),
          testTransaction(
            internalId: 'middle',
            timestamp: DateTime.utc(2026, 7, 10),
          ),
        ], wallet);

        final page = await storage.getTransactions(asset, wallet);
        expect(page.transactions.map((tx) => tx.internalId), [
          'newest',
          'middle',
          'oldest',
        ]);
      });

      test('breaks timestamp ties by internal id descending', () async {
        final sharedTimestamp = DateTime.utc(2026, 7, 10);
        await storage.storeTransactions([
          for (final id in ['tx-a', 'tx-c', 'tx-e', 'tx-b', 'tx-d'])
            testTransaction(internalId: id, timestamp: sharedTimestamp),
        ], wallet);

        final page = await storage.getTransactions(asset, wallet);
        expect(page.transactions.map((tx) => tx.internalId), [
          'tx-e',
          'tx-d',
          'tx-c',
          'tx-b',
          'tx-a',
        ]);
      });
    });

    group('accumulation', () {
      // Regression guard. The ordering used to be maintained by a SplayTreeMap
      // whose comparator resolved keys through a snapshot taken when the tree
      // was built, so the *second* batch for an asset - i.e. every page of
      // history after the first - threw rather than storing.
      test('a later batch introducing new ids accumulates', () async {
        await storage.storeTransactions([
          testTransaction(
            internalId: 'page1-a',
            timestamp: DateTime.utc(2026, 7, 10),
          ),
          testTransaction(
            internalId: 'page1-b',
            timestamp: DateTime.utc(2026, 7, 9),
          ),
        ], wallet);
        await storage.storeTransactions([
          testTransaction(
            internalId: 'page2-a',
            timestamp: DateTime.utc(2026, 7, 8),
          ),
        ], wallet);

        final page = await storage.getTransactions(asset, wallet);
        expect(page.total, 3);
        expect(page.transactions.map((tx) => tx.internalId), [
          'page1-a',
          'page1-b',
          'page2-a',
        ]);
      });

      test('the singular store path accumulates too', () async {
        for (var i = 0; i < 3; i++) {
          await storage.storeTransaction(
            testTransaction(
              internalId: 'tx-$i',
              timestamp: DateTime.utc(2026, 7, 10 + i),
            ),
            wallet,
          );
        }

        final page = await storage.getTransactions(asset, wallet);
        expect(page.transactions.map((tx) => tx.internalId), [
          'tx-2',
          'tx-1',
          'tx-0',
        ]);
      });

      test('re-storing the same id merges rather than replaces', () async {
        // Address-backed APIs return one perspective of the same transfer on
        // different pages: the standard EOA debit first, the GasFree custody
        // credit later. Merging must turn that into a net-zero internal
        // transfer, and re-fetching one perspective must not double-count.
        final amount = Decimal.parse('12.5');
        final debit = testTransaction(
          internalId: 'shared',
          receivedByMe: Decimal.zero,
          spentByMe: amount,
          totalAmount: amount,
        );
        final credit = testTransaction(
          internalId: 'shared',
          receivedByMe: amount,
          spentByMe: Decimal.zero,
          totalAmount: amount,
        );

        await storage.storeTransactions([debit], wallet);
        await storage.storeTransactions([credit], wallet);
        await storage.storeTransactions([debit], wallet);

        final page = await storage.getTransactions(asset, wallet);
        final merged = page.transactions.single;
        expect(merged.balanceChanges.spentByMe, amount);
        expect(merged.balanceChanges.receivedByMe, amount);
        expect(merged.balanceChanges.netChange, Decimal.zero);
      });

      test('merging takes the higher confirmations and block height', () async {
        await storage.storeTransactions([
          testTransaction(
            internalId: 'shared',
            confirmations: 1,
            blockHeight: 100,
          ),
        ], wallet);
        await storage.storeTransactions([
          testTransaction(
            internalId: 'shared',
            confirmations: 9,
            blockHeight: 900,
          ),
        ], wallet);
        // A stale re-fetch must not roll the values back.
        await storage.storeTransactions([
          testTransaction(
            internalId: 'shared',
            confirmations: 2,
            blockHeight: 200,
          ),
        ], wallet);

        final merged = (await storage.getTransactions(
          asset,
          wallet,
        )).transactions.single;
        expect(merged.confirmations, 9);
        expect(merged.blockHeight, 900);
      });

      test('merging unions the from and to address sets', () async {
        await storage.storeTransactions([
          testTransaction(
            internalId: 'shared',
            from: const ['eoa'],
            to: const ['custody'],
          ),
        ], wallet);
        await storage.storeTransactions([
          testTransaction(
            internalId: 'shared',
            from: const ['eoa'],
            to: const ['recipient'],
          ),
        ], wallet);

        final merged = (await storage.getTransactions(
          asset,
          wallet,
        )).transactions.single;
        expect(merged.from, ['eoa']);
        expect(merged.to, containsAll(['custody', 'recipient']));
      });

      test('duplicates within a single batch collapse', () async {
        final amount = Decimal.parse('4');
        await storage.storeTransactions([
          testTransaction(
            internalId: 'shared',
            receivedByMe: Decimal.zero,
            spentByMe: amount,
            totalAmount: amount,
          ),
          testTransaction(
            internalId: 'shared',
            receivedByMe: amount,
            spentByMe: Decimal.zero,
            totalAmount: amount,
          ),
        ], wallet);

        final page = await storage.getTransactions(asset, wallet);
        expect(page.total, 1);
        expect(page.transactions.single.balanceChanges.netChange, Decimal.zero);
      });
    });

    group('pagination', () {
      Future<void> seed({int count = 5}) => storage.storeTransactions([
        for (var i = 0; i < count; i++)
          testTransaction(
            internalId: 'tx-$i',
            // Descending timestamps so tx-0 is newest.
            timestamp: DateTime.utc(2026, 7, 20).subtract(Duration(days: i)),
          ),
      ], wallet);

      test('reports totals and page counts', () async {
        await seed();
        final page = await storage.getTransactions(asset, wallet, limit: 2);
        expect(page.total, 5);
        expect(page.totalPages, 3);
        expect(page.currentPage, 1);
        expect(page.transactions.map((tx) => tx.internalId), ['tx-0', 'tx-1']);
        expect(page.nextPageId, 'tx-1');
      });

      test('walks pages by number', () async {
        await seed();
        final second = await storage.getTransactions(
          asset,
          wallet,
          pageNumber: 2,
          limit: 2,
        );
        expect(second.transactions.map((tx) => tx.internalId), [
          'tx-2',
          'tx-3',
        ]);
        expect(second.currentPage, 2);
      });

      test('a page past the end is empty but keeps the totals', () async {
        await seed();
        final page = await storage.getTransactions(
          asset,
          wallet,
          pageNumber: 99,
          limit: 2,
        );
        expect(page.transactions, isEmpty);
        expect(page.total, 5);
        expect(page.totalPages, 3);
      });

      test('walks pages by fromId, exclusive of the cursor', () async {
        await seed();
        final page = await storage.getTransactions(
          asset,
          wallet,
          fromId: 'tx-1',
          limit: 2,
        );
        expect(page.transactions.map((tx) => tx.internalId), ['tx-2', 'tx-3']);
      });

      test('a fromId on the last row yields an empty page', () async {
        await seed();
        final page = await storage.getTransactions(
          asset,
          wallet,
          fromId: 'tx-4',
        );
        expect(page.transactions, isEmpty);
      });

      test('an unknown fromId throws', () async {
        await seed();
        await expectLater(
          storage.getTransactions(asset, wallet, fromId: 'not-a-real-id'),
          throwsA(isA<TransactionStorageException>()),
        );
      });

      test('an unknown asset yields an empty page', () async {
        await seed();
        final page = await storage.getTransactions(
          testAssetId(id: 'NOPE', subClass: CoinSubClass.utxo),
          wallet,
        );
        expect(page.transactions, isEmpty);
        expect(page.total, 0);
        expect(page.totalPages, 0);
      });
    });

    group('lookups', () {
      test('getLatestTransactionId returns the newest row', () async {
        await storage.storeTransactions([
          testTransaction(
            internalId: 'old',
            timestamp: DateTime.utc(2026, 7, 1),
          ),
          testTransaction(
            internalId: 'new',
            timestamp: DateTime.utc(2026, 7, 20),
          ),
          testTransaction(
            internalId: 'mid',
            timestamp: DateTime.utc(2026, 7, 10),
          ),
        ], wallet);

        expect(await storage.getLatestTransactionId(asset, wallet), 'new');
      });

      test('getLatestTransactionId is null when empty', () async {
        expect(await storage.getLatestTransactionId(asset, wallet), isNull);
      });

      test('getTransactionById finds a stored row', () async {
        await storage.storeTransactions([
          testTransaction(internalId: 'tx-0'),
        ], wallet);
        final found = await storage.getTransactionById('tx-0');
        expect(found?.internalId, 'tx-0');
      });

      test('getTransactionById returns null for an unknown id', () async {
        await storage.storeTransactions([
          testTransaction(internalId: 'tx-0'),
        ], wallet);
        expect(await storage.getTransactionById('nope'), isNull);
      });
    });

    group('clearing', () {
      test('clears only the target wallet and asset', () async {
        final otherAsset = testAssetId(
          id: 'KMD',
          subClass: CoinSubClass.smartChain,
          chainId: AssetChainId(chainId: 1),
        );
        await storage.storeTransactions([
          testTransaction(internalId: 'usdt-tx'),
          testTransaction(internalId: 'kmd-tx', assetId: otherAsset),
        ], wallet);

        await storage.clearTransactions(asset, wallet);

        expect((await storage.getTransactions(asset, wallet)).total, 0);
        expect((await storage.getTransactions(otherAsset, wallet)).total, 1);
      });

      test('clearing an empty asset is a no-op', () async {
        await storage.clearTransactions(asset, wallet);
        expect((await storage.getTransactions(asset, wallet)).total, 0);
      });
    });

    group('isolation', () {
      test('isolates wallets by derivation method', () async {
        final hd = testWallet();
        final iguana = testWallet(derivationMethod: DerivationMethod.iguana);

        await storage.storeTransactions([
          testTransaction(internalId: 'hd-tx'),
        ], hd);
        await storage.storeTransactions([
          testTransaction(internalId: 'iguana-tx'),
        ], iguana);

        expect(
          (await storage.getTransactions(
            asset,
            hd,
          )).transactions.single.internalId,
          'hd-tx',
        );
        expect(
          (await storage.getTransactions(
            asset,
            iguana,
          )).transactions.single.internalId,
          'iguana-tx',
        );
      });

      test('isolates wallets by private key policy', () async {
        final context = testWallet();
        final trezor = testWallet(
          privKeyPolicy: const PrivateKeyPolicy.trezor(),
        );
        final sessionA = testWallet(
          privKeyPolicy: const PrivateKeyPolicy.walletConnect('session-a'),
        );
        final sessionB = testWallet(
          privKeyPolicy: const PrivateKeyPolicy.walletConnect('session-b'),
        );

        await storage.storeTransactions([
          testTransaction(internalId: 'context-tx'),
        ], context);
        await storage.storeTransactions([
          testTransaction(internalId: 'trezor-tx'),
        ], trezor);
        await storage.storeTransactions([
          testTransaction(internalId: 'session-a-tx'),
        ], sessionA);
        await storage.storeTransactions([
          testTransaction(internalId: 'session-b-tx'),
        ], sessionB);

        for (final (walletId, expected) in [
          (context, 'context-tx'),
          (trezor, 'trezor-tx'),
          (sessionA, 'session-a-tx'),
          (sessionB, 'session-b-tx'),
        ]) {
          final page = await storage.getTransactions(asset, walletId);
          expect(page.transactions.single.internalId, expected);
        }
      });

      test('isolates wallets by pubkey hash', () async {
        final first = testWallet(pubkeyHash: 'aaaa');
        final second = testWallet(pubkeyHash: 'bbbb');

        await storage.storeTransactions([
          testTransaction(internalId: 'first-tx'),
        ], first);
        await storage.storeTransactions([
          testTransaction(internalId: 'second-tx'),
        ], second);

        expect(
          (await storage.getTransactions(
            asset,
            first,
          )).transactions.single.internalId,
          'first-tx',
        );
        expect(
          (await storage.getTransactions(
            asset,
            second,
          )).transactions.single.internalId,
          'second-tx',
        );
      });

      test('isolates assets that differ only by sub class', () async {
        final trc20 = testAssetId();
        final erc20 = testAssetId(subClass: CoinSubClass.erc20);

        await storage.storeTransactions([
          testTransaction(internalId: 'trc20-tx', assetId: trc20),
          testTransaction(internalId: 'erc20-tx', assetId: erc20),
        ], wallet);

        expect(
          (await storage.getTransactions(
            trc20,
            wallet,
          )).transactions.single.internalId,
          'trc20-tx',
        );
        expect(
          (await storage.getTransactions(
            erc20,
            wallet,
          )).transactions.single.internalId,
          'erc20-tx',
        );
      });

      test('isolates assets that differ only by chain id', () async {
        final mainnet = testAssetId();
        final other = testAssetId(chainId: AssetChainId(chainId: 1));

        await storage.storeTransactions([
          testTransaction(internalId: 'mainnet-tx', assetId: mainnet),
          testTransaction(internalId: 'other-tx', assetId: other),
        ], wallet);

        expect(
          (await storage.getTransactions(
            mainnet,
            wallet,
          )).transactions.single.internalId,
          'mainnet-tx',
        );
        expect(
          (await storage.getTransactions(
            other,
            wallet,
          )).transactions.single.internalId,
          'other-tx',
        );
      });
    });

    group('stats', () {
      test('throws when nothing is stored', () async {
        await expectLater(
          storage.getStats(),
          throwsA(isA<TransactionStorageException>()),
        );
      });

      test('counts stored transactions and their time bounds', () async {
        await storage.storeTransactions([
          testTransaction(
            internalId: 'tx-0',
            timestamp: DateTime.utc(2026, 7, 1),
          ),
          testTransaction(
            internalId: 'tx-1',
            timestamp: DateTime.utc(2026, 7, 20),
          ),
        ], wallet);

        final stats = await storage.getStats();
        expect(stats.totalTransactions, 2);
        expect(stats.oldestTransaction, DateTime.utc(2026, 7, 1));
        expect(stats.newestTransaction, DateTime.utc(2026, 7, 20));
        expect(
          stats.transactionsPerAsset.values.fold<int>(0, (a, b) => a + b),
          stats.totalTransactions,
        );
      });
    });

    if (reopen != null) {
      group('durability', () {
        test('rows survive a reopen', () async {
          final original = testTransaction(
            internalId: 'tx-0',
            timestamp: DateTime.utc(2026, 7, 10),
          );
          await storage.storeTransactions([original], wallet);

          final restored = await reopen();
          final page = await restored.getTransactions(asset, wallet);
          expect(page.transactions.single, original);
        });

        test('a clear survives a reopen', () async {
          await storage.storeTransactions([
            testTransaction(internalId: 'tx-0'),
          ], wallet);
          await storage.clearTransactions(asset, wallet);

          final restored = await reopen();
          expect((await restored.getTransactions(asset, wallet)).total, 0);
        });

        test('merging continues across a reopen', () async {
          final amount = Decimal.parse('12.5');
          await storage.storeTransactions([
            testTransaction(
              internalId: 'shared',
              receivedByMe: Decimal.zero,
              spentByMe: amount,
              totalAmount: amount,
            ),
          ], wallet);

          final restored = await reopen();
          await restored.storeTransactions([
            testTransaction(
              internalId: 'shared',
              receivedByMe: amount,
              spentByMe: Decimal.zero,
              totalAmount: amount,
            ),
          ], wallet);

          final merged = (await restored.getTransactions(
            asset,
            wallet,
          )).transactions.single;
          expect(merged.balanceChanges.spentByMe, amount);
          expect(merged.balanceChanges.receivedByMe, amount);
          expect(merged.balanceChanges.netChange, Decimal.zero);
        });
      });
    }
  });
}
