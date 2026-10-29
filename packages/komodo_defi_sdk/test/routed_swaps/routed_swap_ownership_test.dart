import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import '../helpers/counting_session_auth.dart';
import 'routed_swap_coverage_fakes.dart';

const _a = KdfUser(
  walletId: WalletId(
    name: 'a',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
  isBip39Seed: false,
);
const _b = KdfUser(
  walletId: WalletId(
    name: 'b',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    pubkeyHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  ),
  isBip39Seed: false,
);

void main() {
  test('cold-start recovery reads every in-flight history page', () async {
    const total = 99;
    final kdf = ScriptedKdf()
      ..always('routed_swap::history', (params) {
        final page = params['page_number'] as int;
        expect(params['status_filter'], 'in_flight');
        expect(params['limit'], 1);
        expect(page, inInclusiveRange(1, total));
        return historyAnswer(
          [entryJson(inProgress(uuidOf(total - page + 1), 'TrackingBridge'))],
          total: total,
          page: page,
          totalPages: total,
          limit: 1,
        );
      });
    final manager = managerFor(kdf);
    addTearDown(manager.dispose);

    final running = await manager.inFlight(pageSize: 1);

    expect(running.map((swap) => swap.uuid), [
      for (var n = total; n > 0; n--) uuidOf(n),
    ]);
    expect(kdf.calls('routed_swap::history'), total);
  });

  test('recovery never returns partial history after a late wallet change', () {
    fakeAsync((async) {
      final auth = HeldSessionStreamAuth(_a);
      final pending = Completer<Map<String, dynamic>>();
      final kdf = ScriptedKdf()
        ..always('routed_swap::history', (params) {
          final page = params['page_number'] as int;
          if (page == 21) return pending.future;
          return historyAnswer(
            [entryJson(inProgress(uuidOf(page), 'TrackingBridge'))],
            total: 21,
            page: page,
            totalPages: 21,
            limit: 1,
          );
        });
      final manager = managerFor(kdf, auth: auth);
      List<RoutedSwapProgress>? recovered;
      Object? failure;
      manager
          .inFlight(pageSize: 1)
          .then<void>(
            (value) {
              recovered = value;
            },
            onError: (Object error) {
              failure = error;
            },
          );
      async.flushMicrotasks();
      expect(kdf.calls('routed_swap::history'), 21);
      auth.runtimeSessions.invalidate();
      auth.user = _b;
      auth.runtimeSessions.observe(_b);
      pending.complete(
        historyAnswer(
          [entryJson(inProgress(uuidOf(21), 'TrackingBridge'))],
          total: 21,
          page: 21,
          totalPages: 21,
          limit: 1,
        ),
      );
      async.flushMicrotasks();
      expect(recovered, isNull);
      expect(failure, isA<AuthSessionChangedException>());
      expect(kdf.calls('routed_swap::history'), 21);
      unawaited(manager.dispose());
      unawaited(auth.runtimeSessions.dispose());
      unawaited(auth.heldSessionEvents.close());
      unawaited(auth.authChanges.close());
      async.flushMicrotasks();
    });
  });

  for (final matches in [1, 2]) {
    test(
      '$matches matching history records never confirm unrelated tasks',
      () async {
        var task = 0;
        final kdf = ScriptedKdf()
          ..always('task::routed_swap::init', (_) => ok({'task_id': ++task}))
          ..always('task::routed_swap::status', dropped)
          ..always(
            'routed_swap::history',
            (_) => historyAnswer([
              for (var i = matches; i > 0; i--)
                entryJson(inProgress(uuidOf(i), 'Signing')),
            ]),
          );
        final manager = managerFor(kdf, firstReadAttempts: 1);
        addTearDown(manager.dispose);
        Future<Object> attempt() async {
          try {
            return await manager.start(offerOf());
          } on Object catch (error) {
            return error;
          }
        }

        final results = await Future.wait([attempt(), attempt()]);
        expect(
          results,
          everyElement(isA<RoutedSwapStartUnconfirmedException>()),
        );
        expect(
          results
              .cast<RoutedSwapStartUnconfirmedException>()
              .map((e) => e.taskId)
              .toSet(),
          {1, 2},
        );
        expect(kdf.calls('routed_swap::history'), 0);
      },
    );
  }

  for (final replacement in [_b, _a]) {
    test('session revocation invalidates cache before auth event: '
        '${replacement.walletId.name}', () {
      fakeAsync((async) {
        final auth = HeldSessionStreamAuth(_a);
        final uuid = uuidOf(1);
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::history',
            (_) => auth.user == _a && auth.runtimeSessions.epoch == 0
                ? historyAnswer([entryJson(inProgress(uuid, 'Signing'))])
                : historyAnswer([]),
          );
        final manager = managerFor(kdf, auth: auth);
        final handle = awaited(async, manager.watch(uuid));
        Object? ended;
        handle.result.then<void>(
          (_) {},
          onError: (Object e) {
            ended = e;
          },
        );
        auth.runtimeSessions.invalidate();
        auth.user = replacement;
        auth.runtimeSessions.observe(replacement);
        expect(
          thrownBy(async, manager.watch(uuid)),
          isA<RoutedSwapNotFoundException>(),
        );
        expect(
          thrownBy(async, handle.cancel()),
          isA<AuthSessionChangedException>(),
        );
        final count = kdf.requests.length;
        async.elapse(const Duration(minutes: 1));
        expect(kdf.requests.length, count);
        expect(ended, isA<AuthSessionChangedException>());
        expect(kdf.calls('task::routed_swap::cancel'), 0);
        unawaited(manager.dispose());
        unawaited(auth.runtimeSessions.dispose());
        unawaited(auth.heldSessionEvents.close());
        unawaited(auth.authChanges.close());
        async.flushMicrotasks();
      });
    });
  }

  test('a start crossing a wallet change stays unconfirmed '
      'without reading its new engine', () {
    fakeAsync((async) {
      final auth = HeldSessionStreamAuth(_a);
      final init = Completer<Map<String, dynamic>>();
      final kdf = ScriptedKdf()
        ..always('task::routed_swap::init', (_) => init.future);
      final manager = managerFor(kdf, auth: auth);
      Object? error;
      manager
          .start(offerOf())
          .then<void>(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      async.flushMicrotasks();
      auth.runtimeSessions.invalidate();
      auth.user = _b;
      auth.runtimeSessions.observe(_b);
      init.complete(ok({'task_id': 7}));
      async.flushMicrotasks();
      expect(
        error,
        isA<RoutedSwapStartUnconfirmedException>().having(
          (e) => e.taskId,
          'task',
          7,
        ),
      );
      expect(kdf.calls('task::routed_swap::status'), 0);
      expect(kdf.calls('routed_swap::history'), 0);
      unawaited(manager.dispose());
      unawaited(auth.runtimeSessions.dispose());
      unawaited(auth.heldSessionEvents.close());
      unawaited(auth.authChanges.close());
      async.flushMicrotasks();
    });
  });

  test('a late poll from a revoked wallet cannot emit or continue polling', () {
    fakeAsync((async) {
      final auth = HeldSessionStreamAuth(_a);
      final pending = Completer<Map<String, dynamic>>();
      final uuid = uuidOf(1);
      final kdf = ScriptedKdf()
        ..always('task::routed_swap::status', (_) => pending.future);
      final manager = managerFor(kdf, auth: auth);
      final handle = startSwap(
        async,
        kdf,
        manager,
        first: inProgress(uuid, 'Signing'),
      );
      final updates = <RoutedSwapProgress>[];
      final subscription = handle.progress.listen(updates.add);
      async.elapse(const Duration(seconds: 3));
      auth.runtimeSessions.invalidate();
      auth.user = _b;
      auth.runtimeSessions.observe(_b);
      pending.complete(ok(inProgress(uuid, 'Broadcasting')));
      async.flushMicrotasks();
      expect(updates, hasLength(1));
      final calls = kdf.requests.length;
      async.elapse(const Duration(minutes: 1));
      expect(kdf.requests.length, calls);
      expect(kdf.calls('task::routed_swap::cancel'), 0);
      unawaited(subscription.cancel());
      unawaited(manager.dispose());
      unawaited(auth.runtimeSessions.dispose());
      unawaited(auth.heldSessionEvents.close());
      unawaited(auth.authChanges.close());
      async.flushMicrotasks();
    });
  });
}
