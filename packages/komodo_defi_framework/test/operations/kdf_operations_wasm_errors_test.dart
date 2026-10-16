@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_wasm.dart';

import 'kdf_error_captures.dart';

/// The web transport against the web build's recorded answers, checked
/// against what the native build reported for the same requests
/// (`kdf_operations_local_executable_errors_test.dart` runs them natively).
void main() {
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
