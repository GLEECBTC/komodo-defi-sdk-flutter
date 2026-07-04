import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/custom_erc20_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/erc20_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_task_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_with_tokens_activation_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

class _RecordingApiClient implements ApiClient {
  final List<JsonMap> requests = [];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(request);
    return {
      'mmrpc': '2.0',
      'result': {
        'current_block': 1,
        'wallet_balance': {'wallet_type': 'iguana', 'accounts': <JsonMap>[]},
        'nfts_infos': <String, dynamic>{},
      },
    };
  }
}

void main() {
  group('TRON activation strategy support', () {
    final client = ApiClientMock();
    final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
    final child = Asset.fromJson(_trc20Config(), knownIds: {parent.id});

    test('non-Trezor platform strategy accepts TRX parent assets', () {
      final strategy = EthWithTokensActivationStrategy(
        client,
        const PrivateKeyPolicy.contextPrivKey(),
      );

      expect(strategy.canHandle(parent), isTrue);
      expect(strategy.canHandle(child), isFalse);
    });

    test('Trezor platform strategy accepts TRX parent assets', () {
      final strategy = EthTaskActivationStrategy(
        client,
        const PrivateKeyPolicy.trezor(),
      );

      expect(strategy.canHandle(parent), isTrue);
      expect(strategy.canHandle(child), isFalse);
    });

    test('token strategy accepts configured TRC20 child assets', () {
      final strategy = Erc20ActivationStrategy(
        client,
        const PrivateKeyPolicy.contextPrivKey(),
      );

      expect(strategy.canHandle(child), isTrue);
    });

    test('custom token strategy accepts custom TRC20 child assets', () {
      final customChild = child.copyWith(
        protocol: (child.protocol as Trc20Protocol).copyWith(
          isCustomToken: true,
        ),
      );
      final strategy = CustomErc20ActivationStrategy(client);

      expect(strategy.canHandle(customChild), isTrue);
    });

    test(
      'batch activation sends TRX gasless provider with TRC20 token config',
      () async {
        const provider = TronGaslessProviderConfig(
          baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
          service: GaslessServiceKomodoProxy(),
          serviceProvider: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
        );
        final recordingClient = _RecordingApiClient();
        final strategy = EthWithTokensActivationStrategy(
          recordingClient,
          const PrivateKeyPolicy.contextPrivKey(),
          tronGaslessProvider: provider,
        );

        await strategy.activate(parent, [child]).drain<void>();

        final request = recordingClient.requests.singleWhere(
          (request) => request['method'] == 'enable_eth_with_tokens',
        );
        final params = request.value<JsonMap>('params');
        expect(params['ticker'], 'TRX');
        expect(params['tron_gasless_provider'], {
          'base_url': 'https://quicknode.gleec.com/gasfree/tron',
          'service': 'komodo_proxy',
          'service_provider': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
          'request_timeout_ms': 15000,
          'status_poll_interval_ms': 3000,
        });
        expect(params['erc20_tokens_requests'], [
          {
            'ticker': 'USDT-TRC20',
            'required_confirmations': 3,
            'gasless': {'enabled': true},
          },
        ]);
      },
    );

    // Regression guard for the `NoSuchCoin USDT-TRC20` activation race: when the
    // TRX platform is already active (e.g. a concurrent standalone TRX
    // activation won the platform), the token is activated individually via
    // `enable_erc20`. That standalone path MUST still carry the gasless config
    // so the gas-free token is registered in KDF — otherwise the join-branch
    // recovery would enable USDT-TRC20 as a plain (non-gasless) token, or the
    // token would be dropped entirely and later fail withdraw with NoSuchCoin.
    test(
      'standalone TRC20 activation carries the gasless config (recovery path '
      'when the TRX platform is already active)',
      () async {
        const provider = TronGaslessProviderConfig(
          baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
          service: GaslessServiceKomodoProxy(),
          serviceProvider: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
        );
        final recordingClient = _RecordingApiClient();
        final strategy = Erc20ActivationStrategy(
          recordingClient,
          const PrivateKeyPolicy.contextPrivKey(),
          tronGaslessProvider: provider,
        );

        await strategy.activate(child).drain<void>();

        final request = recordingClient.requests.singleWhere(
          (request) => request['method'] == 'enable_erc20',
        );
        final params = request.value<JsonMap>('params');
        expect(params['ticker'], 'USDT-TRC20');
        final activationParams = params.value<JsonMap>('activation_params');
        expect(activationParams['gasless'], {'enabled': true});
      },
    );

    test(
      'standalone TRC20 activation omits gasless when no provider is configured',
      () async {
        final recordingClient = _RecordingApiClient();
        final strategy = Erc20ActivationStrategy(
          recordingClient,
          const PrivateKeyPolicy.contextPrivKey(),
        );

        await strategy.activate(child).drain<void>();

        final request = recordingClient.requests.singleWhere(
          (request) => request['method'] == 'enable_erc20',
        );
        final activationParams = request
            .value<JsonMap>('params')
            .value<JsonMap>('activation_params');
        expect(activationParams.containsKey('gasless'), isFalse);
      },
    );
  });
}
