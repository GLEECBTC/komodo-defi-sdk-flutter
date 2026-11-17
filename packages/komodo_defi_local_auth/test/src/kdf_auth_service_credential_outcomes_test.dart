import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'support/fake_kdf_engine.dart';

const _unanswered = 'SECRET_TRANSPORT_CANARY';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeKdfEngine engine;

  setUp(() {
    seedStoredUsers([verifiedUser()]);
    engine = FakeKdfEngine();
  });

  group('KdfAuthService credential operations', () {
    late KdfAuthService service;
    late AuthSessionContext session;
    late List<KdfUser?> events;

    setUp(() async {
      service = authServiceFor(engine);
      addTearDown(service.dispose);
      session = await service.captureSessionContext();
      events = [];
      final subscription = service.authStateChanges.listen(events.add);
      addTearDown(subscription.cancel);
    });

    Future<void> verify() => service.verifyPassword(
      password: testPassword,
      expectedWalletId: session.walletId,
      expectedSession: session,
    );

    Future<void> rotate() => service.updatePassword(
      currentPassword: testPassword,
      newPassword: 'test-only-replacement',
      expectedWalletId: session.walletId,
      expectedSession: session,
    );

    for (final (name, operation) in [
      ('password verification', verify),
      ('password rotation', rotate),
    ]) {
      test('$name keeps the session when the engine cannot be asked '
          'who is signed in', () async {
        engine.answers['get_wallet_names'] = () async =>
            throw ClientException(_unanswered);

        final failure = await operation().then<Object?>(
          (_) => null,
          onError: (Object error) => error,
        );
        await Future<void>.delayed(Duration.zero);

        expect(engine.stops, 0);
        expect(events, isEmpty);
        expect(service.isSessionContextCurrent(session), isTrue);
        expect(engine.sent('get_mnemonic'), 0);
        expect(engine.sent('change_mnemonic_password'), 0);
        expect(
          failure,
          isA<AuthException>()
              .having(
                (error) => error.type,
                'type',
                AuthExceptionType.apiConnectionError,
              )
              .having(
                (error) => error.toString(),
                'redacted error',
                isNot(contains(_unanswered)),
              ),
        );

        engine.answers.remove('get_wallet_names');
        await operation();
        expect(service.isSessionContextCurrent(session), isTrue);
      });
    }

    test('an identity that cannot be trusted still ends the session', () async {
      engine.answers['get_public_key_hash'] = () async =>
          rpcResult({'public_key_hash': 'not-a-public-key-hash'});

      await expectLater(
        verify(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.type,
            'type',
            AuthExceptionType.internalError,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(engine.stops, 1);
      expect(events, [null]);
    });

    test('password verification reports a refused dispatch as not sent, '
        'not as a rejected password', () async {
      await expectLater(
        RpcDispatchGuard.run(
          () => throw StateError('app locked'),
          verify,
          methods: const {'get_mnemonic'},
        ),
        throwsA(isA<RpcDispatchRejected>()),
      );

      expect(engine.sent('get_mnemonic'), 0);
      expect(engine.stops, 0);
      expect(service.isSessionContextCurrent(session), isTrue);
    });

    test('password rotation reports a refused dispatch as not sent', () async {
      await expectLater(
        RpcDispatchGuard.run(
          () => throw StateError('app locked'),
          rotate,
          methods: const {'change_mnemonic_password'},
        ),
        throwsA(isA<RpcDispatchRejected>()),
      );

      expect(engine.sent('change_mnemonic_password'), 0);
      expect(service.isSessionContextCurrent(session), isTrue);
    });

    group('with the identity proof unavailable', () {
      setUp(() {
        engine.answers['get_public_key_hash'] = () async => {
          'mmrpc': '2.0',
          'error': 'identity is unavailable',
        };
      });

      for (final (name, operation) in [
        ('password verification', verify),
        ('password rotation', rotate),
      ]) {
        test('$name is retryable instead of a wallet change', () async {
          await expectLater(
            operation(),
            throwsA(isA<AuthIdentityUnavailableException>()),
          );

          expect(engine.sent('get_mnemonic'), 0);
          expect(engine.sent('change_mnemonic_password'), 0);
          expect(engine.stops, 0);
          expect(service.isSessionContextCurrent(session), isTrue);

          engine.answers.remove('get_public_key_hash');
          await operation();
        });
      }

      test('a reviewed deletion is retryable instead of a wallet '
          'change', () async {
        await service.getUsers();
        await expectLater(
          service.deleteWallet(
            walletName: testWalletName,
            password: testPassword,
            allowActiveWallet: true,
            beforeDelete: (_) async {},
          ),
          throwsA(isA<AuthIdentityUnavailableException>()),
        );

        expect(engine.stops, 0);
        expect(engine.sent('delete_wallet'), 0);
      });
    });

    test('a different wallet is still a wallet change, not a retryable '
        'identity', () async {
      final other = session.walletId.copyWith(
        pubkeyHash: '1111111111111111111111111111111111111111',
      );
      for (final expected in [
        other,
        // Without a proof, a different name is still a different wallet.
        WalletId.fromName('other-wallet', testHdOptions),
      ]) {
        await expectLater(
          service.verifyPassword(
            password: testPassword,
            expectedWalletId: expected,
            expectedSession: session,
          ),
          throwsA(
            isA<WalletChangedDisconnectException>().having(
              (error) => error,
              'exact type',
              isNot(isA<AuthIdentityUnavailableException>()),
            ),
          ),
        );
      }
      expect(engine.sent('get_mnemonic'), 0);
    });
  });

  group('KomodoDefiLocalAuth', () {
    late KomodoDefiLocalAuth auth;

    setUp(() async {
      auth = KomodoDefiLocalAuth(
        kdf: frameworkFor(engine),
        hostConfig: testHostConfig,
      );
      addTearDown(auth.dispose);
      await auth.ensureInitialized();
    });

    Never appLocked() => throw StateError('app locked');

    test('seed export reports a refused dispatch as not sent', () async {
      await expectLater(
        RpcDispatchGuard.run(
          appLocked,
          () => auth.getMnemonicPlainText(testPassword),
          methods: const {'get_mnemonic'},
        ),
        throwsA(isA<RpcDispatchRejected>()),
      );
      await expectLater(
        RpcDispatchGuard.run(
          appLocked,
          auth.getMnemonicEncrypted,
          methods: const {'get_mnemonic'},
        ),
        throwsA(isA<RpcDispatchRejected>()),
      );

      expect(engine.sent('get_mnemonic'), 0);
      expect(await auth.isSignedIn(), isTrue);
    });

    test('password change reports a refused dispatch as not sent', () async {
      await expectLater(
        RpcDispatchGuard.run(
          appLocked,
          () => auth.updatePassword(
            currentPassword: testPassword,
            newPassword: 'test-only-replacement',
          ),
          methods: const {'change_mnemonic_password'},
        ),
        throwsA(isA<RpcDispatchRejected>()),
      );

      expect(engine.sent('change_mnemonic_password'), 0);
      expect(await auth.isSignedIn(), isTrue);
    });
  });
}
