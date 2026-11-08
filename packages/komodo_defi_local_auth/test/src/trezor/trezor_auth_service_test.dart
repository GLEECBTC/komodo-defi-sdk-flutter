import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show KdfStartupResult;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_local_auth/src/auth/kdf_startup_failure.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
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
  final Completer<void> _listening = Completer<void>();

  /// Completes once the service waits for device states.
  Future<void> get listening => _listening.future;

  void emit(TrezorInitializationState state) {
    _controller.add(state);
  }

  Future<void> close() async => _controller.close();

  @override
  Stream<TrezorInitializationState> initializeDevice({
    String? devicePubkey,
    Duration pollingInterval = const Duration(seconds: 1),
  }) async* {
    if (!_listening.isCompleted) _listening.complete();
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
  final sessions = AuthSessionTracker();
  @override
  Future<AuthSessionContext> captureSessionContext() async {
    sessions.observe(activeUser);
    return sessions.current ?? (throw const AuthSessionChangedException());
  }

  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      sessions.isCurrent(context);
  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!isSessionContextCurrent(context)) {
      throw const AuthSessionChangedException();
    }
  }

  @override
  Future<T> runWithSession<T>(
    AuthSessionContext expected,
    Future<T> Function() dispatch,
  ) {
    ensureSessionContextCurrent(expected);
    return dispatch();
  }

  @override
  Stream<AuthSessionContext?> watchSessionContext() => sessions.changes;
  @override
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext context,
    Map<String, dynamic> updates,
  ) async {
    ensureSessionContextCurrent(context);
    return activeUser = activeUser!.copyWith(
      metadata: {...activeUser!.metadata, ...updates},
    );
  }

  @override
  int get authGeneration => 0;

  @override
  Stream<int> get authGenerationChanges => const Stream<int>.empty();

  @override
  bool get isAuthTransitionInProgress => false;

  @override
  void invalidateAuthSession() {}

  @override
  void beginAuthTransition() {}

  @override
  void endAuthTransition() {}

  final StreamController<KdfUser?> _authStateController =
      StreamController<KdfUser?>.broadcast();

  List<KdfUser> users = [];
  KdfUser? activeUser;
  bool signOutCalled = false;

  /// Like [KdfAuthService], a sign-in takes its policy from the stored record.
  SecureLocalStorage? records;
  Exception? signInError;

  /// Thrown by the next sign-ins, one per call, before [signInError].
  final List<AuthException> signInFailures = [];
  Future<void> Function(String walletName)? onSignIn;
  int signInCalls = 0;
  AuthException? registerError;
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
    Future<void> Function(KdfUser target)? beforeDelete,
    Future<void> Function()? afterDelete,
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
  Future<void> verifyPassword({
    required String password,
    required WalletId expectedWalletId,
    AuthSessionContext? expectedSession,
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
    signInCalls++;
    await onSignIn?.call(walletName);
    if (signInFailures.isNotEmpty) throw signInFailures.removeAt(0);
    if (signInError case final error?) throw error;
    final stored = await records?.getUser(walletName);
    final user = KdfUser(
      walletId: WalletId.fromName(
        walletName,
        stored?.walletId.authOptions ?? options,
      ),
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
    Map<String, dynamic> initialMetadata = const {},
    String? provisioningId,
  }) async {
    lastRegisterArgs = (
      walletName: walletName,
      password: password,
      options: options,
    );
    if (registerError case final error?) throw error;
    final user = KdfUser(
      walletId: WalletId.fromName(walletName, options),
      isBip39Seed: true,
    );
    activeUser = user;
    _authStateController.add(user);
    return user;
  }

  @override
  Future<void> setActiveUserMetadata(
    JsonMap metadata, {
    required WalletId expectedWalletId,
  }) async => throw UnimplementedError();

  @override
  Future<void> updateActiveUserMetadataKey(
    String key,
    dynamic Function(dynamic currentValue) transform, {
    required WalletId expectedWalletId,
  }) async => throw UnimplementedError();

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
    WalletId? expectedWalletId,
    AuthSessionContext? expectedSession,
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

    test('clearTrezorPassword deletes the key in secure storage', () async {
      final auth = _FakeAuthService();
      final repo = _FakeTrezorRepository();
      final monitor = _FakeConnectionMonitor();

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'trezor_wallet_password': 'to-remove',
        'trezor_wallet_name': 'My Trezor 2',
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
      expect(await storage.read(key: 'trezor_wallet_name'), isNull);
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

  group('TrezorAuthService - existing local wallets', () {
    const storage = FlutterSecureStorage();
    final userStorage = SecureLocalStorage.withStorage(storage);
    const myTrezor = TrezorAuthService.trezorWalletName;
    final incorrectPassword = AuthException(
      'Incorrect password or invalid seed',
      type: AuthExceptionType.incorrectPassword,
    );

    late _FakeAuthService auth;
    late _FakeTrezorRepository repo;
    late TrezorAuthService service;

    setUp(() {
      auth = _FakeAuthService()..records = userStorage;
      repo = _FakeTrezorRepository();
      service = TrezorAuthService(
        auth,
        repo,
        connectionMonitor: _FakeConnectionMonitor(),
        secureStorage: storage,
        userStorage: userStorage,
        passwordGenerator: (_) => 'fresh-pass',
      );
    });

    tearDown(() => repo.close());

    Future<KdfUser> signIn() async {
      final result = service.signIn(
        walletName: 'ignored',
        password: 'device-passphrase',
        options: _trezorOptions,
      );
      await repo.listening;
      repo.emit(
        const TrezorInitializationState(
          status: AuthenticationStatus.completed,
          taskId: 1,
        ),
      );
      return result;
    }

    test('signs in to a recordless wallet and claims its record', () async {
      // KDF lists the wallet file, so the auth service saved a default record.
      final placeholder = _user(
        myTrezor,
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        metadata: {walletEntryIdMetadataKey: 'entry-1'},
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_$myTrezor': placeholder.toJson().toJsonString(),
      });
      auth.users = [placeholder];

      await signIn();

      expect(auth.lastSignInArgs?.walletName, myTrezor);
      expect(auth.lastSignInArgs?.password, 'saved-pass');
      expect(auth.lastRegisterArgs, isNull);
      final record = await userStorage.getUser(myTrezor);
      expect(record?.walletId.authOptions, _trezorOptions);
      expect(record?.metadata[walletEntryIdMetadataKey], 'entry-1');
    });

    test(
      'registers a new wallet when the saved password is rejected',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'trezor_wallet_password': 'stale-pass',
        });
        auth
          ..users = [_user(myTrezor, _trezorOptions)]
          ..signInError = incorrectPassword;

        final user = await signIn();

        expect(auth.lastSignInArgs?.password, 'stale-pass');
        // A wallet without a verified identity gets no second attempt.
        expect(auth.signInCalls, 1);
        expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
        expect(auth.lastRegisterArgs?.password, 'fresh-pass');
        expect(auth.lastRegisterArgs?.options, _trezorOptions);
        expect(user.walletId.name, '$myTrezor 2');
        expect(await storage.read(key: 'trezor_wallet_name'), '$myTrezor 2');
        expect(await storage.read(key: 'trezor_wallet_password'), 'fresh-pass');
      },
    );

    test(
      'registers a new wallet when desktop KDF exits on the password',
      () async {
        // The desktop executable exits with status 1 for any startup error.
        FlutterSecureStorage.setMockInitialValues({
          'trezor_wallet_password': 'stale-pass',
        });
        auth
          ..users = [_user(myTrezor, _trezorOptions)]
          ..signInError = authExceptionForKdfStartup(
            KdfStartupResult.invalidParams,
            walletPasswordSent: true,
          );

        await signIn();

        expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
        expect(await storage.read(key: 'trezor_wallet_name'), '$myTrezor 2');
      },
    );

    test(
      'restores a claimed record when the saved password is rejected',
      () async {
        final placeholder = _user(
          myTrezor,
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          metadata: {walletEntryIdMetadataKey: 'entry-1'},
        );
        FlutterSecureStorage.setMockInitialValues({
          'trezor_wallet_password': 'stale-pass',
          'user_$myTrezor': placeholder.toJson().toJsonString(),
        });
        auth
          ..users = [placeholder]
          ..signInError = incorrectPassword;

        await signIn();

        expect(auth.lastSignInArgs?.walletName, myTrezor);
        expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
        expect(await userStorage.getUser(myTrezor), placeholder);
      },
    );

    test(
      'restores a claimed record when sign-in fails for another reason',
      () async {
        final placeholder = _user(
          myTrezor,
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        );
        FlutterSecureStorage.setMockInitialValues({
          'trezor_wallet_password': 'saved-pass',
          'user_$myTrezor': placeholder.toJson().toJsonString(),
        });
        auth
          ..users = [placeholder]
          ..signInError = AuthException(
            'KDF is not available. Please try again.',
            type: AuthExceptionType.apiConnectionError,
          );

        await expectLater(
          service.signIn(
            walletName: 'ignored',
            password: 'device-passphrase',
            options: _trezorOptions,
          ),
          throwsA(isA<AuthException>()),
        );
        expect(auth.lastRegisterArgs, isNull);
        expect(await userStorage.getUser(myTrezor), placeholder);
      },
    );

    test('restores a claimed record after an unexpected error', () async {
      final placeholder = _user(
        myTrezor,
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_$myTrezor': placeholder.toJson().toJsonString(),
      });
      auth
        ..users = [placeholder]
        ..signInError = const FormatException('unexpected');

      await expectLater(
        service.signIn(
          walletName: 'ignored',
          password: 'device-passphrase',
          options: _trezorOptions,
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('FormatException'),
          ),
        ),
      );
      expect(await userStorage.getUser(myTrezor), placeholder);
    });

    test('keeps a record that a session verified during the attempt', () async {
      final placeholder = _user(
        myTrezor,
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      );
      final verified = KdfUser(
        walletId: WalletId.withPubkeyHash(myTrezor, _trezorOptions, _hash),
        isBip39Seed: true,
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_$myTrezor': placeholder.toJson().toJsonString(),
      });
      auth
        ..users = [placeholder]
        ..onSignIn = ((_) => userStorage.saveUser(verified))
        ..signInError = AuthException(
          'KDF is not available. Please try again.',
          type: AuthExceptionType.apiConnectionError,
        );

      await expectLater(
        service.signIn(
          walletName: 'ignored',
          password: 'device-passphrase',
          options: _trezorOptions,
        ),
        throwsA(isA<AuthException>()),
      );
      expect(await userStorage.getUser(myTrezor), verified);
    });

    test('retries a wallet opened here before once', () async {
      final trezorWallet = KdfUser(
        walletId: WalletId.withPubkeyHash(myTrezor, _trezorOptions, _hash),
        isBip39Seed: true,
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_$myTrezor': trezorWallet.toJson().toJsonString(),
      });
      auth
        ..users = [trezorWallet]
        ..signInFailures.add(_desktopStartFailure());

      final user = await signIn();

      expect(auth.signInCalls, 2);
      expect(auth.lastRegisterArgs, isNull);
      expect(user.walletId.name, myTrezor);
    });

    test('replaces a wallet opened here before if the retry fails', () async {
      final trezorWallet = KdfUser(
        walletId: WalletId.withPubkeyHash(myTrezor, _trezorOptions, _hash),
        isBip39Seed: true,
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_$myTrezor': trezorWallet.toJson().toJsonString(),
      });
      auth
        ..users = [trezorWallet]
        ..signInFailures.addAll([
          _desktopStartFailure(),
          _desktopStartFailure(),
        ]);

      await signIn();

      expect(auth.signInCalls, 2);
      expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
      expect(await userStorage.getUser(myTrezor), trezorWallet);
    });

    test('signs out of a wallet that turns out not to be Trezor', () async {
      // Listed as a placeholder, but stored with an identity by the time the
      // record is claimed.
      final listed = _user(
        myTrezor,
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      );
      final software = KdfUser(
        walletId: WalletId.withPubkeyHash(
          myTrezor,
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          _hash,
        ),
        isBip39Seed: true,
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_$myTrezor': software.toJson().toJsonString(),
      });
      auth.users = [listed];

      final user = await signIn();

      expect(auth.signOutCalled, isTrue);
      expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
      expect(user.walletId.authOptions, _trezorOptions);
      expect(await userStorage.getUser(myTrezor), software);
    });

    test('finds the wallet under another letter case', () async {
      final placeholder = _user(
        'my trezor',
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_my trezor': placeholder.toJson().toJsonString(),
      });
      auth.users = [placeholder];

      await signIn();

      expect(auth.lastSignInArgs?.walletName, 'my trezor');
      expect(auth.lastRegisterArgs, isNull);
      final record = await userStorage.getUser('my trezor');
      expect(record?.walletId.authOptions, _trezorOptions);
    });

    test('prefers the exact wallet name over another letter case', () async {
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
      });
      auth.users = [
        _user(
          'my trezor',
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
        _user(myTrezor, _trezorOptions),
      ];

      await signIn();

      expect(auth.lastSignInArgs?.walletName, myTrezor);
    });

    test('keeps the saved wallet when KDF fails to spawn', () async {
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
      });
      auth
        ..users = [_user(myTrezor, _trezorOptions)]
        ..signInError = authExceptionForKdfStartup(
          KdfStartupResult.spawnError,
          walletPasswordSent: true,
        );

      await expectLater(
        service.signIn(
          walletName: 'ignored',
          password: 'device-passphrase',
          options: _trezorOptions,
        ),
        throwsA(isA<AuthException>()),
      );
      expect(auth.lastRegisterArgs, isNull);
    });

    test('keeps the saved credentials when the new wallet fails', () async {
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'stale-pass',
      });
      auth
        ..users = [_user(myTrezor, _trezorOptions)]
        ..signInError = incorrectPassword
        ..registerError = AuthException(
          'KDF is not available. Please try again.',
          type: AuthExceptionType.apiConnectionError,
        );

      await expectLater(
        service.signIn(
          walletName: 'ignored',
          password: 'device-passphrase',
          options: _trezorOptions,
        ),
        throwsA(isA<AuthException>()),
      );
      expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
      expect(await storage.read(key: 'trezor_wallet_name'), isNull);
      expect(await storage.read(key: 'trezor_wallet_password'), 'stale-pass');
    });

    test('leaves a software wallet with the same name untouched', () async {
      final software = KdfUser(
        walletId: WalletId.withPubkeyHash(
          myTrezor,
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
        ),
        isBip39Seed: true,
      );
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_password': 'saved-pass',
        'user_$myTrezor': software.toJson().toJsonString(),
      });
      auth.users = [software];

      await signIn();

      expect(auth.lastSignInArgs, isNull);
      expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
      expect(await userStorage.getUser(myTrezor), software);
    });

    test('registers a new wallet when no password is saved', () async {
      FlutterSecureStorage.setMockInitialValues({});
      auth.users = [_user(myTrezor, _trezorOptions)];

      await signIn();

      expect(auth.lastSignInArgs, isNull);
      expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
      expect(auth.lastRegisterArgs?.password, 'fresh-pass');
    });

    test('skips names already taken, ignoring case', () async {
      FlutterSecureStorage.setMockInitialValues({});
      auth.users = [
        _user(myTrezor, _trezorOptions),
        _user('my trezor 2', _trezorOptions),
      ];

      await signIn();

      expect(auth.lastRegisterArgs?.walletName, '$myTrezor 3');
    });

    test('signs in to the saved wallet name on later sessions', () async {
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_name': '$myTrezor 2',
        'trezor_wallet_password': 'saved-pass',
      });
      auth.users = [
        _user(myTrezor, _trezorOptions),
        _user('$myTrezor 2', _trezorOptions),
      ];

      await signIn();

      expect(auth.lastSignInArgs?.walletName, '$myTrezor 2');
      expect(auth.lastSignInArgs?.password, 'saved-pass');
      expect(auth.lastRegisterArgs, isNull);
    });

    test(
      'keeps the saved wallet when sign-in fails for another reason',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'trezor_wallet_password': 'saved-pass',
        });
        auth
          ..users = [_user(myTrezor, _trezorOptions)]
          ..signInError = AuthException(
            'KDF is not available. Please try again.',
            type: AuthExceptionType.apiConnectionError,
          );

        await expectLater(
          service.signIn(
            walletName: 'ignored',
            password: 'device-passphrase',
            options: _trezorOptions,
          ),
          throwsA(
            isA<AuthException>().having(
              (e) => e.type,
              'type',
              AuthExceptionType.apiConnectionError,
            ),
          ),
        );
        expect(auth.lastRegisterArgs, isNull);
        expect(await storage.read(key: 'trezor_wallet_name'), isNull);
        expect(await storage.read(key: 'trezor_wallet_password'), 'saved-pass');
      },
    );

    test('signs out a renamed wallet session when the device fails', () async {
      FlutterSecureStorage.setMockInitialValues({
        'trezor_wallet_name': '$myTrezor 2',
      });

      final result = service.signIn(
        walletName: 'ignored',
        password: 'device-passphrase',
        options: _trezorOptions,
      );
      await repo.listening;
      repo.emit(
        const TrezorInitializationState(
          status: AuthenticationStatus.error,
          message: 'boom',
          taskId: 1,
        ),
      );

      await expectLater(result, throwsA(isA<AuthException>()));
      expect(auth.lastRegisterArgs?.walletName, '$myTrezor 2');
      expect(auth.signOutCalled, isTrue);
    });
  });
}

const _trezorOptions = AuthOptions(
  derivationMethod: DerivationMethod.hdWallet,
  privKeyPolicy: PrivateKeyPolicy.trezor(),
);

const _hash = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678';

/// The desktop executable exits with status 1 for any startup error.
AuthException _desktopStartFailure() => authExceptionForKdfStartup(
  KdfStartupResult.invalidParams,
  walletPasswordSent: true,
);

KdfUser _user(
  String name,
  AuthOptions options, {
  Map<String, dynamic> metadata = const {},
}) => KdfUser(
  walletId: WalletId.fromName(name, options),
  isBip39Seed: true,
  metadata: metadata,
);
