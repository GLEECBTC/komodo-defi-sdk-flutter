import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

Future<GetWalletNamesResponse> _walletNames(
  ReplayKdfOperations operations,
) async => GetWalletNamesResponse.parse(
  await operations.mm2Rpc({'method': 'get_wallet_names'}),
);

void main() {
  for (final walletExists in [false, true]) {
    test('no-auth restart clears activation and preserves '
        '${walletExists ? 'existing' : 'registered'} wallet catalog', () async {
      const walletName = 'lifecycle-wallet';
      final operations = ReplayKdfOperations(
        KdfWalletFixture(
          walletName: walletName,
          walletExists: walletExists,
        ).build(),
      );
      addTearDown(operations.dispose);

      await operations.kdfMain({});
      final initial = await _walletNames(operations);
      expect(initial.walletNames, walletExists ? [walletName] : isEmpty);
      expect(initial.activatedWallet, isNull);

      await operations.kdfStop();
      await operations.kdfMain({'wallet_name': walletName});
      final signedIn = await _walletNames(operations);
      expect(signedIn.walletNames, [walletName]);
      expect(signedIn.activatedWallet, walletName);

      await operations.kdfStop();
      await operations.kdfMain({});
      final signedOut = await _walletNames(operations);
      expect(signedOut.walletNames, [walletName]);
      expect(signedOut.activatedWallet, isNull);

      await operations.kdfStop();
      await operations.kdfMain({'wallet_name': walletName});
      final signedInAgain = await _walletNames(operations);
      expect(signedInAgain.walletNames, [walletName]);
      expect(signedInAgain.activatedWallet, walletName);
    });
  }
}
