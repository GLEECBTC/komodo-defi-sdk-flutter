import 'dart:async';

import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

class _Unprintable {
  @override
  String toString() => throw StateError('Must not stringify diagnostic input');
}

void main() {
  test('unknown payloads and secret-shaped diagnostic text are omitted', () {
    for (final value in <Object?>[
      _Unprintable(),
      {'unexpected': 'synthetic-secret'},
      '{unexpected: synthetic-secret}',
      'RPC response: synthetic-secret',
      'RPC method=unrecognized_value outcome=success',
      'mm2Rpc request: synthetic-secret',
      'privateKey: synthetic-secret',
      'priv_key: synthetic-secret',
      'rpc_pass=unrecognized_value',
      'viewingKey=unrecognized_value',
      'RPCPassword=unrecognized_value',
      'password=synthetic-secret',
      'https://example.test/?key=synthetic-secret',
      'first line\nsynthetic-secret',
      'abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon about',
      '0x${'aa' * 32}',
      'x' * 1025,
    ]) {
      expect(DiagnosticSanitizer.sanitizeMessage(value), isNull);
    }
  });

  test('known RPC metadata is retained; untrusted methods become unknown', () {
    final summary = DiagnosticSanitizer.rpcSummary(
      method: 'get_mnemonic',
      success: true,
      elapsedMilliseconds: 12,
    );
    expect(DiagnosticSanitizer.sanitizeMessage(summary), summary);
    for (final method in <Object?>['synthetic-secret', _Unprintable()]) {
      expect(
        DiagnosticSanitizer.rpcSummary(method: method, success: false),
        'RPC method=unknown outcome=failure',
      );
    }
    expect(
      DiagnosticSanitizer.sanitizeMessage('KDF startup completed'),
      'KDF startup completed',
    );
  });

  test('error classification never reads message, source or toString', () {
    expect(DiagnosticSanitizer.safeError(_Unprintable()), 'unknown');
    expect(
      DiagnosticSanitizer.safeError(
        const FormatException('synthetic-secret', 'synthetic-secret'),
      ),
      'format',
    );
    expect(
      DiagnosticSanitizer.safeError(TimeoutException('synthetic-secret')),
      'timeout',
    );
  });

  test('diagnostic copies do not stringify unknown map keys or values', () {
    final input = <String, dynamic>{
      'nested': {_Unprintable(): _Unprintable()},
      'value': _Unprintable(),
    };
    expect(input.censored().toString(), contains('<redacted>'));
  });

  test(
    'recursive censorship covers KDF aliases without changing RPC input',
    () {
      final input = <String, dynamic>{
        'result': [
          {
            'priv_key': 'secret-1',
            'privKey': 'secret-2',
            'privateKey': 'secret-3',
            'RPCPassword': 'secret-4',
            'nested': [
              {'mnemonic': 'secret-5'},
            ],
          },
        ],
      };
      final output = input.censored();
      for (var i = 1; i <= 5; i++) {
        expect(output.toString(), isNot(contains('secret-$i')));
        expect(input.toString(), contains('secret-$i'));
      }
    },
  );
}
