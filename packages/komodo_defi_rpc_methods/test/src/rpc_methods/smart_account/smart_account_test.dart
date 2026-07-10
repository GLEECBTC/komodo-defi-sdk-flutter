import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

const _safe = '0x1111111111111111111111111111111111111111';
const _delay = '0x2222222222222222222222222222222222222222';
const _token = '0x3333333333333333333333333333333333333333';
const _recipient = '0x4444444444444444444444444444444444444444';
const _bouncer = '0x5555555555555555555555555555555555555555';
const _allowanceKey =
    'fe687fc128d1915040376d20ccb1bf40d838ddd82bf9b0ba3da683cc2a251623';

void main() {
  const codec = SmartAccountIntentCodec();

  group('SmartAccountIntentCodec', () {
    test('normalizes Account Kit domain and decodes ERC-20 withdrawal', () {
      final input = _typedData(
        _outer(
          target: _token,
          inner:
              'a9059cbb${_addressWord(_recipient)}${_word(BigInt.from(1250))}',
        ),
      );
      final prepared = codec.prepare(
        input,
        safeAddress: _safe,
        requested: SmartAccountRequestedAction.withdrawal(
          assetContract: _token,
          recipient: _recipient,
          amount: BigInt.from(1250),
        ),
      );

      expect(prepared.kind, SmartAccountIntentKind.withdrawal);
      expect(prepared.chainId, BigInt.from(100));
      expect(prepared.safeAddress, _safe);
      expect(prepared.delayModule, _delay);
      expect(prepared.target, _token);
      expect(prepared.recipient, _recipient);
      expect(prepared.amount, BigInt.from(1250));
      expect(
        (prepared.typedData['types'] as Map<String, dynamic>),
        contains('EIP712Domain'),
      );
    });

    test('decodes canonical daily-limit payload and rejects request drift', () {
      final limit = BigInt.from(2500);
      final inner =
          'a8ec43ee$_allowanceKey'
          '${_word(limit)}${_word(limit)}${_word(limit)}'
          '${_word(BigInt.from(86400))}${_word(BigInt.zero)}';
      final prepared = codec.prepare(
        _typedData(_outer(target: _bouncer, inner: inner)),
        safeAddress: _safe,
      );

      expect(prepared.kind, SmartAccountIntentKind.dailyLimit);
      expect(prepared.amount, limit);
      expect(prepared.periodSeconds, 86400);
      expect(
        () => prepared.requireMatches(
          SmartAccountRequestedAction.dailyLimit(
            bouncer: _bouncer,
            amount: BigInt.from(2501),
            periodSeconds: 86400,
          ),
        ),
        throwsA(isA<SmartAccountIntentException>()),
      );
    });

    test('payload digest is stable and typed data is defensively copied', () {
      final input = _typedData(
        _outer(
          target: _token,
          inner: 'a9059cbb${_addressWord(_recipient)}${_word(BigInt.one)}',
        ),
      );
      final first = codec.prepare(input, safeAddress: _safe);
      final second = codec.prepare(input, safeAddress: _safe);
      first.typedData['primaryType'] = 'Tampered';

      expect(first.payloadDigest, second.payloadDigest);
      expect(first.typedData['primaryType'], 'ModuleTx');
      expect(
        SignSmartAccountTypedDataRequest(
          rpcPass: 'pass',
          coin: 'GNO',
          intent: first,
        ).toJson()['params'],
        containsPair('typed_data', isA<Map<String, dynamic>>()),
      );
    });
  });
}

Map<String, dynamic> _typedData(String data) => {
  'primaryType': 'ModuleTx',
  'domain': {'chainId': 100, 'verifyingContract': _delay},
  'types': {
    'ModuleTx': [
      {'name': 'data', 'type': 'bytes'},
      {'name': 'salt', 'type': 'bytes32'},
    ],
  },
  'message': {'data': data, 'salt': '0x${_repeat('11', 32)}'},
};

String _outer({required String target, required String inner}) {
  final byteLength = inner.length ~/ 2;
  final padding = _repeat('00', (32 - (byteLength % 32)) % 32);
  return '0x468721a7${_addressWord(target)}${_word(BigInt.zero)}'
      '${_word(BigInt.from(128))}${_word(BigInt.zero)}'
      '${_word(BigInt.from(byteLength))}$inner$padding';
}

String _addressWord(String address) => address.substring(2).padLeft(64, '0');

String _word(BigInt value) => value.toRadixString(16).padLeft(64, '0');

String _repeat(String value, int count) => List.filled(count, value).join();
