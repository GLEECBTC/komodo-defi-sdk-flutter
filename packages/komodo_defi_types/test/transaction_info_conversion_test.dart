import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  test('uses non-zero spent amount when received amount is zero', () {
    final info = TransactionInfo(
      txHash: 'hash',
      from: const ['source'],
      to: const ['recipient', 'provider'],
      myBalanceChange: '-11.5',
      blockHeight: 1,
      confirmations: 1,
      timestamp: 1,
      feeDetails: null,
      coin: 'USDT-TRC20',
      internalId: 'hash',
      spentByMe: '11.5',
      receivedByMe: '0',
      memo: null,
    );

    final transaction = info.asTransaction(
      AssetId(
        id: 'USDT-TRC20',
        name: 'Tether',
        symbol: AssetSymbol(assetConfigId: 'USDT-TRC20'),
        chainId: AssetChainId(chainId: 728126428, decimalsValue: 6),
        derivationPath: "m/44'/195'",
        subClass: CoinSubClass.trc20,
      ),
    );

    expect(transaction.balanceChanges.totalAmount.toString(), '11.5');
  });
}
