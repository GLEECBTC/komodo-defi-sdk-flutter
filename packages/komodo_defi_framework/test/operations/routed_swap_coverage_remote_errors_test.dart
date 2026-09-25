import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_interface.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_remote.dart';

/// Answers one routed-swap RPC with [status] and [body], through the real
/// transport but an in-memory HTTP client.
Future<Map<String, dynamic>> _answer(int status, String body) {
  return http.runWithClient(
    () => KdfOperationsRemote.create(
      logCallback: (_) {},
      rpcUrl: Uri.parse('http://127.0.0.1:7783'),
      userpass: 'rpc-password-value',
    ).mm2Rpc(<String, dynamic>{'method': 'task::routed_swap::cancel'}),
    () => MockClient((_) async => http.Response(body, status)),
  );
}

void main() {
  test('every typed KDF error status passes its envelope through', () async {
    const cases = <int, String>{
      400: 'InvalidParam',
      404: 'NoSuchTask',
      409: 'TaskFinished',
      429: 'RateLimited',
      500: 'InternalError',
      502: 'ProviderApiError',
    };
    for (final MapEntry(key: status, value: type) in cases.entries) {
      final envelope = <String, dynamic>{
        'mmrpc': '2.0',
        'error': '$type happened',
        'error_path': 'routed_swap',
        'error_trace': 'routed_swap:1]',
        'error_type': type,
        'error_data': {'task_id': 3},
        'id': null,
      };

      final response = await _answer(status, jsonEncode(envelope));

      expect(response, isNot(isA<JsonRpcErrorResponse>()), reason: '$status');
      expect(response, envelope, reason: '$status');
    }
  });

  test(
    'a non-200 without a typed envelope stays an opaque HTTP error',
    () async {
      const bodies = [
        '{"error": "legacy failure detail"}',
        '{"mmrpc": "2.0", "error": "untyped failure detail"}',
        '{"mmrpc": "2.0", "error_type": 7, "error": "numeric type detail"}',
        '{"mmrpc": "1.0", "error_type": "X", "error": "old version detail"}',
        '[{"mmrpc": "2.0", "error_type": "X", "error": "list detail"}]',
        'Bad Gateway detail',
        '',
      ];
      for (final body in bodies) {
        final response = await _answer(502, body);

        expect(response, isA<JsonRpcErrorResponse>(), reason: body);
        final error = response as JsonRpcErrorResponse;
        expect(error.code, 502);
        expect(error.message, 'Remote KDF returned HTTP 502');
        expect(jsonDecode(error.error), {'error': 'HTTP Error', 'status': 502});
        expect(response.toString(), isNot(contains('detail')), reason: body);
      }
    },
  );
}
