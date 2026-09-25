part of 'routed_swap_fixture_test.dart';

void _cases2() {
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
}
