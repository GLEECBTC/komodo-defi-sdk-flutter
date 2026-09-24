@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_wasm.dart';

JSObject _module(Future<JSAny?> Function(JSAny?) rpc) {
  return JSObject()
    ..setProperty('isInitialized'.toJS, true.toJS)
    ..setProperty('mm2_rpc'.toJS, ((JSAny? request) => rpc(request).toJS).toJS)
    ..setProperty(
      'mm2_main'.toJS,
      ((JSAny? config, JSFunction logger) {
        logger.callAsFunction(null, 1.toJS, 'synthetic-native-secret'.toJS);
        return 0.toJS;
      }).toJS,
    );
}

void main() {
  tearDown(() => KdfLoggingConfig.verboseLogging = false);

  for (final verbose in [false, true]) {
    test(
      'real JS transport omits body, method and key names verbose=$verbose',
      () async {
        KdfLoggingConfig.verboseLogging = verbose;
        final logs = <String>[];
        Object? received;
        Object? response = {
          'result': {'priv_key': 'synthetic-response-secret'},
        };
        final operations = KdfOperationsWasm.withModule(
          config: LocalConfig(
            https: false,
            rpcPassword: 'synthetic-rpc-secret',
          ),
          module: _module((request) async {
            received = request.dartify();
            return response.jsify();
          }),
          logCallback: logs.add,
        );
        final result = await operations.mm2Rpc({
          'method': 'synthetic-method-secret',
          'mmrpc': '2.0',
          'params': {'password': 'synthetic-password-secret'},
        });
        expect((received! as Map)['userpass'], 'synthetic-rpc-secret');
        expect(
          (result['result'] as Map)['priv_key'],
          'synthetic-response-secret',
        );
        await operations.mm2Rpc({
          'method': {'unexpected': 'synthetic-method-secret'},
          'mmrpc': '2.0',
        });
        await operations.kdfMain({'passphrase': 'synthetic-startup-secret'});
        response = {'synthetic-key-secret': 'synthetic-value-secret'};
        await expectLater(
          operations.mm2Rpc({
            'method': 'synthetic-method-secret',
            'mmrpc': '2.0',
          }),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('synthetic-')),
            ),
          ),
        );
        response = 'synthetic-malformed-body';
        await expectLater(
          operations.mm2Rpc({'method': 'get_mnemonic'}),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('synthetic-')),
            ),
          ),
        );
        expect(logs.join('\n'), isNot(contains('synthetic-')));
        if (verbose) expect(logs.join('\n'), contains('outcome=success'));
      },
    );
  }

  for (final synchronous in [false, true]) {
    test(
      'JS rejection and callback fallback synchronous=$synchronous',
      () async {
        KdfLoggingConfig.verboseLogging = true;
        final printed = <String>[];
        await runZoned(
          () async {
            final operations = KdfOperationsWasm.withModule(
              config: LocalConfig(
                https: false,
                rpcPassword: 'synthetic-rpc-secret',
              ),
              module: _module((_) {
                if (synchronous) throw StateError('synthetic-JS-secret');
                return Future<JSAny?>.error(StateError('synthetic-JS-secret'));
              }),
              logCallback: (_) => throw StateError('synthetic-callback-secret'),
            );
            await expectLater(
              operations.mm2Rpc({'method': 'synthetic-method-secret'}),
              throwsA(
                isA<Exception>().having(
                  (error) => error.toString(),
                  'safe error',
                  isNot(contains('synthetic-')),
                ),
              ),
            );
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) {
              printed.add(line);
            },
          ),
        );
        expect(printed, contains('KDF WASM diagnostic callback failed'));
        expect(printed.join('\n'), isNot(contains('synthetic-')));
      },
    );
  }
}
