import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';

/// Asserts the scripted `routed_swap` KDF against the engine's wire shapes
/// (`komodo-defi-framework` `feat/lifi-integration`, `routed_swap/`).
///
/// These test the fake, not a GUI: every consumer test inherits whatever the
/// fake gets wrong, so the shapes the engine promises are pinned here first.
void main() {
  const from = 'USDT-PLG20';
  const to = 'USDC-ERC20';

  RoutedSwapQuote route({
    RoutedSwapQuoteApproval? approval,
    bool crossChain = true,
    String toAmount = '100.21',
    String toAmountMin = '99.71',
    String? toolLogoUrl,
  }) => RoutedSwapQuote(
    from: from,
    to: to,
    toAmount: toAmount,
    toAmountMin: toAmountMin,
    crossChain: crossChain,
    toolLogoUrl: toolLogoUrl,
    approval: approval,
    steps: [
      const RoutedSwapQuoteStep.swap(tool: '1inch', chainId: 137),
      if (crossChain)
        const RoutedSwapQuoteStep.cross(
          tool: 'stargateV2',
          fromChainId: 137,
          toChainId: 1,
        ),
    ],
    feeCosts: [
      RoutedSwapQuoteFee(
        name: 'LIFI Fixed Fee',
        coin: from,
        amount: '0.05',
        amountUsd: '0.05',
        included: true,
      ),
      RoutedSwapQuoteFee(
        name: 'Bridge fee',
        symbol: 'axlUSDC',
        amount: '0.02',
        included: false,
      ),
    ],
    gasCosts: const [
      RoutedSwapQuoteGas(coin: 'MATIC', amount: '0.012', amountUsd: '0.01'),
      RoutedSwapQuoteGas(coin: 'ETH', amount: '0.001', amountUsd: '2.5'),
      RoutedSwapQuoteGas(coin: 'MATIC', amount: '0.003', amountUsd: '0.002'),
    ],
  );

  const approval = RoutedSwapQuoteApproval.noAllowance(
    gasCoin: 'MATIC',
    gasAmount: '0.0009',
  );

  Future<Map<String, dynamic>> call(
    KdfScript script,
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    final response = await script.respondTo({
      'mmrpc': '2.0',
      'method': method,
      'params': params,
    });
    if (response == null) fail('nothing scripted for $method');
    return response;
  }

  Future<int> start(
    KdfScript script, {
    String amount = '100.5',
    String minToAmount = '99.71',
  }) async {
    final init = await call(script, 'task::routed_swap::init', {
      'from': from,
      'to': to,
      'amount': amount,
      'min_to_amount': minToAmount,
    });
    return _map(init['result'])['task_id'] as int;
  }

  Future<Map<String, dynamic>> poll(
    KdfScript script,
    int taskId, {
    bool? forget = false,
  }) => call(script, 'task::routed_swap::status', {
    'task_id': taskId,
    'forget_if_finished': ?forget,
  });

  /// Polls until terminal, returning every `result` seen.
  Future<List<Map<String, dynamic>>> drain(KdfScript script, int taskId) async {
    final seen = <Map<String, dynamic>>[];
    for (var i = 0; i < 50; i++) {
      final result = _map((await poll(script, taskId))['result']);
      seen.add(result);
      if (result['status'] != 'InProgress') return seen;
    }
    fail('the run never reached a terminal result');
  }

  Future<Map<String, dynamic>> terminal(
    RoutedSwapRun run, {
    RoutedSwapFixture? fixture,
    String minToAmount = '99.71',
  }) async {
    final f = (fixture ?? RoutedSwapFixture())..run(run);
    final script = f.build();
    final taskId = await start(script, minToAmount: minToAmount);
    return (await drain(script, taskId)).last;
  }

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

  group('task::routed_swap::init', () {
    test('answers task_id only and persists before the first read', () async {
      final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
      final script = fixture.build();

      final init = await call(script, 'task::routed_swap::init', {
        'client_id': 42,
        'from': from,
        'to': to,
        'amount': '100.50',
        'min_to_amount': '99.710',
        'slippage': 0.005,
        'order': 'fastest',
        'provider': 'lifi',
      });
      expect(init['result'], {'task_id': 1});

      // Never polled, yet recoverable by uuid.
      final entry = fixture.historyEntries.single;
      expect(entry['requested'], {'from': from, 'to': to, 'amount': '100.5'});
      expect(entry['min_to_amount_accepted'], '99.71');
      expect(entry['swap'], {
        'status': 'InProgress',
        'details': {
          'state': 'FetchingQuote',
          'uuid': fixture.uuidOf(1),
          'provider': 'lifi',
        },
      });
    });

    test('a pre-task rejection is a top-level error and no record', () async {
      final fixture = RoutedSwapFixture()
        ..initFails(RoutedSwapQuoteError.coinNotActive(to))
        ..run(RoutedSwapRun());
      final script = fixture.build();

      final rejected = await call(script, 'task::routed_swap::init', {
        'from': from,
        'to': to,
        'amount': '1',
        'min_to_amount': '1',
      });
      expect(rejected['error_type'], 'CoinNotActive');
      expect(rejected.containsKey('result'), isFalse);
      expect(fixture.historyEntries, isEmpty);

      // The queue moves on to the run.
      expect(await start(script, amount: '1', minToAmount: '1'), 1);
    });

    test('provider errors cannot reject init: the task raises them', () {
      for (final error in [
        RoutedSwapQuoteError.noRouteFound(),
        RoutedSwapQuoteError.rateLimited(),
        RoutedSwapQuoteError.providerApiError('x'),
        RoutedSwapQuoteError.transportError('x'),
        RoutedSwapQuoteError.invalidConfig('x'),
      ]) {
        expect(
          () => RoutedSwapFixture().initFails(error),
          throwsArgumentError,
          reason: error.errorType,
        );
      }
    });

    test('requires min_to_amount and rejects unknown fields', () async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun())).build();
      final missing = await call(script, 'task::routed_swap::init', {
        'from': from,
        'to': to,
        'amount': '1',
      });
      expect(missing['error_type'], 'InvalidRequest');
      final unknown = await call(script, 'task::routed_swap::init', {
        'from': from,
        'to': to,
        'amount': '1',
        'min_to_amount': '1',
        'uuid': 'nope',
      });
      expect(unknown['error_type'], 'InvalidRequest');
    });

    test('with nothing scripted it is a scripting bug', () async {
      await expectLater(start(RoutedSwapFixture().build()), throwsStateError);
    });
  });

  group('the in-progress ladder', () {
    late List<Map<String, dynamic>> seen;
    late Map<String, dynamic> routeJson;
    late String uuid;

    setUp(() async {
      final fixture = RoutedSwapFixture()..quote(route(approval: approval));
      final script = (fixture..run(RoutedSwapRun())).build();
      final taskId = await start(script);
      uuid = fixture.uuidOf(taskId);
      routeJson = route(approval: approval).toJson(amount: '100.5');
      seen = await drain(script, taskId);
    });

    List<Map<String, dynamic>> details(String state) => [
      for (final result in seen)
        if (_map(result['details'])['state'] == state) _map(result['details']),
    ];

    test('walks the engine ladder, then reports Ok', () {
      expect(
        [for (final r in seen) _map(r['details'])['state'] ?? r['status']],
        [
          'FetchingQuote',
          'CheckingAllowance',
          'Approving',
          'Approving',
          'Signing',
          'Broadcasting',
          'WaitingSourceConfirmation',
          'TrackingBridge',
          'TrackingBridge',
          'TrackingBridge',
          'Ok',
        ],
      );
      for (final result in seen) {
        _expectNoNulls(result);
        expect(_json(result), isNot(contains('"tx_hash"')));
      }
    });

    test('every state carries uuid and provider; FetchingQuote no more', () {
      for (final result in seen) {
        expect(_map(result['details'])['uuid'], uuid);
        expect(_map(result['details'])['provider'], 'lifi');
      }
      expect(details('FetchingQuote').single.keys.toSet(), {
        'state',
        'uuid',
        'provider',
      });
    });

    test('executed_route rides every state after FetchingQuote', () {
      for (final result in seen.skip(1)) {
        expect(_map(result['details'])['executed_route'], routeJson);
      }
    });

    test('Approving has no hash until the approval is broadcast', () {
      final approving = details('Approving');
      expect(approving.first.containsKey('approve_tx_hash'), isFalse);
      expect(approving.last['approve_tx_hash'], startsWith('0x'));
      expect(approving.last['approve_tx_hash'], hasLength(66));
    });

    test('the source hash appears at Broadcasting and stays', () {
      final source = details('Broadcasting').single['source_tx_hash'];
      expect(source, isA<String>());
      expect(
        details('WaitingSourceConfirmation').single['source_tx_hash'],
        source,
      );
      for (final tracking in details('TrackingBridge')) {
        expect(tracking['source_tx_hash'], source);
        expect(tracking['execution_duration_s'], 95);
      }
    });

    test('TrackingBridge starts bare, then follows the provider', () {
      final tracking = details('TrackingBridge');
      expect(tracking.first.keys.toSet(), {
        'state',
        'uuid',
        'provider',
        'executed_route',
        'source_tx_hash',
        'stage',
        'execution_duration_s',
      });
      expect(tracking.first['stage'], 'unknown');
      expect(tracking[1]['stage'], 'destination_pending');
      expect(tracking[1]['substatus'], 'WAIT_DESTINATION_TRANSACTION');
      expect(tracking[1]['substatus_message'], isA<String>());
      expect(tracking[1]['provider_explorer_url'], startsWith('https://'));
      // The terminal provider poll is persisted too, and a stage never
      // regresses on a substatus that maps to none.
      expect(tracking.last['substatus'], 'COMPLETED');
      expect(tracking.last['stage'], 'destination_pending');
    });
  });

  group('approvals', () {
    test('a zero-reset shows two hashes and history keeps both', () async {
      final fixture = RoutedSwapFixture()
        ..quote(
          route(
            approval: const RoutedSwapQuoteApproval.zeroReset(
              gasCoin: 'MATIC',
              gasAmount: '0.0018',
            ),
          ),
        )
        ..run(RoutedSwapRun(approvalGas: '0.001', sourceGas: '0.002'));
      final script = fixture.build();
      final taskId = await start(script);
      final seen = await drain(script, taskId);

      final hashes = [
        for (final result in seen)
          if (_map(result['details'])['approve_tx_hash'] case final String h) h,
      ];
      expect(hashes.toSet(), hasLength(2));

      final entry = fixture.historyEntry(fixture.uuidOf(taskId));
      expect(entry['approval_tx_hashes'], hashes.toSet().toList());
      final source = _map(seen.last['details'])['source_tx_hash'];
      expect(entry['gas_spent'], [
        {'tx_hash': hashes.first, 'coin': 'MATIC', 'amount': '0.001'},
        {'tx_hash': hashes.last, 'coin': 'MATIC', 'amount': '0.001'},
        {'tx_hash': source, 'coin': 'MATIC', 'amount': '0.002'},
      ]);
      expect(entry['total_gas_spent'], [
        {'coin': 'MATIC', 'amount': '0.004'},
      ]);
    });
  });

  group('terminal Ok', () {
    test('a completed cross-chain swap has a destination hash', () async {
      final result = await terminal(RoutedSwapRun());
      final details = _map(result['details']);
      expect(result['status'], 'Ok');
      expect(details.keys.toSet(), {
        'outcome',
        'uuid',
        'provider',
        'executed_route',
        'received',
        'source_tx_hash',
        'dest_tx_hash',
        'provider_explorer_url',
      });
      expect(details['outcome'], 'completed');
      expect(details['received'], {'coin': to, 'amount': '99.71'});
    });

    test(
      'a same-chain swap never tracks a bridge nor has a dest hash',
      () async {
        final fixture = RoutedSwapFixture()
          ..quote(route(crossChain: false))
          ..run(RoutedSwapRun());
        final script = fixture.build();
        final seen = await drain(script, await start(script));

        expect(
          seen.map((r) => _map(r['details'])['state']),
          isNot(contains('TrackingBridge')),
        );
        final details = _map(seen.last['details']);
        expect(details['outcome'], 'completed');
        // The executed route's quoted to.amount, not a measured transfer.
        expect(details['received'], {'coin': to, 'amount': '100.21'});
        expect(details.containsKey('dest_tx_hash'), isFalse);
        expect(details.containsKey('provider_explorer_url'), isFalse);
      },
    );

    test('partial below_minimum delivers the requested coin', () async {
      final result = await terminal(
        RoutedSwapRun(
          outcome: RoutedSwapRunOutcome.partial,
          partialReason: 'below_minimum',
          receivedAmount: '98.4',
        ),
      );
      final details = _map(result['details']);
      expect(details['outcome'], 'partial');
      expect(details['partial_reason'], 'below_minimum');
      expect(details['received'], {'coin': to, 'amount': '98.4'});
      expect(details['dest_tx_hash'], isA<String>());
    });

    test('partial intermediate_token can be a provider symbol', () async {
      final result = await terminal(
        RoutedSwapRun(
          outcome: RoutedSwapRunOutcome.partial,
          partialReason: 'intermediate_token',
          receivedSymbol: 'axlUSDC',
          receivedAmount: '100.1',
        ),
      );
      final received = _map(_map(result['details'])['received']);
      expect(received, {'symbol': 'axlUSDC', 'amount': '100.1'});
    });

    test('refunded returns the source coin without a dest hash', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun(outcome: RoutedSwapRunOutcome.refunded));
      final script = fixture.build();
      final seen = await drain(script, await start(script));
      final details = _map(seen.last['details']);

      expect(details['outcome'], 'refunded');
      expect(details['received'], {'coin': from, 'amount': '100.5'});
      expect(details.containsKey('dest_tx_hash'), isFalse);
      final stages = [
        for (final r in seen)
          if (_map(r['details'])['stage'] case final String stage) stage,
      ];
      expect(stages, ['unknown', 'refund_pending', 'refund_pending']);
    });

    test('an outcome the engine would classify otherwise is refused', () async {
      Future<void> refused(RoutedSwapRun run) =>
          expectLater(terminal(run), throwsArgumentError);
      // Below the accepted minimum is partial, never completed.
      await refused(RoutedSwapRun(receivedAmount: '1'));
      // Another token is intermediate_token, not below_minimum.
      await refused(
        RoutedSwapRun(
          outcome: RoutedSwapRunOutcome.partial,
          partialReason: 'below_minimum',
          receivedSymbol: 'axlUSDC',
          receivedAmount: '1',
        ),
      );
      // Same-chain swaps only complete.
      await refused(
        RoutedSwapRun(
          route: route(crossChain: false),
          outcome: RoutedSwapRunOutcome.refunded,
        ),
      );
    });
  });

  group('terminal Error', () {
    Future<Map<String, dynamic>> failed(
      RoutedSwapRunError error, {
      RoutedSwapQuote? executed,
      List<RoutedSwapTick>? ladder,
    }) async {
      final result = await terminal(
        RoutedSwapRun(route: executed, error: error, ladder: ladder),
      );
      expect(result['status'], 'Error');
      final details = _map(result['details']);
      _expectNoNulls(details);
      expect(details['uuid'], isA<String>());
      expect(details['provider'], 'lifi');
      expect(details['error_path'], isA<String>());
      expect(details['error_trace'], isA<String>());
      final data = details['error_data'];
      if (data is Map) {
        expect(
          data.containsKey('uuid'),
          isFalse,
          reason: 'uuid is hoisted beside error_type, never in error_data',
        );
      }
      return details;
    }

    test('QuoteWorsened carries the fresh route and no executed one', () async {
      final fresh = route(toAmount: '98.8', toAmountMin: '98.31');
      final details = await failed(
        RoutedSwapRunError.quoteWorsened(freshRoute: fresh),
      );
      expect(details['error_type'], 'QuoteWorsened');
      expect(details['error'], 'Fresh route is below the accepted minimum');
      expect(details.containsKey('executed_route'), isFalse);
      expect(details['error_data'], {
        'fresh_route': fresh.toJson(amount: '100.5'),
      });
    });

    test('a route below the guard fails QuoteWorsened on its own', () async {
      // Passing the expected amount as min_to_amount instead of the minimum
      // is caught here exactly as the engine's guard catches it.
      final fixture = RoutedSwapFixture()..quote(route());
      final result = await terminal(
        RoutedSwapRun(),
        fixture: fixture,
        minToAmount: '100.21',
      );
      expect(_map(result['details'])['error_type'], 'QuoteWorsened');
    });

    test('fresh-quote errors carry no executed_route', () async {
      for (final error in [
        RoutedSwapRunError.noRouteFound(providerRequestId: 'req'),
        RoutedSwapRunError.rateLimited(),
        RoutedSwapRunError.providerApiError('upstream'),
        RoutedSwapRunError.amountOutOfBounds(
          param: 'amount',
          value: '0.1',
          min: '1',
          max: '100',
        ),
        RoutedSwapRunError.transportError(
          'Unable to reach routed swap provider',
        ),
      ]) {
        final details = await failed(error);
        expect(
          details.containsKey('executed_route'),
          isFalse,
          reason: error.errorType,
        );
      }
    });

    test('errors after FetchingQuote carry executed_route', () async {
      final expected = <RoutedSwapRunError, Map<String, dynamic>>{
        RoutedSwapRunError.insufficientBalance(
          coin: 'MATIC',
          available: '0.001',
          requiredAmount: '0.0159',
        ): {
          'error':
              'Insufficient MATIC balance: available 0.001, required 0.0159',
          'error_data': {
            'coin': 'MATIC',
            'available': '0.001',
            'required': '0.0159',
          },
        },
        RoutedSwapRunError.preflightRejected('target_allowlist'): {
          'error':
              'Routed swap preflight rejected by the target_allowlist check',
          'error_data': {'check': 'target_allowlist'},
        },
        RoutedSwapRunError.approvalFailed('approval_transaction_failed'): {
          'error': 'Token approval failed: approval_transaction_failed',
          'error_data': {'reason': 'approval_transaction_failed'},
        },
        RoutedSwapRunError.signingRejected('user_rejected'): {
          'error': 'Wallet rejected the routed swap transaction: user_rejected',
          'error_data': {'reason': 'user_rejected'},
        },
        RoutedSwapRunError.internalError('Source wallet address changed'): {
          'error': 'Source wallet address changed',
          'error_data': {'message': 'Source wallet address changed'},
        },
      };
      for (final MapEntry(key: error, value: wire) in expected.entries) {
        final details = await failed(error);
        expect(details['executed_route'], isA<Map<String, dynamic>>());
        expect(details['error_type'], error.errorType);
        expect(details['error'], wire['error']);
        expect(details['error_data'], wire['error_data']);
      }
    });

    test('SwapTxFailed names the source transaction', () async {
      for (final reason in [
        'source_transaction_reverted',
        'source_transaction_not_confirmed',
      ]) {
        final details = await failed(RoutedSwapRunError.swapTxFailed(reason));
        final data = _map(details['error_data']);
        expect(data.keys.toSet(), {'source_tx_hash', 'reason'});
        expect(data['reason'], reason);
        expect(
          details['error'],
          'Routed swap transaction ${data['source_tx_hash']} failed: $reason',
        );
      }
    });

    test(
      'BridgeFailed omits absent fields and never has a request id',
      () async {
        final bare = await failed(
          RoutedSwapRunError.bridgeFailed(substatus: null),
        );
        expect(_map(bare['error_data']).keys, ['source_tx_hash']);

        final full = await failed(
          RoutedSwapRunError.bridgeFailed(
            substatusMessage: 'Manual support is required',
            providerExplorerUrl: 'https://scan.li.fi/tx/0x1',
          ),
        );
        expect(full['error_data'], {
          'source_tx_hash': _map(full['error_data'])['source_tx_hash'],
          'substatus': 'UNKNOWN_ERROR',
          'substatus_message': 'Manual support is required',
          'provider_explorer_url': 'https://scan.li.fi/tx/0x1',
        });
      },
    );

    test('InternalError is legal after Broadcasting', () async {
      final details = await failed(
        RoutedSwapRunError.internalError(
          'Broadcast handoff did not return a transaction hash',
        ),
        ladder: const [
          RoutedSwapTick.fetchingQuote,
          RoutedSwapTick.checkingAllowance,
          RoutedSwapTick.signing,
          RoutedSwapTick.broadcasting(withSourceTxHash: false),
        ],
      );
      expect(details['executed_route'], isA<Map<String, dynamic>>());
    });
  });

  group('stage guards', () {
    const preBroadcast = [
      RoutedSwapTick.fetchingQuote,
      RoutedSwapTick.checkingAllowance,
      RoutedSwapTick.signing,
    ];
    const confirming = [
      ...preBroadcast,
      RoutedSwapTick.broadcasting(),
      RoutedSwapTick.waitingSourceConfirmation,
    ];
    const tracking = [...confirming, RoutedSwapTick.trackingBridge()];

    void impossible(
      String why,
      RoutedSwapRunError? error,
      List<RoutedSwapTick> ladder, {
      RoutedSwapQuote? executed,
    }) {
      expect(
        () => RoutedSwapRun(route: executed, error: error, ladder: ladder),
        throwsArgumentError,
        reason: why,
      );
    }

    test('refuses errors raised where the engine cannot raise them', () {
      impossible(
        'fresh-quote errors happen while FetchingQuote',
        RoutedSwapRunError.rateLimited(),
        preBroadcast,
      );
      impossible(
        'balances are checked before any approval or signing',
        RoutedSwapRunError.insufficientBalance(
          coin: 'MATIC',
          available: '0',
          requiredAmount: '1',
        ),
        preBroadcast,
      );
      impossible(
        'preflight runs before Signing',
        RoutedSwapRunError.preflightRejected('simulation'),
        preBroadcast,
      );
      impossible(
        'approvals fail at Approving',
        RoutedSwapRunError.approvalFailed('approval_broadcast_failed'),
        preBroadcast,
      );
      impossible(
        'a failed approval transaction was broadcast, so it has a hash',
        RoutedSwapRunError.approvalFailed('approval_transaction_failed'),
        const [
          RoutedSwapTick.fetchingQuote,
          RoutedSwapTick.checkingAllowance,
          RoutedSwapTick.approving(),
        ],
      );
      impossible(
        'the source transaction fails at WaitingSourceConfirmation',
        RoutedSwapRunError.swapTxFailed('source_transaction_reverted'),
        preBroadcast,
      );
      impossible(
        'a confirmed source transaction cannot fail later',
        RoutedSwapRunError.swapTxFailed('source_transaction_reverted'),
        tracking,
      );
      impossible(
        'BridgeFailed happens while tracking',
        RoutedSwapRunError.bridgeFailed(),
        confirming,
      );
      impossible(
        'same-chain swaps never track a bridge',
        RoutedSwapRunError.bridgeFailed(),
        tracking,
        executed: route(crossChain: false),
      );
      impossible(
        'transport problems after broadcast keep tracking',
        RoutedSwapRunError.transportError('socket closed'),
        confirming,
      );
      impossible(
        'a local signer broadcasting with a hash cannot be rejected',
        RoutedSwapRunError.signingRejected('timeout'),
        [...preBroadcast, const RoutedSwapTick.broadcasting()],
      );
      impossible(
        'an Ok outcome needs a confirmed source transaction',
        null,
        preBroadcast,
      );
    });

    test('accepts the external-wallet exceptions', () {
      expect(
        () => RoutedSwapRun(
          error: RoutedSwapRunError.signingRejected('timeout'),
          ladder: [
            ...preBroadcast,
            const RoutedSwapTick.broadcasting(withSourceTxHash: false),
          ],
        ),
        returnsNormally,
      );
      expect(
        () => RoutedSwapRun(
          error: RoutedSwapRunError.internalError('handoff failed'),
          ladder: tracking,
        ),
        returnsNormally,
      );
    });

    test('refuses a ladder the engine cannot persist', () {
      impossible('init persists FetchingQuote first', null, const [
        RoutedSwapTick.checkingAllowance,
      ]);
      impossible('states only move forward', null, const [
        RoutedSwapTick.fetchingQuote,
        RoutedSwapTick.signing,
      ]);
      impossible(
        'the first Approving precedes any broadcast approval',
        RoutedSwapRunError.approvalFailed('approval_broadcast_failed'),
        const [
          RoutedSwapTick.fetchingQuote,
          RoutedSwapTick.checkingAllowance,
          RoutedSwapTick.approving('0xa'),
        ],
      );
      impossible('the first TrackingBridge is bare', null, [
        ...confirming,
        const RoutedSwapTick.trackingBridge(substatus: 'PENDING'),
      ]);
      expect(
        () => RoutedSwapRun(
          outcome: RoutedSwapRunOutcome.completed,
          error: RoutedSwapRunError.rateLimited(),
        ),
        throwsArgumentError,
      );
      expect(
        () => RoutedSwapRun(outcome: RoutedSwapRunOutcome.partial),
        throwsArgumentError,
      );
      expect(
        () => RoutedSwapRunError.bridgeFailed(substatus: 'REFUND_IN_PROGRESS'),
        throwsArgumentError,
      );
    });

    test('a route below the guard cannot reach a later error', () async {
      final fixture = RoutedSwapFixture()..quote(route());
      await expectLater(
        terminal(
          RoutedSwapRun(
            error: RoutedSwapRunError.insufficientBalance(
              coin: 'MATIC',
              available: '0',
              requiredAmount: '1',
            ),
          ),
          fixture: fixture,
          minToAmount: '100.21',
        ),
        throwsArgumentError,
      );
    });

    test('non-positive amounts are init rejections to script', () async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun())).build();
      await expectLater(start(script, minToAmount: '0'), throwsArgumentError);
      final malformed = await call(script, 'task::routed_swap::init', {
        'from': from,
        'to': to,
        'amount': 'lots',
        'min_to_amount': '1',
      });
      expect(malformed['error_type'], 'InvalidRequest');
    });

    test('QuoteWorsened needs a fresh minimum below the guard', () async {
      await expectLater(
        terminal(
          RoutedSwapRun(
            error: RoutedSwapRunError.quoteWorsened(freshRoute: route()),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('forget_if_finished', () {
    Future<(KdfScript, int)> finishedTask() async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun())).build();
      final taskId = await start(script);
      await drain(script, taskId);
      return (script, taskId);
    }

    test('defaults to true and forgets the terminal result', () async {
      final (script, taskId) = await finishedTask();
      final read = await poll(script, taskId, forget: null);
      expect(_map(read['result'])['status'], 'Ok');

      final again = await poll(script, taskId);
      expect(again['error_type'], 'NoSuchTask');
      expect(again.containsKey('result'), isFalse);
    });

    test('false keeps the terminal result readable', () async {
      final (script, taskId) = await finishedTask();
      final first = await poll(script, taskId);
      final second = await poll(script, taskId);
      expect(first['result'], second['result']);
    });

    test('an in-progress read never forgets', () async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun())).build();
      final taskId = await start(script);
      await poll(script, taskId, forget: true);
      final again = await poll(script, taskId, forget: true);
      expect(_map(again['result'])['status'], 'InProgress');
    });

    test('an unknown task is NoSuchTask with the bare id', () async {
      final response = await poll(RoutedSwapFixture().build(), 99);
      expect(response['error_type'], 'NoSuchTask');
      expect(response['error_data'], 99);
      expect(response['error'], "No such task '99'");
    });
  });

  group('driving', () {
    test('pollsPerState repeats each state before advancing', () async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun(pollsPerState: 2)))
          .build();
      final taskId = await start(script);
      final states = [
        for (var i = 0; i < 4; i++)
          _map(
            _map((await poll(script, taskId))['result'])['details'],
          )['state'],
      ];
      expect(states, [
        'FetchingQuote',
        'FetchingQuote',
        'CheckingAllowance',
        'CheckingAllowance',
      ]);
    });

    test('advance moves the engine between reads', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun(autoAdvance: false));
      final script = fixture.build();
      final taskId = await start(script);
      Future<Object?> state() async => _map(
        _map((await poll(script, taskId))['result'])['details'],
      )['state'];

      expect(await state(), 'FetchingQuote');
      expect(await state(), 'FetchingQuote');
      fixture.advance(taskId, steps: 3);
      expect(await state(), 'Broadcasting');
      fixture.advance(taskId, steps: 100);
      expect(_map((await poll(script, taskId))['result'])['status'], 'Ok');
    });

    test('advanceOnInit lets the task race ahead of the first read', () async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun(advanceOnInit: 2)))
          .build();
      final first = await poll(script, await start(script));
      expect(_map(_map(first['result'])['details'])['state'], 'Signing');
    });
  });

  group('task::routed_swap::cancel', () {
    test('accepted before Broadcasting: removed and recorded', () async {
      final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
      final script = fixture.build();
      final taskId = await start(script);
      await poll(script, taskId);
      await poll(script, taskId); // CheckingAllowance

      final cancel = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      expect(cancel, {'mmrpc': '2.0', 'result': 'success', 'id': null});
      expect((await poll(script, taskId))['error_type'], 'NoSuchTask');

      final entry = fixture.historyEntry(fixture.uuidOf(taskId));
      final swap = _map(entry['swap']);
      expect(swap['status'], 'Error');
      expect(_map(swap['details']).keys.toSet(), {
        'uuid',
        'provider',
        'executed_route',
        'error_type',
        'error',
      });
      expect(_map(swap['details'])['error_type'], 'TaskCancelled');
      expect(
        _map(swap['details'])['error'],
        'Routed swap cancelled before broadcast',
      );
      expect(entry['finished_at'], entry['updated_at']);

      final again = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      expect(again['error_type'], 'NoSuchTask');
      expect(again['error_data'], {'task_id': taskId});
    });

    test('refused once Broadcasting has begun; tracking continues', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun(autoAdvance: false));
      final script = fixture.build();
      final taskId = await start(script);
      fixture.advance(taskId, steps: 3); // Broadcasting

      final cancel = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      expect(cancel['error_type'], 'TaskAlreadyBroadcast');
      expect(cancel['error_data'], {'task_id': taskId});
      expect(
        cancel['error'],
        'Routed swap task has already broadcast: $taskId',
      );
      expect(
        _map((await poll(script, taskId))['result'])['status'],
        'InProgress',
      );
    });

    test('refused with TaskFinished while the result waits', () async {
      final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
      final script = fixture.build();
      final taskId = await start(script);
      fixture.advance(taskId, steps: 100);

      final cancel = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      expect(cancel['error_type'], 'TaskFinished');
      expect(cancel['error_data'], {'task_id': taskId});
      // Not recorded as a cancellation.
      expect(_map(fixture.historyEntries.single['swap'])['status'], 'Ok');
    });

    test('InternalError has a bare message and leaves the task', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun())
        ..cancelFailsInternally();
      final script = fixture.build();
      final taskId = await start(script);

      final cancel = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      expect(cancel['error_type'], 'InternalError');
      expect(cancel['error_data'], 'Unable to persist routed swap state');
      expect(fixture.hasTask(taskId), isTrue);
    });

    test('a late approval hash extends the record, not the outcome', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route(approval: approval))
        ..run(RoutedSwapRun(autoAdvance: false));
      final script = fixture.build();
      final taskId = await start(script);
      fixture.advance(taskId, steps: 2); // Approving, nothing broadcast
      await call(script, 'task::routed_swap::cancel', {'task_id': taskId});
      final uuid = fixture.uuidOf(taskId);
      final before = fixture.historyEntry(uuid);
      expect(before['approval_tx_hashes'], isEmpty);

      fixture.recordLateApprovalHash(uuid, '0xlate');
      final after = fixture.historyEntry(uuid);
      expect(after['approval_tx_hashes'], ['0xlate']);
      expect(after['finished_at'], greaterThan(before['finished_at'] as int));
      expect(
        _map(_map(after['swap'])['details'])['error_type'],
        'TaskCancelled',
      );
    });
  });

  group('restart', () {
    test('pre-broadcast becomes AbortedOnRestart and ids die', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun());
      final script = fixture.build();
      final atQuote = await start(script);
      final atAllowance = await start(script);
      await poll(script, atAllowance);
      await poll(script, atAllowance);

      fixture.restartKdf();

      for (final taskId in [atQuote, atAllowance]) {
        expect((await poll(script, taskId))['error_type'], 'NoSuchTask');
      }
      final quoteSwap = _map(
        fixture.historyEntry(fixture.uuidOf(atQuote))['swap'],
      );
      expect(_map(quoteSwap['details']).keys.toSet(), {
        'uuid',
        'provider',
        'error_type',
        'error',
      });
      final allowanceSwap = _map(
        fixture.historyEntry(fixture.uuidOf(atAllowance))['swap'],
      );
      final details = _map(allowanceSwap['details']);
      expect(details['error_type'], 'AbortedOnRestart');
      expect(details['error'], 'Swap aborted by node restart before broadcast');
      expect(details['executed_route'], isA<Map<String, dynamic>>());
    });

    test('post-broadcast resumes from WaitingSourceConfirmation', () async {
      final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
      final script = fixture.build();
      final taskId = await start(script);
      fixture.advance(taskId, steps: 6); // the second TrackingBridge
      final uuid = fixture.uuidOf(taskId);

      fixture.restartKdf();

      Map<String, dynamic> swap() => _map(fixture.historyEntry(uuid)['swap']);
      expect(swap()['status'], 'InProgress');
      expect(_map(swap()['details'])['stage'], 'destination_pending');
      expect(() => fixture.advance(taskId), throwsArgumentError);

      fixture.advancePersisted(uuid);
      expect(_map(swap()['details'])['state'], 'WaitingSourceConfirmation');
      fixture.advancePersisted(uuid);
      expect(_map(swap()['details'])['stage'], 'unknown');

      fixture.finishPersisted(uuid);
      expect(swap()['status'], 'Ok');
      final entry = fixture.historyEntry(uuid);
      expect(entry['finished_at'], isA<int>());
      // The resumed confirmation does not record the source gas twice.
      expect(entry['gas_spent'], hasLength(1));
    });

    test('a handoff with no saved hash becomes InternalError', () async {
      final fixture = RoutedSwapFixture()
        ..run(
          RoutedSwapRun(
            autoAdvance: false,
            ladder: const [
              RoutedSwapTick.fetchingQuote,
              RoutedSwapTick.checkingAllowance,
              RoutedSwapTick.signing,
              RoutedSwapTick.broadcasting(withSourceTxHash: false),
              RoutedSwapTick.waitingSourceConfirmation,
              RoutedSwapTick.trackingBridge(),
            ],
          ),
        );
      final script = fixture.build();
      final taskId = await start(script);
      fixture
        ..advance(taskId, steps: 3)
        ..restartKdf();

      final details = _map(
        _map(fixture.historyEntry(fixture.uuidOf(taskId))['swap'])['details'],
      );
      expect(details['error_type'], 'InternalError');
      expect(details['error_data'], {
        'message': 'Broadcast handoff did not persist a transaction hash',
      });
      expect(details['executed_route'], isA<Map<String, dynamic>>());
    });

    test('task ids start over after a restart', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun());
      final script = fixture.build();
      final first = await start(script);
      fixture.restartKdf();
      final second = await start(script);
      expect(second, first);
      expect(fixture.uuidOf(second), isNot(_uuid(1)));

      fixture.restartKdf(reuseTaskIds: false);
      expect(await start(script), second + 1);
    });
  });

  group('routed_swap::history', () {
    Future<Map<String, dynamic>> history(
      KdfScript script, [
      Map<String, dynamic> params = const {},
    ]) => call(script, 'routed_swap::history', params);

    test('the envelope defaults to page 1 of 10', () async {
      final fixture = RoutedSwapFixture();
      for (var i = 0; i < 12; i++) {
        fixture.run(RoutedSwapRun());
      }
      final script = fixture.build();
      for (var i = 0; i < 12; i++) {
        await start(script);
      }

      final page = _map((await history(script))['result']);
      expect(page.keys.toSet(), {
        'entries',
        'total',
        'limit',
        'page_number',
        'total_pages',
      });
      expect(_list(page['entries']), hasLength(10));
      expect([page['total'], page['limit'], page['page_number']], [12, 10, 1]);
      expect(page['total_pages'], 2);

      final last = _map(
        (await history(script, {'limit': 5, 'page_number': 3}))['result'],
      );
      expect(_list(last['entries']), hasLength(2));
      expect(last['total_pages'], 3);
    });

    test('sorts newest first, uuid ascending within a second', () async {
      final fixture = RoutedSwapFixture(clock: () => 1000)
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun());
      final script = fixture.build();
      await start(script);
      await start(script);
      final uuids = [
        for (final entry in _list(
          _map((await history(script))['result'])['entries'],
        ))
          _map(_map(_map(entry)['swap'])['details'])['uuid'],
      ];
      expect(uuids, [_uuid(1), _uuid(2)]);

      final counter = RoutedSwapFixture()
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun());
      final counted = counter.build();
      await start(counted);
      await start(counted);
      expect(
        counter.historyEntries.map(
          (e) => _map(_map(e['swap'])['details'])['uuid'],
        ),
        [_uuid(2), _uuid(1)],
      );
    });

    test('filters by uuid, status, coins and created_at', () async {
      var now = 100;
      final fixture = RoutedSwapFixture(clock: () => now)
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun());
      final script = fixture.build();
      final done = await start(script);
      fixture.advance(done, steps: 100);
      now = 200;
      await start(script);
      Future<int> total(Map<String, dynamic> params) async =>
          _map((await history(script, params))['result'])['total'] as int;

      expect(await total({'uuid': _uuid(1)}), 1);
      expect(await total({'uuid': _uuid(1).replaceAll('-', '')}), 1);
      expect(await total({'uuid': null}), 2);
      expect(await total({'status_filter': 'in_flight'}), 1);
      expect(await total({'status_filter': 'terminal'}), 1);
      expect(await total({'my_coin': from}), 2);
      expect(await total({'other_coin': from}), 0);
      expect(await total({'from_timestamp': 200}), 1);
      // to_timestamp is exclusive.
      expect(await total({'to_timestamp': 200}), 1);
      expect(await total({'from_timestamp': 100, 'to_timestamp': 100}), 0);
    });

    test('rejects invalid paging and ranges', () async {
      final script = RoutedSwapFixture().build();
      final zero = await history(script, {'limit': 0});
      expect(zero['error_type'], 'InvalidParam');
      expect(zero['error_data'], {
        'param': 'limit',
        'reason': 'Pagination must have a positive limit',
      });
      final range = await history(script, {
        'from_timestamp': 2,
        'to_timestamp': 1,
      });
      expect(range['error_data'], {
        'param': 'to_timestamp',
        'reason': 'Must not precede from_timestamp',
      });
      for (final bad in [
        {'page_number': 0},
        {'uuid': 'nope'},
        {'status_filter': 'done'},
        {'limit': null},
        {'status_filter': null},
      ]) {
        expect(
          (await history(script, bad))['error_type'],
          'InvalidRequest',
          reason: '$bad',
        );
      }
    });

    test('an entry is the envelope around the exact status result', () async {
      final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
      final script = fixture.build();
      final taskId = await start(script);
      final uuid = fixture.uuidOf(taskId);

      for (var i = 0; i < 20; i++) {
        final live = _map((await poll(script, taskId))['result']);
        expect(fixture.historyEntry(uuid)['swap'], live);
        if (live['status'] != 'InProgress') break;
      }
      final entry = fixture.historyEntry(uuid);
      expect(entry.keys.toSet(), {
        'created_at',
        'updated_at',
        'finished_at',
        'requested',
        'min_to_amount_accepted',
        'approval_tx_hashes',
        'gas_spent',
        'total_gas_spent',
        'swap',
      });
      _expectNoNulls(entry);
    });

    test('finished_at is present only on terminal entries', () async {
      final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
      final script = fixture.build();
      await start(script);
      final entry = fixture.historyEntries.single;
      expect(entry.containsKey('finished_at'), isFalse);
      expect(entry['approval_tx_hashes'], isEmpty);
      expect(entry['gas_spent'], isEmpty);
      expect(entry['total_gas_spent'], isEmpty);
    });
  });
}

String _uuid(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

Map<String, dynamic> _map(Object? value) => value! as Map<String, dynamic>;

List<dynamic> _list(Object? value) => value! as List<dynamic>;

String _json(Object? value) => jsonEncode(value);

/// Optional fields are omitted, never null.
void _expectNoNulls(Object? value, [String path = r'$']) {
  if (value == null) fail('null at $path');
  if (value is Map) {
    for (final entry in value.entries) {
      _expectNoNulls(entry.value, '$path.${entry.key}');
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _expectNoNulls(value[i], '$path[$i]');
    }
  }
}
