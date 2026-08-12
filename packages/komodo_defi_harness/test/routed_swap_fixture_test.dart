import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';

/// Exercises the scripted `routed_swap` KDF against the contract in
/// `GLEECBTC/gleec-specs` PR #2.
///
/// These assert on the *fake*, not on a GUI. That is the point: the fixture is
/// the only executable statement of the contract we have until KDF implements
/// it, so if the fixture drifts from the spec every test built on top inherits
/// the drift silently. When §7 or any of the review's requested edits land,
/// this file is what fails first.
void main() {
  const from = 'USDT-PLG20';
  const to = 'USDC-ERC20';

  RoutedSwapFixture fixtureWith(RoutedSwapRun run) =>
      RoutedSwapFixture()..run(run);

  Future<Map<String, dynamic>> call(
    KdfScript script,
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    final response = await script.respondTo({
      'method': method,
      'params': params,
    });
    if (response == null) {
      fail('nothing scripted for $method');
    }
    return response;
  }

  Future<int> startSwap(KdfScript script) async {
    final init = await call(script, 'task::routed_swap::init', {
      'from': from,
      'to': to,
      'amount': '100.5',
      'min_to_amount': '99.71',
    });
    return (init['result'] as Map<String, dynamic>)['task_id'] as int;
  }

  Future<Map<String, dynamic>> poll(
    KdfScript script,
    int taskId, {
    bool forgetIfFinished = false,
  }) async {
    return call(script, 'task::routed_swap::status', {
      'task_id': taskId,
      'forget_if_finished': forgetIfFinished,
    });
  }

  group('task::routed_swap::init', () {
    test(
      'returns task_id only — the uuid is not in the init response',
      () async {
        final script = fixtureWith(RoutedSwapRun()).build();

        final init = await call(script, 'task::routed_swap::init', {
          'from': from,
          'to': to,
          'amount': '100.5',
          'min_to_amount': '99.71',
        });
        final result = init['result'] as Map<String, dynamic>;

        expect(result.keys, ['task_id']);
        // Revision a625348 removed the uuid from init specifically so routed
        // swap matches every other task::*::init. A fixture that kept returning
        // it would let the GUI build a durable reference the real KDF never
        // hands over.
        expect(result.containsKey('uuid'), isFalse);
      },
    );

    test('persists the uuid before the first status read', () async {
      final fixture = fixtureWith(RoutedSwapRun());
      final script = fixture.build();

      await startSwap(script);

      // Never polled, yet recoverable. This is what makes an app killed
      // between init and the first poll survivable at all.
      expect(fixture.historyEntries, hasLength(1));
      expect(fixture.historyEntries.single['uuid'], isNotEmpty);
      expect(fixture.historyEntries.single['status'], 'InProgress');
    });
  });

  group('the in-progress ladder', () {
    test('walks every state in contract order, then reports Ok', () async {
      final script = fixtureWith(RoutedSwapRun()).build();
      final taskId = await startSwap(script);

      final observed = <String>[];
      Map<String, dynamic> status;
      do {
        status = await poll(script, taskId);
        final result = status['result'] as Map<String, dynamic>;
        final details = result['details'] as Map<String, dynamic>;
        if (result['status'] == 'InProgress') {
          observed.add(details['state'] as String);
        }
      } while ((status['result'] as Map<String, dynamic>)['status'] ==
          'InProgress');

      expect(observed, [
        'FetchingQuote',
        'CheckingAllowance',
        'Approving',
        'Signing',
        'Broadcasting',
        'WaitingSourceConfirmation',
        'TrackingBridge',
      ]);
      expect((status['result'] as Map<String, dynamic>)['status'], 'Ok');
    });

    test('every InProgress details carries uuid, provider and state', () async {
      final script = fixtureWith(RoutedSwapRun()).build();
      final taskId = await startSwap(script);

      for (var i = 0; i < RoutedSwapState.values.length; i++) {
        final result =
            (await poll(script, taskId))['result'] as Map<String, dynamic>;
        final details = result['details'] as Map<String, dynamic>;
        expect(details['uuid'], isNotEmpty, reason: 'poll $i lost the uuid');
        expect(details['provider'], 'lifi');
        expect(details['state'], isNotEmpty);
      }
    });

    test('only the states the contract documents carry extra fields', () async {
      final script = fixtureWith(
        RoutedSwapRun(approveTxHash: '0xapproval'),
      ).build();
      final taskId = await startSwap(script);

      final byState = <String, Map<String, dynamic>>{};
      for (var i = 0; i < RoutedSwapState.values.length; i++) {
        final result =
            (await poll(script, taskId))['result'] as Map<String, dynamic>;
        final details = result['details'] as Map<String, dynamic>;
        byState[details['state'] as String] = details;
      }

      // A bare state must stay bare. If the fixture padded these with a tx
      // hash, a GUI could read one at a point KDF never promises it — and
      // would then render a link to a transaction that does not exist.
      expect(byState['FetchingQuote']!.keys, ['uuid', 'provider', 'state']);
      expect(byState['Signing']!.keys, ['uuid', 'provider', 'state']);
      expect(byState['Broadcasting']!.keys, ['uuid', 'provider', 'state']);

      expect(byState['Approving']!['approve_tx_hash'], '0xapproval');
      expect(byState['WaitingSourceConfirmation']!['tx_hash'], isNotEmpty);
      expect(byState['TrackingBridge']!['substatus'], isNotEmpty);
      expect(byState['TrackingBridge']!['provider_explorer_url'], isNotEmpty);
    });

    test(
      'a sparse ladder is legal — the GUI must not require every state',
      () async {
        // SSE is best-effort and polling lands between transitions, so a GUI
        // that only advances when it sees each state in turn deadlocks in
        // production. Scripting a sparse ladder is how that assumption gets
        // caught here rather than on a user's 30-minute bridge.
        final script = fixtureWith(
          RoutedSwapRun(
            states: const [
              RoutedSwapState.fetchingQuote,
              RoutedSwapState.trackingBridge,
            ],
          ),
        ).build();
        final taskId = await startSwap(script);

        final first =
            (await poll(script, taskId))['result'] as Map<String, dynamic>;
        final second =
            (await poll(script, taskId))['result'] as Map<String, dynamic>;
        final third =
            (await poll(script, taskId))['result'] as Map<String, dynamic>;

        expect((first['details'] as Map)['state'], 'FetchingQuote');
        expect((second['details'] as Map)['state'], 'TrackingBridge');
        expect(third['status'], 'Ok');
      },
    );
  });

  group('forget_if_finished', () {
    test('defaults to true and destroys the terminal result', () async {
      final script = fixtureWith(
        RoutedSwapRun(states: const [RoutedSwapState.fetchingQuote]),
      ).build();
      final taskId = await startSwap(script);

      await poll(script, taskId); // FetchingQuote
      final terminal = await call(script, 'task::routed_swap::status', {
        'task_id': taskId,
      });
      expect((terminal['result'] as Map<String, dynamic>)['status'], 'Ok');

      // The danger the default creates: a background poller that omits the
      // flag deletes the result the foreground screen was about to read.
      final again = await call(script, 'task::routed_swap::status', {
        'task_id': taskId,
      });
      expect(again['error_type'], 'NoSuchTask');
      expect(again.containsKey('result'), isFalse);
    });

    test('false keeps the terminal result readable', () async {
      final script = fixtureWith(
        RoutedSwapRun(states: const [RoutedSwapState.fetchingQuote]),
      ).build();
      final taskId = await startSwap(script);

      await poll(script, taskId);
      final first = await poll(script, taskId);
      final second = await poll(script, taskId);

      expect((first['result'] as Map<String, dynamic>)['status'], 'Ok');
      expect((second['result'] as Map<String, dynamic>)['status'], 'Ok');
      expect(first['result'], second['result']);
    });
  });

  group('cancellation', () {
    test('is accepted before Broadcasting and removes the task', () async {
      final fixture = fixtureWith(RoutedSwapRun());
      final script = fixture.build();
      final taskId = await startSwap(script);

      await poll(script, taskId); // FetchingQuote
      final cancel = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      expect(cancel.containsKey('result'), isTrue);

      // Generic rpc_task cancellation removes the entry, so the GUI cannot
      // wait for a pollable TaskCancelled — it confirms through history.
      final after = await poll(script, taskId);
      expect(after['error_type'], 'NoSuchTask');
      expect(fixture.historyEntries.single['error_type'], 'TaskCancelled');
    });

    test('is refused once Broadcasting has begun', () async {
      final script = fixtureWith(RoutedSwapRun()).build();
      final taskId = await startSwap(script);

      for (var i = 0; i <= RoutedSwapState.broadcasting.index; i++) {
        await poll(script, taskId);
      }

      final cancel = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      expect(cancel['error_type'], 'TaskCancellationNotAllowed');
      expect(
        (cancel['error_data'] as Map<String, dynamic>)['current_state'],
        'Broadcasting',
      );

      // Refusing to cancel must not stop tracking.
      final still = await poll(script, taskId);
      expect((still['result'] as Map<String, dynamic>)['status'], 'InProgress');
    });
  });

  group('restart', () {
    test(
      'pre-broadcast becomes AbortedOnRestart and kills the task_id',
      () async {
        final fixture = fixtureWith(RoutedSwapRun());
        final script = fixture.build();
        final taskId = await startSwap(script);
        await poll(script, taskId); // FetchingQuote — nothing sent

        fixture.restartKdf();

        final entry = fixture.historyEntries.single;
        expect(entry['error_type'], 'AbortedOnRestart');
        expect(entry['status'], 'Error');

        final after = await poll(script, taskId);
        expect(
          after['error_type'],
          'NoSuchTask',
          reason: 'a task_id must never survive a restart',
        );
      },
    );

    test('post-broadcast keeps tracking and stays queryable by uuid', () async {
      final fixture = fixtureWith(RoutedSwapRun());
      final script = fixture.build();
      final taskId = await startSwap(script);
      for (var i = 0; i <= RoutedSwapState.broadcasting.index; i++) {
        await poll(script, taskId);
      }
      final uuid = fixture.historyEntries.single['uuid'] as String;

      fixture.restartKdf();

      final entry = fixture.historyEntries.single;
      expect(
        entry['error_type'],
        isNull,
        reason: 'a broadcast swap must not be reported as aborted',
      );
      expect(entry['status'], 'InProgress');

      final byUuid = await call(script, 'routed_swap::history', {'uuid': uuid});
      final entries =
          (byUuid['result'] as Map<String, dynamic>)['entries'] as List;
      expect(entries, hasLength(1));
    });
  });

  group('terminal outcomes', () {
    test('refunded reports the source coin back and no dest_tx_hash', () async {
      final script = fixtureWith(
        RoutedSwapRun(
          outcome: RoutedSwapOutcome.refunded,
          receivedCoin: from,
          receivedAmount: '99.10',
        ),
      ).build();
      final taskId = await startSwap(script);

      Map<String, dynamic> result;
      do {
        result = (await poll(script, taskId))['result'] as Map<String, dynamic>;
      } while (result['status'] == 'InProgress');

      final details = result['details'] as Map<String, dynamic>;
      expect(details['outcome'], 'refunded');
      expect((details['received'] as Map)['coin'], from);
      expect(
        details.containsKey('dest_tx_hash'),
        isFalse,
        reason: 'a refund never reached the destination chain',
      );
    });

    test('partial can deliver a token with no KDF ticker', () async {
      // §1 defines a coin-or-symbol fallback for fee_costs; §3 leaves
      // `received` unspecified while explicitly allowing an intermediate
      // token. This encodes the GUI's proposed reading — and is exactly the
      // test that should fail if KDF answers the review differently.
      final script = fixtureWith(
        RoutedSwapRun(
          outcome: RoutedSwapOutcome.partial,
          receivedSymbol: 'axlUSDC',
          receivedAmount: '98.40',
        ),
      ).build();
      final taskId = await startSwap(script);

      Map<String, dynamic> result;
      do {
        result = (await poll(script, taskId))['result'] as Map<String, dynamic>;
      } while (result['status'] == 'InProgress');

      final received =
          (result['details'] as Map<String, dynamic>)['received']
              as Map<String, dynamic>;
      expect(received['symbol'], 'axlUSDC');
      expect(
        received.containsKey('coin'),
        isFalse,
        reason: 'a provider symbol must never be offered as a tradable ticker',
      );
    });

    test('QuoteWorsened carries the fresh route and sends nothing', () async {
      const fresh = RoutedSwapQuote(
        from: from,
        to: to,
        amount: '100.5',
        toAmount: '98.80',
        toAmountMin: '98.31',
      );
      final script = fixtureWith(
        RoutedSwapRun(
          error: RoutedSwapTaskError.quoteWorsened(freshRoute: fresh),
        ),
      ).build();
      final taskId = await startSwap(script);

      Map<String, dynamic> result;
      do {
        result = (await poll(script, taskId))['result'] as Map<String, dynamic>;
      } while (result['status'] == 'InProgress');

      expect(result['status'], 'Error');
      final details = result['details'] as Map<String, dynamic>;
      expect(details['error_type'], 'QuoteWorsened');
      expect(details['uuid'], isNotEmpty);
      final errorData = details['error_data'] as Map<String, dynamic>;
      expect((errorData['fresh_route'] as Map)['to'], {
        'coin': to,
        'amount': '98.80',
        'amount_min': '98.31',
      });
    });
  });

  group('contract guards', () {
    test('refuses to script a post-broadcast TransportError', () {
      // §3 says transport problems after broadcast keep the task in
      // TrackingBridge and KDF retries. Letting a fixture terminate there
      // would test the GUI against behaviour KDF has promised never to emit.
      expect(
        () => RoutedSwapRun(
          error: RoutedSwapTaskError.transportError('socket closed'),
          states: RoutedSwapState.values,
        ),
        throwsArgumentError,
      );
    });

    test('refuses a run that both succeeds and fails', () {
      expect(
        () => RoutedSwapRun(
          outcome: RoutedSwapOutcome.completed,
          error: RoutedSwapTaskError.approvalFailed('reverted'),
        ),
        throwsArgumentError,
      );
    });

    test('an unscripted pair throws rather than faking NoRouteFound', () async {
      final script = RoutedSwapFixture().build();
      await expectLater(
        call(script, 'routed_swap::quote', {'from': from, 'to': to}),
        throwsStateError,
      );
    });
  });

  group('routed_swap::quote errors', () {
    test('surface as top-level MMRPC errors, not task results', () async {
      final fixture = RoutedSwapFixture()
        ..quoteFails(
          from,
          to,
          RoutedSwapQuoteError.noRouteFound(
            reasons: const ['Amount too low for the available bridges'],
            providerRequestId: 'req-42',
          ),
        );
      final script = fixture.build();

      final response = await call(script, 'routed_swap::quote', {
        'from': from,
        'to': to,
      });

      expect(response['error_type'], 'NoRouteFound');
      expect(response.containsKey('result'), isFalse);
      final data = response['error_data'] as Map<String, dynamic>;
      expect(data['reasons'], hasLength(1));
      expect(data['provider_request_id'], 'req-42');
    });

    test('RateLimited omits provider_request_id when absent', () async {
      final fixture = RoutedSwapFixture()
        ..quoteFails(from, to, RoutedSwapQuoteError.rateLimited());
      final script = fixture.build();

      final response = await call(script, 'routed_swap::quote', {
        'from': from,
        'to': to,
      });

      expect(response['error_type'], 'RateLimited');
      // §1: absent optional fields are omitted, not null.
      expect(
        (response['error_data'] as Map<String, dynamic>).containsKey(
          'provider_request_id',
        ),
        isFalse,
      );
    });
  });

  group('routed_swap::history', () {
    test('sorts newest first and filters by status', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun(states: const [RoutedSwapState.fetchingQuote]))
        ..run(RoutedSwapRun());
      final script = fixture.build();

      final finished = await startSwap(script);
      await poll(script, finished);
      await poll(script, finished); // terminal Ok, retained

      final inFlight = await startSwap(script);
      await poll(script, inFlight);

      final all = await call(script, 'routed_swap::history', {});
      final entries =
          (all['result'] as Map<String, dynamic>)['entries'] as List;
      expect(entries, hasLength(2));
      expect(
        (entries.first as Map)['created_at'],
        greaterThan((entries.last as Map)['created_at'] as int),
      );

      final live = await call(script, 'routed_swap::history', {
        'status_filter': 'in_flight',
      });
      final liveEntries =
          (live['result'] as Map<String, dynamic>)['entries'] as List;
      expect(liveEntries, hasLength(1));
      expect((liveEntries.single as Map)['status'], 'InProgress');
    });

    test('paginates with a total', () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun())
        ..run(RoutedSwapRun());
      final script = fixture.build();
      for (var i = 0; i < 3; i++) {
        await startSwap(script);
      }

      final page = await call(script, 'routed_swap::history', {
        'limit': 2,
        'page_number': 2,
      });
      final result = page['result'] as Map<String, dynamic>;

      expect(result['total'], 3);
      expect(result['entries'], hasLength(1));
      expect(result['page_number'], 2);
    });

    test('every unratified field is declared as provisional', () async {
      final fixture = fixtureWith(RoutedSwapRun());
      final script = fixture.build();
      await startSwap(script);

      // §7 specifies no schema at all, so the emitted shape is the GUI's
      // proposal. This test exists to make that visible: if KDF publishes §7
      // and it disagrees, the fix is here, and provisionalHistoryKeys is the
      // list of things to re-check.
      final entry = fixture.historyEntries.single;
      for (final key in RoutedSwapFixture.provisionalHistoryKeys) {
        expect(
          entry.containsKey(key),
          isTrue,
          reason: '$key is declared provisional but is not emitted',
        );
      }
    });
  });
}
