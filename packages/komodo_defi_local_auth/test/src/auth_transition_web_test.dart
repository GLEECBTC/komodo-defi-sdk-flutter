@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';

class _Engine implements IKdfOperations {
  int stops = 0;
  int resets = 0;
  Error? stopError;

  @override
  String get operationsName => 'browser-auth-transition-test';

  @override
  Future<StopStatus> kdfStop() async {
    stops++;
    final error = stopError;
    if (error != null) throw error;
    return StopStatus.ok;
  }

  @override
  void resetHttpClient() => resets++;

  @override
  Future<bool> isRunning() async => false;

  @override
  Future<MainStatus> kdfMainStatus() async => MainStatus.notRunning;

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> startParams, {
    int? logLevel,
  }) async => KdfStartupResult.ok;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async => {
    'mmrpc': '2.0',
    'result': <String, dynamic>{},
  };

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async => true;

  @override
  Future<void> validateSetup() async {}

  @override
  Future<String?> version() async => null;

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Engine engine;
  late KdfAuthService auth;

  setUp(() {
    engine = _Engine();
    final config = LocalConfig(https: false, rpcPassword: 'synthetic-rpc');
    auth = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: config,
        kdfOperations: engine,
      ),
      config,
    );
  });

  tearDown(() async {
    engine.stopError = null;
    await auth.dispose().timeout(const Duration(seconds: 5));
  });

  test(
    'nested sign-out transition stops the engine and revokes the session',
    () async {
      final revision = auth.authGeneration;
      final signedOut = auth.signOut();
      expect(auth.isAuthTransitionInProgress, isTrue);
      expect(auth.authGeneration, greaterThan(revision));
      await signedOut.timeout(const Duration(seconds: 5));
      expect(engine.stops, 1);
      expect(engine.resets, greaterThanOrEqualTo(1));
      expect(auth.isAuthTransitionInProgress, isFalse);
    },
  );

  test(
    'a failed nested stop releases the transition and resets transport',
    () async {
      final failure = StateError('synthetic-stop-failure');
      engine.stopError = failure;
      await expectLater(
        auth.signOut().timeout(const Duration(seconds: 5)),
        throwsA(same(failure)),
      );
      expect(engine.stops, 1);
      expect(engine.resets, greaterThanOrEqualTo(1));
      expect(auth.isAuthTransitionInProgress, isFalse);
    },
  );
}
