import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Answers a KDF start that sends no wallet password with [noAuthResult] and
/// one that does with [walletResult].
class _StartupKdfOperations implements IKdfOperations {
  _StartupKdfOperations({
    required this.noAuthResult,
    required this.walletResult,
  });

  final KdfStartupResult noAuthResult;
  final KdfStartupResult walletResult;
  final startParams = <Map<String, dynamic>>[];
  bool _running = false;

  @override
  String get operationsName => 'startup failure fake';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> params, {
    int? logLevel,
  }) async {
    startParams.add(params);
    final result = params.containsKey('wallet_password')
        ? walletResult
        : noAuthResult;
    _running = result.isOk;
    return result;
  }

  @override
  Future<MainStatus> kdfMainStatus() async =>
      _running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
  Future<StopStatus> kdfStop() async {
    final wasRunning = _running;
    _running = false;
    return wasRunning ? StopStatus.ok : StopStatus.notRunning;
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Future<String?> version() async => _running ? 'test-version' : null;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async =>
      switch (request['method']) {
        'get_wallet_names' => {
          'mmrpc': '2.0',
          'result': {'wallet_names': <String>[], 'activated_wallet': null},
        },
        'stream::shutdown_signal::enable' => {
          'mmrpc': '2.0',
          'result': {'streamer_id': 'test-stream'},
        },
        _ => {'mmrpc': '2.0', 'result': <String, dynamic>{}},
      };

  @override
  Future<void> validateSetup() async {}

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async => true;

  @override
  void resetHttpClient() {}

  @override
  void dispose() {}
}

const _walletName = 'test-wallet';
const _password = 'Qz7!sentinel-Wv4#';
const _options = AuthOptions(
  derivationMethod: DerivationMethod.hdWallet,
  allowWeakPassword: true,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testHome;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> logSubscription;
  late Level previousLevel;

  setUpAll(() async {
    testHome = await Directory.systemTemp.createTemp('kdf-startup-failure-');
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
              '{"coins":{"coins_repo_content_url":"http://[",'
              '"cdn_branch_mirrors":{}}}',
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
    final storedUser = KdfUser(
      walletId: WalletId.fromName(_walletName, _options),
      isBip39Seed: true,
    );
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'user_$_walletName': jsonEncode(storedUser.toJson()),
    });
    previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    records = <LogRecord>[];
    logSubscription = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await logSubscription.cancel();
    Logger.root.level = previousLevel;
  });

  (KdfAuthService, _StartupKdfOperations) createService({
    required KdfStartupResult noAuthResult,
    KdfStartupResult walletResult = KdfStartupResult.ok,
  }) {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: noAuthResult,
      walletResult: walletResult,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
    );
    addTearDown(service.dispose);
    return (service, operations);
  }

  void expectLogged(String prefix) {
    final record = records.singleWhere((r) => r.message.startsWith(prefix));
    expect(DiagnosticSanitizer.sanitizeMessage(record.message), record.message);
  }

  Matcher failedStart(KdfStartupResult result) => isA<AuthException>()
      .having((e) => e.type, 'type', AuthExceptionType.walletStartFailed)
      .having((e) => e.details, 'details', {'kdf_error': result.name});

  group('a KDF start that sends no wallet password', () {
    test('reports initError as a failed start, not a wrong password', () async {
      final (service, operations) = createService(
        noAuthResult: KdfStartupResult.initError,
      );

      await expectLater(
        service.getUsers(),
        throwsA(failedStart(KdfStartupResult.initError)),
      );
      expect(operations.startParams.single, isNot(contains('wallet_password')));
      expectLogged('_ensureKdfRunning: startKdf(no-auth) returned initError ');
    });

    test('reports unknownError as a failed start', () async {
      final (service, _) = createService(
        noAuthResult: KdfStartupResult.unknownError,
      );

      await expectLater(
        service.getUsers(),
        throwsA(failedStart(KdfStartupResult.unknownError)),
      );
    });

    test('reports spawnError under the kdf_error key', () async {
      final (service, _) = createService(
        noAuthResult: KdfStartupResult.spawnError,
      );

      await expectLater(
        service.getUsers(),
        throwsA(failedStart(KdfStartupResult.spawnError)),
      );
    });

    test('fails registration with a failed start', () async {
      final (service, _) = createService(
        noAuthResult: KdfStartupResult.initError,
      );

      await expectLater(
        service.register(
          walletName: 'new-wallet',
          password: _password,
          options: _options,
        ),
        throwsA(failedStart(KdfStartupResult.initError)),
      );
    });

    test('fails wallet deletion with a failed start', () async {
      final (service, _) = createService(
        noAuthResult: KdfStartupResult.initError,
      );

      await expectLater(
        service.deleteWallet(walletName: _walletName, password: _password),
        throwsA(failedStart(KdfStartupResult.initError)),
      );
    });

    test('leaves a health check that cannot restart KDF unhealthy', () async {
      final (service, _) = createService(
        noAuthResult: KdfStartupResult.initError,
      );

      expect(await service.ensureKdfHealthy(), isFalse);
      expectLogged('_forceStartKdf: Failed to start KDF: initError');
    });
  });

  group('a KDF start that sends the wallet password', () {
    test('still reads initError as an incorrect password', () async {
      final (service, operations) = createService(
        noAuthResult: KdfStartupResult.ok,
        walletResult: KdfStartupResult.initError,
      );

      await expectLater(
        service.signIn(
          walletName: _walletName,
          password: _password,
          options: _options,
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.type,
            'type',
            AuthExceptionType.incorrectPassword,
          ),
        ),
      );
      expect(
        operations.startParams.last,
        containsPair('wallet_password', _password),
      );
      expectLogged('_restartKdf: auth start returned initError ');
      final diagnostics = records
          .map((r) => '${r.message} ${r.error} ${r.stackTrace}')
          .join('\n');
      expect(diagnostics, isNot(contains(_password)));
    });

    test('reports unknownError as a failed start', () async {
      final (service, _) = createService(
        noAuthResult: KdfStartupResult.ok,
        walletResult: KdfStartupResult.unknownError,
      );

      await expectLater(
        service.signIn(
          walletName: _walletName,
          password: _password,
          options: _options,
        ),
        throwsA(failedStart(KdfStartupResult.unknownError)),
      );
    });
  });
}
