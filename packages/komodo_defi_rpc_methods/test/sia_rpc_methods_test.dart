import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

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

    test('TaskEnableSiaStatus parses object details', () {
      final response = TaskEnableSiaStatus(taskId: 1).parse({
        'mmrpc': '2.0',
        'result': {
          'status': 'Ok',
          'details': {'ticker': 'SC', 'current_block': 100},
        },
        'id': null,
      });

      expect(response.status, 'Ok');
      expect(response.isCompleted, isTrue);
      expect(response.details, isA<Map<String, dynamic>>());
    });

    test('TaskEnableSiaCancel parses success result', () {
      final response = TaskEnableSiaCancel(
        taskId: 1,
      ).parse({'mmrpc': '2.0', 'result': 'success', 'id': null});

      expect(response.result, 'success');
    });
  });
}
