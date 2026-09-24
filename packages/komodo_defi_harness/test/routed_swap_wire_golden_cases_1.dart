part of 'routed_swap_wire_golden_test.dart';

void _cases1() {
  group('routed_swap::quote', () {
    test('an ERC-20 route with approval, totals and a symbol fee', () {
      final response =
          rpc.RoutedSwapQuoteRequest(
            rpcPass: '',
            from: 'USDT-ETH',
            to: 'USDC-POLYGON',
            amount: '1',
          ).parseResponseJson(
            _envelope({
              'routes': [_erc20Route],
            }),
          );
      final route = response.best!;

      expect(response.routes, hasLength(1));
      expect(route.provider, 'lifi');
      expect(route.from.coin, 'USDT-ETH');
      expect(route.from.amount, '1');
      expect(route.to.amount, '2');
      expect(route.toMinimum.amount, '1.9');
      expect(route.toMinimum.coin, 'USDC-POLYGON');
      expect(route.tool.key, 'across');
      expect(route.tool.name, 'Across V4');
      expect(route.tool.logoUrl, isNull);
      expect(route.kind, rpc.RoutedSwapRouteKind.crossChain);
      expect(route.fromAddress, _wallet);
      expect(route.toAddress, _wallet);
      expect(route.executionDurationS, 31);

      final approval = route.approval!;
      expect(approval.required, isTrue);
      expect(approval.txCount, 1);
      expect(approval.reason, rpc.RoutedSwapApprovalReason.noAllowance);
      expect(approval.resetsFirst, isFalse);
      expect(approval.spender, _diamond);
      expect(approval.gasCosts.single.amount.coin, 'ETH');
      expect(approval.gasCosts.single.amount.amount, '0.000057501');
      expect(approval.gasCosts.single.amountUsd, isNull);

      // ETH pays approval gas, which has no USD, so its total has none.
      expect(route.totalGasCosts.map((g) => g.amount.label), ['ETH', 'MATIC']);
      expect(route.totalGasCosts[0].amount.amount, '0.013057501');
      expect(route.totalGasCosts[0].amountUsd, isNull);
      expect(route.totalGasCosts[1].amountUsd, '4');

      expect(route.steps.map((s) => s.stepType), [
        rpc.RoutedSwapStepType.swap,
        rpc.RoutedSwapStepType.cross,
      ]);
      expect(route.steps[0].chainId, 1);
      expect(route.steps[1].fromChainId, 1);
      expect(route.steps[1].toChainId, 137);

      expect(route.feeCosts.map((f) => f.included), [true, false, true]);
      expect(route.feeCosts[1].amount.coin, 'FEE-INACTIVE');
      expect(route.feeCosts[2].amount.symbol, 'BROKEN');
      expect(route.feeCosts[2].amount.coin, isNull);
      expect(route.feeCosts[2].amount.isKnownAsset, isFalse);
      expect(route.gasCosts.map((g) => g.amountUsd), ['20', '4', '6']);

      // The model reproduces the wire exactly, for exports and support.
      expect(route.toJson(), _erc20Route);
    });

    test('a native route has no approval and totals with USD', () {
      final route = rpc.RoutedSwapRoute.fromJson(_nativeRoute);
      expect(route.approval, isNull);
      expect(route.tool.logoUrl, 'https://cdn.example/logo.svg');
      expect(route.totalGasCosts.map((g) => g.amountUsd), ['26', '4']);
      expect(route.toJson(), _nativeRoute);
    });

    test('a zero-reset approval is two transactions', () {
      final route = rpc.RoutedSwapRoute.fromJson({
        ..._erc20Route,
        'approval': const {
          'required': true,
          'tx_count': 2,
          'reason': 'zero_reset',
          'spender': _diamond,
          'gas_costs': [
            {'coin': 'ETH', 'amount': '0.000115002'},
          ],
        },
      });
      expect(route.approval!.txCount, 2);
      expect(route.approval!.reason, rpc.RoutedSwapApprovalReason.zeroReset);
      expect(route.approval!.resetsFirst, isTrue);
    });

    test('every quote error arrives as its typed exception', () {
      rpc.RoutedSwapRpcException thrown(Map<String, dynamic> error) {
        try {
          rpc.RoutedSwapQuoteRequest(
            rpcPass: '',
            from: 'ETH',
            to: 'USDC-POLYGON',
            amount: '1',
          ).parseResponseJson(error);
        } on rpc.RoutedSwapRpcException catch (e) {
          return e;
        }
        fail('${error['error_type']} parsed as a response');
      }

      final coin =
          thrown(
                _rpcError('CoinNotActive', 'Coin FEE-INACTIVE is not active', {
                  'coin': 'FEE-INACTIVE',
                }),
              )
              as rpc.RoutedSwapCoinNotActiveException;
      expect(coin.coin, 'FEE-INACTIVE');
      expect(coin.message, 'Coin FEE-INACTIVE is not active');

      final pair =
          thrown(
                _rpcError(
                  'PairNotSupported',
                  'Pair ETH/BTC is not supported: BTC is not an EVM asset',
                  {
                    'from': 'ETH',
                    'to': 'BTC',
                    'reason': 'BTC is not an EVM asset',
                  },
                ),
              )
              as rpc.RoutedSwapPairNotSupportedException;
      expect([pair.from, pair.to], ['ETH', 'BTC']);

      final param =
          thrown(
                _rpcError(
                  'InvalidParam',
                  'Invalid parameter amount: more than 6 decimal places',
                  {'param': 'amount', 'reason': 'more than 6 decimal places'},
                ),
              )
              as rpc.RoutedSwapInvalidParamException;
      expect(param.param, 'amount');

      final bounds =
          thrown(
                _rpcError(
                  'AmountOutOfBounds',
                  'Parameter slippage out of bounds, value: 0.6, min: 0 max: '
                      '0.5',
                  {
                    'param': 'slippage',
                    'value': '0.6',
                    'min': '0',
                    'max': '0.5',
                  },
                ),
              )
              as rpc.RoutedSwapAmountOutOfBoundsException;
      expect(
        [bounds.param, bounds.value, bounds.min, bounds.max],
        ['slippage', '0.6', '0', '0.5'],
      );

      final address =
          thrown(
                _rpcError(
                  'MyAddressError',
                  'Cannot use ETH source address: no enabled address',
                  {'coin': 'ETH', 'message': 'no enabled address'},
                ),
              )
              as rpc.RoutedSwapMyAddressException;
      expect(address.detail, 'no enabled address');

      final config =
          thrown(
                _rpcError('InvalidConfig', 'lifi_api is invalid', {
                  'message': 'lifi_api is invalid',
                }),
              )
              as rpc.RoutedSwapInvalidConfigException;
      expect(config.detail, 'lifi_api is invalid');

      final noRoute =
          thrown(
                _rpcError('NoRouteFound', 'No route found', {
                  'reasons': _noRouteReasons,
                  'provider_request_id': 'req-1',
                }),
              )
              as rpc.RoutedSwapNoRouteException;
      expect(noRoute.reasons, _noRouteReasons);
      expect(noRoute.providerRequestId, 'req-1');

      final limited =
          thrown(
                _rpcError(
                  'RateLimited',
                  'Routed swap provider rate limit exceeded',
                  <String, dynamic>{},
                ),
              )
              as rpc.RoutedSwapRateLimitedException;
      expect(limited.providerRequestId, isNull);
      expect(limited.isTransient, isTrue);

      final provider =
          thrown(
                _rpcError(
                  'ProviderApiError',
                  'Routed swap provider returned an invalid transaction target',
                  {
                    'message':
                        'Routed swap provider returned an invalid transaction '
                        'target',
                    'provider_request_id': 'req-2',
                  },
                ),
              )
              as rpc.RoutedSwapProviderException;
      expect(provider.providerRequestId, 'req-2');
      expect(provider.detail, startsWith('Routed swap provider returned'));

      final transport =
          thrown(
                _rpcError(
                  'TransportError',
                  'Unable to reach routed swap provider',
                  {'message': 'Unable to reach routed swap provider'},
                ),
              )
              as rpc.RoutedSwapTransportException;
      expect(transport.detail, 'Unable to reach routed swap provider');

      final internal =
          thrown(
                _rpcError(
                  'InternalError',
                  'Unable to access routed swap '
                      'history',
                  {
                    'message':
                        'Unable to access routed swap '
                        'history',
                  },
                ),
              )
              as rpc.RoutedSwapInternalException;
      expect(internal.detail, 'Unable to access routed swap history');

      // A dispatcher rejection before the handler runs.
      final request = thrown(
        _rpcError(
          'InvalidRequest',
          'Error parsing request: unknown field `client_id`',
          'unknown field `client_id`',
        ),
      );
      expect(request, isA<rpc.RoutedSwapUnknownRpcException>());
      expect(request.errorType, 'InvalidRequest');
    });
  });

  test('routed_swap::supported_coins', () {
    final response = rpc.RoutedSwapSupportedCoinsRequest(rpcPass: '')
        .parseResponseJson(
          _envelope({
            'provider': 'lifi',
            'coins': [
              {'coin': 'ETH', 'chain_id': 1},
              {'coin': 'USDC-POLYGON', 'chain_id': 137},
            ],
          }),
        );
    expect(response.provider, 'lifi');
    expect(response.coins.map((c) => [c.coin, c.chainId]), [
      ['ETH', 1],
      ['USDC-POLYGON', 137],
    ]);
  });

  test('task::routed_swap::init answers the task id only', () {
    final response = rpc.RoutedSwapInitRequest(
      rpcPass: '',
      from: 'ETH',
      to: 'USDC-POLYGON',
      amount: '1',
      minToAmount: '1.9',
    ).parseResponseJson(_envelope({'task_id': 3}));
    expect(response.taskId, 3);
  });
}
