import 'dart:convert';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

void main() {
  const nodes = [SolanaNode(url: 'https://api.devnet.solana.com')];
  const balance = {'spendable': '0.01', 'unspendable': '0'};
  const tokenProtocol = {
    'type': 'SOLANATOKEN',
    'protocol_data': {
      'platform': 'SOL-DEV',
      'decimals': 6,
      'mint_address': '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
      'program_id': 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
    },
  };

  test(
    'platform activation has experimental v2 method and only Solana fields',
    () {
      final request = EnableSolanaWithAssetsRequest(
        ticker: 'SOL-DEV',
        nodes: nodes,
        tokensParams: [const SolanaTokenRequest(ticker: 'USDC-SOL-DEV')],
      );
      expect(jsonDecode(jsonEncode(request.toJson())), {
        'method': 'experimental::enable_solana_with_assets',
        'mmrpc': '2.0',
        'params': {
          'ticker': 'SOL-DEV',
          'nodes': [
            {'url': 'https://api.devnet.solana.com'},
          ],
          'tokens_params': [
            {'ticker': 'USDC-SOL-DEV'},
          ],
          'tx_history': true,
        },
      });
      expect(
        (EnableSolanaWithAssetsRequest(
              ticker: 'SOL-DEV',
              nodes: nodes,
            ).toJson()['params']
            as Map<String, dynamic>)['tokens_params'],
        isEmpty,
      );
    },
  );

  test(
    'later token activation sends empty params and complete optional protocol',
    () {
      final request = EnableSolanaTokenRequest(
        ticker: 'USDC-SOL-DEV',
        protocol: tokenProtocol,
      );
      expect(request.toJson(), {
        'method': 'experimental::enable_solana_token',
        'mmrpc': '2.0',
        'params': {
          'ticker': 'USDC-SOL-DEV',
          'activation_params': <String, dynamic>{},
          'protocol': tokenProtocol,
        },
      });
      expect(
        const SolanaTokenRequest(
          ticker: 'USDC-SOL-DEV',
          protocol: tokenProtocol,
        ).toJson(),
        {'ticker': 'USDC-SOL-DEV', 'protocol': tokenProtocol},
      );
    },
  );

  test('activation rejects empty or non-HTTP node lists before dispatch', () {
    expect(
      () => EnableSolanaWithAssetsRequest(ticker: 'SOL', nodes: []).toJson(),
      throwsFormatException,
    );
    expect(
      () => EnableSolanaWithAssetsRequest(
        ticker: 'SOL',
        nodes: const [SolanaNode(url: 'wss://rpc.example')],
      ).toJson(),
      throwsFormatException,
    );
    expect(
      SolanaNode.fromJson(const {
        'url': 'https://rpc.example',
        'komodo_proxy': true,
      }).toJson(),
      {'url': 'https://rpc.example'},
    );
  });

  test('platform response retains zero token balances and slot', () {
    final wire = {
      'mmrpc': '2.0',
      'result': {
        'ticker': 'SOL-DEV',
        'address': 'OwnerBase58',
        'current_block': 515768675,
        'balance': balance,
        'tokens_balances': {
          'USDC-SOL-DEV': {'spendable': '0', 'unspendable': '0'},
        },
      },
    };
    final response = EnableSolanaWithAssetsResponse.parse(wire);
    expect(response.currentBlock, 515768675);
    expect(response.tokensBalances.keys, ['USDC-SOL-DEV']);
    expect(response.toJson(), wire);
  });

  test(
    'independent token response roundtrips without changing address case',
    () {
      final wire = {
        'mmrpc': '2.0',
        'result': {
          'ticker': 'USDC-SOL-DEV',
          'address': 'OwnerBase58',
          'current_block': 515768675,
          'balance': balance,
        },
      };
      expect(EnableSolanaTokenResponse.parse(wire).toJson(), wire);
    },
  );

  test('active key export uses legacy request and redacts diagnostics', () {
    expect(ShowPrivKeyRequest(coin: 'SOL-DEV').toJson(), {
      'method': 'show_priv_key',
      'coin': 'SOL-DEV',
    });
    final response = ShowPrivKeyResponse.parse({
      'result': {'coin': 'SOL-DEV', 'priv_key': 'test-only-keypair'},
    });
    expect(response.privKey, 'test-only-keypair');
    expect(response.toString(), isNot(contains('test-only-keypair')));
  });

  test('incomplete token overrides fail before dispatch', () {
    for (final key in ['platform', 'mint_address', 'program_id', 'decimals']) {
      final data = Map<String, dynamic>.from(
        tokenProtocol['protocol_data']! as Map<String, dynamic>,
      )..remove(key);
      final invalid = {'type': 'SOLANATOKEN', 'protocol_data': data};
      expect(
        () => EnableSolanaTokenRequest(
          ticker: 'USDC-SOL-DEV',
          protocol: invalid,
        ).toJson(),
        throwsFormatException,
      );
      expect(
        () => SolanaTokenRequest(
          ticker: 'USDC-SOL-DEV',
          protocol: invalid,
        ).toJson(),
        throwsFormatException,
      );
    }
  });

  test('malformed activation and private-key responses are rejected', () {
    expect(
      () => EnableSolanaTokenResponse.parse({
        'mmrpc': '2.0',
        'result': {'ticker': 'SOL-DEV'},
      }),
      throwsArgumentError,
    );
    expect(
      () => ShowPrivKeyResponse.parse({
        'result': {'coin': 'SOL-DEV'},
      }),
      throwsArgumentError,
    );
  });

  test('single-address signing preserves message and signature case', () {
    final params = SignMessageRequest(
      rpcPass: 'fixture',
      coin: 'SOL-DEV',
      message: 'Solana 🦀',
    ).toJson()['params'];
    expect(params, {'coin': 'SOL-DEV', 'message': 'Solana 🦀'});
    final response = SignMessageResponse.parse({
      'mmrpc': '2.0',
      'result': {'signature': 'Base58CaseABCabc'},
    });
    expect(response.signature, 'Base58CaseABCabc');
  });
}
