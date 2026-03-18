import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('TRON RPC request serialization', () {
    test('enable_eth_with_tokens serializes TRX without swap contracts', () {
      final request = EnableEthWithTokensRequest(
        rpcPass: 'rpc-pass',
        ticker: 'TRX',
        activationParams: TrxWithTokensActivationParams(
          nodes: [EvmNode(url: 'https://api.trongrid.io')],
          tokenRequests: [TokensRequest(ticker: 'USDT-TRC20')],
          txHistory: true,
          mm2: 1,
          privKeyPolicy: const PrivateKeyPolicy.contextPrivKey(),
        ),
      );

      final json = request.toJson();
      final params = json['params'] as Map<String, dynamic>;

      expect(params['ticker'], 'TRX');
      expect(params['mm2'], 1);
      expect(params['nodes'], [
        {'url': 'https://api.trongrid.io', 'gui_auth': false},
      ]);
      expect(params['erc20_tokens_requests'], [
        {'ticker': 'USDT-TRC20', 'required_confirmations': 3},
      ]);
      expect(params['tx_history'], isTrue);
      expect(params.containsKey('swap_contract_address'), isFalse);
      expect(params.containsKey('fallback_swap_contract'), isFalse);
    });

    test('task::enable_eth::init serializes TRX params', () {
      final request = TaskEnableEthInit(
        rpcPass: 'rpc-pass',
        ticker: 'TRX',
        params: TrxWithTokensActivationParams(
          nodes: [EvmNode(url: 'https://api.trongrid.io')],
          tokenRequests: const [],
          txHistory: false,
          privKeyPolicy: const PrivateKeyPolicy.trezor(),
        ),
      );

      final json = request.toJson();
      final params = json['params'] as Map<String, dynamic>;

      expect(json['method'], 'task::enable_eth::init');
      expect(params['ticker'], 'TRX');
      expect(params['nodes'], [
        {'url': 'https://api.trongrid.io', 'gui_auth': false},
      ]);
      expect(params.containsKey('swap_contract_address'), isFalse);
      expect(
        params['priv_key_policy'],
        equals(const PrivateKeyPolicy.trezor().toJson()),
      );
    });

    test('enable_erc20 custom token request supports TRC20 protocol types', () {
      final request = EnableCustomErc20TokenRequest(
        rpcPass: 'rpc-pass',
        ticker: 'USDT-TRC20',
        activationParams: Trc20ActivationParams(
          nodes: [EvmNode(url: 'https://api.trongrid.io')],
          privKeyPolicy: const PrivateKeyPolicy.contextPrivKey(),
        ),
        platform: 'TRX',
        contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        protocolType: 'TRC20',
      );

      final json = request.toJson();
      final params = json['params'] as Map<String, dynamic>;

      expect(params['protocol'], {
        'type': 'TRC20',
        'protocol_data': {
          'platform': 'TRX',
          'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        },
      });
      expect(
        params['activation_params'],
        containsPair('nodes', [
          {'url': 'https://api.trongrid.io', 'gui_auth': false},
        ]),
      );
    });

    test('withdraw init serializes expiration_seconds for TRON', () {
      final request = WithdrawInitRequest(
        rpcPass: 'rpc-pass',
        params: WithdrawParameters(
          asset: 'TRX',
          toAddress: 'TW9RqU6bTJnM4quyRbvTwm3xfSHgk718qU',
          amount: Decimal.parse('10'),
          expirationSeconds: 90,
        ),
      );

      final json = request.toJson();
      final params = json['params'] as Map<String, dynamic>;

      expect(params['coin'], 'TRX');
      expect(params['expiration_seconds'], 90);
    });
  });

  group('TRON RPC response parsing', () {
    test('enable_eth_with_tokens parses legacy TRON address maps', () {
      final response = EnableEthWithTokensResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'current_block': 68000000,
          'eth_addresses_infos': {
            'TDcxD6E5wTzvqCJd4RfkGfw9NkCBdvYcV9': {
              'derivation_method': {'type': 'Iguana'},
              'pubkey': '04abc',
              'balances': {'spendable': '50.000000', 'unspendable': '0'},
            },
          },
          'erc20_addresses_infos': {
            'TDcxD6E5wTzvqCJd4RfkGfw9NkCBdvYcV9': {
              'derivation_method': {'type': 'Iguana'},
              'pubkey': '04abc',
              'balances': {
                'USDT-TRC20': {'spendable': '10.000000', 'unspendable': '0'},
              },
            },
          },
          'nfts_infos': {},
        },
      }, platformTicker: 'TRX');

      expect(response.currentBlock, 68000000);
      expect(response.walletBalance.accounts, hasLength(1));
      expect(response.walletBalance.accounts.first.addresses, hasLength(1));
      expect(
        response.walletBalance.accounts.first.addresses.first.address,
        'TDcxD6E5wTzvqCJd4RfkGfw9NkCBdvYcV9',
      );
      expect(
        response.walletBalance.accounts.first.addresses.first.balance
            .balanceOf('TRX')
            .spendable,
        Decimal.parse('50.000000'),
      );
      expect(
        response.walletBalance.accounts.first.addresses.first.balance
            .balanceOf('USDT-TRC20')
            .spendable,
        Decimal.parse('10.000000'),
      );
    });
  });
}
