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
