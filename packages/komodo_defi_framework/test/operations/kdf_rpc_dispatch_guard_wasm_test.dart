@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_wasm.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  test('WASM refuses writes revoked during asynchronous setup', () async {
    var dispatched = false;
    var authorized = true;
    final module = JSObject()
      ..setProperty('isInitialized'.toJS, true.toJS)
      ..setProperty(
        'mm2_rpc'.toJS,
        ((JSAny? request) {
          dispatched = true;
          return Future<JSAny?>.value({'result': 'ok'}.jsify()).toJS;
        }).toJS,
      );
    final operations = KdfOperationsWasm.withModule(
      config: LocalConfig(https: false, rpcPassword: 'fixture-only'),
      module: module,
      logCallback: (_) {},
    );
    final pending = RpcDispatchGuard.run(
      () {
        if (!authorized) throw StateError('revoked');
      },
      () => operations.mm2Rpc({'method': 'send_raw_transaction'}),
      methods: const {'send_raw_transaction'},
    );
    authorized = false;
    await expectLater(pending, throwsA(isA<RpcDispatchRejected>()));
    expect(dispatched, isFalse);
  });
}
