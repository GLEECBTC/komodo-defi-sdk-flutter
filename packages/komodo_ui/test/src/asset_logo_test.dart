// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';

void main() {
  group('AssetLogo', () {
    testWidgets('uses the TRX protocol badge for TRC20 child assets', (
      tester,
    ) async {
      final parent = AssetId(
        id: 'TRX',
        name: 'TRON',
        symbol: AssetSymbol(assetConfigId: 'TRX'),
        chainId: AssetChainId(chainId: 195, decimalsValue: 6),
        derivationPath: "m/44'/195'",
        subClass: CoinSubClass.trx,
      );
      final child = AssetId(
        id: 'USDT-TRC20',
        name: 'Tether',
        symbol: AssetSymbol(assetConfigId: 'USDT-TRC20'),
        chainId: AssetChainId(chainId: 195, decimalsValue: 6),
        derivationPath: "m/44'/195'",
        subClass: CoinSubClass.trc20,
        parentId: parent,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: AssetLogo.ofId(child))),
        ),
      );

      final protocolIcon = tester.widget<AssetProtocolIcon>(
        find.byType(AssetProtocolIcon),
      );

      expect(protocolIcon.protocolTicker, 'TRX');
    });
  });
}
