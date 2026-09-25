part of 'routed_swap_manager_test.dart';

void _cases2() {
  group('progress', () {
    test('listeners share one follow; a late one gets the latest', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      final early = <RoutedSwapProgress>[];
      final done = Completer<void>();
      handle.progress.listen(early.add, onDone: done.complete);

      await until(handle, (p) => p.phase == RoutedSwapPhase.bridging);
      final seen = handle.latest;
      final late = await handle.progress.first.timeout(_timeout);
      expect(late, same(seen));

      await done.future.timeout(_timeout);
      expect(early.first.phase, RoutedSwapPhase.preparing);
      expect(early.last.isTerminal, isTrue);
      expect(early.last, await handle.result);
      expect(
        early.map((p) => p.phase).toSet(),
        containsAll([
          RoutedSwapPhase.preparing,
          RoutedSwapPhase.signing,
          RoutedSwapPhase.sending,
          RoutedSwapPhase.confirming,
          RoutedSwapPhase.bridging,
          RoutedSwapPhase.finished,
        ]),
      );
    });

    test('the stream ends at the terminal snapshot', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      final all = await handle.progress.toList().timeout(_timeout);
      expect(all.last.isTerminal, isTrue);
      expect(all.where((p) => p.isTerminal), hasLength(1));
      expect(await handle.result, all.last);
      // A listener after the end still gets the final snapshot.
      expect(await handle.progress.toList(), [all.last]);
    });

    test('polling carries on with nobody listening', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      final result = await handle.result.timeout(_timeout);
      expect(result.phase, RoutedSwapPhase.finished);
    });

    test('unchanged FetchingQuote polls do not re-emit', () async {
      final (handle, _, client) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      final seen = <RoutedSwapProgress>[];
      final sub = handle.progress.listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        client.requestsFor('task::routed_swap::status').length,
        greaterThan(5),
      );
      expect(seen, [handle.latest]);
    });

    test('unchanged polls with an executed route do not re-emit', () async {
      final (handle, _, _) = await started(RoutedSwapRun(pollsPerState: 3));
      final all = await handle.progress.toList().timeout(_timeout);
      final keys = [for (final p in all) _key(p)];
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i], isNot(keys[i - 1]), reason: 'emission $i repeats');
      }
    });

    test('a nudge refreshes before the poll interval', () async {
      final nudges = StreamController<void>.broadcast();
      addTearDown(nudges.close);
      final (handle, _, _) = await started(
        RoutedSwapRun(),
        pollInterval: const Duration(minutes: 1),
        nudges: (_) => nudges.stream,
      );
      expect(handle.latest.rawState, 'FetchingQuote');

      nudges.add(null);
      final next = await until(handle, (p) => p.rawState != 'FetchingQuote');
      expect(next.rawState, 'CheckingAllowance');
    });

    test('a broken event stream does not stop the swap', () async {
      final (handle, _, _) = await started(
        RoutedSwapRun(),
        nudges: (_) => Stream<void>.error(StateError('sse down')),
      );
      expect((await handle.result.timeout(_timeout)).isSuccess, isTrue);
    });
  });

  group('reconciliation', () {
    test('a vanished task is followed through history', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.advance(1, steps: 5);
      await until(handle, (p) => p.phase == RoutedSwapPhase.bridging);

      fixture.restartKdf();
      final recovered = await until(handle, (p) => p.createdAt != null);
      expect(recovered.isTerminal, isFalse);
      expect(recovered.canCancel, isFalse);
      expect(recovered.phase, RoutedSwapPhase.bridging);

      fixture.finishPersisted(handle.uuid);
      final result = await handle.result.timeout(_timeout);
      expect(result.isSuccess, isTrue);
      expect(result.finishedAt, isNotNull);
    });

    test('failing reads back off, flag a delay, then clear it', () async {
      final (handle, fixture, client) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      final seen = <RoutedSwapProgress>[];
      final sub = handle.progress.listen(seen.add);
      addTearDown(sub.cancel);
      fixture.statusFailsInternally(times: 4);

      await until(handle, (p) => p.delayedSince != null);
      final reads = client.requestsFor('task::routed_swap::status').length;
      await until(handle, (p) => p.delayedSince == null);

      expect(reads, greaterThanOrEqualTo(4));
      expect(seen.where((p) => p.delayedSince != null), hasLength(1));
      expect(handle.latest.phase, RoutedSwapPhase.preparing);
      expect(handle.latest.isTerminal, isFalse);
    });

    test('a terminal read is enriched from history, then forgotten', () async {
      final (handle, fixture, client) = await started(
        RoutedSwapRun(approvalGas: '0.001', sourceGas: '0.002'),
        quoted: route(
          approval: const RoutedSwapQuoteApproval.zeroReset(
            gasCoin: 'MATIC',
            gasAmount: '0.0018',
          ),
        ),
      );
      final result = await handle.result.timeout(_timeout);
      await _settle();

      expect(result.createdAt, isNotNull);
      expect(result.updatedAt, isNotNull);
      expect(result.finishedAt, isNotNull);
      expect(result.approvalTxHashes, hasLength(2));
      expect(result.approvalTxHash, result.approvalTxHashes.last);
      expect(result.gasSpent.map((g) => g.amount), [
        Decimal.parse('0.001'),
        Decimal.parse('0.001'),
        Decimal.parse('0.002'),
      ]);
      expect(result.gasSpent.first.assetId, matic);
      expect(result.totalGasSpent.single.amount, Decimal.parse('0.004'));
      expect(result.requested!.from, usdt);
      expect(result.requested!.amount, Decimal.parse('100.5'));
      expect(result.minToAmountAccepted, Decimal.parse('99.71'));

      expect(client.paramsFor('task::routed_swap::status').last, {
        'task_id': 1,
        'forget_if_finished': true,
      });
      expect(fixture.hasTask(1), isFalse);
    });

    test(
      'a task id reused after a restart never adopts another swap',
      () async {
        final fixture = RoutedSwapFixture()
          ..quote(route())
          ..run(RoutedSwapRun(autoAdvance: false))
          ..run(RoutedSwapRun(autoAdvance: false));
        final script = fixture.build();
        final manager = _managerFor(
          _Client(script),
          pollInterval: const Duration(milliseconds: 30),
        );
        final first = await manager.start(await offerFrom(manager));
        fixture.advance(1, steps: 5);
        await until(first, (p) => p.phase == RoutedSwapPhase.bridging);

        fixture.restartKdf();
        // Another client starts a swap: the engine hands out id 1 again.
        await script.respondTo({
          'method': 'task::routed_swap::init',
          'params': {
            'from': 'USDT-PLG20',
            'to': 'USDC-ERC20',
            'amount': '1',
            'min_to_amount': '0.9',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(first.latest.uuid, first.uuid);
        expect(first.latest.phase, RoutedSwapPhase.bridging);
      },
    );
  });

  group('cancel', () {
    test('accepted before broadcast: cancelled, funds untouched', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      await handle.cancel();

      final latest = handle.latest;
      expect(latest.phase, RoutedSwapPhase.failed);
      expect(latest.failure!.kind, RoutedSwapFailureKind.cancelled);
      expect(latest.failure!.errorType, 'TaskCancelled');
      expect(latest.failure!.fundsMovement, RoutedSwapFundsMovement.none);
      expect(latest.failure!.retryPolicy, RoutedSwapRetryPolicy.retry);
      expect(await handle.result.timeout(_timeout), latest);
      expect(fixture.hasTask(1), isFalse);
    });

    test('accepted after an approval: only fees were spent', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        quoted: route(approval: approval),
      );
      fixture.advance(1, steps: 3);
      await until(handle, (p) => p.approvalTxHashes.isNotEmpty);

      await handle.cancel();

      final failure = handle.latest.failure!;
      expect(failure.kind, RoutedSwapFailureKind.cancelled);
      expect(failure.fundsMovement, RoutedSwapFundsMovement.feesOnly);
      expect(handle.latest.approvalTxHashes, hasLength(1));
    });

    test('refused by KDF once broadcast began', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        pollInterval: const Duration(minutes: 1),
      );
      fixture.advance(1, steps: 3);
      expect(handle.latest.canCancel, isTrue, reason: 'not yet re-read');

      await expectLater(
        handle.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.alreadyBroadcast,
          ),
        ),
      );
    });

    test('refused by KDF once the task finished', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        pollInterval: const Duration(minutes: 1),
      );
      fixture.advance(1, steps: 100);

      await expectLater(
        handle.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.alreadyFinished,
          ),
        ),
      );
    });

    test('refused locally once the snapshot is past broadcast', () async {
      final (handle, fixture, client) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.advance(1, steps: 3);
      await until(handle, (p) => p.phase == RoutedSwapPhase.sending);

      await expectLater(
        handle.cancel(),
        throwsA(isA<RoutedSwapNotCancellableException>()),
      );
      expect(client.requestsFor('task::routed_swap::cancel'), isEmpty);
    });

    test('a finished swap refuses as alreadyFinished', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      await handle.result.timeout(_timeout);
      await expectLater(
        handle.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.alreadyFinished,
          ),
        ),
      );
    });

    test('NoSuchTask after an earlier cancel counts as done', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun(autoAdvance: false));
      final script = fixture.build();
      final manager = _managerFor(
        _Client(script),
        pollInterval: const Duration(minutes: 1),
      );
      final handle = await manager.start(await offerFrom(manager));
      // Another client, or an earlier attempt whose answer was lost.
      await script.respondTo({
        'method': 'task::routed_swap::cancel',
        'params': {'task_id': 1},
      });

      await handle.cancel();
      expect(handle.latest.failure!.kind, RoutedSwapFailureKind.cancelled);
    });

    test('a history-only handle has nothing to cancel', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.advance(1, steps: 5);
      await until(handle, (p) => p.phase == RoutedSwapPhase.bridging);
      fixture.restartKdf();

      // A fresh app session finds the swap by its uuid.
      final watched = await _managerFor(
        _Client(fixture.build()),
      ).watch(handle.uuid);
      expect(watched.latest.canCancel, isFalse);
      await expectLater(
        watched.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.notAddressable,
          ),
        ),
      );
    });

    test('an unanswered cancel is unconfirmed', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        pollInterval: const Duration(minutes: 1),
      );
      fixture.cancelFailsInternally();
      await expectLater(
        handle.cancel(),
        throwsA(isA<RoutedSwapCancelUnconfirmedException>()),
      );
    });
  });
}
