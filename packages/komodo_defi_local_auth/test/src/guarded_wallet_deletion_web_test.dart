@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'support/fake_kdf_engine.dart';

// Deletion runs inside a Web Lock the browser grants from its own event loop.
// The app's authorization scope must still be the one the deletion checks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeKdfEngine engine;
  late KdfAuthService service;
  var authorized = true;

  Future<void> guarded(Future<void> Function() deletion) =>
      RpcDispatchGuard.run(
        () {
          if (!authorized) throw StateError('app locked');
        },
        deletion,
        methods: const {'delete_wallet'},
      );

  setUp(() async {
    authorized = true;
    seedStoredUsers([verifiedUser(), verifiedUser('other-wallet')]);
    engine = FakeKdfEngine(wallets: [testWalletName, 'other-wallet']);
    service = authServiceFor(engine);
    addTearDown(service.dispose);
    await service.getUsers();
  });

  test('app lock during the password proof never stops or deletes the '
      'active wallet', () async {
    engine.onSent = (method) {
      if (method == 'get_mnemonic') authorized = false;
    };

    await expectLater(
      guarded(
        () => service.deleteWallet(
          walletName: testWalletName,
          password: testPassword,
          allowActiveWallet: true,
          beforeDelete: (_) async {},
        ),
      ),
      throwsA(isA<RpcDispatchRejected>()),
    );

    expect(engine.stops, 0);
    expect(engine.sent('delete_wallet'), 0);
    expect(engine.wallets, contains(testWalletName));
    expect(await SecureLocalStorage().getUser(testWalletName), isNotNull);
    expect((await service.getActiveUser())?.walletId.name, testWalletName);
  });

  test('app lock after the review never dispatches the deletion of an '
      'inactive wallet', () async {
    await expectLater(
      guarded(
        () => service.deleteWallet(
          walletName: 'other-wallet',
          password: testPassword,
          beforeDelete: (_) async => authorized = false,
        ),
      ),
      throwsA(isA<RpcDispatchRejected>()),
    );

    expect(engine.sent('delete_wallet'), 0);
    expect(engine.wallets, contains('other-wallet'));
    expect(await SecureLocalStorage().getUser('other-wallet'), isNotNull);
  });
}
