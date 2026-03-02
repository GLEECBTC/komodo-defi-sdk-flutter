import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class _FakeKdfOperations implements IKdfOperations {
  _FakeKdfOperations({required this.responsesByMethod});

  final Map<String, Map<String, dynamic>> responsesByMethod;

  @override
  String get operationsName => 'fake';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async => KdfStartupResult.ok;

  @override
  Future<MainStatus> kdfMainStatus() async => MainStatus.rpcIsUp;

  @override
  Future<StopStatus> kdfStop() async => StopStatus.ok;

  @override
  Future<bool> isRunning() async => true;

  @override
  Future<String?> version() async => 'test-version';

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    final method = request['method'] as String?;
    if (method == null) {
      return {'mmrpc': '2.0', 'result': <String, dynamic>{}};
    }

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
}

KdfAuthService _createService({
  Map<String, dynamic>? deleteWalletResponse,
  Map<String, dynamic>? changeMnemonicPasswordResponse,
}) {
  final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
  final framework = KomodoDefiFramework.createWithOperations(
    hostConfig: hostConfig,
    kdfOperations: _FakeKdfOperations(
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
        'stream::shutdown_signal::enable': {
          'mmrpc': '2.0',
          'result': {'streamer_id': 'test-stream'},
        },
      },
    ),
  );

  return KdfAuthService(framework, hostConfig);
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
