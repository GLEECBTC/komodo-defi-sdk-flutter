import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

final class _RecordingOperations implements IKdfOperations {
  final List<JsonMap> requests = [];
  int disposed = 0;

  @override
  String get operationsName => 'recording';

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async {
    requests.add(request);
    return {'result': 'ok'};
  }

  @override
  Future<KdfStartupResult> kdfMain(
    JsonMap startParams, {
    int? logLevel,
  }) async => KdfStartupResult.ok;

  @override
  Future<MainStatus> kdfMainStatus() async => MainStatus.rpcIsUp;

  @override
  Future<StopStatus> kdfStop() async => StopStatus.ok;

  @override
  Future<bool> isRunning() async => true;

  @override
  Future<String?> version() async => 'test';

  @override
  Future<void> validateSetup() async {}

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async => true;

  @override
  void resetHttpClient() {}

  @override
  void dispose() => disposed++;
}

final class _ClosingRouting implements NativeWssElectrumRouting {
  bool closed = false;

  @override
  Future<JsonMap?> replacementFor(JsonMap wssServer) async => null;

  @override
  Future<void> close() async => closed = true;
}

void main() {
  test('routes WSS servers before the request reaches KDF', () async {
    final inner = _RecordingOperations();
    final operations = ElectrumBridgingKdfOperations(
      inner,
      routing: const DropWssElectrumRouting(),
    );

    final response = await operations.mm2Rpc({
      'method': 'electrum',
      'coin': 'KMD',
      'servers': [
        {'url': 'a.example:30001', 'protocol': 'WSS'},
        {'url': 'a.example:20001', 'protocol': 'SSL'},
      ],
    });

    expect(response, {'result': 'ok'});
    expect(inner.requests.single['servers'], [
      {'url': 'a.example:20001', 'protocol': 'SSL'},
    ]);
  });

  test('delegates everything else unchanged', () async {
    final inner = _RecordingOperations();
    final operations = ElectrumBridgingKdfOperations(
      inner,
      routing: const DropWssElectrumRouting(),
    );

    expect(operations.operationsName, 'recording');
    expect(await operations.version(), 'test');
    expect(await operations.kdfMainStatus(), MainStatus.rpcIsUp);
    expect(await operations.isRunning(), isTrue);
  });

  test('dispose closes the routing and the wrapped operations', () async {
    final inner = _RecordingOperations();
    final routing = _ClosingRouting();

    ElectrumBridgingKdfOperations(inner, routing: routing).dispose();
    await Future<void>.delayed(Duration.zero);

    expect(routing.closed, isTrue);
    expect(inner.disposed, 1);
  });
}
