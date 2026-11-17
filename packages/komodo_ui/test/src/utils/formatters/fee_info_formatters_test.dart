import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/src/utils/formatters/fee_info_formatters.dart';

void main() {
  group('FeeInfoFormatting.description', () {
    test('falls back to the formatted total for fees without a gas price', () {
      final solana = FeeInfo.solana(
        coin: 'SOL',
        feeAmount: Decimal.parse('0.000005'),
        rentAmount: Decimal.parse('0.00203928'),
        totalAmount: Decimal.parse('0.00204428'),
      );
      final utxo = FeeInfo.utxoFixed(
        coin: 'KMD',
        amount: Decimal.parse('0.0001'),
      );

      expect(solana.description, '0.00204428 SOL');
      expect(solana.description, solana.formatTotal());
      expect(utxo.description, '0.0001 KMD');
    });

    test('describes gas fees by their gas price', () {
      final gas = FeeInfo.ethGas(
        coin: 'ETH',
        gasPrice: Decimal.parse('0.00000002'),
        gas: 21000,
      );

      expect(gas.description, 'Gas: 21000 @ 20 Gwei');
    });
  });
}
