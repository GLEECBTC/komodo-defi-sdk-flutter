import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/base_strategies/activation_strategy_factory.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/erc20_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_task_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_with_tokens_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart'
    show ActivationConfigService;
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

const _swapContract = '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D';
const _kmdGrc20Contract = '0x3341acA97C71E12A80D1e01D8c86bE93ba669752';

// GLEEC and KMD-GRC20 as coins_config.json lists them, plus the trezor_coin
// that Trezor support requires.
Map<String, dynamic> _gleecConfig() => {
  'coin': 'GLEEC',
  'type': 'GRC-20',
  'name': 'Gleec',
  'fname': 'Gleec',
  'mm2': 1,
  'chain_id': 11169,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 11169},
  },
  'derivation_path': "m/44'/60'",
  'trezor_coin': 'Gleec',
  'swap_contract_address': _swapContract,
  'fallback_swap_contract': _swapContract,
  'nodes': [
    {'url': 'https://evm-rpc.gleec.com', 'ws_url': 'wss://evm-ws.gleec.com'},
  ],
};

Map<String, dynamic> _kmdGrc20Config() => {
  'coin': 'KMD-GRC20',
  'type': 'GRC-20',
  'name': 'Komodo',
  'fname': 'Komodo',
  'mm2': 1,
  'chain_id': 11169,
  'decimals': 18,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ERC20',
    'protocol_data': {
      'platform': 'GLEEC',
      'contract_address': _kmdGrc20Contract,
    },
  },
  'derivation_path': "m/44'/60'",
  'trezor_coin': 'Komodo (grc20)',
  'contract_address': _kmdGrc20Contract,
  'parent_coin': 'GLEEC',
  'swap_contract_address': _swapContract,
  'fallback_swap_contract': _swapContract,
  'nodes': [
    {'url': 'https://evm-rpc.gleec.com', 'ws_url': 'wss://evm-ws.gleec.com'},
  ],
};

class _RecordingApiClient implements ApiClient {
  final List<JsonMap> requests = [];

  List<String> get methods => [
    for (final request in requests) request['method'] as String,
  ];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(request);
    return switch (request['method']) {
      'task::enable_eth::init' => {
        'mmrpc': '2.0',
        'result': {'task_id': 7},
      },
      'task::enable_eth::status' => {
        'mmrpc': '2.0',
        'result': {'status': 'Ok', 'details': ''},
      },
      'enable_erc20' => {
        'mmrpc': '2.0',
        'result': {
          'balances': <String, dynamic>{},
          'platform_coin': 'GLEEC',
          'token_contract_address': _kmdGrc20Contract,
          'required_confirmations': 3,
        },
      },
      final method => throw StateError('Unexpected RPC $method'),
    };
  }
}

class _MockConfigService extends Mock implements ActivationConfigService {}

class _MockActivatedAssetsCache extends Mock implements ActivatedAssetsCache {}

void main() {
  group('Trezor GRC-20 activation', () {
    const trezor = PrivateKeyPolicy.trezor();
    final gleec = Asset.fromJson(_gleecConfig(), knownIds: const {});
    final kmdGrc20 = Asset.fromJson(_kmdGrc20Config(), knownIds: {gleec.id});

    late _RecordingApiClient client;
    late _MockActivatedAssetsCache cache;

    setUp(() {
      client = _RecordingApiClient();
      cache = _MockActivatedAssetsCache();
    });

    void stubActive(Set<AssetId> ids) {
      when(() => cache.getActivatedAssetIds()).thenAnswer((_) async => ids);
    }

    Future<List<ActivationProgress>> activate(Asset asset, List<Asset> kids) =>
        ActivationStrategyFactory.createStrategy(
          client,
          trezor,
          _MockConfigService(),
          cache,
        ).activate(asset, kids).toList();

    test('activates GLEEC and its tokens in one Trezor task', () async {
      stubActive({});

      final progress = await activate(gleec, [kmdGrc20]);

      expect(progress.last.isSuccess, isTrue);
      expect(client.methods, [
        'task::enable_eth::init',
        'task::enable_eth::status',
      ]);
      final params = client.requests.first.value<JsonMap>('params');
      expect(params['ticker'], 'GLEEC');
      expect(params['priv_key_policy'], trezor.toJson());
      expect(params['erc20_tokens_requests'], [
        {'ticker': 'KMD-GRC20', 'required_confirmations': 3},
      ]);
    });

    test('adds a GRC-20 token to an active GLEEC via enable_erc20', () async {
      stubActive({gleec.id});

      final progress = await activate(gleec, [kmdGrc20]);

      expect(progress.last.isSuccess, isTrue);
      expect(client.methods, ['enable_erc20']);
      final params = client.requests.single.value<JsonMap>('params');
      expect(params['ticker'], 'KMD-GRC20');
    });

    // CompositeAssetActivator takes the first match, so these three must not
    // overlap; CustomErc20ActivationStrategy matches both and stays last.
    test(
      'splits GLEEC and KMD-GRC20 between platform and token strategies',
      () {
        for (final policy in const [
          trezor,
          PrivateKeyPolicy.contextPrivKey(),
        ]) {
          final platformTask = EthTaskActivationStrategy(client, policy);
          final platformWithTokens = EthWithTokensActivationStrategy(
            client,
            policy,
          );
          final token = Erc20ActivationStrategy(client, policy);
          List<Object> takers(Asset asset) => [
            platformTask,
            platformWithTokens,
            token,
          ].where((strategy) => strategy.canHandle(asset)).toList();

          expect(takers(gleec), [
            if (policy == trezor) platformTask else platformWithTokens,
          ], reason: policy.pascalCaseName);
          expect(takers(kmdGrc20), [token], reason: policy.pascalCaseName);
        }
      },
    );
  });
}
