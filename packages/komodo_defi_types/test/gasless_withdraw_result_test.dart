import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _requestId = '123e4567-e89b-42d3-a456-426614174000';
const _fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _relayPayload() => {
  'relay_type': 'tron_gasfree',
  'request_id': _requestId,
  'chain_id': '728126428',
  'coin': 'USDT-TRC20',
  'hd_from': {'account_id': 0, 'chain': 'external', 'address_id': 0},
  'from_address': 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
  'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
  'verifying_contract': 'THQGuFzL87ZqhxkgqYEryRAd7gqFqL5rdc',
  'signed_authorization': {
    'token': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    'service_provider': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
    'user': 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
    'receiver': 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
    'value': '5000000',
    'max_fee': '5000000',
    'deadline': '1999999999',
    'version': '1',
    'nonce': '9',
    'sig': 'redacted-in-production-records',
  },
  'authorization_fingerprint': _fingerprint,
  'created_at': '2026-07-10T12:00:00Z',
};

Map<String, dynamic> _withdrawJson({required bool nested}) {
  final payload = _relayPayload();
  return {
    if (nested) 'tx_json': payload else ...payload,
    'coin': 'USDT-TRC20',
    'my_balance_change': '-7',
    'received_by_me': '0',
    'spent_by_me': '7',
    'total_amount': '5',
    'fee_details': {
      'type': 'TronGasless',
      'coin': 'USDT-TRC20',
      'fee_method': 'gasless',
      'provider_name': 'GasFree',
      'provider_address': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
      'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      'transfer_fee': '2',
      'total_token_fee': '2',
      'signed_max_fee': '5',
      'authorization_deadline': '1999999999',
      'request_id': _requestId,
      'authorization_fingerprint': _fingerprint,
    },
  };
}

void main() {
  for (final nested in [false, true]) {
    test('parses ${nested ? 'nested' : 'top-level'} GasFree relay payload', () {
      final result = WithdrawResult.fromJson(_withdrawJson(nested: nested));

      expect(result.txHash, isNull);
      expect(result.txHex, isNull);
      expect(result.txJson?['request_id'], _requestId);
      expect(result.from.single, 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC');
      expect(result.to.single, 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC');
      expect(result.balanceChanges.totalAmount, Decimal.parse('5'));

      final authorization = result.gaslessAuthorization;
      expect(authorization, isNotNull);
      expect(authorization?.signedMaxFee, Decimal.parse('5'));
      expect(authorization?.deadline, 1999999999);
      expect(authorization?.fingerprint, _fingerprint);
      expect(authorization?.provider, 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E');
    });
  }

  test('rejects a relay payload missing its authorization fingerprint', () {
    final json = _withdrawJson(nested: true);
    final txJson = json['tx_json']! as Map<String, dynamic>;
    txJson.remove('authorization_fingerprint');

    expect(() => WithdrawResult.fromJson(json), throwsFormatException);
  });

  test('accepts a literal legacy PR #9 relay payload', () {
    final json = _withdrawJson(nested: true);
    final txJson = json['tx_json']! as Map<String, dynamic>
      ..remove('request_id')
      ..remove('authorization_fingerprint');

    final result = WithdrawResult.fromJson(json);

    expect(result.txJson, txJson);
    expect(result.txJson, isNot(contains('request_id')));
    expect(result.txJson, isNot(contains('authorization_fingerprint')));
  });
}
