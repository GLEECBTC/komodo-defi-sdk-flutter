import 'dart:collection';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/zhtlc_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _QueueApiClient implements ApiClient {
  _QueueApiClient({required Map<String, List<JsonMap>> responsesByMethod})
    : _responsesByMethod = {
        for (final entry in responsesByMethod.entries)
          entry.key: Queue<JsonMap>.from(entry.value),
      };

  final Map<String, Queue<JsonMap>> _responsesByMethod;
  final List<JsonMap> requests = <JsonMap>[];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(Map<String, dynamic>.from(request));
    final method = request['method'] as String?;
    if (method == null || method.isEmpty) {
      throw StateError('Missing RPC method in request: $request');
    }

    final queue = _responsesByMethod[method];
    if (queue == null || queue.isEmpty) {
      throw StateError('No queued response for method $method');
    }

    return queue.removeFirst();
  }
}

Asset _createZhtlcAsset() {
  final protocol = ZhtlcProtocol.fromJson(const {
    'type': 'ZHTLC',
    'light_wallet_d_servers': ['https://lightd.example'],
    'electrum_servers': [
      {'url': 'electrum.example:50002', 'protocol': 'SSL'},
    ],
  });

  return Asset(
    id: AssetId(
      id: 'ARRR',
      name: 'Pirate Chain',
      symbol: AssetSymbol(assetConfigId: 'ARRR'),
      chainId: AssetChainId(chainId: 1),
      derivationPath: null,
      subClass: CoinSubClass.zhtlc,
    ),
    protocol: protocol,
    isWalletOnly: false,
    signMessagePrefix: null,
  );
}

void main() {
  group('ZhtlcActivationStrategy', () {
    test('applies one-shot sync params once and omits sync_params '
        'on subsequent activations', () async {
      final walletId = WalletId.fromName(
        'Test Wallet',
        const AuthOptions(derivationMethod: DerivationMethod.iguana),
      );
      final configService = ActivationConfigService(
        JsonActivationConfigRepository(InMemoryKeyValueStore()),
        walletIdResolver: () async => walletId,
      );
      final asset = _createZhtlcAsset();

      await configService.saveZhtlcConfig(
        asset.id,
        ZhtlcUserConfig(
          zcashParamsPath: '/zcash-params',
          recurringSyncPolicy: ZhtlcRecurringSyncPolicy.recentTransactions(),
          syncParams: ZhtlcSyncParams.height(123456),
        ),
      );

      final client = _QueueApiClient(
        responsesByMethod: {
          'task::enable_z_coin::init': [
            {
              'mmrpc': '2.0',
              'result': {'task_id': 1},
            },
            {
              'mmrpc': '2.0',
              'result': {'task_id': 2},
            },
          ],
          'task::enable_z_coin::status': [
            {
              'mmrpc': '2.0',
              'result': {'status': 'Ok', 'details': 'done'},
            },
            {
              'mmrpc': '2.0',
              'result': {'status': 'Ok', 'details': 'done'},
            },
          ],
        },
      );
      final strategy = ZhtlcActivationStrategy(
        client,
        const PrivateKeyPolicy.contextPrivKey(),
        configService,
        pollingInterval: const Duration(milliseconds: 1),
      );

      await strategy.activate(asset).toList();
      await strategy.activate(asset).toList();

      final initRequests = client.requests
          .where((request) => request['method'] == 'task::enable_z_coin::init')
          .toList(growable: false);
      expect(initRequests, hasLength(2));

      final firstRpcData =
          ((initRequests.first['params']
                      as Map<String, dynamic>)['activation_params']
                  as Map<String, dynamic>)['mode']
              as Map<String, dynamic>;
      final firstModeRpcData = firstRpcData['rpc_data'] as Map<String, dynamic>;
      expect(firstModeRpcData['sync_params'], <String, dynamic>{
        'height': 123456,
      });

      final secondRpcData =
          ((initRequests.last['params']
                      as Map<String, dynamic>)['activation_params']
                  as Map<String, dynamic>)['mode']
              as Map<String, dynamic>;
      final secondModeRpcData =
          secondRpcData['rpc_data'] as Map<String, dynamic>;
      expect(secondModeRpcData.containsKey('sync_params'), isFalse);

      final savedConfig = await configService.getSavedZhtlc(asset.id);
      expect(savedConfig, isNotNull);
      expect(savedConfig?.syncParams, isNull);
      expect(
        savedConfig?.recurringSyncPolicy?.mode,
        ZhtlcRecurringSyncMode.recentTransactions,
      );

      final remainingOneShot = await configService.takeOneShotSyncParams(
        asset.id,
      );
      expect(remainingOneShot, isNull);
    });
  });
}
