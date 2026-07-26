import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

TronGasfreeRelayPayload _relayPayload() => TronGasfreeRelayPayload(
  chainId: '728126428',
  coin: 'USDT-TRC20',
  hdFrom: const {'account_id': 0, 'chain': 'External', 'address_id': 0},
  fromAddress: 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
  gasfreeAddress: 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
  verifyingContract: 'THQGuFzL87ZqhxkgqYEryRAd7gqFqL5rdc',
  signedAuthorization: GaslessSignedAuthorization(
    token: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    serviceProvider: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
    user: 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
    receiver: 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
    value: '5000000',
    maxFee: '5000000',
    deadline: BigInt.from(1999999999),
    version: '1',
    nonce: '9',
    signature:
        '1111111111111111111111111111111111111111111111111111111111111111'
        '111111111111111111111111111111111111111111111111111111111111111111',
  ),
  createdAt: '2026-07-10T12:00:00Z',
);

Map<String, dynamic> _traceStatusResult({
  String state = 'submitted',
  String? txHashOnChain,
  int? blockHeight,
  int? confirmedAt,
  String? finalFee,
  String? failureReason,
}) => {
  'state': state,
  'tx_hash_on_chain': txHashOnChain,
  'block_height': blockHeight,
  'confirmed_at': confirmedAt,
  'final_fee': finalFee,
  'failure_reason': failureReason,
};

Map<String, dynamic> _availableAccountStatusResult() => {
  'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
  'service_provider': 'TProvider',
  'availability': 'available',
  'active': false,
  'on_chain_balance': '12.5',
  'frozen_balance': '0',
  'spendable_balance': '12.5',
  'transfer_fee': '2',
  'activation_fee': '1',
  'max_withdrawable': '9.5',
};

