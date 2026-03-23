import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class _DummyApiClient implements ApiClient {
  @override
  FutureOr<JsonMap> executeRpc(JsonMap request) => <String, dynamic>{};
}

class _FakeTrezorRepository extends TrezorRepository {
  _FakeTrezorRepository() : super(_DummyApiClient());

  final StreamController<TrezorInitializationState> _controller =
      StreamController<TrezorInitializationState>.broadcast();

  final Map<int, String> providedPassphrases = {};
  final Map<int, String> providedPins = {};
  int? lastCancelledTaskId;

  void emit(TrezorInitializationState state) {
    _controller.add(state);
  }

  Future<void> close() async => _controller.close();

  @override
  Stream<TrezorInitializationState> initializeDevice({
    String? devicePubkey,
    Duration pollingInterval = const Duration(seconds: 1),
  }) async* {
    yield* _controller.stream;
  }

  @override
  Future<void> providePassphrase(int taskId, String passphrase) async {
    providedPassphrases[taskId] = passphrase;
  }

  @override
  Future<void> providePin(int taskId, String pin) async {
    providedPins[taskId] = pin;
  }

  @override
  Future<bool> cancelInitialization(int taskId) async {
    lastCancelledTaskId = taskId;
    return true;
  }
}

class _FakeConnectionMonitor extends TrezorConnectionMonitor {
  _FakeConnectionMonitor() : super(_FakeTrezorRepository());

  bool started = false;
  bool stopped = false;
  int startCalls = 0;
  int stopCalls = 0;
  String? lastDevicePubkey;

  @override
  void startMonitoring({
    String? devicePubkey,
    Duration pollInterval = const Duration(seconds: 1),
    Duration? maxDuration,
    VoidCallback? onConnectionLost,
    VoidCallback? onConnectionRestored,
    void Function(TrezorConnectionStatus)? onStatusChanged,
  }) {
    started = true;
    stopped = false;
    startCalls += 1;
    lastDevicePubkey = devicePubkey;
  }

  @override
  Future<void> stopMonitoring() async {
    stopCalls += 1;
    started = false;
    stopped = true;
  }

  @override
  bool get isMonitoring => started;

  @override
  void dispose() {
    stopped = true;
    started = false;
  }
}

class _FakeAuthService implements IAuthService {
  final StreamController<KdfUser?> _authStateController =
      StreamController<KdfUser?>.broadcast();

  List<KdfUser> users = [];
  KdfUser? activeUser;
  bool signOutCalled = false;
  ({String walletName, String password, AuthOptions options})? lastSignInArgs;
  ({String walletName, String password, AuthOptions options})? lastRegisterArgs;
  bool ensureHealthyReturn = true;
  int ensureHealthyCalls = 0;

  @override
  Stream<KdfUser?> get authStateChanges => _authStateController.stream;

  @override
  Future<void> deleteWallet({
    required String walletName,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<void> dispose() async {
    await _authStateController.close();
  }

  @override
  Future<KdfUser?> getActiveUser() async => activeUser;

  @override
  Future<Mnemonic> getMnemonic({
    required bool encrypted,
    required String? walletPassword,
  }) async => throw UnimplementedError();

  @override
  Future<List<KdfUser>> getUsers() async => users;

  @override
  Future<bool> isSignedIn() async => activeUser != null;

  @override
  Future<void> restoreSession(KdfUser user) async {
    activeUser = user;
    _authStateController.add(user);
  }

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    required AuthOptions options,
  }) async {
    lastSignInArgs = (
      walletName: walletName,
      password: password,
      options: options,
    );
    final user = KdfUser(
      walletId: WalletId.fromName(walletName, options),
      isBip39Seed: true,
    );
    activeUser = user;
    _authStateController.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    activeUser = null;
    _authStateController.add(null);
  }

  @override
  Future<KdfUser> register({
    required String walletName,
    required String password,
    required AuthOptions options,
    Mnemonic? mnemonic,
  }) async {
    lastRegisterArgs = (
      walletName: walletName,
      password: password,
      options: options,
    );
    final user = KdfUser(
      walletId: WalletId.fromName(walletName, options),
      isBip39Seed: true,
    );
    activeUser = user;
    _authStateController.add(user);
    return user;
  }

  @override
  Future<void> setActiveUserMetadata(JsonMap metadata) async =>
      throw UnimplementedError();

