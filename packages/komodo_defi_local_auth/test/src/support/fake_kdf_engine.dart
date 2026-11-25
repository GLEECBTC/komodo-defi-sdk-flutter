import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_local_auth/src/auth/storage/secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

const testWalletName = 'test-wallet';
const testPublicKeyHash = '05aab5342166f8594baf17a7d9bef5d567443327';
const testPassword = 'test-only-password';
const testHdOptions = AuthOptions(derivationMethod: DerivationMethod.hdWallet);

typedef RpcAnswer = Future<Map<String, dynamic>> Function();

Map<String, dynamic> rpcResult(Object? result) => {
  'mmrpc': '2.0',
  'result': result,
};

/// An engine whose wallet catalog follows its own starts, stops and deletions.
///
/// Like the real transports, it runs the caller's dispatch guard before a
/// request leaves, so [requests] holds only what an engine would have received.
class FakeKdfEngine implements IKdfOperations {
  FakeKdfEngine({List<String>? wallets, this.activeWallet = testWalletName})
    : wallets = wallets ?? [testWalletName];

  final List<String> wallets;
  String? activeWallet;
  bool running = true;
  int stops = 0;
  final starts = <Map<String, dynamic>>[];
  final requests = <Map<String, dynamic>>[];

  /// Replaces the engine's own answer to a method.
  final answers = <String, RpcAnswer>{};
  Future<void> Function()? beforeStop;

  /// Observes a request the engine received, before it is answered.
  void Function(String method)? onSent;

  int sent(String method) =>
      requests.where((request) => request['method'] == method).length;

  @override
  String get operationsName => 'fake-kdf-engine';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async {
    starts.add(startParams);
    final name = startParams['wallet_name'] as String?;
    if (name != null &&
        startParams['allow_registrations'] == true &&
        !wallets.contains(name)) {
      wallets.add(name);
    }
    activeWallet = name;
    running = true;
    return KdfStartupResult.ok;
  }

  @override
  Future<MainStatus> kdfMainStatus() async =>
      running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
  Future<StopStatus> kdfStop() async {
    stops++;
    await beforeStop?.call();
    running = false;
    activeWallet = null;
    return StopStatus.ok;
  }

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<String?> version() async => running ? 'test-version' : null;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    final method = request['method'] as String?;
    if (method != null) RpcDispatchGuard.ensureCurrent(method);
    requests.add(request);
    if (method != null) onSent?.call(method);
    final answer = answers[method];
    if (answer != null) return answer();
    switch (method) {
      case 'get_wallet_names':
        return rpcResult({
          'wallet_names': wallets.toList(),
          'activated_wallet': activeWallet,
        });
      case 'get_public_key_hash':
        return rpcResult({'public_key_hash': testPublicKeyHash});
      case 'get_mnemonic':
        return rpcResult({
          'format': 'plaintext',
          'mnemonic':
              'abandon abandon abandon abandon abandon abandon abandon '
              'abandon abandon abandon abandon about',
        });
      case 'delete_wallet':
        wallets.remove((request['params'] as Map)['wallet_name']);
        return rpcResult(null);
      case 'change_mnemonic_password':
        return rpcResult(null);
      case 'stream::shutdown_signal::enable':
        return rpcResult({'streamer_id': 'test-stream'});
      default:
        return rpcResult(<String, dynamic>{});
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

final testHostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');

KomodoDefiFramework frameworkFor(FakeKdfEngine engine) =>
    KomodoDefiFramework.createWithOperations(
      hostConfig: testHostConfig,
      kdfOperations: engine,
    );

KdfAuthService authServiceFor(
  FakeKdfEngine engine, {
  SecureLocalStorage? storage,
}) => KdfAuthService(
  frameworkFor(engine),
  testHostConfig,
  secureStorage: storage,
);

KdfUser verifiedUser([String name = testWalletName]) => KdfUser(
  walletId: WalletId.withPubkeyHash(name, testHdOptions, testPublicKeyHash),
  isBip39Seed: true,
  metadata: const {'has_backup': false},
);

/// Replaces secure storage with exactly [users], as an earlier run left them.
void seedStoredUsers(Iterable<KdfUser> users) {
  FlutterSecureStorage.setMockInitialValues({
    for (final user in users)
      'user_${user.walletId.name}': jsonEncode(user.toJson()),
  });
}
