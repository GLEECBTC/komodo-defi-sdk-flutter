import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

class _FakeKdfOperations implements IKdfOperations {
  _FakeKdfOperations({
    required this.responsesByMethod,
    this.responseHandlersByMethod = const {},
  });

  final Map<String, Map<String, dynamic>> responsesByMethod;
  final Map<String, Future<Map<String, dynamic>> Function()>
  responseHandlersByMethod;
  bool _isRunning = true;
  int stopCount = 0;
  final starts = <Map<String, dynamic>>[];
  final requests = <Map<String, dynamic>>[];
  void Function(Map<String, dynamic>)? onStart;
  Future<void> Function()? beforeStop;
  Future<void> Function()? beforeStart;

  @override
  String get operationsName => 'fake';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async {
    starts.add(startParams);
    onStart?.call(startParams);
    await beforeStart?.call();
    _isRunning = true;
    return KdfStartupResult.ok;
  }

  @override
  Future<MainStatus> kdfMainStatus() async => MainStatus.rpcIsUp;

  @override
  Future<StopStatus> kdfStop() async {
    stopCount++;
    await beforeStop?.call();
    _isRunning = false;
    return StopStatus.ok;
  }

  @override
  Future<bool> isRunning() async => _isRunning;

  @override
  Future<String?> version() async => _isRunning ? 'test-version' : null;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    requests.add(request);
    final method = request['method'] as String?;
    if (method == null) {
      return {'mmrpc': '2.0', 'result': <String, dynamic>{}};
    }

    final handler = responseHandlersByMethod[method];
    if (handler != null) return handler();

    return responsesByMethod[method] ??
        <String, dynamic>{'mmrpc': '2.0', 'result': <String, dynamic>{}};
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

class _WriteFailingFlutterSecureStorage extends FlutterSecureStorage {
  const _WriteFailingFlutterSecureStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future<void>.error(StateError('secure storage write failed'));
}

class _ObservedFlutterSecureStorage extends FlutterSecureStorage {
  _ObservedFlutterSecureStorage({required this.beforeWrite});
  final Future<void> Function(String key, String? value) beforeWrite;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await beforeWrite(key, value);
    await super.write(key: key, value: value);
  }
}

