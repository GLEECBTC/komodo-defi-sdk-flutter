import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

const _walletName = 'dispatch-wallet';
const _hash = '05aab5342166f8594baf17a7d9bef5d567443327';

/// Long enough for every awaited step here, short enough to wait out.
const _leaseBound = Duration(milliseconds: 200);

/// The engine is replaceable only through the real auth service's write lock.
/// Identity and dispatch gates put tests at exact asynchronous boundaries.
class _Engine implements IKdfOperations {
  bool running = true;
  int stops = 0;
  Completer<void>? identityEntered;
  Completer<void>? identityGate;

  @override
  String get operationsName => 'session-dispatch-test';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async {
    running = true;
    return KdfStartupResult.ok;
  }

  @override
  Future<MainStatus> kdfMainStatus() async =>
      running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
  Future<StopStatus> kdfStop() async {
    stops++;
    running = false;
    return StopStatus.ok;
  }

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<String?> version() async => running ? 'test-version' : null;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    switch (request['method']) {
      case 'get_wallet_names':
        return {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': [_walletName],
            'activated_wallet': running ? _walletName : null,
          },
        };
      case 'get_public_key_hash':
        final entered = identityEntered;
        if (entered != null && !entered.isCompleted) entered.complete();
        await identityGate?.future;
        return {
          'mmrpc': '2.0',
          'result': {'public_key_hash': _hash},
        };
      default:
        return {'mmrpc': '2.0', 'result': <String, dynamic>{}};
    }
  }

  @override
  Future<void> validateSetup() async {}

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async => true;

  @override
  void resetHttpClient() {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Engine engine;
  late KomodoDefiFramework framework;
  late LocalConfig config;
  late KdfAuthService auth;
  late AuthSessionContext session;

  setUp(() async {
    final user = KdfUser(
      walletId: WalletId.fromName(
        _walletName,
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      ),
      isBip39Seed: true,
    );
    FlutterSecureStorage.setMockInitialValues({
      'user_$_walletName': jsonEncode(user.toJson()),
    });
    engine = _Engine();
    config = LocalConfig(https: false, rpcPassword: 'test-rpc-password');
    framework = KomodoDefiFramework.createWithOperations(
      hostConfig: config,
      kdfOperations: engine,
    );
    auth = KdfAuthService(framework, config, dispatchLeaseTimeout: _leaseBound);
    session = await auth.captureSessionContext();
  });

  tearDown(() async {
    final gate = engine.identityGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await auth.dispose();
  });

  test('a revoked session never enters dispatch', () async {
    await auth.signOut();
    var calls = 0;
    expect(
      () => auth.runWithSession(session, () async => calls++),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(calls, 0);
  });

  test('an identity read in progress does not delay a dispatch', () async {
    engine
      ..identityEntered = Completer<void>()
      ..identityGate = Completer<void>();
    final identityRead = auth.getActiveUser();
    await engine.identityEntered!.future;

    try {
      final sent = auth.runWithSession(session, () async => 'sent');
      expect(await sent.timeout(_leaseBound), 'sent');
    } finally {
      engine.identityGate!.complete();
      await identityRead;
    }
  });

  test('a queued dispatch is rechecked after acquiring the lease', () async {
    var calls = 0;
    final pending = auth.runWithSession(session, () async => calls++);
    final rejected = expectLater(
      pending,
      throwsA(isA<AuthSessionChangedException>()),
    );
    final signOut = auth.signOut();
    expect(auth.isSessionContextCurrent(session), isFalse);
    await rejected;
    await signOut;
    expect(calls, 0);
  });

  test(
    'an unanswered dispatch holds off sign-out only for its bound',
    () async {
      final entered = Completer<void>();
      final response = Completer<String>();
      final pending = auth.runWithSession(session, () {
        entered.complete();
        return response.future;
      });
      await entered.future;

      try {
        await auth.signOut().timeout(_leaseBound * 10);
        expect(engine.stops, 1);
        expect(engine.running, isFalse);
      } finally {
        // The caller still holds the request's own answer, however late.
        response.complete('late');
      }
      expect(await pending, 'late');
    },
  );

  test('sign-out revokes immediately but waits for dispatched work', () async {
    final entered = Completer<void>();
    final response = Completer<String>();
    final pending = auth.runWithSession(session, () {
      entered.complete();
      return response.future;
    });
    await entered.future;
    var signedOut = false;
    final signOut = auth.signOut().then((_) => signedOut = true);
    await Future<void>.delayed(Duration.zero);
    expect(auth.isSessionContextCurrent(session), isFalse);
    expect(signedOut, isFalse);
    expect(engine.stops, 0);
    expect(engine.running, isTrue);
    response.complete('accepted');
    expect(await pending, 'accepted');
    await signOut;
    expect(signedOut, isTrue);
    expect(engine.stops, 1);
  });

  test('disposal waits for the actual dispatch future to settle', () async {
    final entered = Completer<void>();
    final response = Completer<void>();
    final pending = auth.runWithSession(session, () {
      entered.complete();
      return response.future;
    });
    await entered.future;
    var disposed = false;
    final disposal = auth.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    expect(engine.stops, 0);
    response.complete();
    await pending;
    await disposal;
    expect(disposed, isTrue);
    expect(engine.stops, 1);
  });

  test(
    'a caller timeout does not release an unsettled dispatch lease',
    () async {
      final entered = Completer<void>();
      final response = Completer<void>();
      final pending = auth.runWithSession(session, () {
        entered.complete();
        return response.future;
      });
      await entered.future;
      await expectLater(
        pending.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      var signedOut = false;
      final signOut = auth.signOut().then((_) => signedOut = true);
      await Future<void>.delayed(Duration.zero);
      expect(signedOut, isFalse);
      expect(engine.stops, 0);
      response.complete();
      await pending;
      await signOut;
      expect(signedOut, isTrue);
      expect(engine.stops, 1);
    },
  );

  test(
    'transport failure releases the lease without changing the error',
    () async {
      final entered = Completer<void>();
      final response = Completer<void>();
      final error = StateError('transport lost');
      final pending = auth.runWithSession(session, () {
        entered.complete();
        return response.future;
      });
      final failed = expectLater(pending, throwsA(same(error)));
      await entered.future;
      final signOut = auth.signOut();
      response.completeError(error);
      await failed;
      await signOut;
      expect(engine.stops, 1);
    },
  );

  test('a synchronous dispatch rejection releases the lease', () async {
    final error = StateError('intent revoked');
    await expectLater(
      auth.runWithSession<void>(session, () => throw error),
      throwsA(same(error)),
    );
    expect(await auth.runWithSession(session, () async => 7), 7);
    await auth.signOut();
    expect(engine.stops, 1);
  });

  test('reopening the same wallet does not restore an old session', () async {
    await auth.signOut();
    engine.running = true;
    final reopened = await auth.captureSessionContext();
    expect(reopened.walletId, session.walletId);
    expect(reopened, isNot(session));
    expect(
      () => auth.runWithSession(session, () async => fail('old dispatch')),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(await auth.runWithSession(reopened, () async => 'new'), 'new');
  });

  test('Trezor dispatch uses the underlying authentication lease', () async {
    final trezor = TrezorAuthService(auth, TrezorRepository(framework));
    final entered = Completer<void>();
    final response = Completer<void>();
    final pending = trezor.runWithSession(session, () {
      entered.complete();
      return response.future;
    });
    await entered.future;
    final signOut = auth.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(engine.stops, 0);
    response.complete();
    await pending;
    await signOut;
    expect(engine.stops, 1);
  });

  test('the public facade delegates to its authentication lease', () async {
    await auth.dispose();
    engine.running = true;
    final facade = KomodoDefiLocalAuth(kdf: framework, hostConfig: config);
    addTearDown(facade.dispose);
    final facadeSession = await facade.captureSessionContext();
    final entered = Completer<void>();
    final response = Completer<void>();
    final pending = facade.runWithSession(facadeSession, () {
      entered.complete();
      return response.future;
    });
    await entered.future;
    var disposed = false;
    final disposal = facade.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    response.complete();
    await pending;
    await disposal;
    expect(disposed, isTrue);
  });
}
