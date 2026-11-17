@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_wasm.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'kdf_error_captures.dart';

/// The web transport against the web build's recorded answers, checked
/// against what the native build reported for the same requests
/// (`kdf_operations_local_executable_errors_test.dart` runs them natively).
void main() {
  test(
    'parses encrypted mnemonic metadata across the real JS boundary',
    () async {
      const data = EncryptedMnemonicData.encryptedDataExample;
      final details = data['key_derivation_details'] as Map<String, dynamic>;
      final argon2 = details['Argon2'] as Map<String, dynamic>;
      final payload = {
        'mmrpc': '2.0',
        'result': {
          'format': 'encrypted',
          'encrypted_mnemonic_data': {
            ...data,
            'key_derivation_details': {
              'Argon2': {
                ...argon2,
                'params': {
                  ...argon2['params'] as Map<String, dynamic>,
                  'version': 19,
                },
              },
            },
          },
        },
      };
      final module = JSObject()
        ..setProperty('isInitialized'.toJS, true.toJS)
        ..setProperty(
          'mm2_rpc'.toJS,
          ((JSAny? _) => Future<JSAny?>.value(payload.jsify()).toJS).toJS,
        );
      final kdf = KdfOperationsWasm.withModule(
        config: LocalConfig(https: false, rpcPassword: 'synthetic-rpc'),
        module: module,
      );
      final response = await kdf.mm2Rpc({
        'mmrpc': '2.0',
        'method': 'get_mnemonic',
        'params': {'format': 'encrypted'},
      });
      final mnemonic = Mnemonic.fromRpcJson(
        response['result'] as Map<String, dynamic>,
      );
      expect(mnemonic.isEncrypted, isTrue);
      expect(mnemonic.encryptedMnemonic!.keyDerivationDetails.version, 19);
      expect(mnemonic.plaintextMnemonic, isNull);
    },
  );

  for (final capture in kdfCaptures) {
    test('reports ${capture.name} as the native build does', () async {
      final module = JSObject()
        ..setProperty('isInitialized'.toJS, true.toJS)
        ..setProperty(
          'mm2_rpc'.toJS,
          ((JSAny? _) => Future<JSAny?>.value(capture.web.jsify()).toJS).toJS,
        );
      final kdf = KdfOperationsWasm.withModule(
        config: LocalConfig(https: false, rpcPassword: 'rpc'),
        module: module,
      );

      final response = await kdf.mm2Rpc({...capture.request});

      expect(response, capture.web);
      expect(
        withoutTraces(response),
        withoutTraces(jsonDecode(capture.native) as Map<String, dynamic>),
      );
    });
  }
}
