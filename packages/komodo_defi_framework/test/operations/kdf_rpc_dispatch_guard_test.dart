import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_remote.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  test('remote transport refuses revoked writes before sending', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <String>[];
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      received.add(body['method'] as String);
      request.response.write('{"result":"ok"}');
      await request.response.close();
    });
    final operations = KdfOperationsRemote.create(
      logCallback: (_) {},
      rpcUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      userpass: 'fixture-only',
    );
    await expectLater(
      RpcDispatchGuard.run(
        () => throw StateError('revoked'),
        () => operations.mm2Rpc({'method': 'send_raw_transaction'}),
        methods: const {'send_raw_transaction'},
      ),
      throwsA(isA<RpcDispatchRejected>()),
    );
    await operations.mm2Rpc({'method': 'version'});
    expect(received, ['version']);
  });
}
