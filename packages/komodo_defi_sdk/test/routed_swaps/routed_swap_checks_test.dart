import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

const _status = 'task::routed_swap::status';
const _history = 'routed_swap::history';

/// Covers when KDF last answered for a swap: what `progress`, carrying only
/// changes, cannot tell a caller.
void main() {
  final start = DateTime.utc(2026, 10, 1, 12);

  test('every answer is a check, whether or not anything changed', () {
    fakeAsync((async) {
      final uuid = uuidOf(21);
      final kdf = ScriptedKdf()
        ..always(_status, (_) => ok(inProgress(uuid, 'FetchingQuote')));
      final manager = managerFor(kdf, now: () => start.add(async.elapsed));
      final handle = startSwap(
        async,
        kdf,
        manager,
        first: inProgress(uuid, 'FetchingQuote'),
      );
      final started = handle.checkedAt;
      expect(started, isNotNull, reason: 'the first read is an answer');
      final checks = <DateTime>[];
      final progress = <RoutedSwapProgress>[];
      handle.checks.listen(checks.add);
      handle.progress.listen(progress.add);

      async.elapse(const Duration(seconds: 6));

      expect(checks, [
        started!.add(const Duration(seconds: 3)),
        started.add(const Duration(seconds: 6)),
      ]);
      expect(handle.checkedAt, checks.last);
      expect(progress, hasLength(1), reason: 'only the replayed snapshot');
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('a read that fails is not a check', () {
    fakeAsync((async) {
      final uuid = uuidOf(22);
      var failing = false;
      final kdf = ScriptedKdf()
        ..always(
          _status,
          (params) =>
              failing ? dropped(params) : ok(inProgress(uuid, 'FetchingQuote')),
        );
      final manager = managerFor(kdf, now: () => start.add(async.elapsed));
      final handle = startSwap(
        async,
        kdf,
        manager,
        first: inProgress(uuid, 'FetchingQuote'),
      );
      async.elapse(const Duration(seconds: 3));
      final answered = handle.checkedAt;

      failing = true;
      final checks = <DateTime>[];
      handle.checks.listen(checks.add);
      async.elapse(const Duration(seconds: 30));

      expect(checks, isEmpty);
      expect(handle.checkedAt, answered);
      expect(handle.latest.delayedSince, isNotNull);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('a swap followed from its record counts the record read', () {
    fakeAsync((async) {
      final uuid = uuidOf(23);
      final kdf = ScriptedKdf()
        ..always(
          _history,
          (_) => historyAnswer([entryJson(inProgress(uuid, 'Bridging'))]),
        );
      final manager = managerFor(kdf, now: () => start.add(async.elapsed));
      final handle = awaited(async, manager.watch(uuid));

      expect(handle.checkedAt, isNotNull);
      final checks = <DateTime>[];
      handle.checks.listen(checks.add);
      async.elapse(const Duration(seconds: 5));
      expect(checks, hasLength(1));
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('checks end with the swap', () {
    fakeAsync((async) {
      final uuid = uuidOf(24);
      var done = false;
      final kdf = ScriptedKdf()
        ..always(
          _status,
          (_) => ok(
            done
                ? completed(uuid)
                : inProgress(uuid, 'WaitingSourceConfirmation'),
          ),
        );
      final manager = managerFor(kdf, now: () => start.add(async.elapsed));
      final handle = startSwap(
        async,
        kdf,
        manager,
        first: inProgress(uuid, 'WaitingSourceConfirmation'),
      );
      var closed = false;
      handle.checks.listen((_) {}, onDone: () => closed = true);

      done = true;
      async.elapse(const Duration(seconds: 10));

      expect(handle.latest.isTerminal, isTrue);
      expect(closed, isTrue);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
