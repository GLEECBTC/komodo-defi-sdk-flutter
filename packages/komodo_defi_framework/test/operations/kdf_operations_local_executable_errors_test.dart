@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

import 'kdf_error_captures.dart';

/// The desktop transport against the native build's recorded answers, checked
/// against what the web build reported for the same requests
/// (`kdf_operations_wasm_errors_test.dart` runs the same captures there).
void main() {
  late HttpServer server;
  late KdfOperationsLocalExecutable kdf;
  late KdfCapture answer;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // dart:io would label every answer text/plain; the native build labels
    // none of these.
    server.defaultResponseHeaders.clear();
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = answer.status
        ..add(utf8.encode(answer.native));
      await request.response.close();
    });
    kdf = KdfOperationsLocalExecutable.create(
      logCallback: (_) {},
      config: LocalConfig(https: false, rpcPassword: 'rpc', port: server.port),
    );
  });

  tearDown(() async {
    kdf.dispose();
    await server.close(force: true);
  });

  for (final capture in kdfCaptures) {
    test('reports ${capture.name} as the web build does', () async {
      answer = capture;

      final response = await kdf.mm2Rpc({...capture.request});

      expect(response, jsonDecode(capture.native));
      expect(withoutTraces(response), withoutTraces(capture.web));
    });
  }
}
