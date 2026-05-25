import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/custom_erc20_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/erc20_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_task_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_with_tokens_activation_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _xdaiConfig() => {
  'coin': 'XDAI',
  'type': 'Gnosis',
  'name': 'xDAI',
  'fname': 'Gnosis',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 100,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 100},
  },
  'swap_contract_address': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'fallback_swap_contract': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'nodes': [
    {'url': 'https://rpc.gnosischain.com'},
  ],
};

Map<String, dynamic> _gnosisTokenConfig({
  required String coin,
  required String name,
  required String contractAddress,
  required int decimals,
}) => {
  'coin': coin,
  'type': 'Gnosis',
  'name': name,
  'fname': name,
  'wallet_only': true,
  'mm2': 1,
  'chain_id': 100,
  'decimals': decimals,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {
      'platform': 'XDAI',
      'contract_address': contractAddress,
      'decimals': decimals,
    },
  },
  'contract_address': contractAddress,
  'parent_coin': 'XDAI',
  'swap_contract_address': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'fallback_swap_contract': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'nodes': [
    {'url': 'https://rpc.gnosischain.com'},
  ],
};

const _gnosisTokenConfigs = [
  (
    coin: 'EURE-GNO',
    name: 'Monerium EUR emoney',
    contractAddress: '0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430',
    decimals: 18,
  ),
  (
    coin: 'GBPE-GNO',
    name: 'Monerium GBP emoney',
    contractAddress: '0x8E34bfEC4f6Eb781f9743D9b4af99CD23F9b7053',
    decimals: 18,
  ),
  (
    coin: 'GNO-GNO',
    name: 'Gnosis Token on Gnosis',
    contractAddress: '0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb',
    decimals: 18,
  ),
  (
    coin: 'USDC-GNO',
    name: 'USD Coin',
    contractAddress: '0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0',
    decimals: 6,
  ),
];

void main() {
  group('Gnosis activation strategy support', () {
    final client = ApiClientMock();
    final parent = Asset.fromJson(_xdaiConfig(), knownIds: const {});
    final children = [
      for (final token in _gnosisTokenConfigs)
        Asset.fromJson(
          _gnosisTokenConfig(
            coin: token.coin,
            name: token.name,
            contractAddress: token.contractAddress,
            decimals: token.decimals,
          ),
          knownIds: {parent.id},
        ),
    ];
    final child = children.first;

    test('non-Trezor platform strategy accepts XDAI parent assets', () {
      final strategy = EthWithTokensActivationStrategy(
        client,
        const PrivateKeyPolicy.contextPrivKey(),
      );

      expect(strategy.canHandle(parent), isTrue);
      for (final token in children) {
        expect(strategy.canHandle(token), isFalse, reason: token.id.id);
      }
    });

    test('Trezor platform strategy accepts XDAI parent assets', () {
      final strategy = EthTaskActivationStrategy(
        client,
        const PrivateKeyPolicy.trezor(),
      );

      expect(strategy.canHandle(parent), isTrue);
      for (final token in children) {
        expect(strategy.canHandle(token), isFalse, reason: token.id.id);
      }
    });

    test('token strategy accepts configured Gnosis ERC-20 child assets', () {
      final strategy = Erc20ActivationStrategy(
        client,
        const PrivateKeyPolicy.contextPrivKey(),
      );

      for (final token in children) {
        expect(strategy.canHandle(token), isTrue, reason: token.id.id);
      }
    });

    test('custom token strategy accepts custom Gnosis ERC-20 child assets', () {
      final customChild = child.copyWith(
        protocol: (child.protocol as Erc20Protocol).copyWith(
          isCustomToken: true,
        ),
      );
      final strategy = CustomErc20ActivationStrategy(client);

      expect(strategy.canHandle(customChild), isTrue);
    });
  });
}
