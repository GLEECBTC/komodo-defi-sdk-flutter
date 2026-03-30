import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('withdraw request serialization', () {
    test('serializes Tendermint fee requests as CosmosGas', () {
      final request = WithdrawInitRequest(
        rpcPass: 'rpc-pass',
        params: WithdrawParameters(
          asset: 'ATOM',
          toAddress: 'cosmos1destination',
          amount: Decimal.parse('0.1'),
          fee: FeeInfo.tendermint(
            coin: 'ATOM',
            amount: Decimal.parse('0.038553'),
            gasLimit: 100000,
          ),
        ),
      );

      final json = request.toJson();
      final params = json['params'] as Map<String, dynamic>;
      final fee = params['fee'] as Map<String, dynamic>;

      expect(fee['type'], equals('CosmosGas'));
      expect(fee['coin'], equals('ATOM'));
      expect(fee['gas_limit'], equals(100000));
      expect(
        (fee['gas_price'] as num).toDouble(),
        closeTo(0.00000038553, 1e-18),
      );
    });

    test('parses SIA-style non-task v2 withdraw response', () {
      final request = WithdrawRequest(
        rpcPass: 'rpc-pass',
        coin: 'SC',
        to: 'recipient',
        amount: Decimal.parse('1'),
      );

      final parsed = request.parse({
        'mmrpc': '2.0',
        'result': {
          'tx_json': {
            'siacoinInputs': <Map<String, dynamic>>[],
            'siacoinOutputs': <Map<String, dynamic>>[],
            'minerFee': '10000000000000000000',
          },
          'tx_hash': '0xabc',
          'from': ['sender'],
          'to': ['recipient'],
          'total_amount': '1.000000000000000000000000',
          'spent_by_me': '1.000000000000000000000000',
          'received_by_me': '0',
          'my_balance_change': '-1.000000000000000000000000',
          'block_height': 1,
          'timestamp': 123456,
          'fee_details': {
            'type': 'Sia',
            'coin': 'SC',
            'policy': 'Fixed',
            'total_amount': '0.000010000000000000000000',
          },
          'coin': 'SC',
          'internal_id': '',
          'transaction_type': 'SiaV2Transaction',
          'memo': null,
        },
        'id': null,
      });

      expect(parsed.status, 'Ok');
      expect(parsed.details, isA<WithdrawResult>());

      final details = parsed.details as WithdrawResult;
      expect(details.coin, 'SC');
      expect(details.txHex, isNull);
      expect(details.txJson, isNotNull);
      expect(details.txHash, '0xabc');
      expect(
        details.fee,
        FeeInfo.sia(
          coin: 'SC',
          amount: Decimal.parse('0.000010000000000000000000'),
          policy: 'Fixed',
        ),
      );
    });
  });
}
