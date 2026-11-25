import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'support/fake_kdf_engine.dart';
import 'support/source_assets.dart';

/// The real framework over a shutdown-signal stream the test can drive.
class _Framework implements KomodoDefiFramework {
  _Framework(this._real);

  final KomodoDefiFramework _real;
  final shutdownSignals = StreamController<ShutdownSignalEvent>.broadcast();
  late final _streaming = _Streaming(shutdownSignals.stream);

  @override
  KdfEventStreamingService get streaming => _streaming;

  @override
  ApiClient get client => _real.client;

  @override
  Future<bool> isRunning({bool allowVersionFallback = true}) =>
      _real.isRunning(allowVersionFallback: allowVersionFallback);

  @override
  Future<KdfStartupResult> startKdf(
    KdfStartupConfig startupConfig, {
    bool validateHostConfig = true,
  }) => _real.startKdf(startupConfig, validateHostConfig: validateHostConfig);

  @override
  Future<StopStatus> kdfStop() => _real.kdfStop();

  @override
  void resetHttpClient() => _real.resetHttpClient();

  @override
  Future<MainStatus> kdfMainStatus() => _real.kdfMainStatus();

  @override
  Future<String?> version() => _real.version();

  @override
  Future<bool> isHealthy() => _real.isHealthy();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Streaming implements KdfEventStreamingService {
  _Streaming(this.shutdownSignals);

  @override
  final Stream<ShutdownSignalEvent> shutdownSignals;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useSourceAssets(binding);

  group('a reviewed deletion refused before the engine stops', () {
    for (final cause in ['app lock', 'superseding authentication revision']) {
      test('$cause leaves the active session as it was', () async {
        seedStoredUsers(const []);
        final engine = FakeKdfEngine(wallets: [], activeWallet: null);
        final framework = _Framework(frameworkFor(engine));
        final service = KdfAuthService(framework, testHostConfig);
        addTearDown(service.dispose);

        final created = await service.register(
          walletName: 'new-wallet',
          password: testPassword,
        );
        expect(created.isGeneratedThisSession, isTrue);
        final session = await service.captureSessionContext();
        final stops = engine.stops;
        final events = <KdfUser?>[];
        final subscription = service.authStateChanges.listen(events.add);
        addTearDown(subscription.cancel);

        // An unanswered dispatch leases the engine, so the deletion waits
        // between starting its transition and stopping the engine.
        final dispatched = Completer<void>();
        final answer = Completer<void>();
        final pendingDispatch = service.runWithSession(session, () {
          dispatched.complete();
          return answer.future;
        });
        await dispatched.future;
        final transitionStarted = Completer<void>();
        final generations = service.authGenerationChanges.listen((_) {
          if (service.isAuthTransitionInProgress &&
              !transitionStarted.isCompleted) {
            transitionStarted.complete();
          }
        });
        addTearDown(generations.cancel);

        var authorized = true;
        final rejected = expectLater(
          RpcDispatchGuard.run(
            () {
              if (!authorized) throw StateError('app locked');
            },
            () => service.deleteWallet(
              walletName: 'new-wallet',
              password: testPassword,
              allowActiveWallet: true,
              beforeDelete: (_) async {},
            ),
            methods: const {'delete_wallet'},
          ),
          throwsA(
            cause == 'app lock'
                ? isA<RpcDispatchRejected>()
                : isA<AuthSessionChangedException>(),
          ),
        );
        await transitionStarted.future;
        if (cause == 'app lock') {
          authorized = false;
        } else {
          service.invalidateAuthSession();
        }
        answer.complete();
        await pendingDispatch;
        await rejected;
        await Future<void>.delayed(Duration.zero);

        expect(engine.stops, stops);
        expect(engine.sent('delete_wallet'), 0);
        expect(events, isEmpty);
        expect(service.isAuthTransitionInProgress, isFalse);
        expect(framework.shutdownSignals.hasListener, isTrue);
        final active = await service.getActiveUser();
        expect(active?.walletId, created.walletId);
        expect(active?.isGeneratedThisSession, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        // The refused transition revoked the old token, not the session.
        expect(service.isSessionContextCurrent(session), isFalse);
        expect(
          (await service.captureSessionContext()).walletId,
          created.walletId,
        );

        // The still-running engine can report its own shutdown.
        final signedOut = service.authStateChanges
            .firstWhere((user) => user == null)
            .timeout(const Duration(seconds: 2));
        framework.shutdownSignals.add(ShutdownSignalEvent(signalName: 'TEST'));
        await signedOut;
      });
    }
  });

  group('a deletion whose answer is lost', () {
    late FakeKdfEngine engine;
    late KdfAuthService service;
    late List<KdfUser?> events;
    late bool cleaned;

    setUp(() async {
      seedStoredUsers([verifiedUser()]);
      engine = FakeKdfEngine();
      service = authServiceFor(engine);
      addTearDown(service.dispose);
      await service.getUsers();
      await service.getActiveUser();
      events = [];
      final subscription = service.authStateChanges.listen(events.add);
      addTearDown(subscription.cancel);
      cleaned = false;
    });

    Future<void> remove({bool reviewed = true}) => service.deleteWallet(
      walletName: testWalletName,
      password: testPassword,
      allowActiveWallet: reviewed,
      beforeDelete: reviewed ? (_) async {} : null,
      afterDelete: () async => cleaned = true,
    );

    Matcher notDeleted() => isA<AuthException>()
        .having((e) => e.type, 'type', AuthExceptionType.generalAuthError)
        .having((e) => e.message, 'message', 'Failed to delete wallet');

    test('is committed once the engine no longer lists the wallet', () async {
      engine.answers['delete_wallet'] = () async {
        engine.wallets.remove(testWalletName);
        throw ClientException('connection closed before the answer');
      };

      await remove();
      await Future<void>.delayed(Duration.zero);

      expect(engine.sent('delete_wallet'), 1);
      expect(cleaned, isTrue);
      expect(await SecureLocalStorage().getUser(testWalletName), isNull);
      expect(events, [null]);
      expect(service.isAuthTransitionInProgress, isFalse);
    });

    test('still reports a failed catalog cleanup as committed', () async {
      engine.answers['delete_wallet'] = () async {
        engine.wallets.remove(testWalletName);
        throw ClientException('connection closed before the answer');
      };
      final stored = (await SecureLocalStorage().getUser(testWalletName))!;
      final failing = authServiceFor(
        engine,
        storage: SecureLocalStorage.withStorage(const _DeleteFailingStorage()),
      );
      addTearDown(failing.dispose);

      await expectLater(
        failing.deleteWallet(
          walletName: testWalletName,
          password: testPassword,
          allowActiveWallet: true,
          beforeDelete: (_) async {},
          afterDelete: () async => cleaned = true,
        ),
        throwsA(
          isA<WalletDeletionCommittedException>()
              .having((e) => e.walletId, 'removed identity', stored.walletId)
              .having(
                (e) => e.entryId,
                'entry',
                stored.metadata[walletEntryIdMetadataKey],
              ),
        ),
      );
      expect(cleaned, isTrue);
    });

    test('is not deleted while the engine still lists the wallet', () async {
      engine.answers['delete_wallet'] = () async =>
          throw ClientException('connection closed before the request');

      await expectLater(remove(), throwsA(notDeleted()));

      expect(engine.sent('delete_wallet'), 1);
      expect(cleaned, isFalse);
      expect(await SecureLocalStorage().getUser(testWalletName), isNotNull);
    });

    test('is not deleted when the catalog cannot be read again', () async {
      engine.answers['delete_wallet'] = () async {
        engine.wallets.remove(testWalletName);
        engine.answers['get_wallet_names'] = () async =>
            throw ClientException('engine unreachable');
        throw ClientException('connection closed before the answer');
      };

      await expectLater(remove(), throwsA(notDeleted()));

      expect(cleaned, isFalse);
      expect(await SecureLocalStorage().getUser(testWalletName), isNotNull);
    });

    test('is not attributed to a deletion that never reviewed the '
        'wallet', () async {
      engine
        ..activeWallet = null
        ..answers['delete_wallet'] = () async {
          engine.wallets.remove(testWalletName);
          throw ClientException('connection closed before the answer');
        };

      await expectLater(remove(reviewed: false), throwsA(notDeleted()));

      expect(cleaned, isFalse);
    });

    test('an engine refusal is never re-read as a deletion', () async {
      engine.answers['delete_wallet'] = () async {
        engine.wallets.remove(testWalletName);
        return {
          'mmrpc': '2.0',
          'error': 'Wallet storage is unavailable',
          'error_type': 'WalletsStorageError',
        };
      };

      await expectLater(
        remove(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.type,
            'type',
            AuthExceptionType.internalError,
          ),
        ),
      );

      expect(cleaned, isFalse);
      expect(await SecureLocalStorage().getUser(testWalletName), isNotNull);
    });
  });
}

class _DeleteFailingStorage extends FlutterSecureStorage {
  const _DeleteFailingStorage();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future<void>.error(StateError('secure storage delete failed'));
}
