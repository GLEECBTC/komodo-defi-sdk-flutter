import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/src/defi/withdraw/withdraw_amount_field.dart';

Map<String, dynamic> _assetConfig() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'nodes': <Map<String, dynamic>>[],
};

void main() {
  final asset = Asset.fromJson(_assetConfig(), knownIds: const {});

  testWidgets('wraps at narrow width and 200 percent text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              width: 260,
              child: WithdrawAmountField(
                asset: asset,
                amount: '1',
                isMaxAmount: false,
                availableBalance: '123456789.123456',
                symbol: 'USDT',
                onChanged: (_) {},
                onMaxToggled: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Send maximum available'), findsOneWidget);
  });

  testWidgets('uses caller-provided localized labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WithdrawAmountField(
            asset: asset,
            amount: '1',
            isMaxAmount: false,
            hasInsufficientBalance: true,
            amountLabel: 'Montant',
            insufficientBalanceLabel: 'Solde insuffisant',
            amountHelperLabel: 'Saisissez le montant',
            sendMaximumLabel: 'Envoyer le maximum',
            maxButtonLabel: 'TOUT',
            onChanged: (_) {},
            onMaxToggled: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Montant'), findsOneWidget);
    expect(find.text('Solde insuffisant'), findsOneWidget);
    expect(find.text('Envoyer le maximum'), findsOneWidget);
    expect(find.text('TOUT'), findsOneWidget);
  });
}
