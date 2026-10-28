import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_merge_utils.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Transaction _perspective({required bool custodyCredit}) {
  final amount = Decimal.parse('12.5');
  return Transaction(
    id: 'tx-hash',
    internalId: 'tx-hash',
    assetId: AssetId(
      id: 'USDT-TRC20',
      name: 'Tether',
      symbol: AssetSymbol(assetConfigId: 'USDT-TRC20'),
      chainId: AssetChainId(chainId: 728126428),
      derivationPath: "m/44'/195'",
      subClass: CoinSubClass.trc20,
    ),
    balanceChanges: BalanceChanges(
      netChange: custodyCredit ? amount : -amount,
      receivedByMe: custodyCredit ? amount : Decimal.zero,
      spentByMe: custodyCredit ? Decimal.zero : amount,
      totalAmount: amount,
    ),
    timestamp: DateTime.utc(2026, 7, 10),
    confirmations: 1,
    blockHeight: 123,
    from: const ['standard-eoa'],
    to: const ['gasfree-custody'],
    txHash: 'tx-hash',
  );
}

void main() {
  test(
    're-fetching net-only proxy history preserves outgoing direction',
    () async {
      final debit = _perspective(custodyCredit: false).copyWith(
        balanceChanges: BalanceChanges(
          netChange: Decimal.parse('-12.5'),
          receivedByMe: Decimal.zero,
          spentByMe: Decimal.zero,
          totalAmount: Decimal.parse('12.5'),
        ),
      );
      final reconciler = TransactionListReconciler();
      var merged = <Transaction>[];
      for (var i = 0; i < 3; i++) {
        merged = reconciler.merge(existing: merged, incoming: [debit]);
        expect(merged, hasLength(1));
        expect(merged.single.amount, Decimal.parse('-12.5'));
      }
      final storage = InMemoryTransactionStorage();
      const wallet = WalletId(
        name: 'proxy-wallet',
        pubkeyHash: 'proxy-wallet-key',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
      );
      await storage.storeTransactions([debit], wallet);
      await storage.storeTransactions([debit], wallet);
      final page = await storage.getTransactions(debit.assetId, wallet);
      expect(page.transactions.single.amount, Decimal.parse('-12.5'));
    },
  );

  test(
    'net-only complementary perspectives reconcile a self-transfer once',
    () {
      final debit = _perspective(custodyCredit: false);
      Transaction withoutComponents(Transaction transaction) =>
          transaction.copyWith(
            balanceChanges: BalanceChanges(
              netChange: transaction.amount,
              receivedByMe: Decimal.zero,
              spentByMe: Decimal.zero,
              totalAmount: transaction.balanceChanges.totalAmount,
            ),
          );
      final reconciler = TransactionListReconciler();
      final first = reconciler.merge(
        existing: const [],
        incoming: [withoutComponents(debit)],
      );
      final merged = reconciler.merge(
        existing: first,
        incoming: [withoutComponents(_perspective(custodyCredit: true))],
      );
      expect(merged, hasLength(1));
      expect(merged.single.amount, Decimal.zero);
      expect(merged.single.balanceChanges.spentByMe, Decimal.parse('12.5'));
      expect(merged.single.balanceChanges.receivedByMe, Decimal.parse('12.5'));
    },
  );

  test('cross-page address perspectives merge without data loss', () {
    final reconciler = TransactionListReconciler();
    final firstPage = reconciler.merge(
      existing: const [],
      incoming: [_perspective(custodyCredit: false)],
    );
    final merged = reconciler
        .merge(
          existing: firstPage,
          incoming: [_perspective(custodyCredit: true)],
        )
        .single;

    expect(merged.balanceChanges.spentByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.receivedByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.netChange, Decimal.zero);
  });

  test('re-fetching one perspective never double-counts it', () {
    final reconciler = TransactionListReconciler();
    final debit = _perspective(custodyCredit: false);
    final first = reconciler.merge(existing: const [], incoming: [debit]);
    final repeated = reconciler.merge(existing: first, incoming: [debit]);

    expect(repeated.single.balanceChanges.spentByMe, Decimal.parse('12.5'));
    expect(repeated.single.balanceChanges.netChange, Decimal.parse('-12.5'));
  });

  test('storage preserves richer cross-page address perspectives', () async {
    final storage = InMemoryTransactionStorage();
    const wallet = WalletId(
      name: 'wallet',
      pubkeyHash: 'wallet-pubkey',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    );

    await storage.storeTransactions([
      _perspective(custodyCredit: false),
    ], wallet);
    await storage.storeTransactions([
      _perspective(custodyCredit: true),
    ], wallet);

    final page = await storage.getTransactions(
      _perspective(custodyCredit: false).assetId,
      wallet,
    );
    final merged = page.transactions.single;
    expect(merged.balanceChanges.spentByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.receivedByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.netChange, Decimal.zero);
  });
}
