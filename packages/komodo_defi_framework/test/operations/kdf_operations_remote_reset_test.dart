import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_remote.dart';

/// The local executable sends every request through this transport. Before a
/// replacement engine starts, the auth service stops the old one and resets
/// the transport, so a request still awaiting the old engine must fail rather
/// than reach the new one.
void main() {
  late HttpServer server;
  late KdfOperationsRemote operations;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    operations = KdfOperationsRemote.create(
      logCallback: (_) {},
      rpcUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      userpass: 'rpc-password-value',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('a reset aborts every request still awaiting an answer', () async {
    final held = <HttpRequest>[];
    final bothArrived = Completer<void>();
    // An engine that accepts requests and never answers them.
    server.listen((request) {
      held.add(request);
      if (held.length == 2) bothArrived.complete();
    });

    final first = operations.mm2Rpc(<String, dynamic>{'method': 'version'});
    final second = operations.mm2Rpc(<String, dynamic>{
      'method': 'task::routed_swap::init',
    });
    await bothArrived.future.timeout(const Duration(seconds: 5));

    operations.resetHttpClient();

    for (final pending in [first, second]) {
      final response = await pending.timeout(const Duration(seconds: 5));
      expect(response, isA<ConnectionError>());
    }
  });

  test('requests sent after a reset are answered', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.write('{"result": "test-version"}');
      await request.response.close();
    });

    operations.resetHttpClient();

    expect(await operations.version(), 'test-version');
    expect(await operations.version(), 'test-version');
  });
}
