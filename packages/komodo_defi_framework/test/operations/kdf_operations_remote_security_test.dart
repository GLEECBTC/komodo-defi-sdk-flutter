import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_remote.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    KdfLoggingConfig.verboseLogging = true;
  });

  tearDown(() async {
    KdfLoggingConfig.verboseLogging = false;
    await server.close(force: true);
  });

  test(
    'redacts credentials and signed payloads without mutating the RPC',
    () async {
      final received = Completer<Map<String, dynamic>>();
      server.listen((httpRequest) async {
        final body = await utf8.decoder.bind(httpRequest).join();
        received.complete(jsonDecode(body) as Map<String, dynamic>);
        httpRequest.response
          ..statusCode = HttpStatus.badGateway
          ..write('upstream-provider-api-secret signed-gasfree-payload');
        await httpRequest.response.close();
      });

      final logs = <String>[];
      final operations = KdfOperationsRemote.create(
        logCallback: logs.add,
        rpcUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        userpass: 'rpc-password-value',
      );
      final request = <String, dynamic>{
        'method': 'send_raw_transaction',
        'tron_gasless_provider': <String, dynamic>{
          'service': <String, dynamic>{
            'gas_free': <String, dynamic>{
              'api_key': 'provider-api-key',
              'api_secret': 'provider-api-secret',
            },
          },
        },
        'tx_json': <String, dynamic>{
          'from_address': 'private-wallet-address',
          'signed_authorization': <String, dynamic>{
            'sig': 'signed-gasfree-payload',
          },
        },
      };

      final response = await operations.mm2Rpc(request);
      final sent = await received.future;
      final diagnostics = '${logs.join('\n')}\n$response';

      for (final secret in <String>[
        'rpc-password-value',
        'provider-api-key',
        'provider-api-secret',
        'private-wallet-address',
        'signed-gasfree-payload',
        'upstream-provider-api-secret',
      ]) {
        expect(diagnostics, isNot(contains(secret)));
      }
      expect(logs, ['KDF remote RPC request dispatched']);

      // Redaction is log-only: KDF still receives the exact credentials/payload.
      expect(sent['userpass'], 'rpc-password-value');
      expect(
        (((sent['tron_gasless_provider'] as Map<String, dynamic>)['service']
                as Map<String, dynamic>)['gas_free']
            as Map<String, dynamic>)['api_secret'],
        'provider-api-secret',
      );
      expect(
        ((sent['tx_json'] as Map<String, dynamic>)['signed_authorization']
            as Map<String, dynamic>)['sig'],
        'signed-gasfree-payload',
      );
    },
  );

  test('does not expose a malformed upstream response body', () async {
    server.listen((httpRequest) async {
      await utf8.decoder.bind(httpRequest).drain<void>();
      httpRequest.response
        ..statusCode = HttpStatus.ok
        ..write('malformed-provider-secret');
      await httpRequest.response.close();
    });

    final operations = KdfOperationsRemote.create(
      logCallback: (_) {},
      rpcUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      userpass: 'rpc-password-value',
    );

    final response = await operations.mm2Rpc(<String, dynamic>{
      'method': 'version',
    });

    expect(response.toString(), isNot(contains('malformed-provider-secret')));
    expect(response['error'], 'InvalidKdfResponse');
  });

  test('passes a typed KDF error envelope through on a non-200', () async {
    // KDF reports MMRPC 2.0 errors with HTTP 4xx/5xx statuses; the typed
    // error_type is what callers branch on, so it must survive the transport.
    final envelope = <String, dynamic>{
      'mmrpc': '2.0',
      'error': 'Routed swap task has already broadcast: 3',
      'error_path': 'swap_task',
      'error_trace': 'swap_task:1',
      'error_type': 'TaskAlreadyBroadcast',
      'error_data': {'task_id': 3},
    };
    server.listen((httpRequest) async {
      await utf8.decoder.bind(httpRequest).drain<void>();
      httpRequest.response
        ..statusCode = HttpStatus.conflict
        ..write(jsonEncode(envelope));
      await httpRequest.response.close();
    });

    final operations = KdfOperationsRemote.create(
      logCallback: (_) {},
      rpcUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      userpass: 'rpc-password-value',
    );

    final response = await operations.mm2Rpc(<String, dynamic>{
      'method': 'task::routed_swap::cancel',
    });

    expect(response['error_type'], 'TaskAlreadyBroadcast');
    expect(response['error_data'], {'task_id': 3});
  });
}
