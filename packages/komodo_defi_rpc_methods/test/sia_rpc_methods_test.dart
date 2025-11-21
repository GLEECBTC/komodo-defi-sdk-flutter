import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

void main() {
  group('SIA RPC', () {
    test('TaskEnableSiaInit toJson matches expected shape', () {
      const params = SiaActivationParams(
        serverUrl: 'https://api.siascan.com/wallet/api',
        requiredConfirmations: 1,
      );
      final req = TaskEnableSiaInit(
        rpcPass: 'pass',
        ticker: 'SC',
        params: params,
      );
      final json = req.toJson();
      expect(json['method'], 'task::enable_sia::init');
      final activationParams =
          (json['params'] as Map)['activation_params'] as Map;
      final clientConf = activationParams['client_conf'] as Map;
      expect(clientConf['server_url'], 'https://api.siascan.com/wallet/api');
      expect(activationParams['tx_history'], true);
      expect(activationParams['required_confirmations'], 1);
    });

    test('SiaWithdrawResponse parses full SIA withdraw shape', () {
      final response = {
        'mmrpc': '2.0',
        'result': {
          'tx_json': <String, dynamic>{'siacoinOutputs': <dynamic>[]},
          'tx_hash': 'hash',
          'from': ['from_addr'],
          'to': ['to_addr'],
          'total_amount': '10',
          'spent_by_me': '0',
          'received_by_me': '100',
          'my_balance_change': '100',
          'block_height': 1,
          'timestamp': 123456,
          'fee_details': {
            'type': 'Sia',
            'coin': 'SC',
            'policy': 'Fixed',
            'total_amount': '0.1',
          },
          'coin': 'SC',
          'internal_id': '',
          'transaction_type': 'SiaV2Transaction',
          'memo': null,
        },
      };
      final parsed = SiaWithdrawResponse.parse(JsonMap.of(response));
      expect(parsed.txHash, 'hash');
      expect(parsed.from, <String>['from_addr']);
      expect(parsed.to, <String>['to_addr']);
      expect(parsed.totalAmount, '10');
      expect(parsed.feeDetails.coin, 'SC');
    });
  });
}
