part of 'routed_swap_fixture_test.dart';

void _cases4() {
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