class _DeleteFailingFlutterSecureStorage extends FlutterSecureStorage {
  const _DeleteFailingFlutterSecureStorage();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future<void>.error(StateError('SECRET_DELETE_CANARY'));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testHome;
  setUpAll(() async {
    testHome = await Directory.systemTemp.createTemp('local-auth-test-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => testHome.path,
    );
    // Read the existing source assets without running build transformers.
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key.endsWith('app_build/build_config.json')) {
        // Force the local seed-node fallback without a network request.
        return ByteData.sublistView(
          Uint8List.fromList(
            utf8.encode(
              '{"coins":{"coins_repo_content_url":"http://[","cdn_branch_mirrors":{}}}',
            ),
          ),
        );
      }
      if (!key.startsWith('packages/')) return null;
      final source = File('../${key.substring('packages/'.length)}');
      if (!source.existsSync()) return null;
      return ByteData.sublistView(await source.readAsBytes());
    });
  });
  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    await testHome.delete(recursive: true);
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('fresh credential verification', () {
    late KdfAuthService service;
    late _FakeKdfOperations operations;
    setUp(() {
      final user = _verifiedTestUser();
      FlutterSecureStorage.setMockInitialValues({
        'user_test-wallet': jsonEncode(user.toJson()),
      });
      service = _createService(
        onOperationsCreated: (value) => operations = value,
      );
      addTearDown(service.dispose);
    });

    test('verifies password through KDF even for the active wallet', () async {
      final session = await service.captureSessionContext();
      await service.verifyPassword(
        password: 'test-only-correct-password',
        expectedWalletId: session.walletId,
        expectedSession: session,
      );
      final requests = operations.requests.where(
        (r) => r['method'] == 'get_mnemonic',
      );
      expect(requests, hasLength(1));
      expect(
        (requests.single['params'] as Map)['password'],
        'test-only-correct-password',
      );
      expect(operations.starts, isEmpty);
      operations.responsesByMethod['get_mnemonic'] = {
        'mmrpc': '2.0',
        'error': 'Error decrypting mnemonic: HMAC error: MAC tag mismatch',
        'error_type': 'Internal',
      };
      await expectLater(
        service.verifyPassword(
          password: 'wrong',
          expectedWalletId: session.walletId,
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.type,
            'type',
            AuthExceptionType.incorrectPassword,
          ),
        ),
      );
    });

    test('rejects a different expected identity before secret RPC', () async {
      await expectLater(
        service.verifyPassword(
          password: 'pw',
          expectedWalletId: _verifiedTestUser().walletId.copyWith(
            pubkeyHash: _secondPublicKeyHash,
          ),
        ),
        throwsA(isA<WalletChangedDisconnectException>()),
      );
      expect(
        operations.requests.where((r) => r['method'] == 'get_mnemonic'),
        isEmpty,
      );
    });

    test(
      'password rotation rejects a different target before dispatch',
      () async {
        final session = await service.captureSessionContext();
        await expectLater(
          service.updatePassword(
            currentPassword: 'same-custom-password',
            newPassword: 'replacement-password',
            expectedWalletId: session.walletId.copyWith(
              pubkeyHash: _secondPublicKeyHash,
            ),
            expectedSession: session,
          ),
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        expect(
          operations.requests.where(
            (r) => r['method'] == 'change_mnemonic_password',
          ),
          isEmpty,
        );
      },
    );

    test(
      'password rotation rejects a superseded session before dispatch',
      () async {
        final session = await service.captureSessionContext();
        service
          ..beginAuthTransition()
          ..endAuthTransition();
        await expectLater(
          service.updatePassword(
            currentPassword: 'same-custom-password',
            newPassword: 'replacement-password',
            expectedWalletId: session.walletId,
            expectedSession: session,
          ),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(
          operations.requests.where(
            (r) => r['method'] == 'change_mnemonic_password',
          ),
          isEmpty,
        );
      },
    );

    test(
      'password rotation does not expose rejected credential payloads',
      () async {
        final session = await service.captureSessionContext();
        operations.responsesByMethod['change_mnemonic_password'] = {
          'mmrpc': '2.0',
          'error': 'rejected SECRET_CREDENTIAL_CANARY',
          'error_type': 'Internal',
        };
        await expectLater(
          service.updatePassword(
            currentPassword: 'same-custom-password',
            newPassword: 'replacement-password',
            expectedWalletId: session.walletId,
            expectedSession: session,
          ),
          throwsA(
            isA<AuthException>().having(
              (error) => error.toString(),
              'sanitized error',
              isNot(contains('SECRET_CREDENTIAL_CANARY')),
            ),
          ),
        );
      },
    );

    test(
      'logout invalidates a pending successful credential response',
      () async {
        final session = await service.captureSessionContext();
        final reachedRpc = Completer<void>();
        final response = Completer<Map<String, dynamic>>();
        operations.responseHandlersByMethod['get_mnemonic'] = () {
          reachedRpc.complete();
          return response.future;
        };
        final checking = service.verifyPassword(
          password: 'pw',
          expectedWalletId: session.walletId,
          expectedSession: session,
        );
        final rejected = expectLater(
          checking,
          throwsA(isA<AuthSessionChangedException>()),
        );
        await reachedRpc.future;
        final signingOut = service.signOut();
        response.complete(operations.responsesByMethod['get_mnemonic']);
        await rejected;
        await signingOut;
      },
    );
  });

  test(
    'authentication diagnostics omit wallet input and raw stream errors',
    () async {
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final records = <LogRecord>[];
      final failureSeen = Completer<void>();
      final subscription = Logger.root.onRecord.listen((record) {
        records.add(record);
        if (record.loggerName == 'KdfAuthService' &&
            record.message.contains(
              'Could not enable shutdown signal stream',
            ) &&
            !failureSeen.isCompleted) {
          failureSeen.complete();
        }
      });
      addTearDown(() async {
        await subscription.cancel();
        Logger.root.level = previousLevel;
      });
      final service = _createService(
        onOperationsCreated: (operations) {
          operations
                  .responseHandlersByMethod['stream::shutdown_signal::enable'] =
              () async => Error.throwWithStackTrace(
                StateError('RPC_PAYLOAD_SENTINEL'),
                StackTrace.fromString('STACK_PAYLOAD_SENTINEL'),
              );
        },
      );
      addTearDown(service.dispose);
      await failureSeen.future.timeout(const Duration(seconds: 3));
      await expectLater(
        service.signIn(
          walletName: 'WALLET_INPUT_SENTINEL',
          password: 'PASSWORD_INPUT_SENTINEL',
          options: _testUser().walletId.authOptions,
        ),
        throwsA(isA<AuthException>()),
      );
      final diagnostics = records
          .map(
            (record) =>
                '${record.message} ${record.error} ${record.stackTrace}',
          )
          .join('\n');
      for (final sentinel in [
        'RPC_PAYLOAD_SENTINEL',
        'STACK_PAYLOAD_SENTINEL',
        'WALLET_INPUT_SENTINEL',
        'PASSWORD_INPUT_SENTINEL',
      ]) {
        expect(diagnostics, isNot(contains(sentinel)));
      }
    },
  );

  group('KdfAuthService.authGeneration', () {
    test(
      'nested transitions notify synchronously with the busy state visible',
      () async {
        final service = _createService();
        addTearDown(service.dispose);
        final observed = <({int generation, bool busy})>[];
        final subscription = service.authGenerationChanges.listen((generation) {
          observed.add((
            generation: generation,
            busy: service.isAuthTransitionInProgress,
          ));
        });
        addTearDown(subscription.cancel);
        final generation = service.authGeneration;

        service.beginAuthTransition();
        expect(observed, [(generation: generation + 1, busy: true)]);
        service.beginAuthTransition();
        service.endAuthTransition();
        expect(service.isAuthTransitionInProgress, isTrue);
        service.endAuthTransition();
        expect(service.isAuthTransitionInProgress, isFalse);
        expect(observed, hasLength(2));
      },
    );

    test('ordinary identity reads keep the session revision stable', () async {
      final service = _createService();
      addTearDown(service.dispose);
      await service.restoreSession(_testUser());
      final generation = service.authGeneration;

      await service.getActiveUser();
      await service.getActiveUser();

      expect(service.authGeneration, generation);
    });

    test(
      'restoring the same wallet invalidates prior work synchronously',
      () async {
        final service = _createService();
        addTearDown(service.dispose);
        await service.restoreSession(_testUser());
        final generation = service.authGeneration;

        final restoration = service.restoreSession(_testUser());

        expect(service.authGeneration, greaterThan(generation));
        await restoration;
        expect((await service.getActiveUser())?.walletId.name, 'test-wallet');
      },
    );

    test(
      'sign-out invalidates work before the authentication lock is free',
      () async {
        final readStarted = Completer<void>();
        final releaseRead = Completer<void>();
        var blockReads = false;
        final service = _createService(
          publicKeyHashResponseHandler: () async {
            if (blockReads) {
              readStarted.complete();
              await releaseRead.future;
            }
            return {
              'mmrpc': '2.0',
              'result': {'public_key_hash': _publicKeyHash},
            };
          },
        );
        addTearDown(service.dispose);
        await service.restoreSession(_testUser());
        final generation = service.authGeneration;
        blockReads = true;
        final pendingRead = service.getActiveUser();
        await readStarted.future;

        final signOut = service.signOut();

        expect(service.authGeneration, greaterThan(generation));
        releaseRead.complete();
        await pendingRead;
        await signOut;
        expect(await service.getActiveUser(), isNull);
      },
    );

    test(
      'a sign-out and same-wallet restoration never reuse a revision',
      () async {
        late _FakeKdfOperations operations;
        final service = _createService(
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);
        await service.restoreSession(_testUser());
        final generation = service.authGeneration;

        await service.signOut();
        final signedOutGeneration = service.authGeneration;
        operations._isRunning = true;
        await service.restoreSession(_testUser());

        expect(signedOutGeneration, greaterThan(generation));
        expect(service.authGeneration, greaterThan(signedOutGeneration));
        expect((await service.getActiveUser())?.walletId.name, 'test-wallet');
      },
    );
  });

  group('KomodoDefiLocalAuth public transition races', () {
    for (final transition in ['signOut', 'same-wallet signIn', 'register']) {
      test(
        '$transition revokes before its blocked authentication read',
        () async {
          final readStarted = Completer<void>();
          final releaseRead = Completer<void>();
          var blockReads = false;
          final auth = _createPublicAuth(
            publicKeyHashResponseHandler: () async {
              if (blockReads) {
                if (!readStarted.isCompleted) readStarted.complete();
                await releaseRead.future;
              }
              return {
                'mmrpc': '2.0',
                'result': {'public_key_hash': _publicKeyHash},
              };
            },
          );
          addTearDown(auth.dispose);
          final originalUser = await auth.currentUser;
          expect(originalUser, isNotNull);
          final generation = auth.authGeneration;
          var notifiedSynchronously = false;
          final subscription = auth.authGenerationChanges.listen((_) {
            notifiedSynchronously = true;
          });
          addTearDown(subscription.cancel);
          blockReads = true;

          final transitionFuture = switch (transition) {
            'signOut' => auth.signOut(),
            'same-wallet signIn' =>
              auth
                  .signIn(
                    walletName: originalUser!.walletId.name,
                    password: 'synthetic-password',
                  )
                  .then((_) {}),
            _ =>
              auth
                  .register(
                    walletName: 'new-wallet',
                    password: 'synthetic-password',
                  )
                  .then((_) {}),
          };
          final completion = transition == 'signOut'
              ? expectLater(transitionFuture, completes)
              : expectLater(transitionFuture, throwsA(isA<AuthException>()));

          expect(notifiedSynchronously, isTrue);
          expect(auth.authGeneration, greaterThan(generation));
          expect(auth.isAuthTransitionInProgress, isTrue);
          await readStarted.future;
          expect(auth.isAuthTransitionInProgress, isTrue);

          releaseRead.complete();
          await completion;
          expect(auth.isAuthTransitionInProgress, isFalse);
          if (transition != 'signOut') {
            // A rejected transition must still revoke prior results, without
            // leaving the same authenticated wallet permanently busy.
            expect((await auth.currentUser)?.walletId, originalUser!.walletId);
          }
        },
      );
    }

    test(
      'dispose revokes before a paused wallet-deletion stream can close',
      () async {
        final auth = _createPublicAuth();
        await auth.currentUser;
        final generation = auth.authGeneration;
        var notifiedSynchronously = false;
        final generations = auth.authGenerationChanges.listen((_) {
          notifiedSynchronously = true;
        });
        final deletions = auth.walletDeletions.listen((_) {})..pause();
        var disposalCompleted = false;

        final disposal = auth.dispose().then((_) => disposalCompleted = true);

        expect(notifiedSynchronously, isTrue);
        expect(auth.authGeneration, greaterThan(generation));
        expect(auth.isAuthTransitionInProgress, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(disposalCompleted, isFalse);
        expect(auth.isAuthTransitionInProgress, isTrue);
        deletions.resume();
        await disposal;
        expect(auth.isAuthTransitionInProgress, isTrue);
        await generations.cancel();
        await deletions.cancel();
      },
    );
  });

  group('KomodoDefiLocalAuth.getMnemonicPlainText', () {
    const secretCanary = 'synthetic-secret-error-detail';
    for (final kind in ['typed', 'json-rpc', 'general']) {
      test(
        'normalizes delayed $kind wrong-password errors and allows retry',
        () async {
          final requestStarted = Completer<void>();
          final response = Completer<Map<String, dynamic>>();
          var attempts = 0;
          final auth = _createPublicAuth(
            mnemonicResponseHandler: () {
              if (attempts++ == 0) {
                requestStarted.complete();
                return response.future;
              }
              return Future.value({
                'mmrpc': '2.0',
                'result': {
                  'format': 'plaintext',
                  'mnemonic':
                      'abandon abandon abandon abandon abandon abandon '
                      'abandon abandon abandon abandon abandon about',
                },
              });
            },
          );
          addTearDown(auth.dispose);
          await auth.currentUser;
          final generation = auth.authGeneration;

          final rejection = expectLater(
            auth.getMnemonicPlainText('wrong-password'),
            throwsA(
              isA<AuthException>()
                  .having(
                    (error) => error.type,
                    'type',
                    AuthExceptionType.incorrectPassword,
                  )
                  .having((error) => error.details, 'details', isEmpty)
                  .having(
                    (error) => error.toString(),
                    'redacted error',
                    isNot(contains(secretCanary)),
                  ),
            ),
          );
          await requestStarted.future;
          switch (kind) {
            case 'typed':
              response.completeError(
                const MnemonicRpcErrorInvalidPasswordException(secretCanary),
              );
            case 'json-rpc':
              response.complete(
                JsonRpcErrorResponse(
                  code: null,
                  error: 'InvalidPassword',
                  message: secretCanary,
                ),
              );
            default:
              response.complete({
                'mmrpc': '2.0',
                'result': {
                  'details': {
                    'error_type': 'InvalidPassword',
                    'error': secretCanary,
                  },
                },
              });
          }
          await rejection;

          expect(auth.authGeneration, generation);
          expect(auth.isAuthTransitionInProgress, isFalse);
          expect(await auth.currentUser, isNotNull);
          final mnemonic = await auth.getMnemonicPlainText('correct-password');
          expect(mnemonic.plaintextMnemonic, endsWith('about'));
        },
      );
    }

    test('keeps a KDF outage retryable and secret-free', () async {
      final auth = _createPublicAuth(
        mnemonicResponseHandler: () =>
            Future.error(ClientException(secretCanary)),
      );
      addTearDown(auth.dispose);

      await expectLater(
        auth.getMnemonicPlainText('synthetic-password'),
        throwsA(
          isA<AuthException>()
              .having(
                (error) => error.type,
                'type',
                AuthExceptionType.apiConnectionError,
              )
              .having((error) => error.details, 'details', isEmpty)
              .having(
                (error) => error.toString(),
                'redacted error',
                isNot(contains(secretCanary)),
              ),
        ),
      );
    });

    test('keeps other delayed failures generic and secret-free', () async {
      final auth = _createPublicAuth(
        mnemonicResponseHandler: () => Future.error(StateError(secretCanary)),
      );
      addTearDown(auth.dispose);

      await expectLater(
        auth.getMnemonicPlainText('synthetic-password'),
        throwsA(
          isA<AuthException>()
              .having(
                (error) => error.type,
                'type',
                AuthExceptionType.generalAuthError,
              )
              .having((error) => error.details, 'details', isEmpty)
              .having(
                (error) => error.toString(),
                'redacted error',
                isNot(contains(secretCanary)),
              ),
        ),
      );
    });
  });

  group('reviewed active-wallet deletion', () {
    late KdfAuthService service;
    late _FakeKdfOperations operations;
    late AuthSessionContext session;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({
        'user_test-wallet': jsonEncode(_verifiedTestUser().toJson()),
      });
      service = _createService(
        onOperationsCreated: (value) => operations = value,
      );
      addTearDown(() async {
        operations
          ..beforeStop = null
          ..beforeStart = null;
        await service.dispose();
      });
      await service.getUsers();
      session = await service.captureSessionContext();
      operations.onStart = (params) {
        operations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet'],
            'activated_wallet': params['wallet_name'],
          },
        };
      };
    });

    Future<void> remove({
      Future<void> Function(KdfUser)? review,
      Future<void> Function()? cleanup,
    }) => service.deleteWallet(
      walletName: 'test-wallet',
      password: 'test-only-password',
      allowActiveWallet: true,
      beforeDelete: review ?? (_) async {},
      afterDelete: cleanup,
    );

    test(
      'reviews and proves password before stop; cleanup precedes sign-out',
      () async {
        final events = <KdfUser?>[];
        final subscription = service.authStateChanges.listen(events.add);
        addTearDown(subscription.cancel);
        var reviewed = false;
        operations.beforeStop = () async {
          expect(reviewed, isTrue);
          expect(
            operations.requests.where((r) => r['method'] == 'get_mnemonic'),
            hasLength(1),
          );
          expect(service.isSessionContextCurrent(session), isFalse);
          expect(service.isAuthTransitionInProgress, isTrue);
        };
        operations.responseHandlersByMethod['delete_wallet'] = () async {
          expect(operations.stopCount, 1);
          expect(operations.starts, hasLength(1));
          expect(operations.starts.single['wallet_name'], isNull);
          expect(operations.starts.single['wallet_password'], isNull);
          expect(operations.starts.single['passphrase'], isNull);
          return {'mmrpc': '2.0', 'result': null};
        };
        await remove(
          review: (target) async {
            reviewed = true;
            expect(target.walletId, session.walletId);
          },
          cleanup: () async {
            expect(await SecureLocalStorage().getUser('test-wallet'), isNull);
            // An ordinary observer during cleanup must not discard its grant.
            expect(await service.getActiveUser(), isNull);
            await Future<void>.delayed(Duration.zero);
            expect(events, isEmpty);
            expect(service.isAuthTransitionInProgress, isTrue);
          },
        );
        await Future<void>.delayed(Duration.zero);
        expect(events, [null]);
        expect(service.isAuthTransitionInProgress, isFalse);
      },
    );

    test('changed review never stops or deletes the active wallet', () async {
      final rejection = StateError('review changed');
      await expectLater(
        remove(review: (_) async => throw rejection),
        throwsA(same(rejection)),
      );
      expect(operations.stopCount, 0);
      expect(
        operations.requests.where((r) => r['method'] == 'delete_wallet'),
        isEmpty,
      );
      expect(service.isSessionContextCurrent(session), isTrue);
    });

    test('wrong password preserves the active session and wallet', () async {
      operations.responsesByMethod['get_mnemonic'] = {
        'mmrpc': '2.0',
        'error': 'invalid password',
        'error_type': 'InvalidPassword',
      };
      await expectLater(
        remove(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.type,
            'type',
            AuthExceptionType.incorrectPassword,
          ),
        ),
      );
      expect(operations.stopCount, 0);
      expect(service.isSessionContextCurrent(session), isTrue);
      expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
    });

    test(
      'session invalidated while password proof is pending cannot stop',
      () async {
        operations.responseHandlersByMethod['get_mnemonic'] = () async {
          service.invalidateAuthSession();
          return operations.responsesByMethod['get_mnemonic']!;
        };
        await expectLater(
          remove(),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(operations.stopCount, 0);
        expect(
          operations.requests.where((r) => r['method'] == 'delete_wallet'),
          isEmpty,
        );
      },
    );

    test('replacement entry during password proof cannot stop', () async {
      operations.responseHandlersByMethod['get_mnemonic'] = () async {
        final user = (await SecureLocalStorage().getUser('test-wallet'))!;
        await SecureLocalStorage().saveUser(
          user.copyWith(
            metadata: {
              ...user.metadata,
              walletEntryIdMetadataKey: 'replacement-entry',
            },
          ),
        );
        return operations.responsesByMethod['get_mnemonic']!;
      };
      await expectLater(remove(), throwsA(isA<AuthSessionChangedException>()));
      expect(operations.stopCount, 0);
    });

    for (final phase in ['stop', 'start']) {
      test(
        'failed $phase preserves wallet and publishes revoked session',
        () async {
          final events = <KdfUser?>[];
          final subscription = service.authStateChanges.listen(events.add);
          addTearDown(subscription.cancel);
          Future<void> fail() async =>
              throw StateError('synthetic lifecycle failure');
          if (phase == 'stop') operations.beforeStop = fail;
          if (phase == 'start') operations.beforeStart = fail;
          await expectLater(remove(), throwsA(isA<Object>()));
          await Future<void>.delayed(Duration.zero);
          expect(events, [null]);
          expect(service.isSessionContextCurrent(session), isFalse);
          expect(service.isAuthTransitionInProgress, isFalse);
          expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
          expect(
            operations.requests.where((r) => r['method'] == 'delete_wallet'),
            isEmpty,
          );
        },
      );

      test('competing auth transition during $phase blocks deletion', () async {
        Future<void> supersede() async => service.invalidateAuthSession();
        if (phase == 'stop') operations.beforeStop = supersede;
        if (phase == 'start') operations.beforeStart = supersede;
        await expectLater(
          remove(),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
        expect(
          operations.requests.where((r) => r['method'] == 'delete_wallet'),
          isEmpty,
        );
      });
    }

    test(
      'read-only startup unexpectedly activating a wallet blocks deletion',
      () async {
        operations.onStart = (_) {};
        await expectLater(
          remove(),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
        expect(
          operations.requests.where((r) => r['method'] == 'delete_wallet'),
          isEmpty,
        );
      },
    );

    test(
      'app lock during fresh proof rejects before stopping the engine',
      () async {
        var authorized = true;
        operations.responseHandlersByMethod['get_mnemonic'] = () async {
          authorized = false;
          return operations.responsesByMethod['get_mnemonic']!;
        };
        await expectLater(
          RpcDispatchGuard.run(
            () {
              if (!authorized) throw StateError('app locked');
            },
            remove,
            methods: const {'delete_wallet'},
          ),
          throwsA(isA<RpcDispatchRejected>()),
        );
        expect(operations.stopCount, 0);
        expect(service.isSessionContextCurrent(session), isTrue);
        expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
      },
    );

    test(
      'app lock while existing dispatch drains prevents the actual stop',
      () async {
        final dispatched = Completer<void>();
        final releaseDispatch = Completer<void>();
        final pendingDispatch = service.runWithSession(session, () {
          dispatched.complete();
          return releaseDispatch.future;
        });
        await dispatched.future;
        final transitionStarted = Completer<void>();
        final subscription = service.authGenerationChanges.listen((_) {
          if (service.isAuthTransitionInProgress &&
              !transitionStarted.isCompleted) {
            transitionStarted.complete();
          }
        });
        addTearDown(subscription.cancel);
        var authorized = true;
        final deletion = RpcDispatchGuard.run(
          () {
            if (!authorized) throw StateError('app locked');
          },
          remove,
          methods: const {'delete_wallet'},
        );
        final rejected = expectLater(
          deletion,
          throwsA(isA<RpcDispatchRejected>()),
        );
        await transitionStarted.future;
        authorized = false;
        releaseDispatch.complete();
        await pendingDispatch;
        await rejected;
        expect(operations.stopCount, 0);
        expect(
          operations.requests.where((r) => r['method'] == 'delete_wallet'),
          isEmpty,
        );
        expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
      },
    );

    test(
      'app lock after stop rejects destructive dispatch and preserves wallet',
      () async {
        var authorized = true;
        operations.beforeStart = () async => authorized = false;
        // The fake has no transport implementation, so invoke the same final
        // dispatch check as native/WASM/HTTP before recording this test RPC.
        operations.responseHandlersByMethod['delete_wallet'] = () async {
          RpcDispatchGuard.ensureCurrent('delete_wallet');
          return {'mmrpc': '2.0', 'result': null};
        };
        await expectLater(
          RpcDispatchGuard.run(
            () {
              if (!authorized) throw StateError('app locked');
            },
            remove,
            methods: const {'delete_wallet'},
          ),
          throwsA(isA<RpcDispatchRejected>()),
        );
        expect(operations.stopCount, 1);
        expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
        expect(service.isAuthTransitionInProgress, isFalse);
      },
    );

    test(
      'switch during review cannot bypass stale checks through inactive branch',
      () async {
        await expectLater(
          remove(
            review: (_) async {
              service.invalidateAuthSession();
              operations.responsesByMethod['get_wallet_names'] = {
                'mmrpc': '2.0',
                'result': {
                  'wallet_names': ['test-wallet'],
                  'activated_wallet': null,
                },
              };
            },
          ),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(operations.stopCount, 0);
        expect(
          operations.requests.where((r) => r['method'] == 'delete_wallet'),
          isEmpty,
        );
        expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
      },
    );

    test(
      'cleanup failure still ends the revoked session after committed deletion',
      () async {
        final events = <KdfUser?>[];
        final subscription = service.authStateChanges.listen(events.add);
        addTearDown(subscription.cancel);
        final failure = StateError('cleanup pending');
        await expectLater(
          remove(cleanup: () async => throw failure),
          throwsA(same(failure)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(events, [null]);
        expect(service.isAuthTransitionInProgress, isFalse);
        expect(await SecureLocalStorage().getUser('test-wallet'), isNull);
      },
    );

    test(
      'new authenticated user during cleanup is not overwritten by sign-out',
      () async {
        final other = _verifiedTestUser().copyWith(
          walletId: _verifiedTestUser().walletId.copyWith(name: 'other-wallet'),
        );
        await SecureLocalStorage().saveUser(other);
        final events = <KdfUser?>[];
        final subscription = service.authStateChanges.listen(events.add);
        addTearDown(subscription.cancel);
        await remove(
          cleanup: () async {
            operations.responsesByMethod['get_wallet_names'] = {
              'mmrpc': '2.0',
              'result': {
                'wallet_names': ['other-wallet'],
                'activated_wallet': 'other-wallet',
              },
            };
            await service.restoreSession(other);
          },
        );
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        expect(events.single?.walletId.name, 'other-wallet');
        expect(
          (await service.captureSessionContext()).walletId.name,
          'other-wallet',
        );
      },
    );

    test('committed engine deletion still runs cleanup '
        'after catalog write failure', () async {
      late _FakeKdfOperations failingOperations;
      final failingService = _createService(
        secureStorage: SecureLocalStorage.withStorage(
          const _DeleteFailingFlutterSecureStorage(),
        ),
        onOperationsCreated: (value) => failingOperations = value,
      );
      addTearDown(failingService.dispose);
      await failingService.getUsers();
      final oldSession = await failingService.captureSessionContext();
      failingOperations.onStart = (_) {
        failingOperations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet'],
            'activated_wallet': null,
          },
        };
      };
      failingOperations.responseHandlersByMethod['delete_wallet'] = () async {
        failingOperations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {'wallet_names': <String>[], 'activated_wallet': null},
        };
        return {'mmrpc': '2.0', 'result': null};
      };
      final events = <KdfUser?>[];
      final subscription = failingService.authStateChanges.listen(events.add);
      addTearDown(subscription.cancel);
      var cleaned = false;
      await expectLater(
        failingService.deleteWallet(
          walletName: 'test-wallet',
          password: 'test-only-password',
          allowActiveWallet: true,
          beforeDelete: (_) async {},
          afterDelete: () async {
            cleaned = true;
            expect(failingService.isSessionContextCurrent(oldSession), isFalse);
            await Future<void>.delayed(Duration.zero);
            expect(events, isEmpty);
          },
        ),
        throwsA(
          isA<WalletDeletionCommittedException>()
              .having(
                (e) => e.walletId,
                'removed identity',
                oldSession.walletId,
              )
              .having((e) => e.entryId, 'immutable entry', isA<String>())
              .having(
                (e) => e.toString(),
                'safe error',
                isNot(contains('SECRET_DELETE_CANARY')),
              ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isTrue);
      expect(events, [null]);
      expect(await failingService.getUsers(), isEmpty);
    });

    test(
      'metadata retry clears only the removed entry and matching reservation',
      () async {
        final stored = (await SecureLocalStorage().getUser('test-wallet'))!;
        final entryId = stored.metadata[walletEntryIdMetadataKey] as String;
        final committed = WalletDeletionCommittedException(
          walletId: stored.walletId,
          entryId: entryId,
        );
        await SecureLocalStorage().saveProvisioning('test-wallet', {
          'id': entryId,
        });
        operations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {'wallet_names': <String>[], 'activated_wallet': null},
        };
        expect(await service.retryWalletDeletionCleanup(committed), isTrue);
        expect(await SecureLocalStorage().getUser('test-wallet'), isNull);
        expect(
          await SecureLocalStorage().getProvisioning('test-wallet'),
          isNull,
        );
        expect(await service.retryWalletDeletionCleanup(committed), isTrue);
        expect(
          operations.requests.where((r) => r['method'] == 'delete_wallet'),
          isEmpty,
        );
        expect(operations.stopCount, 0);
      },
    );

    test('metadata retry preserves a live engine wallet', () async {
      final stored = (await SecureLocalStorage().getUser('test-wallet'))!;
      final committed = WalletDeletionCommittedException(
        walletId: stored.walletId,
        entryId: stored.metadata[walletEntryIdMetadataKey] as String,
      );
      expect(await service.retryWalletDeletionCleanup(committed), isFalse);
      expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
      expect(operations.stopCount, 0);
    });

    test(
      'metadata retry preserves same-name same-seed replacement entry',
      () async {
        final stored = (await SecureLocalStorage().getUser('test-wallet'))!;
        final committed = WalletDeletionCommittedException(
          walletId: stored.walletId,
          entryId: stored.metadata[walletEntryIdMetadataKey] as String,
        );
        await SecureLocalStorage().saveUser(
          stored.copyWith(
            metadata: {
              ...stored.metadata,
              walletEntryIdMetadataKey: 'replacement-entry',
            },
          ),
        );
        operations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {'wallet_names': <String>[], 'activated_wallet': null},
        };
        expect(await service.retryWalletDeletionCleanup(committed), isFalse);
        expect(
          (await SecureLocalStorage().getUser(
            'test-wallet',
          ))!.metadata[walletEntryIdMetadataKey],
          'replacement-entry',
        );
      },
    );

    test('metadata retry preserves a new provisioning reservation', () async {
      final stored = (await SecureLocalStorage().getUser('test-wallet'))!;
      final committed = WalletDeletionCommittedException(
        walletId: stored.walletId,
        entryId: stored.metadata[walletEntryIdMetadataKey] as String,
      );
      await SecureLocalStorage().deleteUser('test-wallet');
      await SecureLocalStorage().saveProvisioning('test-wallet', {
        'id': 'new-provisioning',
      });
      operations.responsesByMethod['get_wallet_names'] = {
        'mmrpc': '2.0',
        'result': {'wallet_names': <String>[], 'activated_wallet': null},
      };
      expect(await service.retryWalletDeletionCleanup(committed), isFalse);
      expect(
        (await SecureLocalStorage().getProvisioning('test-wallet'))!['id'],
        'new-provisioning',
      );
    });

    test('deleting an inactive target does not stop another wallet', () async {
      final other = _verifiedTestUser().copyWith(
        walletId: _verifiedTestUser().walletId.copyWith(name: 'other-wallet'),
      );
      await SecureLocalStorage().saveUser(other);
      operations.responsesByMethod['get_wallet_names'] = {
        'mmrpc': '2.0',
        'result': {
          'wallet_names': ['test-wallet', 'other-wallet'],
          'activated_wallet': 'other-wallet',
        },
      };
      await remove();
      expect(operations.stopCount, 0);
      expect(operations.starts, isEmpty);
      expect(await SecureLocalStorage().getUser('test-wallet'), isNull);
      expect(await SecureLocalStorage().getUser('other-wallet'), isNotNull);
    });
  });

  group('KdfAuthService.deleteWallet', () {
    test(
      'maps WalletNotFound GeneralErrorResponse to AuthException.notFound',
      () async {
        final service = _createService(
          deleteWalletResponse: {
            'mmrpc': '2.0',
            'result': {
              'details': {
                'error': 'Wallet not found',
                'error_type': 'WalletNotFound',
              },
            },
          },
        );
        addTearDown(service.dispose);

        await expectLater(
          () => service.deleteWallet(walletName: 'missing', password: 'secret'),
          throwsA(
            isA<AuthException>().having(
              (error) => error.type,
              'type',
              AuthExceptionType.walletNotFound,
            ),
          ),
        );
      },
    );

    test(
      'maps CannotDeleteActiveWallet GeneralErrorResponse to auth error',
      () async {
        final service = _createService(
          deleteWalletResponse: {
            'mmrpc': '2.0',
            'result': {
              'details': {
                'error': 'Cannot delete active wallet',
                'error_type': 'CannotDeleteActiveWallet',
              },
            },
          },
        );
        addTearDown(service.dispose);

        await expectLater(
          () => service.deleteWallet(walletName: 'active', password: 'secret'),
          throwsA(
            isA<AuthException>()
                .having(
                  (error) => error.type,
                  'type',
                  AuthExceptionType.generalAuthError,
                )
                .having(
                  (error) => error.message,
                  'message',
                  'Cannot delete active wallet',
                ),
          ),
        );
      },
    );
  });

  group('KdfAuthService.updatePassword', () {
    test('maps incorrect-password GeneralErrorResponse '
        'to AuthException.incorrectPassword', () async {
      final service = _createService(
        changeMnemonicPasswordResponse: {
          'mmrpc': '2.0',
          'result': {
            'details': {
              'error':
                  'Error decrypting mnemonic: HMAC error: MAC tag mismatch',
            },
          },
        },
      );
      addTearDown(service.dispose);

      await service.restoreSession(_testUser());

      await expectLater(
        () => service.updatePassword(
          currentPassword: 'wrong-password',
          newPassword: 'new-password',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.type,
            'type',
            AuthExceptionType.incorrectPassword,
          ),
        ),
      );
    });
  });

  group('KdfAuthService authenticated wallet identity', () {
    test('upgrades and persists a name-only active wallet', () async {
      final user = _testUser();
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'user_${user.walletId.name}': jsonEncode(user.toJson()),
      });
      final service = _createService();
      addTearDown(service.dispose);

      final activeUser = await service.getActiveUser();

      expect(activeUser?.walletId.pubkeyHash, _publicKeyHash);
      final persisted = await const FlutterSecureStorage().read(
        key: 'user_${user.walletId.name}',
      );
      expect(
        KdfUser.fromJson(
          (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
        ).walletId.pubkeyHash,
        _publicKeyHash,
      );
    });

    test('rejects a stored identity that disagrees with KDF', () async {
      final user = _testUser().copyWith(
        walletId: _testUser().walletId.copyWith(
          pubkeyHash: '1111111111111111111111111111111111111111',
        ),
      );
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'user_${user.walletId.name}': jsonEncode(user.toJson()),
      });
      final service = _createService();
      addTearDown(service.dispose);

      await expectLater(
        service.getActiveUser,
        throwsA(
          isA<AuthException>()
              .having(
                (error) => error.type,
                'type',
                AuthExceptionType.internalError,
              )
              .having(
                (error) => error.message,
                'message',
                contains('does not match'),
              ),
        ),
      );
      expect(await service.getActiveUser(), isNull);
    });

    test('rejects a malformed KDF wallet identity', () async {
      final user = _testUser();
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'user_${user.walletId.name}': jsonEncode(user.toJson()),
      });
      final service = _createService(publicKeyHash: 'not-an-h160');
      addTearDown(service.dispose);

      await expectLater(
        service.getActiveUser,
        throwsA(
          isA<AuthException>()
              .having(
                (error) => error.type,
                'type',
                AuthExceptionType.internalError,
              )
              .having((error) => error.message, 'message', contains('invalid')),
        ),
      );
      expect(await service.getActiveUser(), isNull);
    });

    test('rejects a malformed KDF wallet identity response shape', () async {
      final user = _testUser();
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'user_${user.walletId.name}': jsonEncode(user.toJson()),
      });
      final service = _createService(
        publicKeyHashResponse: {'mmrpc': '2.0', 'result': <String, dynamic>{}},
      );
      addTearDown(service.dispose);

      await expectLater(
        service.getActiveUser,
        throwsA(
          isA<AuthException>()
              .having(
                (error) => error.type,
                'type',
                AuthExceptionType.internalError,
              )
              .having(
                (error) => error.message,
                'message',
                contains('malformed'),
              ),
        ),
      );
      expect(await service.getActiveUser(), isNull);
    });

    test(
      'a transport failure does not stop KDF or sign the user out',
      () async {
        // getActiveUser() is read-shaped - isSignedIn() and several managers
        // call it, some on a poll. It used to clear authentication on ANY
        // throw, so one dropped loopback socket meant kdfStop() plus a forced
        // sign-out. Failing to *ask* is not evidence of a bad identity.
        final user = _testUser();
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${user.walletId.name}': jsonEncode(user.toJson()),
        });
        _FakeKdfOperations? captured;
        final service = _createService(
          walletNamesResponseHandler: () => Future<Map<String, dynamic>>.error(
            ClientException('Connection closed before full header'),
          ),
          onOperationsCreated: (operations) => captured = operations,
        );
        addTearDown(service.dispose);

        await expectLater(service.getActiveUser(), throwsA(isA<Exception>()));

        expect(
          captured?.stopCount,
          0,
          reason: 'a transport failure must not tear down the KDF runtime',
        );
        final stillStored = await const FlutterSecureStorage().read(
          key: 'user_${user.walletId.name}',
        );
        expect(stillStored, isNotNull);
      },
    );

    test(
      'keeps Standard access when the identity RPC is unavailable',
      () async {
        final user = _testUser();
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${user.walletId.name}': jsonEncode(user.toJson()),
        });
        final service = _createService(
          publicKeyHashResponse: {
            'mmrpc': '2.0',
            'error': 'get_public_key_hash is unavailable',
          },
        );
        addTearDown(service.dispose);

        final activeUser = await service.getActiveUser();

        expect(activeUser?.walletId.name, user.walletId.name);
        expect(activeUser?.walletId.pubkeyHash, isNull);
      },
    );

    test(
      'does not trust a stored identity while the identity RPC is unavailable',
      () async {
        final storedUser = _testUser().copyWith(
          walletId: WalletId.withPubkeyHash(
            _testUser().walletId.name,
            _testUser().walletId.authOptions,
            _publicKeyHash,
          ),
        );
        final publicKeyHashResponse = <String, dynamic>{
          'mmrpc': '2.0',
          'error': 'get_public_key_hash is unavailable',
        };
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${storedUser.walletId.name}': jsonEncode(storedUser.toJson()),
        });
        final service = _createService(
          publicKeyHashResponse: publicKeyHashResponse,
        );
        addTearDown(service.dispose);

        final unavailableUser = await service.getActiveUser();

        expect(unavailableUser?.walletId.name, storedUser.walletId.name);
        expect(unavailableUser?.walletId.pubkeyHash, isNull);
        final persistedWhileUnavailable = await const FlutterSecureStorage()
            .read(key: 'user_${storedUser.walletId.name}');
        expect(
          KdfUser.fromJson(
            (jsonDecode(persistedWhileUnavailable!) as Map)
                .cast<String, dynamic>(),
          ).walletId.pubkeyHash,
          _publicKeyHash,
        );

        publicKeyHashResponse
          ..clear()
          ..addAll(<String, dynamic>{
            'mmrpc': '2.0',
            'result': {'public_key_hash': _publicKeyHash},
          });

        expect(
          (await service.getActiveUser())?.walletId.pubkeyHash,
          _publicKeyHash,
        );
      },
    );

    test('keeps Standard access when identity persistence fails', () async {
      final user = _testUser();
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'user_${user.walletId.name}': jsonEncode(user.toJson()),
      });
      late _FakeKdfOperations operations;
      final service = _createService(
        secureStorage: SecureLocalStorage.withStorage(
          const _WriteFailingFlutterSecureStorage(),
        ),
        onOperationsCreated: (value) => operations = value,
      );
      addTearDown(service.dispose);

      final activeUser = await service.getActiveUser();

      expect(activeUser?.walletId.name, user.walletId.name);
      expect(activeUser?.walletId.pubkeyHash, isNull);
      expect(await operations.isRunning(), isTrue);
      expect(operations.stopCount, 0);
    });

    for (final writeKind in _MetadataWriteKind.values) {
      test('${writeKind.name} rejects degraded runtime identity without '
          'changing stored identity or metadata', () async {
        final storedUser = _verifiedTestUser();
        final storedJson = jsonEncode(storedUser.toJson());
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${storedUser.walletId.name}': storedJson,
        });
        late _FakeKdfOperations operations;
        final service = _createService(
          publicKeyHashResponse: {
            'mmrpc': '2.0',
            'error': 'get_public_key_hash is unavailable',
          },
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);

        expect((await service.getActiveUser())?.walletId.pubkeyHash, isNull);
        var transformed = false;
        await expectLater(
          _writeMetadata(
            service,
            writeKind,
            storedUser.walletId,
            onTransform: (_) => transformed = true,
          ),
          throwsA(isA<WalletChangedDisconnectException>()),
        );

        expect(transformed, isFalse);
        expect(operations.stopCount, 0);
        expect(await operations.isRunning(), isTrue);
        final runtimeUser = await service.getActiveUser();
        expect(runtimeUser?.walletId.pubkeyHash, isNull);
        expect(runtimeUser?.metadata, storedUser.metadata);
        expect(
          await const FlutterSecureStorage().read(
            key: 'user_${storedUser.walletId.name}',
          ),
          storedJson,
        );
      });

      test(
        '${writeKind.name} rejects name-only identity captured before '
        'same-name wallet replacement during an identity RPC outage',
        () async {
          final originalUser = _verifiedTestUser();
          FlutterSecureStorage.setMockInitialValues(<String, String>{
            'user_${originalUser.walletId.name}': jsonEncode(
              originalUser.toJson(),
            ),
          });
          late _FakeKdfOperations operations;
          final service = _createService(
            publicKeyHashResponse: {
              'mmrpc': '2.0',
              'error': 'get_public_key_hash is unavailable',
            },
            onOperationsCreated: (value) => operations = value,
          );
          addTearDown(service.dispose);

          // Capture the real degraded value callers receive, not an
          // artificially forged ID. Equality alone cannot distinguish it
          // from a replacement wallet with the same display name.
          final expectedWalletId = (await service.getActiveUser())!.walletId;
          expect(expectedWalletId.pubkeyHash, isNull);
          final replacementUser = originalUser.copyWith(
            walletId: originalUser.walletId.copyWith(
              pubkeyHash: _secondPublicKeyHash,
            ),
            metadata: const {'has_backup': false, 'replacement': true},
          );
          final replacementJson = jsonEncode(replacementUser.toJson());
          await const FlutterSecureStorage().write(
            key: 'user_${replacementUser.walletId.name}',
            value: replacementJson,
          );

          var transformed = false;
          await expectLater(
            _writeMetadata(
              service,
              writeKind,
              expectedWalletId,
              onTransform: (_) => transformed = true,
            ),
            throwsA(isA<WalletChangedDisconnectException>()),
          );

          expect(transformed, isFalse);
          expect(operations.stopCount, 0);
          expect(await operations.isRunning(), isTrue);
          expect(
            await const FlutterSecureStorage().read(
              key: 'user_${replacementUser.walletId.name}',
            ),
            replacementJson,
          );
          final runtimeUser = await service.getActiveUser();
          expect(runtimeUser?.walletId.name, replacementUser.walletId.name);
          expect(runtimeUser?.walletId.pubkeyHash, isNull);
          expect(runtimeUser?.metadata, replacementUser.metadata);
        },
      );

      final validWalletId = _verifiedTestUser().walletId;
      final invalidExpectedIdentities = <String, WalletId>{
        'name-only': _testUser().walletId,
        'empty hash': validWalletId.copyWith(pubkeyHash: ''),
        'whitespace hash': validWalletId.copyWith(pubkeyHash: ' \t '),
        'different hash': validWalletId.copyWith(
          pubkeyHash: _secondPublicKeyHash,
        ),
        'different authentication options': validWalletId.copyWith(
          authOptions: const AuthOptions(
            derivationMethod: DerivationMethod.iguana,
          ),
        ),
      };
      for (final entry in invalidExpectedIdentities.entries) {
        test('${writeKind.name} rejects ${entry.key} expected identity '
            'without signing out the verified active wallet', () async {
          final storedUser = _verifiedTestUser();
          final storedJson = jsonEncode(storedUser.toJson());
          FlutterSecureStorage.setMockInitialValues(<String, String>{
            'user_${storedUser.walletId.name}': storedJson,
          });
          late _FakeKdfOperations operations;
          final service = _createService(
            onOperationsCreated: (value) => operations = value,
          );
          addTearDown(service.dispose);
          var transformed = false;

          await expectLater(
            _writeMetadata(
              service,
              writeKind,
              entry.value,
              onTransform: (_) => transformed = true,
            ),
            throwsA(isA<WalletChangedDisconnectException>()),
          );

          expect(transformed, isFalse);
          expect(operations.stopCount, 0);
          expect(await operations.isRunning(), isTrue);
          expect(
            (await service.getActiveUser())?.walletId,
            storedUser.walletId,
          );
          expect(
            await const FlutterSecureStorage().read(
              key: 'user_${storedUser.walletId.name}',
            ),
            storedJson,
          );
        });
      }

      test('${writeKind.name} accepts matching verified identity', () async {
        final storedUser = _verifiedTestUser();
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${storedUser.walletId.name}': jsonEncode(storedUser.toJson()),
        });
        final service = _createService();
        addTearDown(service.dispose);
        final expectedWalletId = (await service.getActiveUser())!.walletId;

        await _writeMetadata(
          service,
          writeKind,
          expectedWalletId,
          onTransform: (current) => expect(current, isFalse),
        );

        final runtimeUser = await service.getActiveUser();
        expect(runtimeUser?.walletId, expectedWalletId);
        expect(runtimeUser?.metadata, {'has_backup': true});
        final persisted = await const FlutterSecureStorage().read(
          key: 'user_${storedUser.walletId.name}',
        );
        final persistedUser = KdfUser.fromJson(
          (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
        );
        expect(persistedUser.walletId, expectedWalletId);
        expect(persistedUser.metadata, {'has_backup': true});
      });
    }

    test(
      'scoped metadata rejects a confirmation after switching wallets',
      () async {
        final walletA = _testUser().copyWith(
          walletId: _testUser().walletId.copyWith(pubkeyHash: _publicKeyHash),
          metadata: const {'has_backup': false},
        );
        final walletB = walletA.copyWith(
          walletId: walletA.walletId.copyWith(
            name: 'other-wallet',
            pubkeyHash: _secondPublicKeyHash,
          ),
        );
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          for (final wallet in [walletA, walletB])
            'user_${wallet.walletId.name}': jsonEncode(wallet.toJson()),
        });
        var activeWallet = walletA;
        late _FakeKdfOperations operations;
        final service = _createService(
          walletNamesResponseHandler: () async => {
            'mmrpc': '2.0',
            'result': {
              'wallet_names': [walletA.walletId.name, walletB.walletId.name],
              'activated_wallet': activeWallet.walletId.name,
            },
          },
          publicKeyHashResponseHandler: () async => {
            'mmrpc': '2.0',
            'result': {'public_key_hash': activeWallet.walletId.pubkeyHash},
          },
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);

        final expectedWalletId = (await service.getActiveUser())!.walletId;
        activeWallet = walletB;
        var transformed = false;
        await expectLater(
          service.updateActiveUserMetadataKey('has_backup', (_) {
            transformed = true;
            return true;
          }, expectedWalletId: expectedWalletId),
          throwsA(isA<WalletChangedDisconnectException>()),
        );

        expect(transformed, isFalse);
        expect(operations.stopCount, 0);
        for (final wallet in [walletA, walletB]) {
          final persisted = await const FlutterSecureStorage().read(
            key: 'user_${wallet.walletId.name}',
          );
          expect(
            KdfUser.fromJson(
              (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
            ).metadata['has_backup'],
            isFalse,
          );
        }

        // A confirmation belonging to the active wallet still succeeds.
        await service.updateActiveUserMetadataKey(
          'has_backup',
          (_) => true,
          expectedWalletId: walletB.walletId,
        );
        expect((await service.getActiveUser())!.metadata['has_backup'], isTrue);
      },
    );

    test(
      'signOut cannot race a metadata write and resurrect its user',
      () async {
        final storedUser = _testUser().copyWith(
          walletId: WalletId.withPubkeyHash(
            _testUser().walletId.name,
            _testUser().walletId.authOptions,
            _publicKeyHash,
          ),
        );
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${storedUser.walletId.name}': jsonEncode(storedUser.toJson()),
        });
        final identityRequestStarted = Completer<void>();
        final identityResponse = Completer<Map<String, dynamic>>();
        final service = _createService(
          publicKeyHashResponseHandler: () {
            if (!identityRequestStarted.isCompleted) {
              identityRequestStarted.complete();
            }
            return identityResponse.future;
          },
        );
        addTearDown(service.dispose);

        final metadataWrite = service.setActiveUserMetadata({
          'seedBackupConfirmed': true,
        }, expectedWalletId: storedUser.walletId);
        await identityRequestStarted.future;

        var signOutCompleted = false;
        final signOut = service.signOut().then((_) {
          signOutCompleted = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(signOutCompleted, isFalse);

        identityResponse.complete({
          'mmrpc': '2.0',
          'result': {'public_key_hash': _publicKeyHash},
        });
        await metadataWrite;
        await signOut;

        expect(await service.getActiveUser(), isNull);
        final persisted = await const FlutterSecureStorage().read(
          key: 'user_${storedUser.walletId.name}',
        );
        expect(
          KdfUser.fromJson(
            (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
          ).metadata['seedBackupConfirmed'],
          isTrue,
        );
      },
    );

    test('identity cleanup remains serialized with signOut', () async {
      final storedUser = _testUser().copyWith(
        walletId: WalletId.withPubkeyHash(
          _testUser().walletId.name,
          _testUser().walletId.authOptions,
          _publicKeyHash,
        ),
      );
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'user_${storedUser.walletId.name}': jsonEncode(storedUser.toJson()),
      });
      final staleIdentityRequestStarted = Completer<void>();
      final staleIdentityResponse = Completer<Map<String, dynamic>>();
      var identityRequestCount = 0;
      late _FakeKdfOperations operations;
      final service = _createService(
        publicKeyHashResponseHandler: () {
          identityRequestCount++;
          if (identityRequestCount == 1) {
            return Future.value({
              'mmrpc': '2.0',
              'error': 'get_public_key_hash is unavailable',
            });
          }
          staleIdentityRequestStarted.complete();
          return staleIdentityResponse.future;
        },
        onOperationsCreated: (value) => operations = value,
      );
      addTearDown(service.dispose);

      expect((await service.getActiveUser())?.walletId.pubkeyHash, isNull);

      final staleRead = service.getActiveUser();
      await staleIdentityRequestStarted.future;
      var signOutCompleted = false;
      final signOut = service.signOut().then((_) {
        signOutCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(signOutCompleted, isFalse);

      staleIdentityResponse.complete({
        'mmrpc': '2.0',
        'result': <String, dynamic>{},
      });

      await expectLater(staleRead, throwsA(isA<AuthException>()));
      await signOut;

      expect(operations.stopCount, 2);
      expect(await service.getActiveUser(), isNull);
    });

    test(
      'queued signOut cannot deadlock registration wallet discovery',
      () async {
        final walletNamesRequestStarted = Completer<void>();
        final walletNamesResponse = Completer<Map<String, dynamic>>();
        late _FakeKdfOperations operations;
        final service = _createService(
          onOperationsCreated: (value) => operations = value,
        );
        operations.responseHandlersByMethod['get_wallet_names'] = () {
          walletNamesRequestStarted.complete();
          return walletNamesResponse.future;
        };
        addTearDown(service.dispose);

        final registration = service.register(
          walletName: 'test-wallet',
          password: 'correct horse battery staple',
        );
        await walletNamesRequestStarted.future;

        var signOutCompleted = false;
        final signOut = service.signOut().then((_) {
          signOutCompleted = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(signOutCompleted, isFalse);

        walletNamesResponse.complete({
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet'],
            'activated_wallet': 'test-wallet',
          },
        });

        await expectLater(
          registration.timeout(const Duration(seconds: 2)),
          throwsA(
            isA<AuthException>().having(
              (error) => error.message,
              'message',
              'Wallet already exists',
            ),
          ),
        );
        await signOut.timeout(const Duration(seconds: 2));
        expect(signOutCompleted, isTrue);
      },
    );

    test(
      'authenticated operation clears an invalid identity without deadlock',
      () async {
        final storedUser = _testUser();
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${storedUser.walletId.name}': jsonEncode(storedUser.toJson()),
        });
        final service = _createService(
          publicKeyHashResponse: {
            'mmrpc': '2.0',
            'result': <String, dynamic>{},
          },
        );
        addTearDown(service.dispose);

        await expectLater(
          service
              .getMnemonic(encrypted: true, walletPassword: null)
              .timeout(const Duration(seconds: 2)),
          throwsA(isA<AuthException>()),
        );
        expect(await service.getActiveUser(), isNull);
      },
    );

    test(
      'preserves an equivalent uppercase identity for journal compatibility',
      () async {
        final uppercaseIdentity = _publicKeyHash.toUpperCase();
        final user = _testUser().copyWith(
          walletId: _testUser().walletId.copyWith(
            pubkeyHash: uppercaseIdentity,
          ),
        );
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${user.walletId.name}': jsonEncode(user.toJson()),
        });
        final service = _createService();
        addTearDown(service.dispose);

        final activeUser = await service.getActiveUser();

        expect(activeUser?.walletId.pubkeyHash, uppercaseIdentity);
        final persisted = await const FlutterSecureStorage().read(
          key: 'user_${user.walletId.name}',
        );
        expect(
          KdfUser.fromJson(
            (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
          ).walletId.pubkeyHash,
          uppercaseIdentity,
        );
      },
    );

    test(
      'does not reuse a cached identity after KDF switches wallets',
      () async {
        final firstUser = _testUser();
        final secondUser = KdfUser(
          walletId: WalletId.fromName(
            'second-wallet',
            const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          ),
          isBip39Seed: true,
        );
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${firstUser.walletId.name}': jsonEncode(firstUser.toJson()),
          'user_${secondUser.walletId.name}': jsonEncode(secondUser.toJson()),
        });
        late _FakeKdfOperations operations;
        final service = _createService(
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);

        expect((await service.getActiveUser())?.walletId.name, 'test-wallet');

        operations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet', 'second-wallet'],
            'activated_wallet': 'second-wallet',
          },
        };
        operations.responsesByMethod['get_public_key_hash'] = {
          'mmrpc': '2.0',
          'result': {'public_key_hash': _secondPublicKeyHash},
        };

        final activeUser = await service.getActiveUser();
        expect(activeUser?.walletId.name, 'second-wallet');
        expect(activeUser?.walletId.pubkeyHash, _secondPublicKeyHash);
      },
    );

    test(
      'does not reuse a cached identity after KDF enters no-auth mode',
      () async {
        final user = _testUser();
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${user.walletId.name}': jsonEncode(user.toJson()),
        });
        late _FakeKdfOperations operations;
        final service = _createService(
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);

        expect(
          (await service.getActiveUser())?.walletId.pubkeyHash,
          _publicKeyHash,
        );

        operations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet'],
            'activated_wallet': null,
          },
        };

        await expectLater(
          () => service.signIn(
            walletName: user.walletId.name,
            password: 'correct horse battery staple',
            options: user.walletId.authOptions,
          ),
          throwsA(anything),
        );
        expect(await operations.isRunning(), isFalse);
        expect(await service.getActiveUser(), isNull);
      },
    );

    test(
      'restoreSession emits the KDF-authenticated wallet identity',
      () async {
        final user = _testUser();
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${user.walletId.name}': jsonEncode(user.toJson()),
        });
        final service = _createService();
        addTearDown(service.dispose);

        await service.restoreSession(user);

        expect(
          (await service.getActiveUser())?.walletId.pubkeyHash,
          _publicKeyHash,
        );
      },
    );

    test(
      'registration identity validation failure stops KDF and stores no user',
      () async {
        final service = _createService(publicKeyHash: 'not-an-h160');
        addTearDown(service.dispose);

        await expectLater(
          () => service.register(
            walletName: 'new-wallet',
            password: 'correct horse battery staple',
            mnemonic: Mnemonic.plaintext(
              'abandon abandon abandon abandon abandon abandon abandon '
              'abandon abandon abandon abandon about',
            ),
          ),
          throwsA(isA<AuthException>()),
        );

        expect(await service.getActiveUser(), isNull);
        expect(
          await const FlutterSecureStorage().read(key: 'user_new-wallet'),
          isNull,
        );
      },
    );
  });
  group('runtime session ownership', () {
    late KdfAuthService service;
    late _FakeKdfOperations operations;
    setUp(() {
      final user = _verifiedTestUser();
      FlutterSecureStorage.setMockInitialValues({
        'user_${user.walletId.name}': jsonEncode(user.toJson()),
      });
      service = _createService(
        onOperationsCreated: (value) => operations = value,
      );
      addTearDown(service.dispose);
    });

    test(
      'metadata refresh and identity outage preserve runtime ownership',
      () async {
        final context = await service.captureSessionContext();
        final strictGeneration = service.authGeneration;
        await service.updateMetadataForSession(context, {'has_backup': true});
        expect(service.isSessionContextCurrent(context), isTrue);
        expect(service.authGeneration, greaterThan(strictGeneration));
        operations.responsesByMethod['get_public_key_hash'] = {
          'mmrpc': '2.0',
          'error': 'identity unavailable',
          'error_type': 'Internal',
        };
        final degraded = await service.getActiveUser();
        expect(degraded!.walletId.pubkeyHash, isNull);
        expect(service.isSessionContextCurrent(context), isTrue);
        await expectLater(
          service.updateMetadataForSession(context, {'has_backup': false}),
          throwsA(isA<AuthIdentityUnavailableException>()),
        );
        expect(service.isSessionContextCurrent(context), isTrue);
        expect(
          (await SecureLocalStorage().getUser(
            'test-wallet',
          ))!.metadata['has_backup'],
          isTrue,
        );
        operations.responsesByMethod['get_public_key_hash'] = {
          'mmrpc': '2.0',
          'result': {'public_key_hash': _publicKeyHash},
        };
        final saved = await service.updateMetadataForSession(context, {
          'has_backup': false,
        });
        expect(saved.metadata['has_backup'], isFalse);
        expect(service.isSessionContextCurrent(context), isTrue);
      },
    );

    test('a name-only context survives fresh identity enrichment', () async {
      operations.responsesByMethod['get_public_key_hash'] = {
        'mmrpc': '2.0',
        'error': 'identity unavailable',
        'error_type': 'Internal',
      };
      final context = await service.captureSessionContext();
      expect(context.walletId.pubkeyHash, isNull);
      operations.responsesByMethod['get_public_key_hash'] = {
        'mmrpc': '2.0',
        'result': {'public_key_hash': _publicKeyHash},
      };
      await service.updateMetadataForSession(context, {'has_backup': true});
      final enriched = await service.captureSessionContext();
      expect(enriched, context);
      expect(enriched.walletId.pubkeyHash, _publicKeyHash);
    });

    test(
      'same-wallet reauthentication invalidates the previous context',
      () async {
        final context = await service.captureSessionContext();
        await service.signIn(
          walletName: 'test-wallet',
          password: 'pw',
          options: context.walletId.authOptions,
        );
        expect(service.isSessionContextCurrent(context), isFalse);
        await expectLater(
          service.updateMetadataForSession(context, {'has_backup': true}),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(await service.captureSessionContext(), isNot(context));
      },
    );

    test(
      'wallet replacement inside the write lock rejects the prior context',
      () async {
        final context = await service.captureSessionContext();
        final replacement = _verifiedTestUser().copyWith(
          walletId: WalletId.withPubkeyHash(
            'replacement',
            context.walletId.authOptions,
            _secondPublicKeyHash,
          ),
        );
        await SecureLocalStorage().saveUser(replacement);
        operations.responsesByMethod['get_wallet_names'] = {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet', 'replacement'],
            'activated_wallet': 'replacement',
          },
        };
        operations.responsesByMethod['get_public_key_hash'] = {
          'mmrpc': '2.0',
          'result': {'public_key_hash': _secondPublicKeyHash},
        };
        await expectLater(
          service.updateMetadataForSession(context, {'has_backup': true}),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(
          (await SecureLocalStorage().getUser(
            'replacement',
          ))!.metadata['has_backup'],
          isFalse,
        );
      },
    );

    test(
      'metadata patch preserves unrelated values and protects entry identity',
      () async {
        final catalogUser = (await service.getUsers()).single;
        final entryId = catalogUser.metadata[walletEntryIdMetadataKey];
        expect(entryId, isA<String>());
        final context = await service.captureSessionContext();
        await service.updateMetadataForSession(context, {
          'activated_coins': ['BTC'],
        });
        final saved = await service.updateMetadataForSession(context, {
          'has_backup': true,
        });
        expect(saved.metadata['activated_coins'], ['BTC']);
        expect(saved.metadata[walletEntryIdMetadataKey], entryId);
        await expectLater(
          service.updateMetadataForSession(context, {
            walletEntryIdMetadataKey: 'spoof',
          }),
          throwsArgumentError,
        );
        expect(
          (await service.getUsers()).single.metadata[walletEntryIdMetadataKey],
          entryId,
        );
      },
    );
  });

  group('shared wallet record transactions', () {
    test(
      'catalog identity and concurrent instance metadata patches are preserved',
      () async {
        final user = _verifiedTestUser();
        FlutterSecureStorage.setMockInitialValues({
          'user_test-wallet': jsonEncode(user.toJson()),
        });
        final saving = Completer<void>();
        final allowSave = Completer<void>();
        final storage = SecureLocalStorage.withStorage(
          _ObservedFlutterSecureStorage(
            beforeWrite: (key, value) async {
              if (key == 'user_test-wallet' && !saving.isCompleted) {
                saving.complete();
                await allowSave.future;
              }
            },
          ),
        );
        final first = _createService(secureStorage: storage);
        final second = _createService();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        final firstContext = await first.captureSessionContext();
        final secondContext = await second.captureSessionContext();
        final backup = first.updateMetadataForSession(firstContext, {
          'has_backup': true,
        });
        await saving.future;
        final catalog = second.getUsers();
        final otherPatch = second.updateMetadataForSession(secondContext, {
          'label': 'saved concurrently',
        });
        allowSave.complete();
        await backup;
        await catalog;
        await otherPatch;
        final saved = (await SecureLocalStorage().getUser('test-wallet'))!;
        expect(saved.metadata['has_backup'], isTrue);
        expect(saved.metadata['label'], 'saved concurrently');
        expect(saved.metadata[walletEntryIdMetadataKey], isA<String>());
      },
    );

    test(
      'delayed identity enrichment keeps newer metadata and catalog identity',
      () async {
        final user = _testUser();
        FlutterSecureStorage.setMockInitialValues({
          'user_test-wallet': jsonEncode(user.toJson()),
        });
        final verifying = Completer<void>();
        final allowProof = Completer<void>();
        final first = _createService(
          publicKeyHashResponseHandler: () async {
            verifying.complete();
            await allowProof.future;
            return {
              'mmrpc': '2.0',
              'result': {'public_key_hash': _publicKeyHash},
            };
          },
        );
        final second = _createService();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        final resolving = first.getActiveUser();
        await verifying.future;
        final catalog = await second.getUsers();
        final context = await second.captureSessionContext();
        await second.updateMetadataForSession(context, {'has_backup': true});
        allowProof.complete();
        final resolved = (await resolving)!;
        expect(resolved.metadata['has_backup'], isTrue);
        expect(
          resolved.metadata[walletEntryIdMetadataKey],
          catalog.single.metadata[walletEntryIdMetadataKey],
        );
        expect(resolved.walletId.pubkeyHash, _publicKeyHash);
      },
    );

    test(
      'same-name same-seed replacement invalidates the runtime context',
      () async {
        final user = _verifiedTestUser().copyWith(
          metadata: {walletEntryIdMetadataKey: 'old-entry'},
        );
        FlutterSecureStorage.setMockInitialValues({
          'user_test-wallet': jsonEncode(user.toJson()),
        });
        final service = _createService();
        addTearDown(service.dispose);
        final context = await service.captureSessionContext();
        await SecureLocalStorage().saveUser(
          user.copyWith(metadata: {walletEntryIdMetadataKey: 'new-entry'}),
        );
        await expectLater(
          service.updateMetadataForSession(context, {'has_backup': true}),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(
          (await SecureLocalStorage().getUser(
            'test-wallet',
          ))!.metadata['has_backup'],
          isNull,
        );
      },
    );
  });

  test('deletion keeps catalog ownership through cache cleanup', () async {
    final cleanupStarted = Completer<void>();
    final cleanupFinished = Completer<void>();
    final catalogRead = Completer<void>();
    final deleting = _createService();
    final creating = _createService(
      walletNamesResponseHandler: () async {
        catalogRead.complete();
        return {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet'],
            'activated_wallet': null,
          },
        };
      },
    );
    addTearDown(deleting.dispose);
    addTearDown(creating.dispose);
    final deletion = deleting.deleteWallet(
      walletName: 'test-wallet',
      password: 'pw',
      afterDelete: () async {
        cleanupStarted.complete();
        await cleanupFinished.future;
      },
    );
    await cleanupStarted.future;
    final registration = creating.register(
      walletName: 'test-wallet',
      password: 'pw',
    );
    final rejected = expectLater(
      registration,
      throwsA(
        isA<AuthException>().having(
          (error) => error.type,
          'type',
          AuthExceptionType.walletAlreadyExists,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(catalogRead.isCompleted, isFalse);
    cleanupFinished.complete();
    await deletion;
    await rejected;
    expect(catalogRead.isCompleted, isTrue);
  });

  test(
    'deletion permits validate the fresh target and cannot be reused',
    () async {
      final auth = _createPublicAuth();
      addTearDown(auth.dispose);
      final owner = Object();
      auth.requireWalletDeletionReview(owner);
      await expectLater(
        auth.deleteWallet(walletName: 'test-wallet', password: 'pw'),
        throwsA(isA<WalletDeletionReviewRequiredException>()),
      );
      final rejection = StateError('review changed');
      final permit = auth.authorizeWalletDeletion(owner, (target) async {
        expect(target.metadata['fresh'], isTrue);
        expect(target.metadata[walletEntryIdMetadataKey], isA<String>());
        throw rejection;
      });
      await SecureLocalStorage().saveUser(
        _testUser().copyWith(metadata: {'fresh': true}),
      );
      await expectLater(
        auth.deleteWallet(
          walletName: 'test-wallet',
          password: 'pw',
          permit: permit,
        ),
        throwsA(same(rejection)),
      );
      await expectLater(
        auth.deleteWallet(
          walletName: 'test-wallet',
          password: 'pw',
          permit: permit,
        ),
        throwsA(isA<WalletDeletionReviewRequiredException>()),
      );
      expect(await SecureLocalStorage().getUser('test-wallet'), isNotNull);
    },
  );

  group('atomic wallet registration', () {
    const provisioningId = 'provisioning-test-entry-0001';

    test(
      'managed creation persists identity and retries without a new seed',
      () async {
        late _FakeKdfOperations operations;
        final names = <String>[];
        String? active;
        final service = _createService(
          walletNamesResponseHandler: () async => {
            'mmrpc': '2.0',
            'result': {'wallet_names': names, 'activated_wallet': active},
          },
          onOperationsCreated: (value) {
            operations = value;
            value.onStart = (params) {
              active = params['wallet_name'] as String?;
              if (active != null && params['allow_registrations'] == true) {
                names.add(active!);
              }
            };
          },
        );
        addTearDown(service.dispose);
        final first = await service.register(
          walletName: 'new-wallet',
          password: 'test-password',
          provisioningId: provisioningId,
          initialMetadata: {'has_backup': false},
        );
        expect(first.metadata[walletEntryIdMetadataKey], provisioningId);
        expect(
          await SecureLocalStorage().getProvisioning('new-wallet'),
          isNull,
        );
        final second = await service.register(
          walletName: 'new-wallet',
          password: 'test-password',
          provisioningId: provisioningId,
          initialMetadata: {'has_backup': true},
        );
        expect(second.walletId, first.walletId);
        expect(second.metadata['has_backup'], isFalse);
        expect(names, ['new-wallet']);
        expect(
          operations.starts.where((p) => p['allow_registrations'] == true),
          hasLength(1),
        );
        expect(operations.starts.last['allow_registrations'], isFalse);
      },
    );

    test(
      'resumes engine wallet after initial user record write failed',
      () async {
        var failUserSave = true;
        final storage = SecureLocalStorage.withStorage(
          _ObservedFlutterSecureStorage(
            beforeWrite: (key, _) async {
              if (key == 'user_new-wallet' && failUserSave) {
                failUserSave = false;
                throw StateError('simulated storage interruption');
              }
            },
          ),
        );
        final names = <String>[];
        String? active;
        late _FakeKdfOperations operations;
        final service = _createService(
          secureStorage: storage,
          walletNamesResponseHandler: () async => {
            'mmrpc': '2.0',
            'result': {'wallet_names': names, 'activated_wallet': active},
          },
          onOperationsCreated: (value) {
            operations = value;
            value.onStart = (params) {
              active = params['wallet_name'] as String?;
              if (active != null && params['allow_registrations'] == true) {
                names.add(active!);
              }
            };
          },
        );
        addTearDown(service.dispose);
        await expectLater(
          service.register(
            walletName: 'new-wallet',
            password: 'test-password',
            provisioningId: provisioningId,
          ),
          throwsA(isA<StateError>()),
        );
        expect(names, ['new-wallet']);
        expect(
          (await storage.getProvisioning('new-wallet'))?['id'],
          provisioningId,
        );
        // The normal startup wallet list may repair the incomplete catalog
        // before the creation coordinator resumes. Preserve its reserved ID.
        final discovered = await service.getUsers();
        expect(
          discovered.single.metadata[walletEntryIdMetadataKey],
          provisioningId,
        );
        final resumed = await service.register(
          walletName: 'new-wallet',
          password: 'test-password',
          provisioningId: provisioningId,
        );
        expect(resumed.metadata[walletEntryIdMetadataKey], provisioningId);
        expect(
          operations.starts.where((p) => p['allow_registrations'] == true),
          hasLength(1),
        );
        expect(await storage.getProvisioning('new-wallet'), isNull);
      },
    );

    test(
      'reservation persistence failure never starts wallet creation',
      () async {
        late _FakeKdfOperations operations;
        final service = _createService(
          secureStorage: SecureLocalStorage.withStorage(
            _ObservedFlutterSecureStorage(
              beforeWrite: (key, _) async {
                if (key.startsWith('wallet_provisioning_')) {
                  throw StateError('simulated reservation failure');
                }
              },
            ),
          ),
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);
        await expectLater(
          service.register(
            walletName: 'new-wallet',
            password: 'test-password',
            provisioningId: provisioningId,
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          operations.starts.where((p) => p['allow_registrations'] == true),
          isEmpty,
        );
      },
    );

    test(
      'another provisioning operation cannot take a reserved name',
      () async {
        await SecureLocalStorage().saveProvisioning('new-wallet', {
          'id': provisioningId,
          'options': _testUser().walletId.authOptions.toJson(),
          'initial_metadata': <String, dynamic>{},
        });
        late _FakeKdfOperations operations;
        final service = _createService(
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);
        for (final id in [null, 'other-provisioning-entry-0002']) {
          await expectLater(
            service.register(
              walletName: 'new-wallet',
              password: 'different-password',
              provisioningId: id,
            ),
            throwsA(
              isA<AuthException>()
                  .having(
                    (e) => e.type,
                    'type',
                    AuthExceptionType.walletAlreadyExists,
                  )
                  .having(
                    (e) => e.details?['canRetryWithDifferentName'],
                    'can choose another name before owning a reservation',
                    id != null,
                  ),
            ),
          );
        }
        expect(
          operations.starts.where((p) => p['allow_registrations'] == true),
          isEmpty,
        );
      },
    );

    test(
      'missing engine wallet with completed identity is never regenerated',
      () async {
        await SecureLocalStorage().saveUser(
          KdfUser(
            walletId: WalletId.withPubkeyHash(
              'new-wallet',
              _testUser().walletId.authOptions,
              _publicKeyHash,
            ),
            isBip39Seed: true,
            metadata: const {walletEntryIdMetadataKey: provisioningId},
          ),
        );
        late _FakeKdfOperations operations;
        final service = _createService(
          onOperationsCreated: (value) => operations = value,
        );
        addTearDown(service.dispose);
        await expectLater(
          service.register(
            walletName: 'new-wallet',
            password: 'test-password',
            provisioningId: provisioningId,
          ),
          throwsA(
            isA<AuthException>().having(
              (e) => e.details?['canRetryWithDifferentName'],
              'completed entry cannot choose another name',
              false,
            ),
          ),
        );
        expect(
          operations.starts.where((p) => p['allow_registrations'] == true),
          isEmpty,
        );
      },
    );

    test(
      'initial metadata is persisted before publishing the authenticated user',
      () async {
        final saving = Completer<void>();
        final allowSave = Completer<void>();
        final storage = SecureLocalStorage.withStorage(
          _ObservedFlutterSecureStorage(
            beforeWrite: (key, value) async {
              if (key == 'user_new-wallet' && !saving.isCompleted) {
                saving.complete();
                await allowSave.future;
              }
            },
          ),
        );
        final service = _createService(secureStorage: storage);
        addTearDown(service.dispose);
        final emitted = <KdfUser>[];
        final subscription = service.authStateChanges.listen((user) {
          if (user != null) emitted.add(user);
        });
        addTearDown(subscription.cancel);
        final created = service.register(
          walletName: 'new-wallet',
          password: 'correct horse battery staple',
          initialMetadata: {
            'has_backup': true,
            'type': 'hdwallet',
            'activated_coins': ['BTC'],
          },
        );
        await saving.future;
        expect(emitted, isEmpty);
        expect(await storage.getUser('new-wallet'), isNull);
        allowSave.complete();
        final user = await created;
        expect(user.metadata['has_backup'], isTrue);
        expect(user.metadata['activated_coins'], ['BTC']);
        expect(user.metadata[walletEntryIdMetadataKey], isA<String>());
        expect((await storage.getUser('new-wallet'))!.metadata, user.metadata);
        await Future<void>.delayed(Duration.zero);
        expect(emitted.single.metadata, user.metadata);
      },
    );

    test('concurrent service instances reject a colliding creation '
        'after the first save', () async {
      final saving = Completer<void>();
      final allowSave = Completer<void>();
      final names = <String>[];
      final storage = SecureLocalStorage.withStorage(
        _ObservedFlutterSecureStorage(
          beforeWrite: (key, value) async {
            if (key == 'user_new-wallet' && !saving.isCompleted) {
              saving.complete();
              await allowSave.future;
              names.add('new-wallet');
            }
          },
        ),
      );
      Future<Map<String, dynamic>> catalog() async => {
        'mmrpc': '2.0',
        'result': {'wallet_names': names.toList(), 'activated_wallet': null},
      };
      final first = _createService(
        secureStorage: storage,
        walletNamesResponseHandler: catalog,
      );
      final second = _createService(
        secureStorage: storage,
        walletNamesResponseHandler: catalog,
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final created = first.register(
        walletName: 'new-wallet',
        password: 'correct horse battery staple',
      );
      await saving.future;
      final collision = second.register(
        walletName: 'new-wallet',
        password: 'different correct password',
      );
      final rejected = expectLater(
        collision,
        throwsA(
          isA<AuthException>().having(
            (error) => error.type,
            'type',
            AuthExceptionType.walletAlreadyExists,
          ),
        ),
      );
      allowSave.complete();
      await created;
      await rejected;
      expect(names, ['new-wallet']);
    });
  });

  test(
    'commission and proxy survive creation, sign-out and sign-in restarts',
    () async {
      const url = 'https://swap.example.com/lifi';
      final commission = LifiIntegratorConfig(
        name: 'gleec-dex-staging',
        feeBps: 178,
        lifiFeeBps: 22,
      );
      late _FakeKdfOperations operations;
      final createdNames = <String>{};
      final service = _createService(
        lifiProxyUrl: url,
        lifiIntegrator: commission,
        onOperationsCreated: (created) {
          operations = created;
          created._isRunning = false;
          created.onStart = (params) {
            final name = params['wallet_name'] as String?;
            if (name != null && params['allow_registrations'] == true) {
              createdNames.add(name);
            }
            created.responsesByMethod['get_wallet_names'] = {
              'mmrpc': '2.0',
              'result': {
                'wallet_names': createdNames.toList(),
                'activated_wallet': params['wallet_name'],
              },
            };
          };
          created.responsesByMethod['get_wallet_names'] = {
            'mmrpc': '2.0',
            'result': {'wallet_names': <String>[], 'activated_wallet': null},
          };
        },
      );
      addTearDown(service.dispose);

      await service.register(
        walletName: 'new-wallet',
        password: 'correct horse battery staple',
      );

      expect(operations.starts.map((params) => params['wallet_name']), [
        null,
        'new-wallet',
      ]);
      expect(operations.starts.map((params) => params['lifi_proxy_url']), [
        url,
        url,
      ]);
      await service.signOut();
      await service.signIn(
        walletName: 'new-wallet',
        password: 'correct horse battery staple',
        options: _testUser().walletId.authOptions,
      );
      expect(operations.starts.length, greaterThan(2));
      expect(
        operations.starts.map((params) => params['lifi_integrator']),
        everyElement(commission.toJson()),
      );
      // KDF signs proxy requests with its P2P key on every restart.
      expect(
        operations.starts.map((params) => params['disable_p2p']),
        everyElement(isNot(isTrue)),
      );
    },
  );
}

const _publicKeyHash = '05aab5342166f8594baf17a7d9bef5d567443327';
const _secondPublicKeyHash = '1111111111111111111111111111111111111111';

KomodoDefiLocalAuth _createPublicAuth({
  Future<Map<String, dynamic>> Function()? publicKeyHashResponseHandler,
  Future<Map<String, dynamic>> Function()? mnemonicResponseHandler,
}) {
  final user = _testUser();
  FlutterSecureStorage.setMockInitialValues({
    'user_${user.walletId.name}': jsonEncode(user.toJson()),
  });
  final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
  final operations = _FakeKdfOperations(
    responsesByMethod: {
      'get_wallet_names': {
        'mmrpc': '2.0',
        'result': {
          'wallet_names': ['test-wallet'],
          'activated_wallet': 'test-wallet',
        },
      },
      'get_public_key_hash': {
        'mmrpc': '2.0',
        'result': {'public_key_hash': _publicKeyHash},
      },
      'stream::shutdown_signal::enable': {
        'mmrpc': '2.0',
        'result': {'streamer_id': 'test-stream'},
      },
    },
    responseHandlersByMethod: {
      if (publicKeyHashResponseHandler != null)
        'get_public_key_hash': publicKeyHashResponseHandler,
      if (mnemonicResponseHandler != null)
        'get_mnemonic': mnemonicResponseHandler,
    },
  );
  return KomodoDefiLocalAuth(
    kdf: KomodoDefiFramework.createWithOperations(
      hostConfig: hostConfig,
      kdfOperations: operations,
    ),
    hostConfig: hostConfig,
  );
}

KdfAuthService _createService({
  Map<String, dynamic>? deleteWalletResponse,
  Map<String, dynamic>? changeMnemonicPasswordResponse,
  String publicKeyHash = _publicKeyHash,
  Map<String, dynamic>? publicKeyHashResponse,
  Future<Map<String, dynamic>> Function()? publicKeyHashResponseHandler,
  Future<Map<String, dynamic>> Function()? walletNamesResponseHandler,
  void Function(_FakeKdfOperations operations)? onOperationsCreated,
  SecureLocalStorage? secureStorage,
  String? lifiProxyUrl,
  LifiIntegratorConfig? lifiIntegrator,
}) {
  final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
  final operations = _FakeKdfOperations(
    responsesByMethod: {
      'delete_wallet':
          deleteWalletResponse ??
          <String, dynamic>{'mmrpc': '2.0', 'result': null},
      'change_mnemonic_password':
          changeMnemonicPasswordResponse ??
          <String, dynamic>{'mmrpc': '2.0', 'result': null},
      'get_wallet_names': {
        'mmrpc': '2.0',
        'result': {
          'wallet_names': ['test-wallet'],
          'activated_wallet': 'test-wallet',
        },
      },
      'get_public_key_hash':
          publicKeyHashResponse ??
          {
            'mmrpc': '2.0',
            'result': {'public_key_hash': publicKeyHash},
          },
      'get_mnemonic': {
        'mmrpc': '2.0',
        'result': {
          'format': 'plaintext',
          'mnemonic':
              'abandon abandon abandon abandon abandon abandon abandon '
              'abandon abandon abandon abandon about',
        },
      },
      'stream::shutdown_signal::enable': {
        'mmrpc': '2.0',
        'result': {'streamer_id': 'test-stream'},
      },
    },
    responseHandlersByMethod: {
      if (walletNamesResponseHandler != null)
        'get_wallet_names': walletNamesResponseHandler,
      if (publicKeyHashResponseHandler != null)
        'get_public_key_hash': publicKeyHashResponseHandler,
    },
  );
  onOperationsCreated?.call(operations);
  final framework = KomodoDefiFramework.createWithOperations(
    hostConfig: hostConfig,
    kdfOperations: operations,
  );

  return KdfAuthService(
    framework,
    hostConfig,
    secureStorage: secureStorage,
    lifiProxyUrl: lifiProxyUrl,
    lifiIntegrator: lifiIntegrator,
  );
}

KdfUser _testUser() {
  return KdfUser(
    walletId: WalletId.fromName(
      'test-wallet',
      const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    ),
    isBip39Seed: true,
  );
}

KdfUser _verifiedTestUser() => _testUser().copyWith(
  walletId: _testUser().walletId.copyWith(pubkeyHash: _publicKeyHash),
  metadata: const {'has_backup': false},
);

enum _MetadataWriteKind { replaceMetadata, updateMetadataKey }

Future<void> _writeMetadata(
  KdfAuthService service,
  _MetadataWriteKind kind,
  WalletId expectedWalletId, {
  void Function(dynamic currentValue)? onTransform,
}) => switch (kind) {
  _MetadataWriteKind.replaceMetadata => service.setActiveUserMetadata({
    'has_backup': true,
  }, expectedWalletId: expectedWalletId),
  _MetadataWriteKind.updateMetadataKey => service.updateActiveUserMetadataKey(
    'has_backup',
    (current) {
      onTransform?.call(current);
      return true;
    },
    expectedWalletId: expectedWalletId,
  ),
};
