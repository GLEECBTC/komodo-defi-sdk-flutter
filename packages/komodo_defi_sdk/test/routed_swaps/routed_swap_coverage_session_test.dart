import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

const _status = 'task::routed_swap::status';

void main() {
  group('polling', () {
    test('failing reads back off to the cap and flag a delay on the third', () {
      fakeAsync((async) {
        final uuid = uuidOf(1);
        var failing = true;
        final kdf = ScriptedKdf()
          ..always(
            _status,
            (params) => failing
                ? dropped(params)
                : ok(inProgress(uuid, 'FetchingQuote')),
          );
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'FetchingQuote'),
        );

        // (second, reads so far, delay flagged): 3 s, then doubling, then
        // the 30 s cap.
        const timeline = [
          (3, 2, false),
          (9, 3, false),
          (21, 4, true),
          (45, 5, true),
          (75, 6, true),
        ];
        var now = 0;
        for (final (second, reads, delayed) in timeline) {
          async.elapse(
            Duration(seconds: second - now) - const Duration(milliseconds: 1),
          );
          expect(kdf.calls(_status), reads - 1, reason: 'before ${second}s');
          async.elapse(const Duration(milliseconds: 1));
          expect(kdf.calls(_status), reads, reason: 'at ${second}s');
          expect(
            handle.latest.delayedSince != null,
            delayed,
            reason: 'delay flag at ${second}s',
          );
          now = second;
        }

        failing = false;
        async.elapse(const Duration(seconds: 30));
        expect(kdf.calls(_status), 7);
        expect(handle.latest.delayedSince, isNull);
        async.elapse(const Duration(seconds: 3));
        expect(kdf.calls(_status), 8);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });

    test('a nudge during a read waits for it instead of reading twice', () {
      fakeAsync((async) {
        final uuid = uuidOf(2);
        final nudges = StreamController<void>.broadcast();
        final gate = Completer<JsonMap>();
        final kdf = ScriptedKdf()
          ..always(_status, (_) => ok(inProgress(uuid, 'CheckingAllowance')));
        final manager = managerFor(kdf, nudges: (_) => nudges.stream);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'FetchingQuote'),
        );
        kdf.next(_status, (_) => gate.future);

        async.elapse(const Duration(seconds: 3));
        expect(kdf.calls(_status), 2);
        nudges.add(null);
        async.flushMicrotasks();
        expect(kdf.calls(_status), 2);

        gate.complete(ok(inProgress(uuid, 'CheckingAllowance')));
        async.flushMicrotasks();
        expect(handle.latest.rawState, 'CheckingAllowance');
        nudges.add(null);
        async.flushMicrotasks();
        expect(kdf.calls(_status), 3, reason: 'a nudge reads right away');

        unawaited(nudges.close());
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });

    test('an event source that throws on subscribe falls back to polling', () {
      fakeAsync((async) {
        final uuid = uuidOf(3);
        final kdf = ScriptedKdf()
          ..always(_status, (_) => ok(inProgress(uuid, 'FetchingQuote')));
        final manager = managerFor(
          kdf,
          nudges: (_) => throw StateError('no event stream'),
        );
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'FetchingQuote'),
        );

        expect(handle.uuid, uuid);
        async.elapse(const Duration(seconds: 3));
        expect(kdf.calls(_status), 2);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });
  });

  group('a terminal read', () {
    RoutedSwapProgress finishWith(
      FakeAsync async,
      ScriptedKdf kdf, {
      required KdfHandler history,
      KdfHandler? forget,
    }) {
      final uuid = uuidOf(4);
      kdf
        ..always(_status, (_) => ok(completed(uuid)))
        ..always('routed_swap::history', history);
      final manager = managerFor(kdf);
      final handle = startSwap(
        async,
        kdf,
        manager,
        first: inProgress(uuid, 'TrackingBridge', route: routeJson()),
      );
      if (forget != null) {
        kdf
          ..next(_status, (_) => ok(completed(uuid)))
          ..next(_status, forget);
      }
      async.elapse(const Duration(seconds: 3));
      final result = awaited(async, handle.result);
      unawaited(manager.dispose());
      async.flushMicrotasks();
      return result;
    }

    test('stands on its own when the durable record cannot be read', () {
      fakeAsync((async) {
        final kdf = ScriptedKdf();
        final result = finishWith(async, kdf, history: dropped);

        expect(result.isSuccess, isTrue);
        expect(result.createdAt, isNull);
        expect(kdf.paramsFor(_status).last, {
          'task_id': 1,
          'forget_if_finished': true,
        });
      });
    });

    test('stands on its own while the durable record lags behind', () {
      fakeAsync((async) {
        final kdf = ScriptedKdf();
        final result = finishWith(
          async,
          kdf,
          history: (_) => historyAnswer([
            entryJson(inProgress(uuidOf(4), 'TrackingBridge')),
          ]),
        );

        expect(result.isSuccess, isTrue);
        expect(result.createdAt, isNull);
        expect(result.destinationTxHash, '0xdest');
      });
    });

    test('a forget that fails changes nothing, and polling stops', () {
      fakeAsync((async) {
        final kdf = ScriptedKdf();
        final result = finishWith(
          async,
          kdf,
          history: (_) => historyAnswer(const []),
          forget: dropped,
        );

        expect(result.isSuccess, isTrue);
        expect(kdf.calls(_status), 3);
        expect(kdf.paramsFor(_status).last['forget_if_finished'], isTrue);
        async.elapse(const Duration(minutes: 1));
        expect(kdf.calls(_status), 3);
      });
    });
  });

  test('a followed record that disappears is flagged, then recovers', () {
    fakeAsync((async) {
      final uuid = uuidOf(5);
      var reads = 0;
      var recovered = false;
      final kdf = ScriptedKdf()
        ..always('routed_swap::history', (_) {
          reads++;
          final present = reads <= 2 || recovered;
          return historyAnswer([
            if (present)
              entryJson(inProgress(uuid, 'TrackingBridge', stage: 'bridging')),
          ]);
        });
      final manager = managerFor(kdf);
      final handle = awaited(async, manager.watch(uuid));
      expect(reads, 2, reason: 'the lookup, then the first follow-up read');

      // Reads at 5 s, 15 s and 35 s miss the record; the third is flagged.
      async.elapse(const Duration(seconds: 34));
      expect(reads, 4);
      expect(handle.latest.delayedSince, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(handle.latest.delayedSince, isNotNull);
      expect(handle.latest.phase, RoutedSwapPhase.bridging);
      expect(handle.latest.isTerminal, isFalse);

      recovered = true;
      async.elapse(const Duration(seconds: 30));
      expect(reads, 6);
      expect(handle.latest.delayedSince, isNull);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  group('cancel', () {
    test('during a read it waits for the read, then confirms from history', () {
      fakeAsync((async) {
        final uuid = uuidOf(6);
        final gate = Completer<JsonMap>();
        final kdf = ScriptedKdf()
          ..always('task::routed_swap::cancel', (_) => ok('success'))
          ..always(
            'routed_swap::history',
            (_) => historyAnswer([
              entryJson(
                failedWith(uuid, 'TaskCancelled', message: 'cancelled'),
                finishedAt: 1754784020,
              ),
            ]),
          );
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'CheckingAllowance'),
        );
        kdf.next(_status, (_) => gate.future);
        async.elapse(const Duration(seconds: 3));

        var cancelled = false;
        unawaited(handle.cancel().then((_) => cancelled = true));
        async.elapse(const Duration(milliseconds: 100));
        expect(cancelled, isFalse);
        expect(kdf.calls('task::routed_swap::cancel'), 1);
        expect(kdf.calls('routed_swap::history'), 0);

        gate.complete(ok(inProgress(uuid, 'CheckingAllowance')));
        async.elapse(const Duration(milliseconds: 40));
        expect(cancelled, isTrue);
        expect(handle.latest.failure!.kind, RoutedSwapFailureKind.cancelled);
        expect(kdf.calls(_status), 2);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });

    RoutedSwapNotCancellableException refusedWhenGone(
      FakeAsync async,
      JsonMap recorded,
      void Function(RoutedSwapHandle) check,
    ) {
      final uuid = uuidOf(7);
      final kdf = ScriptedKdf()
        ..always(
          'task::routed_swap::cancel',
          (_) => rpcError('NoSuchTask', {'task_id': 1}),
        )
        ..always(
          'routed_swap::history',
          (_) => historyAnswer([entryJson(recorded)]),
        );
      final manager = managerFor(kdf);
      final handle = startSwap(
        async,
        kdf,
        manager,
        first: inProgress(uuid, 'Signing'),
      );
      final error = thrownBy(async, handle.cancel());
      check(handle);
      unawaited(manager.dispose());
      async.flushMicrotasks();
      return error! as RoutedSwapNotCancellableException;
    }

    test('a task gone while the swap runs on is not addressable', () {
      fakeAsync((async) {
        final error = refusedWhenGone(
          async,
          inProgress(
            uuidOf(7),
            'WaitingSourceConfirmation',
            sourceTxHash: '0xsource',
          ),
          (handle) {
            expect(handle.latest.phase, RoutedSwapPhase.confirming);
            expect(handle.latest.canCancel, isFalse);
          },
        );
        expect(error.refusal, RoutedSwapCancelRefusal.notAddressable);
        expect(error.phase, RoutedSwapPhase.confirming);
      });
    });

    test('a task gone because the swap ended is already finished', () {
      fakeAsync((async) {
        final error = refusedWhenGone(async, completed(uuidOf(7)), (handle) {
          expect(awaited(async, handle.result).isSuccess, isTrue);
        });
        expect(error.refusal, RoutedSwapCancelRefusal.alreadyFinished);
        expect(error.phase, RoutedSwapPhase.finished);
      });
    });
  });

  group('dispose', () {
    test(
      'stops polling; a later listener gets the last snapshot, then done',
      () {
        fakeAsync((async) {
          final uuid = uuidOf(8);
          final kdf = ScriptedKdf()
            ..always(_status, (_) => ok(inProgress(uuid, 'FetchingQuote')));
          final manager = managerFor(kdf);
          final handle = startSwap(
            async,
            kdf,
            manager,
            first: inProgress(uuid, 'FetchingQuote'),
          );

          unawaited(manager.dispose());
          async.elapse(const Duration(minutes: 1));

          expect(kdf.calls(_status), 1);
          expect(awaited(async, handle.progress.toList()), [handle.latest]);
        });
      },
    );

    // Real zone: a done event forwarded through a cancelled subscription
    // completes on the root zone, which fake time never flushes.
    test(
      'a listener attached before dispose is told the stream ended',
      () async {
        final uuid = uuidOf(8);
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::quote',
            (_) => ok({
              'routes': [routeJson()],
            }),
          )
          ..always('task::routed_swap::init', (_) => ok({'task_id': 1}))
          ..always(_status, (_) => ok(inProgress(uuid, 'FetchingQuote')));
        final manager = managerFor(kdf);
        final offer = await manager.quote(
          from: usdc,
          to: usdt,
          amount: d('100'),
        );
        final handle = await manager.start(offer);
        var done = false;
        handle.progress.listen(null, onDone: () => done = true);

        await manager.dispose();
        await pumpEventQueue();

        expect(done, isTrue);
        expect(kdf.calls(_status), 1);
      },
    );

    test('a read that lands after dispose changes nothing', () {
      fakeAsync((async) {
        final uuid = uuidOf(9);
        final gate = Completer<JsonMap>();
        var reads = 0;
        final kdf = ScriptedKdf()
          ..always(_status, (params) {
            reads++;
            if (reads <= 3) return dropped(params);
            if (reads == 4) return gate.future;
            return ok(inProgress(uuid, 'Signing'));
          });
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'FetchingQuote'),
        );
        async.elapse(const Duration(seconds: 21));
        expect(handle.latest.delayedSince, isNotNull);
        final seen = <RoutedSwapProgress>[];
        handle.progress.listen(seen.add);
        async.elapse(const Duration(seconds: 24));
        expect(reads, 4, reason: 'the fourth read is in flight');

        unawaited(manager.dispose());
        async.flushMicrotasks();
        gate.complete(ok(inProgress(uuid, 'Signing')));
        async.elapse(const Duration(minutes: 5));

        expect(handle.latest.rawState, 'FetchingQuote');
        expect(handle.latest.delayedSince, isNotNull);
        expect(seen, hasLength(1), reason: 'only the replayed snapshot');
        expect(reads, 4);
      });
    });
  });
}
