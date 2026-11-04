import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

const _publicKeyHash = '05aab5342166f8594baf17a7d9bef5d567443327';

final _unavailable = <String, dynamic>{
  'mmrpc': '2.0',
  'error': 'get_public_key_hash is unavailable',
};

final _available = <String, dynamic>{
  'mmrpc': '2.0',
  'result': {'public_key_hash': _publicKeyHash},
};

/// A running, signed-in KDF whose identity RPC can be switched off and on.
class _FakeKdfOperations implements IKdfOperations {
  Map<String, dynamic> publicKeyHash = _unavailable;
  int publicKeyHashCalls = 0;
  bool _running = true;

  @override
  String get operationsName => 'fake';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async {
    _running = true;
    return KdfStartupResult.ok;
  }

  @override
  Future<MainStatus> kdfMainStatus() async =>
      _running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
  Future<StopStatus> kdfStop() async {
    _running = false;
    return StopStatus.ok;
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Future<String?> version() async => _running ? 'test-version' : null;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    switch (request['method']) {
      case 'get_wallet_names':
        return {
          'mmrpc': '2.0',
          'result': {
            'wallet_names': ['test-wallet'],
            'activated_wallet': 'test-wallet',
          },
        };
      case 'get_public_key_hash':
        publicKeyHashCalls++;
        return publicKeyHash;
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

KdfUser _storedUser() => KdfUser(
  walletId: WalletId.fromName(
    'test-wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

/// A degraded identity must recover on its own.
///
/// `get_public_key_hash` failing (KDF saturated by a web login) leaves a
/// name-only user, and GasFree stays paused until an enriched one is emitted.
/// The SDK managers used to re-read the user several times a second, which
/// recovered it as a side effect; they no longer do, so the service re-reads
/// a degraded identity itself, backing off, and stops after a bound.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeKdfOperations operations;
  late KdfAuthService service;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'user_test-wallet': jsonEncode(_storedUser().toJson()),
    });
    operations = _FakeKdfOperations();
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
      identityRecheckDelay: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
  });

  test('re-reads a degraded identity until KDF answers again', () async {
    final emitted = <KdfUser?>[];
    final subscription = service.authStateChanges.listen(emitted.add);
    addTearDown(subscription.cancel);

    final degraded = await service.getActiveUser();
    expect(degraded?.walletId.pubkeyHash, isNull);

    operations.publicKeyHash = _available;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(emitted.last?.walletId.pubkeyHash, _publicKeyHash);
    final callsAfterRecovery = operations.publicKeyHashCalls;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      operations.publicKeyHashCalls,
      callsAfterRecovery,
      reason: 'an enriched identity must stop the re-reads',
    );
  });

  test('stops re-reading an identity that never recovers', () async {
    await service.getActiveUser();

    // Six re-reads back off from 20 ms: 20 + 40 + ... + 640 = 1260 ms.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final callsAtBound = operations.publicKeyHashCalls;
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(operations.publicKeyHashCalls, callsAtBound);
    expect(callsAtBound, greaterThan(1));
  });

  test('signing out cancels a pending re-read', () async {
    await service.getActiveUser();
    await service.signOut();
    final callsAfterSignOut = operations.publicKeyHashCalls;

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(operations.publicKeyHashCalls, callsAfterSignOut);
  });
}
