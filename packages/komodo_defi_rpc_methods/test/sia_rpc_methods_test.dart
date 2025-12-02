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
      final p = (json['params'] as Map)['activation_params'] as Map;
      final clientConf = p['client_conf'] as Map;
      expect(clientConf['server_url'], 'https://api.siascan.com/wallet/api');
      expect(p['tx_history'], true);
      expect(p['required_confirmations'], 1);
    });

    test('SiaWithdrawResponse parses nullable fee_details safely', () {
      final response = {
        'mmrpc': '2.0',
        'result': {
          'status': 'Ok',
          'spent_by_me': '0',
          'received_by_me': '100',
          'my_balance_change': '100',
          // fee_details intentionally omitted
        },
      };
      final parsed = SiaWithdrawResponse.parse(JsonMap.of(response));
      expect(parsed.status, 'Ok');
      expect(parsed.feeDetails, isNull);
    });
  });
}
