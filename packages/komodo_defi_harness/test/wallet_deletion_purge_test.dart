import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
// The persisted store is deliberately not public API. This package is test
// infrastructure for the SDK, so reaching into src is the intended way to
// assert on it rather than a layering slip.
// ignore: implementation_imports
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
// ignore: implementation_imports
import 'package:komodo_defi_sdk/src/transaction_history/hive_transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Deleting a wallet must take its derived caches with it.
///
/// `AuthService.deleteWallet` issues the KDF RPC and clears secure storage and
/// nothing else, so wallet-scoped caches used to survive the wallet they
/// described. The per-store purges are unit-tested in
/// `komodo_defi_sdk/test/storage/wallet_deletion_purge_test.dart`; this covers
/// the chain that drives them - auth emits the deleted identity, and
/// `bootstrap`'s listener fans it out - through the real bootstrap.
const _ticker = 'KMD';
const _internalId = 'harness-tx-0';

Asset _assetFor(KdfHarness harness) => harness.sdk.assets.available.values
    .firstWhere((asset) => asset.id.id == _ticker);

Map<String, dynamic> _historyResult() => {
  'mmrpc': '2.0',
  'result': {
    'coin': _ticker,
    'current_block': 900,
    'from_id': null,
    'limit': 50,
    'skipped': 0,
    'sync_status': {'state': 'Finished'},
    'total': 1,
    'total_pages': 1,
    'page_number': 1,
    'transactions': [
      {
        'tx_hash': 'harness-hash-0',
        'from': ['from-address'],
        'to': ['to-address'],
        'my_balance_change': '-1.5',
        'block_height': 900,
        'confirmations': 6,
        'timestamp': 1783641600,
        'coin': _ticker,
        'internal_id': _internalId,
        'spent_by_me': '1.5',
        'received_by_me': '0',
      },
    ],
  },
};

KdfScript _script() {
  final script =
      (KdfWalletFixture()
            ..enableUtxo(_ticker)
            ..balance(_ticker))
          .build();
  script
    ..reply('my_tx_history', _historyResult())
    ..reply('delete_wallet', {'mmrpc': '2.0', 'result': null});
  return script;
}

void main() {
  group('wallet deletion purge (integration)', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('purge_wiring_');
    });

    tearDown(() async {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });

    test('deleting a wallet drops its transaction history', () async {
      final harness = await KdfHarness.replayed(
        script: _script(),
        workspace: workspace,
        deleteWorkspaceOnDispose: false,
      );
      addTearDown(harness.dispose);

      const password = 'harness-Password1!';
      final user = await harness.signIn(
        walletType: KdfWalletType.iguana,
        password: password,
      );
      final asset = _assetFor(harness);

      await harness.sdk.transactions
          .getTransactionsStreamed(asset)
          .first
          .timeout(const Duration(seconds: 20));

      // Prove there is something to lose before deleting. Both caches are read
      // through fresh instances, which share the process-global Hive boxes the
      // SDK is using.
      final storage = HiveTransactionStorage();
      final pubkeys = HivePubkeysStorage();
      expect(
        (await storage.getTransactions(
          asset.id,
          user.walletId,
        )).transactions.single.internalId,
        _internalId,
        reason: 'the history should be on disk before the wallet is deleted',
      );
      expect(
        await pubkeys.listForWallet(user.walletId),
        isNotEmpty,
        reason: 'the pubkey cache should be populated by sign-in',
      );

      await harness.sdk.auth.deleteWallet(
        walletName: user.walletId.name,
        password: password,
      );

      // The purge is driven by a stream listener, so let the event settle.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // A fresh instance, deliberately: the order index is per-instance and
      // rebuilt at open, so the reader above still holds the pre-deletion view.
      // Only one instance exists in production, where the purge updates it.
      expect(
        (await HiveTransactionStorage().getTransactions(
          asset.id,
          user.walletId,
        )).total,
        0,
        reason: 'the deleted wallet must not leave history behind',
      );
      expect(
        await pubkeys.listForWallet(user.walletId),
        isEmpty,
        reason: 'nor its derived addresses',
      );
    });

    test('deleting a wallet leaves another wallet alone', () async {
      final harness = await KdfHarness.replayed(
        script: _script(),
        workspace: workspace,
        deleteWorkspaceOnDispose: false,
      );
      addTearDown(harness.dispose);

      const password = 'harness-Password1!';
      final user = await harness.signIn(
        walletType: KdfWalletType.iguana,
        password: password,
      );
      final asset = _assetFor(harness);
      await harness.sdk.transactions
          .getTransactionsStreamed(asset)
          .first
          .timeout(const Duration(seconds: 20));

      // A second wallet's history, written directly: signing a second wallet
      // in through the replay backend would need a whole second identity in
      // the script, and the claim under test is only about scoping.
      final other = WalletId(
        name: 'other-wallet',
        pubkeyHash: 'other-pubkey-hash',
        authOptions: user.walletId.authOptions,
      );
      final otherStorage = HiveTransactionStorage();
      await otherStorage.storeTransactions([
        (await harness.sdk.transactions.getTransactionHistory(
          asset,
        )).transactions.single,
      ], other);

      await harness.sdk.auth.deleteWallet(
        walletName: user.walletId.name,
        password: password,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        (await otherStorage.getTransactions(asset.id, other)).total,
        1,
        reason: 'only the deleted wallet should be purged',
      );
    });
  });
}
