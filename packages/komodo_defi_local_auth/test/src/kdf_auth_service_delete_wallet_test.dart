import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' show ClientException;
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

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

  @override
  String get operationsName => 'fake';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async {
    _isRunning = true;
    return KdfStartupResult.ok;
  }

  @override
  Future<MainStatus> kdfMainStatus() async => MainStatus.rpcIsUp;

  @override
  Future<StopStatus> kdfStop() async {
    stopCount++;
    _isRunning = false;
    return StopStatus.ok;
  }

  @override
  Future<bool> isRunning() async => _isRunning;

  @override
  Future<String?> version() async => _isRunning ? 'test-version' : null;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
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
          walletNamesResponseHandler: () =>
              Future<Map<String, dynamic>>.error(
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

    test(
      'setActiveUserMetadata keeps an unverified stored identity locked',
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
        final service = _createService(
          publicKeyHashResponse: {
            'mmrpc': '2.0',
            'error': 'get_public_key_hash is unavailable',
          },
        );
        addTearDown(service.dispose);

        expect((await service.getActiveUser())?.walletId.pubkeyHash, isNull);

        await service.setActiveUserMetadata({'seedBackupConfirmed': true});

        final runtimeUser = await service.getActiveUser();
        expect(runtimeUser?.walletId.pubkeyHash, isNull);
        expect(runtimeUser?.metadata['seedBackupConfirmed'], isTrue);

        final persisted = await const FlutterSecureStorage().read(
          key: 'user_${storedUser.walletId.name}',
        );
        final persistedUser = KdfUser.fromJson(
          (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
        );
        expect(persistedUser.walletId.pubkeyHash, _publicKeyHash);
        expect(persistedUser.metadata['seedBackupConfirmed'], isTrue);
      },
    );

    test(
      'updateActiveUserMetadataKey keeps an unverified stored identity locked',
      () async {
        final storedUser = _testUser().copyWith(
          walletId: WalletId.withPubkeyHash(
            _testUser().walletId.name,
            _testUser().walletId.authOptions,
            _publicKeyHash,
          ),
          metadata: const {'activationCount': 1},
        );
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'user_${storedUser.walletId.name}': jsonEncode(storedUser.toJson()),
        });
        final service = _createService(
          publicKeyHashResponse: {
            'mmrpc': '2.0',
            'error': 'get_public_key_hash is unavailable',
          },
        );
        addTearDown(service.dispose);

        expect((await service.getActiveUser())?.walletId.pubkeyHash, isNull);

        await service.updateActiveUserMetadataKey(
          'activationCount',
          (current) => (current as int) + 1,
        );

        final runtimeUser = await service.getActiveUser();
        expect(runtimeUser?.walletId.pubkeyHash, isNull);
        expect(runtimeUser?.metadata['activationCount'], 2);

        final persisted = await const FlutterSecureStorage().read(
          key: 'user_${storedUser.walletId.name}',
        );
        final persistedUser = KdfUser.fromJson(
          (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
        );
        expect(persistedUser.walletId.pubkeyHash, _publicKeyHash);
        expect(persistedUser.metadata['activationCount'], 2);
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
        });
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
        expect(operations.stopCount, 1);
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
}

const _publicKeyHash = '05aab5342166f8594baf17a7d9bef5d567443327';
const _secondPublicKeyHash = '1111111111111111111111111111111111111111';

KdfAuthService _createService({
  Map<String, dynamic>? deleteWalletResponse,
  Map<String, dynamic>? changeMnemonicPasswordResponse,
  String publicKeyHash = _publicKeyHash,
  Map<String, dynamic>? publicKeyHashResponse,
  Future<Map<String, dynamic>> Function()? publicKeyHashResponseHandler,
  Future<Map<String, dynamic>> Function()? walletNamesResponseHandler,
  void Function(_FakeKdfOperations operations)? onOperationsCreated,
  SecureLocalStorage? secureStorage,
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

  return KdfAuthService(framework, hostConfig, secureStorage: secureStorage);
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
