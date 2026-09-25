part of 'routed_swap_fixture_test.dart';

void _cases1() {
  group('routed_swap::supported_coins', () {
    test('echoes the provider and lists coins sorted by ticker', () async {
      final fixture = RoutedSwapFixture()
        ..supportedCoin(from, chainId: 137)
        ..supportedCoin('ETH', chainId: 1);
      final response = await call(
        fixture.build(),
        'routed_swap::supported_coins',
      );

      expect(response['result'], {
        'provider': 'lifi',
        'coins': [
          {'coin': 'ETH', 'chain_id': 1},
          {'coin': from, 'chain_id': 137},
        ],
      });
    });

    test('rejects an unknown provider and an unknown field', () async {
      final script = RoutedSwapFixture().build();

      final provider = await call(script, 'routed_swap::supported_coins', {
        'provider': 'oneinch',
      });
      expect(provider['error_type'], 'InvalidParam');
      expect(provider['error_data'], {
        'param': 'provider',
        'reason': 'Unsupported routed swap provider',
      });

      final unknown = await call(script, 'routed_swap::supported_coins', {
        'chain': 1,
      });
      expect(unknown['error_type'], 'InvalidRequest');
    });
  });

  group('routed_swap::quote', () {
    test('emits the engine route: approval, totals, steps, fees', () async {
      final fixture = RoutedSwapFixture()
        ..quote(
          route(
            approval: approval,
            toolLogoUrl: 'https://li.fi/logos/stargate.png',
          ),
        );
      final response = await call(fixture.build(), 'routed_swap::quote', {
        'from': from,
        'to': to,
        'amount': '100.5',
      });

      expect(response.keys, containsAll(['mmrpc', 'result']));
      final routes = _list(_map(response['result'])['routes']);
      expect(routes, hasLength(1));
      expect(routes.single, {
        'provider': 'lifi',
        'from': {'coin': from, 'amount': '100.5'},
        'to': {'coin': to, 'amount': '100.21', 'amount_min': '99.71'},
        'tool': {
          'key': 'stargateV2',
          'name': 'Stargate V2',
          'logo_url': 'https://li.fi/logos/stargate.png',
        },
        'kind': 'cross_chain',
        'from_address': RoutedSwapQuote.defaultAddress,
        'to_address': RoutedSwapQuote.defaultAddress,
        'approval': {
          'required': true,
          'tx_count': 1,
          'reason': 'no_allowance',
          'spender': RoutedSwapQuoteApproval.lifiDiamond,
          'gas_costs': [
            {'coin': 'MATIC', 'amount': '0.0009'},
          ],
        },
        // MATIC sums both execution rows and the approval, which has no USD,
        // so its total omits amount_usd; ETH's only row has one.
        'total_gas_costs': [
          {'coin': 'MATIC', 'amount': '0.0159'},
          {'coin': 'ETH', 'amount': '0.001', 'amount_usd': '2.5'},
        ],
        'steps': [
          {'type': 'swap', 'tool': '1inch', 'chain_id': 137},
          {
            'type': 'cross',
            'tool': 'stargateV2',
            'from_chain_id': 137,
            'to_chain_id': 1,
          },
        ],
        'fee_costs': [
          {
            'name': 'LIFI Fixed Fee',
            'coin': from,
            'amount': '0.05',
            'amount_usd': '0.05',
            'included': true,
          },
          {
            'name': 'Bridge fee',
            'symbol': 'axlUSDC',
            'amount': '0.02',
            'included': false,
          },
        ],
        'gas_costs': [
          {'coin': 'MATIC', 'amount': '0.012', 'amount_usd': '0.01'},
          {'coin': 'ETH', 'amount': '0.001', 'amount_usd': '2.5'},
          {'coin': 'MATIC', 'amount': '0.003', 'amount_usd': '0.002'},
        ],
        'execution_duration_s': 95,
      });
    });

    test('a total keeps amount_usd when every row it sums has one', () {
      final json = route().toJson(amount: '1');
      expect(json['total_gas_costs'], [
        {'coin': 'MATIC', 'amount': '0.015', 'amount_usd': '0.012'},
        {'coin': 'ETH', 'amount': '0.001', 'amount_usd': '2.5'},
      ]);
      expect(json.containsKey('approval'), isFalse);
    });

    test('a zero-reset approval is two transactions', () {
      final json = route(
        approval: const RoutedSwapQuoteApproval.zeroReset(
          gasCoin: 'MATIC',
          gasAmount: '0.0018',
        ),
      ).toJson(amount: '1');
      final approvalJson = _map(json['approval']);
      expect(approvalJson['tx_count'], 2);
      expect(approvalJson['reason'], 'zero_reset');
    });

    test('omits absent optional fields instead of sending null', () async {
      final fixture = RoutedSwapFixture()
        ..quote(
          RoutedSwapQuote(
            from: from,
            to: to,
            toAmount: '1',
            toAmountMin: '1',
            gasCosts: const [RoutedSwapQuoteGas(coin: 'MATIC', amount: '1')],
          ),
        );
      final response = await call(fixture.build(), 'routed_swap::quote', {
        'from': from,
        'to': to,
        'amount': '2',
      });
      _expectNoNulls(response['result']);
      final routeJson = _map(_list(_map(response['result'])['routes']).single);
      expect(_map(routeJson['tool']).containsKey('logo_url'), isFalse);
      expect(routeJson.containsKey('approval'), isFalse);
      expect(_list(routeJson['gas_costs']).single, {
        'coin': 'MATIC',
        'amount': '1',
      });
    });

    test(
      'echoes the requested amount, and a fixed amount must match',
      () async {
        final fixture = RoutedSwapFixture()
          ..quote(
            RoutedSwapQuote(
              from: from,
              to: to,
              amount: '5',
              toAmount: '4.9',
              toAmountMin: '4.8',
            ),
          );
        final script = fixture.build();

        final five = await call(script, 'routed_swap::quote', {
          'from': from,
          'to': to,
          'amount': '5.0',
        });
        final routeJson = _map(_list(_map(five['result'])['routes']).single);
        expect(_map(routeJson['from'])['amount'], '5');

        await expectLater(
          call(script, 'routed_swap::quote', {
            'from': from,
            'to': to,
            'amount': '6',
          }),
          throwsStateError,
        );
      },
    );

    test('an unscripted pair is a scripting bug, not NoRouteFound', () async {
      await expectLater(
        call(RoutedSwapFixture().build(), 'routed_swap::quote', {
          'from': from,
          'to': to,
          'amount': '1',
        }),
        throwsStateError,
      );
    });

    test('validates provider, order and slippage before quoting', () async {
      final script = (RoutedSwapFixture()..quote(route())).build();
      Future<Map<String, dynamic>> quote(Map<String, dynamic> extra) => call(
        script,
        'routed_swap::quote',
        {'from': from, 'to': to, 'amount': '1', ...extra},
      );

      final provider = await quote({'provider': 'LIFI'});
      expect(provider['error_type'], 'InvalidParam');
      expect(_map(provider['error_data'])['param'], 'provider');

      final order = await quote({'order': 'best'});
      expect(
        order['error'],
        'Invalid parameter order: Unsupported routed '
        'swap order',
      );

      final slippage = await quote({'slippage': 0.6});
      expect(slippage['error_type'], 'AmountOutOfBounds');
      expect(slippage['error_data'], {
        'param': 'slippage',
        'value': '0.6',
        'min': '0',
        'max': '0.5',
      });

      for (final bad in [
        {'order': null},
        {'slippage': null},
        {'client_id': 1},
      ]) {
        expect(
          (await quote(bad))['error_type'],
          'InvalidRequest',
          reason: 'serde rejects $bad before the handler runs',
        );
      }
    });

    test('every quote error is a top-level MMRPC error', () async {
      final errors = <RoutedSwapQuoteError, Map<String, dynamic>>{
        RoutedSwapQuoteError.coinNotActive(from): {
          'error': 'Coin $from is not active',
          'error_data': {'coin': from},
        },
        RoutedSwapQuoteError.pairNotSupported(from, to, 'no EVM chain'): {
          'error': 'Pair $from/$to is not supported: no EVM chain',
          'error_data': {'from': from, 'to': to, 'reason': 'no EVM chain'},
        },
        RoutedSwapQuoteError.invalidParam(
          'amount',
          'more than 6 decimal '
              'places',
        ): {
          'error': 'Invalid parameter amount: more than 6 decimal places',
          'error_data': {
            'param': 'amount',
            'reason': 'more than 6 decimal places',
          },
        },
        RoutedSwapQuoteError.amountOutOfBounds(
          param: 'amount',
          value: '0',
          min: '0.000001',
          max: '1000',
        ): {
          'error':
              'Parameter amount out of bounds, value: 0, min: 0.000001 max: '
              '1000',
          'error_data': {
            'param': 'amount',
            'value': '0',
            'min': '0.000001',
            'max': '1000',
          },
        },
        RoutedSwapQuoteError.myAddressError(
          from,
          'HD wallet has no enabled '
          'address',
        ): {
          'error':
              'Cannot use $from source address: HD wallet has no enabled '
              'address',
          'error_data': {
            'coin': from,
            'message': 'HD wallet has no enabled address',
          },
        },
        RoutedSwapQuoteError.invalidConfig('lifi_api is not a URL'): {
          'error': 'lifi_api is not a URL',
          'error_data': {'message': 'lifi_api is not a URL'},
        },
        RoutedSwapQuoteError.noRouteFound(
          reasons: const ['Amount too low (across)'],
          providerRequestId: 'req-1',
        ): {
          'error': 'No route found',
          'error_data': {
            'reasons': ['Amount too low (across)'],
            'provider_request_id': 'req-1',
          },
        },
        RoutedSwapQuoteError.rateLimited(): {
          'error': 'Routed swap provider rate limit exceeded',
          'error_data': <String, dynamic>{},
        },
        RoutedSwapQuoteError.providerApiError('bad route'): {
          'error': 'bad route',
          'error_data': {'message': 'bad route'},
        },
        RoutedSwapQuoteError.transportError(
          'Unable to reach routed swap '
          'provider',
        ): {
          'error': 'Unable to reach routed swap provider',
          'error_data': {'message': 'Unable to reach routed swap provider'},
        },
        RoutedSwapQuoteError.internalError('boom'): {
          'error': 'boom',
          'error_data': {'message': 'boom'},
        },
      };
      for (final MapEntry(key: error, value: expected) in errors.entries) {
        final script = (RoutedSwapFixture()..quoteFails(from, to, error))
            .build();
        final response = await call(script, 'routed_swap::quote', {
          'from': from,
          'to': to,
          'amount': '1',
        });
        expect(response.containsKey('result'), isFalse);
        expect(response['mmrpc'], '2.0');
        expect(response['error_type'], error.errorType);
        expect(response['error'], expected['error']);
        expect(response['error_data'], expected['error_data']);
        expect(response['error_path'], isA<String>());
        expect(response['error_trace'], isA<String>());
      }
    });

    test('NoRouteFound always carries at least one reason', () {
      expect(
        () => RoutedSwapQuoteError.noRouteFound(reasons: const []),
        throwsArgumentError,
      );
      expect(RoutedSwapQuoteError.noRouteFound().errorData, {
        'reasons': ['No route found'],
      });
    });

    test('a scripted failure can be limited to the next calls', () async {
      final script =
          (RoutedSwapFixture()
                ..quote(route())
                ..quoteFails(
                  from,
                  to,
                  RoutedSwapQuoteError.rateLimited(providerRequestId: 'r'),
                  times: 1,
                ))
              .build();
      final params = {'from': from, 'to': to, 'amount': '1'};

      final first = await call(script, 'routed_swap::quote', params);
      expect(first['error_type'], 'RateLimited');
      expect(first['error_data'], {'provider_request_id': 'r'});
      final second = await call(script, 'routed_swap::quote', params);
      expect(second.containsKey('result'), isTrue);
    });
  });
}
