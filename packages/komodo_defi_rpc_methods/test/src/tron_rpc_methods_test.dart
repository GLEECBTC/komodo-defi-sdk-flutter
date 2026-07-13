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

    test('parses a gasless relay response', () {
      final response = SendRawTransactionResponse.parse({
        'relay_type': 'tron_gasfree',
        'request_id': '123e4567-e89b-42d3-a456-426614174000',
        'trace_id': '6c3ff67e-0bf4-4c09-91ca-0c7c254b01a0',
        'state': 'WAITING',
        'expected_authorization': {
          'request_id': '123e4567-e89b-42d3-a456-426614174000',
          'account': 'TAccount',
          'custody_address': 'TCustody',
          'provider': 'TProvider',
          'receiver': 'TReceiver',
          'token': 'TToken',
          'amount': '5000000',
          'max_fee': '2000000',
          'deadline': '1783690000',
          'version': '1',
          'nonce': '9',
          'signature_fingerprint':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        },
      });

      expect(response.isGaslessRelay, isTrue);
      expect(response.requestId, '123e4567-e89b-42d3-a456-426614174000');
      expect(response.traceId, '6c3ff67e-0bf4-4c09-91ca-0c7c254b01a0');
      expect(response.state, 'WAITING');
      expect(response.txHash, isNull);
    });

    test('parses a standard tx_hash response', () {
      final response = SendRawTransactionResponse.parse({
        'result': {'tx_hash': 'abc123'},
      });

      expect(response.isGaslessRelay, isFalse);
      expect(response.txHash, 'abc123');
    });

    test('parses the legacy relay response without bound context', () {
      final response = SendRawTransactionResponse.parse({
        'relay_type': 'tron_gasfree',
        'trace_id': 'legacy-trace',
        'state': 'WAITING',
      });

      expect(response.isGaslessRelay, isTrue);
      expect(response.hasBoundRelayContext, isFalse);
      expect(response.requestId, isNull);
      expect(response.expectedAuthorization, isNull);
    });
  });

  group('gasless::configure', () {
    const provider = TronGaslessProviderConfig(
      baseUrl: 'https://quicknode.gleec.com/gasfree',
      service: GaslessServiceKomodoProxy(),
      serviceProvider: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
    );

    test('serializes provider and non-empty token configuration', () {
      final request = GaslessConfigureRequest(
        rpcPass: 'rpc-pass',
        platformCoin: 'TRX',
        provider: provider,
        tokens: [
          GaslessConfigureToken(
            coin: 'USDT-TRC20',
            transferMaxFee: Decimal.parse('2'),
          ),
        ],
      );

      final json = request.toJson();
      expect(json['method'], 'gasless::configure');
      expect(json['params'], {
        'platform_coin': 'TRX',
        'provider': provider.toJson(),
        'tokens': [
          {'coin': 'USDT-TRC20', 'transfer_max_fee': '2'},
        ],
      });
    });

    test('rejects an empty token list at runtime', () {
      expect(
        () => GaslessConfigureRequest(
          rpcPass: 'rpc-pass',
          platformCoin: 'TRX',
          provider: provider,
          tokens: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('gasless::trace_status', () {
    const expected = GaslessExpectedAuthorization(
      requestId: '123e4567-e89b-42d3-a456-426614174000',
      account: 'TAccount',
      custodyAddress: 'TCustody',
      provider: 'TProvider',
      receiver: 'TReceiver',
      token: 'TToken',
      amount: '5000000',
      maxFee: '2000000',
      deadline: '1783690000',
      version: '1',
      nonce: '9',
      signatureFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    test('request serializes coin and trace_id', () {
      final request = GaslessTraceStatusRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
        traceId: 'trace-1',
        expectedAuthorization: expected,
      );

      final json = request.toJson();
      expect(json['method'], 'gasless::trace_status');
      expect(json['params'], {
        'coin': 'USDT-TRC20',
        'trace_id': 'trace-1',
        'expected_authorization': expected.toJson(),
      });
    });

    test('legacy request omits unsupported authorization binding', () {
      final request = GaslessTraceStatusRequest(
        rpcPass: 'rpc-pass',
        coin: 'USDT-TRC20',
        traceId: 'trace-1',
      );

      expect(request.toJson()['params'], {
        'coin': 'USDT-TRC20',
        'trace_id': 'trace-1',
      });
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

    test('normalizes legacy double-divided and millisecond timestamps', () {
      GaslessTraceStatusResponse parse(Object timestamp) =>
          GaslessTraceStatusResponse.parse({
            'result': {'state': 'confirmed', 'confirmed_at': timestamp},
          });

      expect(parse(1747909).confirmedAt, 1747909000);
      expect(parse(1747909638).confirmedAt, 1747909638);
      expect(parse(1747909638000).confirmedAt, 1747909638);
    });

    test('parses a failed status', () {
      final response = GaslessTraceStatusResponse.parse({
        'mmrpc': '2.0',
        'result': {'state': 'failed', 'failure_reason': 'provider rejected'},
      });

      expect(response.state.isFailed, isTrue);
      expect(response.failureReason, 'provider rejected');
    });

    test('GaslessTraceState.parse maps known values and rejects unknown', () {
      expect(GaslessTraceState.parse('on_chain'), GaslessTraceState.onChain);
      expect(GaslessTraceState.parse('WAITING'), GaslessTraceState.pending);
      expect(
        GaslessTraceState.parse('INPROGRESS'),
        GaslessTraceState.submitted,
      );
      expect(GaslessTraceState.parse('CONFIRMING'), GaslessTraceState.onChain);
      expect(GaslessTraceState.parse('SUCCEED'), GaslessTraceState.confirmed);
      expect(
        () => GaslessTraceState.parse('provider_added_new_state'),
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
        'result': {
          'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
          'active': false,
          'on_chain_balance': '12.5',
          'frozen_balance': '0',
          'spendable_balance': '12.5',
          'transfer_fee': '2',
          'activation_fee': '1',
          'max_withdrawable': '9.5',
          'availability': 'available',
          'service_provider': 'TProvider',
        },
      });

      expect(response.gasfreeAddress, 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF');
      expect(response.active, isFalse);
      expect(response.onChainBalance, Decimal.parse('12.5'));
      expect(response.transferFee, Decimal.parse('2'));
      expect(response.activationFee, Decimal.parse('1'));
      expect(response.maxWithdrawable, Decimal.parse('9.5'));
      expect(response.availability, GaslessAccountAvailability.available);
      expect(response.hasExplicitAvailability, isTrue);
      expect(response.serviceProvider, 'TProvider');
      expect(
        response.toJson()['result'],
        containsPair('service_provider', 'TProvider'),
      );
      // total = on-chain, spendable = on-chain - frozen, unspendable = frozen
      expect(response.custodyBalance.total, Decimal.parse('12.5'));
      expect(response.custodyBalance.spendable, Decimal.parse('12.5'));
      expect(response.custodyBalance.unspendable, Decimal.zero);
    });

    test('parses a degraded (provider-unavailable) status', () {
      final response = GaslessAccountStatusResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
          'on_chain_balance': '7',
          'availability': 'provider_unreachable',
        },
      });

      expect(
        response.availability,
        GaslessAccountAvailability.providerUnreachable,
      );
      expect(response.serviceProvider, isNull);
      expect(response.active, isNull);
      expect(response.transferFee, isNull);
      expect(response.maxWithdrawable, isNull);
      expect(response.reasonCode, isNull);
      // Unknown spendability is represented conservatively, never synthesized.
      expect(response.custodyBalance.total, Decimal.parse('7'));
      expect(response.custodyBalance.spendable, Decimal.zero);
      expect(response.custodyBalance.unspendable, Decimal.parse('7'));
    });
  });

  test('root legacy error preserves typed GasFree relay envelope', () {
    final error = GeneralErrorResponse.parse({
      'error': 'GasFree relay submission failed',
      'error_type': 'GaslessRelaySubmission',
      'error_data': {
        'code': 'authorization_expired',
        'stage': 'submission',
        'retryable': true,
        'terminal': true,
        'relay_accepted': false,
      },
    });

    expect(error.errorType, 'GaslessRelaySubmission');
    expect(error.error, 'GasFree relay submission failed');
    expect(
      (error.errorData as Map<String, dynamic>)['code'],
      'authorization_expired',
    );
  });
}
