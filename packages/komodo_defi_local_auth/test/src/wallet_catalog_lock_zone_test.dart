import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/src/auth/wallet_catalog_lock.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

// Runs on every platform: the lock a browser grants from its own event loop
// must still run its body where the caller's dispatch guard is in scope.
void main() {
  for (final (name, withLock) in [
    ('catalog', withWalletCatalogLock<void>),
    ('record', withWalletRecordLock<void>),
  ]) {
    test('the $name lock body keeps its caller dispatch guard', () async {
      var checks = 0;
      await RpcDispatchGuard.run(
        () => checks++,
        () => withLock(() async {
          RpcDispatchGuard.ensureCurrent('delete_wallet');
          await Future<void>.delayed(Duration.zero);
          RpcDispatchGuard.ensureCurrent('delete_wallet');
        }),
        methods: const {'delete_wallet'},
      );
      expect(checks, 2);
    });

    test('the $name lock reports a refused dispatch to its caller', () async {
      var entered = false;
      await expectLater(
        RpcDispatchGuard.run(
          () => throw StateError('app locked'),
          () => withLock(() async {
            entered = true;
            RpcDispatchGuard.ensureCurrent('delete_wallet');
          }),
          methods: const {'delete_wallet'},
        ),
        throwsA(isA<RpcDispatchRejected>()),
      );
      expect(entered, isTrue);
    });
  }
}