Map<String, dynamic> _unreachableAccountStatusResult() => {
  'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
  'service_provider': null,
  'availability': 'provider_unreachable',
  'active': null,
  'on_chain_balance': '7',
  'frozen_balance': null,
  'spendable_balance': null,
  'transfer_fee': null,
  'activation_fee': null,
  'max_withdrawable': null,
};

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
        {'url': 'https://api.trongrid.io', 'komodo_proxy': false},
      ]);
      expect(params['erc20_tokens_requests'], [
        {'ticker': 'USDT-TRC20', 'required_confirmations': 3},
      ]);
      expect(params['tx_history'], isTrue);
      expect(params.containsKey('swap_contract_address'), isFalse);
      expect(params.containsKey('fallback_swap_contract'), isFalse);
    });

    test('EvmNode serializes KDF komodo_proxy and reads legacy gui_auth', () {
      final node = EvmNode.fromJson({
        'url': 'https://quicknode.gleec.com/',
        'gui_auth': true,
      });

      expect(node.komodoProxy, isTrue);
      expect(node.guiAuth, isTrue);
      expect(node.toJson(), {
        'url': 'https://quicknode.gleec.com/',
        'komodo_proxy': true,
      });
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
        {'url': 'https://api.trongrid.io', 'komodo_proxy': false},
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
          {'url': 'https://api.trongrid.io', 'komodo_proxy': false},
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
              'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
              'balances': {
                'USDT-TRC20': {'spendable': '10.000000', 'unspendable': '0'},
              },
            },
          },
          'nfts_infos': <String, dynamic>{},
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
      expect(
        response.walletBalance.accounts.first.addresses.first.gasfreeAddress,
        'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      );
    });
  });

  group('TRON gasless activation serialization', () {
    const komodoProxyProvider = TronGaslessProviderConfig(
      baseUrl: 'https://quicknode.gleec.com/gasfree',
      service: GaslessServiceKomodoProxy(),
      serviceProvider: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
    );

    test('enable_eth_with_tokens emits komodo_proxy tron_gasless_provider', () {
      final request = EnableEthWithTokensRequest(
        rpcPass: 'rpc-pass',
        ticker: 'TRX',
        activationParams: TrxWithTokensActivationParams(
          nodes: [EvmNode(url: 'https://api.trongrid.io')],
          tokenRequests: const [],
          txHistory: false,
          privKeyPolicy: const PrivateKeyPolicy.contextPrivKey(),
          tronGaslessProvider: komodoProxyProvider,
        ),
      );

      final params = request.toJson()['params'] as Map<String, dynamic>;
      expect(params['tron_gasless_provider'], {
        'base_url': 'https://quicknode.gleec.com/gasfree',
        'service': 'komodo_proxy',
        'service_provider': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
        'request_timeout_ms': 15000,
        'status_poll_interval_ms': 3000,
      });
    });

    test('enable_eth_with_tokens emits gasless token activation', () {
      final request = EnableEthWithTokensRequest(
        rpcPass: 'rpc-pass',
        ticker: 'TRX',
        activationParams: TrxWithTokensActivationParams(
          nodes: [EvmNode(url: 'https://api.trongrid.io')],
          tokenRequests: [
            TokensRequest(
              ticker: 'USDT-TRC20',
              gasless: TronGaslessTokenActivationConfig(
                enabled: true,
                transferMaxFee: Decimal.parse('10'),
              ),
            ),
          ],
          txHistory: false,
          privKeyPolicy: const PrivateKeyPolicy.contextPrivKey(),
          tronGaslessProvider: komodoProxyProvider,
        ),
      );

      final params = request.toJson()['params'] as Map<String, dynamic>;
      expect(params['erc20_tokens_requests'], [
        {
          'ticker': 'USDT-TRC20',
          'required_confirmations': 3,
          'gasless': {'enabled': true, 'transfer_max_fee': '10'},
        },
      ]);
    });

    test('omitted gasless enabled field defaults to false', () {
      final parsed = TronGaslessTokenActivationConfig.fromJson({
        'transfer_max_fee': '10',
      });

      expect(parsed.enabled, isFalse);
      expect(parsed.transferMaxFee, Decimal.parse('10'));
      expect(parsed.toJson(), {'enabled': false, 'transfer_max_fee': '10'});
    });

    test('enable_erc20 emits standalone TRC20 gasless activation', () {
      final request = EnableErc20Request(
        rpcPass: 'rpc-pass',
        ticker: 'USDT-TRC20',
        activationParams: Trc20ActivationParams(
          nodes: [EvmNode(url: 'https://api.trongrid.io')],
          gasless: const TronGaslessTokenActivationConfig(enabled: true),
        ),
      );

      final params = request.toJson()['params'] as Map<String, dynamic>;
      expect(params['activation_params'], {
        'requires_notarization': false,
        'nodes': [
          {'url': 'https://api.trongrid.io', 'komodo_proxy': false},
        ],
        'priv_key_policy': const PrivateKeyPolicy.contextPrivKey().toJson(),
        'gasless': {'enabled': true},
      });
    });

    test('task::enable_eth::init emits gas_free tron_gasless_provider', () {
      final request = TaskEnableEthInit(
        rpcPass: 'rpc-pass',
        ticker: 'TRX',
        params: TrxWithTokensActivationParams(
          nodes: [EvmNode(url: 'https://api.trongrid.io')],
          tokenRequests: const [],
          txHistory: false,
          privKeyPolicy: const PrivateKeyPolicy.contextPrivKey(),
          tronGaslessProvider: const TronGaslessProviderConfig(
            baseUrl: 'https://open.gasfree.io',
            service: GaslessServiceGasFree(apiKey: 'KEY', apiSecret: 'SECRET'),
            serviceProvider: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
          ),
        ),
      );

      final params = request.toJson()['params'] as Map<String, dynamic>;
      final provider = params['tron_gasless_provider'] as Map<String, dynamic>;
      expect(provider['service'], {
        'gas_free': {'api_key': 'KEY', 'api_secret': 'SECRET'},
      });
      expect(provider['base_url'], 'https://open.gasfree.io');
    });

    test('TronGaslessProviderConfig round-trips through fromJson', () {
      final parsed = TronGaslessProviderConfig.fromJson(
        komodoProxyProvider.toJson(),
      );
      expect(parsed, equals(komodoProxyProvider));
    });
  });

  group('TRON gasless withdraw serialization', () {
    test('withdraw init emits fee_method and gasless options', () {
      final request = WithdrawInitRequest(
        rpcPass: 'rpc-pass',
        params: WithdrawParameters(
          asset: 'USDT-TRC20',
          toAddress: 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
          amount: Decimal.parse('5'),
          feeMethod: WithdrawalFeeMethod.gasless,
          gaslessOptions: GaslessWithdrawalOptions(
            maxFee: Decimal.parse('5'),
            deadlineSeconds: 300,
          ),
        ),
      );

      final params = request.toJson()['params'] as Map<String, dynamic>;
      expect(params['fee_method'], 'gasless');
      expect(params['gasless'], {
        'max_fee': '5',
        'deadline_seconds': 300,
        'fallback_to_native': false,
      });
    });

    test('withdraw max omits amount and delegates calculation to KDF', () {
      final request = WithdrawInitRequest(
        rpcPass: 'rpc-pass',
        params: const WithdrawParameters(
          asset: 'USDT-TRC20',
          toAddress: 'TJM1BE5wq1VdHh3gwjUeyaVkvZp9DVYCfC',
          amount: null,
          isMax: true,
          feeMethod: WithdrawalFeeMethod.gasless,
          gaslessOptions: GaslessWithdrawalOptions(deadlineSeconds: 300),
        ),
      );

      final params = request.toJson()['params'] as Map<String, dynamic>;
      expect(params['max'], isTrue);
      expect(params, isNot(contains('amount')));
      expect(params['fee_method'], 'gasless');
      expect(params['gasless'], {
        'deadline_seconds': 300,
        'fallback_to_native': false,
      });
    });
  });

  group('send_raw_transaction response parsing', () {
    test('rejects an empty broadcast payload at runtime', () {
      expect(
        () => SendRawTransactionLegacyRequest(
          rpcPass: 'rpc-pass',
          coin: 'USDT-TRC20',
        ),
        throwsArgumentError,
      );
    });

    test('serializes the exact typed GasFree relay payload', () {
      final relay = _relayPayload();
      final request = SendRawTransactionLegacyRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
        gaslessRelayPayload: relay,
      );

      expect(request.toJson(), {
        'method': 'send_raw_transaction',
        'rpc_pass': 'rpc-pass',
        'coin': 'USDT-TRC20',
        'tx_json': relay.toJson(),
      });
    });

    test('rejects legacy relay generations passed as raw tx_json', () {
      final request = SendRawTransactionLegacyRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
        txJson: {..._relayPayload().toJson(), 'relay_type': 'tron_gasfree_v1'},
      );

      expect(request.toJson, throwsFormatException);
    });

    test('parses a gasless relay response', () {
      final response = SendRawTransactionResponse.parse({
        'relay_type': 'tron_gasfree',
        'trace_id': '6c3ff67e-0bf4-4c09-91ca-0c7c254b01a0',
        'state': 'WAITING',
      });

      expect(response.isGaslessRelay, isTrue);
      expect(response.traceId, '6c3ff67e-0bf4-4c09-91ca-0c7c254b01a0');
      expect(response.state, GaslessSubmitState.waiting);
      expect(response.txHash, isNull);
      expect(response.toJson(), {
        'relay_type': 'tron_gasfree',
        'trace_id': '6c3ff67e-0bf4-4c09-91ca-0c7c254b01a0',
        'state': 'WAITING',
      });
    });

    test('parses a standard tx_hash response', () {
      final response = SendRawTransactionResponse.parse({
        'result': {'tx_hash': 'abc123'},
      });

      expect(response.isGaslessRelay, isFalse);
      expect(response.txHash, 'abc123');
    });

    test('rejects undocumented relay response fields', () {
      expect(
        () => SendRawTransactionResponse.parse({
          'relay_type': 'tron_gasfree',
          'trace_id': 'trace-1',
          'state': 'WAITING',
          'request_id': 'must-not-be-accepted',
        }),
        throwsFormatException,
      );
    });

    test('rejects an accepted relay with an empty trace id', () {
      expect(
        () => SendRawTransactionResponse.parse({
          'relay_type': 'tron_gasfree',
          'trace_id': '  ',
          'state': 'WAITING',
        }),
        throwsFormatException,
      );
    });

    test('rejects a locally fabricated result-wrapped relay response', () {
      expect(
        () => SendRawTransactionResponse.parse({
          'result': {
            'relay_type': 'tron_gasfree',
            'trace_id': 'trace-1',
            'state': 'WAITING',
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('gasless::trace_status', () {
    test('request serializes coin and trace_id', () {
      final request = GaslessTraceStatusRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
        traceId: 'trace-1',
      );

      final json = request.toJson();
      expect(json['method'], 'gasless::trace_status');
      expect(json['params'], {'coin': 'USDT-TRC20', 'trace_id': 'trace-1'});
    });

    test('parses a confirmed status', () {
      final response = GaslessTraceStatusResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'state': 'confirmed',
          'tx_hash_on_chain': '22',
          'block_height': 57175988,
          'confirmed_at': 1747909638,
          'final_fee': '2.000000',
          'failure_reason': null,
        },
      });

      expect(response.state, GaslessTraceState.confirmed);
      expect(response.state.isConfirmed, isTrue);
      expect(response.txHashOnChain, '22');
      expect(response.blockHeight, 57175988);
      expect(response.finalFee, Decimal.parse('2.000000'));
      expect(response.confirmedAt, 1747909638);
    });

    test('does not impose a year-9999 cap on confirmed_at', () {
      final response = GaslessTraceStatusResponse.parse({
        'mmrpc': '2.0',
        'result': _traceStatusResult(
          state: 'confirmed',
          confirmedAt: 253402300800,
        ),
      });

      expect(response.confirmedAt, 253402300800);
    });

    test('accepts zero and rejects negative u64 trace fields', () {
      expect(
        GaslessTraceStatusResponse.parse({
          'mmrpc': '2.0',
          'result': _traceStatusResult(
            state: 'confirmed',
            blockHeight: 0,
            confirmedAt: 0,
          ),
        }).confirmedAt,
        0,
      );

      expect(
        () => GaslessTraceStatusResponse.parse({
          'mmrpc': '2.0',
          'result': _traceStatusResult(state: 'confirmed', confirmedAt: -1),
        }),
        throwsFormatException,
      );
      expect(
        () => GaslessTraceStatusResponse.parse({
          'mmrpc': '2.0',
          'result': _traceStatusResult(state: 'confirmed', blockHeight: -1),
        }),
        throwsFormatException,
      );
    });

    test('rejects a numeric final_fee instead of KDF numeric string', () {
      final result = _traceStatusResult()..['final_fee'] = 2;

      expect(
        () => GaslessTraceStatusResponse.parse({
          'mmrpc': '2.0',
          'result': result,
        }),
        throwsFormatException,
      );

      for (final finalFee in const ['not-a-number', '-1']) {
        final invalid = _traceStatusResult()..['final_fee'] = finalFee;
        expect(
          () => GaslessTraceStatusResponse.parse({
            'mmrpc': '2.0',
            'result': invalid,
          }),
          throwsFormatException,
        );
      }
    });

    test('parses a failed status', () {
      final response = GaslessTraceStatusResponse.parse({
        'mmrpc': '2.0',
        'result': _traceStatusResult(state: 'failed', failureReason: 'unknown'),
      });

      expect(response.state.isFailed, isTrue);
      expect(response.failureReason, 'unknown');
      expect(
        () => GaslessTraceStatusResponse.parse({
          'mmrpc': '2.0',
          'result': _traceStatusResult(
            state: 'failed',
            failureReason: 'provider rejected',
          ),
        }),
        throwsFormatException,
      );
    });

    test('GaslessTraceState.parse maps known values and rejects unknown', () {
      expect(GaslessTraceState.parse('on_chain'), GaslessTraceState.onChain);
      expect(() => GaslessTraceState.parse('WAITING'), throwsFormatException);
    });

    test('rejects a naked trace-status result body', () {
      expect(
        () => GaslessTraceStatusResponse.parse({
          'state': 'confirmed',
          'tx_hash_on_chain': 'hash',
        }),
        throwsFormatException,
      );
    });

    for (final field in const {
      'state',
      'tx_hash_on_chain',
      'block_height',
      'confirmed_at',
      'final_fee',
      'failure_reason',
    }) {
      test('rejects a trace-status result missing $field', () {
        final result = _traceStatusResult()..remove(field);

        expect(
          () => GaslessTraceStatusResponse.parse({
            'mmrpc': '2.0',
            'result': result,
          }),
          throwsFormatException,
        );
      });
    }
  });

  group('stream::gasless_trace::enable', () {
    test('serializes the coin-scoped stream request', () {
      final request = StreamGaslessTraceEnableRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
        clientId: 7,
      );

      expect(request.toJson(), {
        'method': 'stream::gasless_trace::enable',
        'mmrpc': '2.0',
        'rpc_pass': 'rpc-pass',
        'params': {'coin': 'USDT-TRC20', 'client_id': 7},
      });
      expect(
        request.parse({
          'mmrpc': '2.0',
          'result': {'streamer_id': 'GASLESS_TRACE:USDT-TRC20'},
        }).streamerId,
        'GASLESS_TRACE:USDT-TRC20',
      );
    });

    test('rejects a streamer id for a different coin', () {
      final request = StreamGaslessTraceEnableRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
      );

      expect(
        () => request.parse({
          'mmrpc': '2.0',
          'result': {'streamer_id': 'GASLESS_TRACE:USDC-TRC20'},
        }),
        throwsFormatException,
      );
    });

    test('rejects a response missing the exact streamer id', () {
      final request = StreamGaslessTraceEnableRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
      );

      expect(
        () => request.parse({'mmrpc': '2.0', 'result': <String, dynamic>{}}),
        throwsFormatException,
      );
    });
  });

  group('gasless::account_status', () {
    test('serializes coin param', () {
      final request = GaslessAccountStatusRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
      );

      final json = request.toJson();
      expect(json['method'], 'gasless::account_status');
      expect(json['params'], {'coin': 'USDT-TRC20'});
    });

    test('parses a full (provider-available) status', () {
      final response = GaslessAccountStatusResponse.parse({
        'mmrpc': '2.0',
        'result': _availableAccountStatusResult(),
      });

      expect(response.gasfreeAddress, 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF');
      expect(response.active, isFalse);
      expect(response.onChainBalance, Decimal.parse('12.5'));
      expect(response.transferFee, Decimal.parse('2'));
      expect(response.activationFee, Decimal.parse('1'));
      expect(response.maxWithdrawable, Decimal.parse('9.5'));
      expect(response.availability, GaslessAccountAvailability.available);
      expect(response.serviceProvider, 'TProvider');
      expect(
        response.toJson()['result'],
        containsPair('service_provider', 'TProvider'),
      );
      expect(response.spendableBalance, Decimal.parse('12.5'));
      expect(response.frozenBalance, Decimal.zero);
    });

    test('parses a degraded (provider-unavailable) status', () {
      final response = GaslessAccountStatusResponse.parse({
        'mmrpc': '2.0',
        'result': _unreachableAccountStatusResult(),
      });

      expect(
        response.availability,
        GaslessAccountAvailability.providerUnreachable,
      );
      expect(response.serviceProvider, isNull);
      expect(response.active, isNull);
      expect(response.transferFee, isNull);
      expect(response.maxWithdrawable, isNull);
      // The fresh custody total remains distinct from unknown spendability.
      expect(response.onChainBalance, Decimal.parse('7'));
      expect(response.spendableBalance, isNull);
      expect(response.frozenBalance, isNull);
    });

    test('rejects account-status amounts that are not numeric strings', () {
      for (final field in const {
        'on_chain_balance',
        'frozen_balance',
        'spendable_balance',
        'transfer_fee',
        'activation_fee',
        'max_withdrawable',
      }) {
        final result = _availableAccountStatusResult()..[field] = 1;

        expect(
          () => GaslessAccountStatusResponse.parse({
            'mmrpc': '2.0',
            'result': result,
          }),
          throwsFormatException,
          reason: '$field must remain a KDF numeric string',
        );
      }
    });

    test('rejects malformed or negative account-status numeric strings', () {
      for (final field in const {
        'on_chain_balance',
        'frozen_balance',
        'spendable_balance',
        'transfer_fee',
        'activation_fee',
        'max_withdrawable',
      }) {
        for (final amount in const ['not-a-number', '-1']) {
          final result = _availableAccountStatusResult()..[field] = amount;

          expect(
            () => GaslessAccountStatusResponse.parse({
              'mmrpc': '2.0',
              'result': result,
            }),
            throwsFormatException,
            reason: '$field must remain a non-negative KDF numeric string',
          );
        }
      }
    });

    test('rejects a naked account-status result body', () {
      expect(
        () => GaslessAccountStatusResponse.parse({
          'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
          'on_chain_balance': '7',
          'availability': 'provider_unreachable',
        }),
        throwsFormatException,
      );
    });

    for (final field in const {
      'gasfree_address',
      'service_provider',
      'availability',
      'active',
      'on_chain_balance',
      'frozen_balance',
      'spendable_balance',
      'transfer_fee',
      'activation_fee',
      'max_withdrawable',
    }) {
      test('rejects an account-status result missing $field', () {
        final result = _availableAccountStatusResult()..remove(field);

        expect(
          () => GaslessAccountStatusResponse.parse({
            'mmrpc': '2.0',
            'result': result,
          }),
          throwsFormatException,
        );
      });
    }
  });

  test('plain submission failure carries no invented lifecycle metadata', () {
    final error = GeneralErrorResponse.parse({
      'error': 'GasFree authorization expired at deadline 1999999999',
    });

    expect(error.error, 'GasFree authorization expired at deadline 1999999999');
    expect(error.errorType, isNull);
    expect(error.errorData, isNull);
    expect(error.object, isNot(contains('stage')));
    expect(error.object, isNot(contains('retryable')));
    expect(error.object, isNot(contains('terminal')));
    expect(error.object, isNot(contains('relay_accepted')));
  });
}
