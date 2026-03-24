import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/custom_erc20_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/erc20_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_task_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/eth_with_tokens_activation_strategy.dart';
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
  });
}