  @override
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform,
  ) async =>
      throw UnimplementedError();

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async => throw UnimplementedError();

  @override
  Future<bool> ensureKdfHealthy() async {
    ensureHealthyCalls++;
    return ensureHealthyReturn;
  }
}

void main() {
  group('TrezorAuthService - DI and basic behavior', () {
    test('signIn throws if privKeyPolicy is not trezor', () async {
      final auth = _FakeAuthService();
      final repo = _FakeTrezorRepository();
      final monitor = _FakeConnectionMonitor();

      final service = TrezorAuthService(
        auth,
        repo,
        connectionMonitor: monitor,
        secureStorage: const FlutterSecureStorage(),
        passwordGenerator: (_) => 'gen',
      );

      expect(
        () => service.signIn(
          walletName: 'anything',
          password: 'irrelevant',
          options: const AuthOptions(
            derivationMethod: DerivationMethod.hdWallet,
          ),
        ),
        throwsA(isA<AuthException>()),
      );

      await repo.close();
    });

    test('register throws if privKeyPolicy is not trezor', () async {
      final auth = _FakeAuthService();
      final repo = _FakeTrezorRepository();
      final monitor = _FakeConnectionMonitor();

      final service = TrezorAuthService(
        auth,
        repo,
        connectionMonitor: monitor,
        secureStorage: const FlutterSecureStorage(),
        passwordGenerator: (_) => 'gen',
      );

      expect(
        () => service.register(
          walletName: 'anything',
          password: 'irrelevant',
          options: const AuthOptions(
            derivationMethod: DerivationMethod.hdWallet,
          ),
        ),
        throwsA(isA<AuthException>()),
      );

      await repo.close();
    });

    test(
      'signIn success: registers new wallet, sends passphrase, starts monitor',
      () async {
        final auth = _FakeAuthService()
          // No existing users => new user => register branch
          ..users = [];

        final repo = _FakeTrezorRepository();
        final monitor = _FakeConnectionMonitor();

        // initialize storage state
        FlutterSecureStorage.setMockInitialValues(<String, String>{});
        const storage = FlutterSecureStorage();

        final service = TrezorAuthService(
          auth,
          repo,
          connectionMonitor: monitor,
          secureStorage: storage,
          passwordGenerator: (_) => 'generated-pass',
        );

        final future = service.signIn(
          walletName: 'ignored-by-service',
          password: 'user-passphrase',
          options: const AuthOptions(
            derivationMethod: DerivationMethod.hdWallet,
            privKeyPolicy: PrivateKeyPolicy.trezor(),
          ),
        );

        // Drive the repo stream after a brief delay to ensure listeners
        // are attached
        const taskId = 1;
        // ignore: discarded_futures
        Future<void>.delayed(const Duration(milliseconds: 5), () {
          repo
            ..emit(
              const TrezorInitializationState(
                status: AuthenticationStatus.initializing,
                taskId: taskId,
              ),
            )
            ..emit(
              const TrezorInitializationState(
                status: AuthenticationStatus.passphraseRequired,
                taskId: taskId,
              ),
            )
            ..emit(
              const TrezorInitializationState(
                status: AuthenticationStatus.completed,
                taskId: taskId,
              ),
            );
        });

        final user = await future;

        // Ensured register path used generated wallet password
        expect(auth.lastRegisterArgs, isNotNull);
        expect(
          auth.lastRegisterArgs!.walletName,
          TrezorAuthService.trezorWalletName,
        );
        expect(auth.lastRegisterArgs!.password, 'generated-pass');
        expect(
          auth.lastRegisterArgs!.options.privKeyPolicy,
          const PrivateKeyPolicy.trezor(),
        );

        // Passphrase forwarded to repo
        expect(repo.providedPassphrases[taskId], 'user-passphrase');

        // Password stored
        final all = await storage.read(key: 'trezor_wallet_password');
        expect(all, 'generated-pass');

        // Monitoring started
        expect(monitor.started, isTrue);

        // Returned user is active user
        expect(user.walletId.name, TrezorAuthService.trezorWalletName);

        await repo.close();
      },
    );

    test(
      'signInStreamed yields states and starts monitor on completion',
      () async {
        final auth = _FakeAuthService()..users = [];

        final repo = _FakeTrezorRepository();
        final monitor = _FakeConnectionMonitor();

        final service = TrezorAuthService(
          auth,
          repo,
          connectionMonitor: monitor,
          secureStorage: const FlutterSecureStorage(),
          passwordGenerator: (_) => 'gen',
        );

        final states = <AuthenticationState>[];
        final sub = service
            .signInStreamed(
              options: const AuthOptions(
                derivationMethod: DerivationMethod.hdWallet,
                privKeyPolicy: PrivateKeyPolicy.trezor(),
              ),
            )
            .listen(states.add);

        const taskId = 2;
        Future<void>.delayed(const Duration(milliseconds: 5), () {
          repo
            ..emit(
              const TrezorInitializationState(
                status: AuthenticationStatus.initializing,
                taskId: taskId,
              ),
            )
            ..emit(
              const TrezorInitializationState(
                status: AuthenticationStatus.completed,
                taskId: taskId,
              ),
            );
        });

        // Allow stream to process
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await sub.cancel();

        expect(
          states.map((e) => e.status),
          contains(AuthenticationStatus.initializing),
        );
        expect(states.last.status, AuthenticationStatus.completed);
        expect(monitor.started, isTrue);

        await repo.close();
      },
    );

    test('signIn errors on trezor init error and signs out', () async {
      final auth = _FakeAuthService()..users = [];
      final repo = _FakeTrezorRepository();
      final monitor = _FakeConnectionMonitor();

      final service = TrezorAuthService(
        auth,
        repo,
        connectionMonitor: monitor,
        secureStorage: const FlutterSecureStorage(),
        passwordGenerator: (_) => 'gen',
      );

      final future = service.signIn(
        walletName: 'w',
        password: 'p',
        options: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          privKeyPolicy: PrivateKeyPolicy.trezor(),
        ),
      );

      Future<void>.delayed(const Duration(milliseconds: 5), () {
        repo.emit(
          const TrezorInitializationState(
            status: AuthenticationStatus.error,
            message: 'boom',
            taskId: 3,
          ),
        );
      });

      await expectLater(future, throwsA(isA<AuthException>()));
      // Active user should be cleared by signOut in error path
      expect(auth.signOutCalled, isTrue);
      await repo.close();
    });

    test('existing user without stored password throws before auth', () async {
      final auth = _FakeAuthService()
        // Pre-existing Trezor user
        ..users = [
          KdfUser(
            walletId: WalletId.fromName(
              TrezorAuthService.trezorWalletName,
              const AuthOptions(
                derivationMethod: DerivationMethod.hdWallet,
                privKeyPolicy: PrivateKeyPolicy.trezor(),
              ),
            ),
            isBip39Seed: true,
          ),
        ];

      final repo = _FakeTrezorRepository();
      final monitor = _FakeConnectionMonitor();

      // Ensure storage has no saved password for this test
      FlutterSecureStorage.setMockInitialValues(<String, String>{});

      final service = TrezorAuthService(
        auth,
        repo,
        connectionMonitor: monitor,
        secureStorage: const FlutterSecureStorage(), // missing stored password
        passwordGenerator: (_) => 'gen',
      );

      await expectLater(
        service.signIn(
          walletName: 'ignored',
          password: 'user-pass',
          options: const AuthOptions(
            derivationMethod: DerivationMethod.hdWallet,
            privKeyPolicy: PrivateKeyPolicy.trezor(),
          ),
        ),
        throwsA(isA<AuthException>()),
      );

      await repo.close();
    });

    test('clearTrezorPassword deletes the key in secure storage', () async {
      final auth = _FakeAuthService();
      final repo = _FakeTrezorRepository();
      final monitor = _FakeConnectionMonitor();

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'trezor_wallet_password': 'to-remove',
      });
      const storage = FlutterSecureStorage();

      final service = TrezorAuthService(
        auth,
        repo,
        connectionMonitor: monitor,
        secureStorage: storage,
        passwordGenerator: (_) => 'gen',
      );

      await service.clearTrezorPassword();
      final value = await storage.read(key: 'trezor_wallet_password');
      expect(value, isNull);
      await repo.close();
    });

    test(
      'signOut stops monitoring and calls underlying auth signOut',
      () async {
        final auth = _FakeAuthService();
        final repo = _FakeTrezorRepository();
        final monitor = _FakeConnectionMonitor()
          ..started = true; // simulate active

        final service = TrezorAuthService(
          auth,
          repo,
          connectionMonitor: monitor,
          secureStorage: const FlutterSecureStorage(),
          passwordGenerator: (_) => 'gen',
        );

        await service.signOut();
        expect(monitor.stopCalls, 1);
        expect(auth.signOutCalled, isTrue);
        await repo.close();
      },
    );
  });
}
