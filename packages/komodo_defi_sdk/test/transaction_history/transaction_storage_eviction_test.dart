import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:test/test.dart';

import 'transaction_fixtures.dart';

void main() {
  group('InMemoryTransactionStorage eviction', () {
    // Regression guard. `storeTransactions` used to call the *locking*
    // `_enforceStorageLimit` from inside its own `_mutex.protect` body.
    // `package:mutex`'s Mutex is a write-only ReadWriteMutex and is not
    // reentrant, so that combination hung forever rather than throwing - and
    // because the release is in a `finally` that is itself waiting, every
    // later call on the instance hung too. It only stayed invisible because
    // the cap was a hardcoded `null` that returned before taking the lock.
    //
    // This test therefore fails by TIMEOUT on the old code, not by assertion.
    test(
      'enforcing a cap does not deadlock',
      () async {
        final storage = InMemoryTransactionStorage(maxTransactionsPerAsset: 2);
        final wallet = testWallet();

        await storage.storeTransactions([
          for (var i = 0; i < 5; i++)
            testTransaction(
              internalId: 'tx-$i',
              timestamp: DateTime.utc(2026, 7, 10 + i),
            ),
        ], wallet);

        final page = await storage.getTransactions(testAssetId(), wallet);
        expect(page.transactions, hasLength(2));
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'evicts oldest-first and keeps the newest rows',
      () async {
        final storage = InMemoryTransactionStorage(maxTransactionsPerAsset: 3);
        final wallet = testWallet();

        await storage.storeTransactions([
          for (var i = 0; i < 6; i++)
            testTransaction(
              internalId: 'tx-$i',
              timestamp: DateTime.utc(2026, 7, 10 + i),
            ),
        ], wallet);

        final page = await storage.getTransactions(testAssetId(), wallet);
        expect(
          page.transactions.map((tx) => tx.internalId),
          ['tx-5', 'tx-4', 'tx-3'],
          reason: 'ordering is timestamp DESC, so the newest three survive',
        );
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'the singular store path also enforces the cap',
      () async {
        final storage = InMemoryTransactionStorage(maxTransactionsPerAsset: 2);
        final wallet = testWallet();

        for (var i = 0; i < 4; i++) {
          await storage.storeTransaction(
            testTransaction(
              internalId: 'tx-$i',
              timestamp: DateTime.utc(2026, 7, 10 + i),
            ),
            wallet,
          );
        }

        final page = await storage.getTransactions(testAssetId(), wallet);
        expect(page.transactions.map((tx) => tx.internalId), ['tx-3', 'tx-2']);
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test('remains unbounded by default', () async {
      final storage = InMemoryTransactionStorage();
      final wallet = testWallet();

      await storage.storeTransactions([
        for (var i = 0; i < 25; i++)
          testTransaction(
            internalId: 'tx-$i',
            timestamp: DateTime.utc(2026, 7, 10).add(Duration(days: i)),
          ),
      ], wallet);

      final page = await storage.getTransactions(
        testAssetId(),
        wallet,
        limit: 100,
      );
      expect(page.total, 25);
    });
  });
}
