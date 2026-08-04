import 'dart:convert';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

/// Every request must survive `jsonEncode`.
///
/// This exists because `GetPublicKeyHashRequest.toJson` shipped
/// `'params': <JsonMap>{}` from 2024 to 2026. A single type argument on `{}`
/// makes it a **Set**, not a Map, and `jsonEncode` refuses it with
/// `Converting object to an encodable object failed: _Set len:0`.
///
/// Nothing caught it because the type system cannot: `Set<JsonMap>` is a
/// perfectly good `dynamic` value in a `Map<String, dynamic>`. It only fails at
/// the transport, and only on transports that serialise - which is every
/// non-web one (`KdfOperationsRemote.mm2Rpc`,
/// `KdfOperationsNativeLibrary.mm2Rpc`; the WASM path hands the object to JS
/// instead). A replay/mock backend that reads the map directly never notices
/// either, which is exactly how it survived a test suite.
void main() {
  group('request payloads are JSON-encodable', () {
    // Constructed directly rather than discovered, because there is no
    // registry of request types. Add new ones here; the assertion is cheap and
    // the failure mode it guards is invisible until runtime.
    final requests = <String, BaseRequest<dynamic, dynamic>>{
      'get_public_key_hash': GetPublicKeyHashRequest(rpcPass: 'test-pass'),
      'get_wallet_names': GetWalletNamesRequest('test-pass'),
      'get_enabled_coins': GetEnabledCoinsRequest(rpcPass: 'test-pass'),
      'my_balance': MyBalanceRequest(rpcPass: 'test-pass', coin: 'KMD'),
    };

    requests.forEach((name, request) {
      test('$name encodes', () {
        final json = request.toJson();
        expect(
          () => jsonEncode(json),
          returnsNormally,
          reason:
              '$name produced a payload jsonEncode cannot serialise. The usual '
              'cause is a `<T>{}` literal, which is an empty Set - write '
              '`<String, dynamic>{}` for an empty map.',
        );

        // Belt and braces: a Set nested anywhere is the same bug one level in,
        // and `returnsNormally` above would still catch it - but naming the
        // offending key is what makes the failure actionable.
        _assertNoSets(json, path: name);
      });
    });
  });
}

void _assertNoSets(Object? value, {required String path}) {
  if (value is Set) {
    fail('$path is a Set; jsonEncode cannot serialise it');
  }
  if (value is Map) {
    value.forEach((key, child) => _assertNoSets(child, path: '$path.$key'));
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _assertNoSets(value[i], path: '$path[$i]');
    }
  }
}
