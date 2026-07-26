import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _relayPayload() => {
  'relay_type': 'tron_gasfree',
  'chain_id': '728126428',
  'coin': 'USDT-TRC20',
  'hd_from': {'account_id': 0, 'chain': 'External', 'address_id': 0},
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
    'sig': List.filled(65, '11').join(),
  },
  'created_at': '2026-07-10T12:00:00Z',
};

Map<String, dynamic> _withdrawJson() {
  final payload = _relayPayload();
  return {
    ...payload,
    'coin': 'USDT-TRC20',
    'from': ['TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC'],
    'to': ['TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC'],
    'my_balance_change': '-7',
    'received_by_me': '0',
    'spent_by_me': '7',
    'total_amount': '5',
    'block_height': 0,
    // KDF stamps preview creation time here; it is not transfer finality.
    'timestamp': 1783684800,
    'fee_details': {
      'type': 'TronGasless',
      'coin': 'USDT-TRC20',
      'fee_method': 'gasless',
      'provider_name': 'gasfree',
      'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      'transfer_fee': '2',
      'total_token_fee': '2',
      'signed_max_fee': '5',
      'trace_id': null,
    },
    'internal_id': '',
    'transaction_type': 'StandardTransfer',
    'memo': null,
  };
}

void main() {
  test('parses the flattened top-level GasFree relay payload', () {
    final result = WithdrawResult.fromJson(_withdrawJson());

    expect(result.txHash, isNull);
    expect(result.txHex, isNull);
    expect(result.txJson, _relayPayload());
    expect(result.from.single, 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC');
    expect(result.to.single, 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC');
    expect(result.balanceChanges.totalAmount, Decimal.parse('5'));

    final relay = result.gaslessRelayPayload;
    expect(relay, isNotNull);
    expect(relay?.relayType, 'tron_gasfree');
    expect(relay?.signedAuthorization.value, '5000000');
    expect(relay?.signedAuthorization.maxFee, '5000000');
    expect(relay?.signedAuthorization.deadline, BigInt.from(1999999999));
    expect(
      relay?.signedAuthorization.serviceProvider,
      'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
    );

    final domain = WithdrawalResult.fromWithdrawResult(result);
    expect(domain.txHash, isNull);
    expect(domain.confirmationBlockHeight, isNull);
    expect(domain.confirmedAt, isNull);
    expect(domain.gaslessFinalFee, isNull);
    expect(domain.gaslessTraceId, isNull);

    final serialized = result.toJson();
    expect(serialized['relay_type'], 'tron_gasfree');
    expect(serialized, isNot(contains('tx_json')));
    expect(serialized['from'], ['TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC']);
    expect(serialized['to'], ['TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC']);
    expect(serialized['block_height'], 0);
    expect(serialized['timestamp'], 1783684800);
    expect(serialized['internal_id'], '');
    expect(serialized['transaction_type'], 'StandardTransfer');
    expect(serialized, containsPair('memo', null));
    expect(
      serialized['signed_authorization'],
      _relayPayload()['signed_authorization'],
    );
  });

  test('rejects a nested GasFree relay compatibility shape', () {
    final json = _withdrawJson();
    final relay = {
      for (final key in _relayPayload().keys) key: json.remove(key),
    };
    json['tx_json'] = relay;

    expect(() => WithdrawResult.fromJson(json), throwsFormatException);
  });

  test('rejects undocumented top-level relay keys', () {
    final json = _withdrawJson()..['request_id'] = 'must-not-be-serialized';

    expect(() => WithdrawResult.fromJson(json), throwsFormatException);
  });

  test('rejects arbitrary undocumented top-level provider echoes', () {
    final json = _withdrawJson()..['provider_address'] = 'must-not-be-accepted';

    expect(() => WithdrawResult.fromJson(json), throwsFormatException);
  });

  for (final field in const [
    'from',
    'to',
    'block_height',
    'timestamp',
    'internal_id',
    'transaction_type',
    'memo',
  ]) {
    test('rejects a GasFree result missing documented $field', () {
      final json = _withdrawJson()..remove(field);

      expect(() => WithdrawResult.fromJson(json), throwsFormatException);
    });
  }

  test('rejects undocumented signed authorization keys', () {
    final json = _withdrawJson();
    final authorization = json['signed_authorization']! as Map<String, dynamic>;
    authorization['fingerprint'] = 'must-not-be-serialized';

    expect(() => WithdrawResult.fromJson(json), throwsFormatException);
  });

  test('requires an RFC3339 relay creation timestamp', () {
    final json = _withdrawJson()..['created_at'] = '2026-07-10';

    expect(() => WithdrawResult.fromJson(json), throwsFormatException);
  });

  test('accepts a signed deadline beyond year 9999', () {
    final json = _withdrawJson();
    final authorization = json['signed_authorization']! as Map<String, dynamic>;
    authorization['deadline'] = '253402300800';

    final result = WithdrawResult.fromJson(json);

    expect(
      result.gaslessRelayPayload?.signedAuthorization.deadline,
      BigInt.from(253402300800),
    );
    expect(
      result.gaslessRelayPayload?.signedAuthorization.expiresAt?.year,
      10000,
    );
  });

  test('preserves the full unsigned 256-bit deadline domain exactly', () {
    final json = _withdrawJson();
    final authorization = json['signed_authorization']! as Map<String, dynamic>;
    final maximum = (BigInt.one << 256) - BigInt.one;
    authorization['deadline'] = maximum.toString();

    final result = WithdrawResult.fromJson(json);
    final signed = result.gaslessRelayPayload!.signedAuthorization;

    expect(signed.deadline, maximum);
    expect(signed.toJson()['deadline'], maximum.toString());
    expect(signed.expiresAt, isNull);
    expect(signed.isExpiredAt(DateTime.now().toUtc()), isFalse);
  });

  test('rejects a deadline outside the unsigned 256-bit domain', () {
    final json = _withdrawJson();
    final authorization = json['signed_authorization']! as Map<String, dynamic>;
    authorization['deadline'] = (BigInt.one << 256).toString();

    expect(() => WithdrawResult.fromJson(json), throwsFormatException);
  });

  test('rejects non-decimal signed deadline strings', () {
    for (final malformed in ['+1', '0x10']) {
      final json = _withdrawJson();
      final authorization =
          json['signed_authorization']! as Map<String, dynamic>;
      authorization['deadline'] = malformed;

      expect(() => WithdrawResult.fromJson(json), throwsFormatException);
    }
  });

  test('rejects malformed signed U256 values and signatures', () {
    for (final field in ['value', 'max_fee', 'nonce']) {
      final json = _withdrawJson();
      final authorization =
          json['signed_authorization']! as Map<String, dynamic>;
      authorization[field] = '0x10';

      expect(() => WithdrawResult.fromJson(json), throwsFormatException);
    }

    for (final signature in ['0x${List.filled(65, '11').join()}', '11']) {
      final json = _withdrawJson();
      final authorization =
          json['signed_authorization']! as Map<String, dynamic>;
      authorization['sig'] = signature;

      expect(() => WithdrawResult.fromJson(json), throwsFormatException);
    }
  });

  test('GasFree relay owns an immutable hd_from snapshot', () {
    final input = _relayPayload();
    final inputHdFrom = input['hd_from']! as Map<String, dynamic>;
    final relay = TronGasfreeRelayPayload.fromJson(input);

    inputHdFrom['account_id'] = 99;
    expect(relay.hdFrom?['account_id'], 0);
    expect(() => relay.hdFrom!['account_id'] = 7, throwsUnsupportedError);

    final serialized = relay.toJson();
    final serializedHdFrom = serialized['hd_from']! as Map<String, dynamic>;
    serializedHdFrom['account_id'] = 42;

    expect(relay.toJson()['hd_from'], {
      'account_id': 0,
      'chain': 'External',
      'address_id': 0,
    });
  });
}
