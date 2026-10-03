import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

const _status = 'task::routed_swap::status';
const _cancel = 'task::routed_swap::cancel';

void main() {
  group('cancellation identity', () {
    test('a reused task id never cancels the replacement swap', () {
      fakeAsync((async) {
        final uuid = uuidOf(1);
        final kdf = ScriptedKdf()
          ..always(_status, (_) => ok(inProgress(uuidOf(2), 'Signing')))
          ..always(_cancel, (_) => ok('success'))
          ..always(
            'routed_swap::history',
            (_) => historyAnswer([
              entryJson(failedWith(uuid, 'AbortedOnRestart')),
            ]),
          );
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'Signing'),
        );

        final error = thrownBy(async, handle.cancel());
        expect(error, isA<RoutedSwapNotCancellableException>());
        expect(kdf.calls(_cancel), 0);
        expect(handle.latest.uuid, uuid);
        expect(
          handle.latest.failure!.kind,
          RoutedSwapFailureKind.abortedOnRestart,
        );
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });

    test('an unanswered identity check sends no cancellation', () {
      fakeAsync((async) {
        final kdf = ScriptedKdf()
          ..always(_status, dropped)
          ..always(_cancel, (_) => ok('success'));
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuidOf(1), 'Signing'),
        );

        expect(
          thrownBy(async, handle.cancel()),
          isA<RoutedSwapCancelUnconfirmedException>(),
        );
        expect(kdf.calls(_cancel), 0);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });

    test('a fresh broadcast state refuses cancellation', () {
      fakeAsync((async) {
        final uuid = uuidOf(1);
        final kdf = ScriptedKdf()
          ..always(_status, (_) => ok(inProgress(uuid, 'Broadcasting')))
          ..always(_cancel, (_) => ok('success'));
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'Signing'),
        );

        expect(
          thrownBy(async, handle.cancel()),
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.alreadyBroadcast,
          ),
        );
        expect(kdf.calls(_cancel), 0);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });
  });

  group('skipped broadcast observations', () {
    for (final phase in ['Signing', 'Approving']) {
      for (final approved in [false, true]) {
        for (final errorType in ['SigningRejected', 'InternalError']) {
          test(
            '$errorType after $phase, approved=$approved stays uncertain',
            () {
              fakeAsync((async) {
                final uuid = uuidOf(1);
                final terminal = failedWith(
                  uuid,
                  errorType,
                  data: errorType == 'SigningRejected'
                      ? {'reason': 'timeout'}
                      : {'message': 'Broadcast handoff lost'},
                );
                final kdf = ScriptedKdf()
                  ..always(_status, (_) => ok(terminal))
                  ..always(
                    'routed_swap::history',
                    (_) => historyAnswer([
                      entryJson(
                        terminal,
                        approvals: approved ? ['0xapprove'] : [],
                      ),
                    ]),
                  );
                final manager = managerFor(kdf);
                final handle = startSwap(
                  async,
                  kdf,
                  manager,
                  first: inProgress(
                    uuid,
                    phase,
                    approveTxHash: approved ? '0xapprove' : null,
                  ),
                );
                // The engine advances through Broadcasting and errors between
                // polls, without returning the broadcast hash.
                async.elapse(const Duration(seconds: 3));
                final result = awaited(async, handle.result);
                final policy = errorType == 'SigningRejected'
                    ? RoutedSwapRetryPolicy.wait
                    : RoutedSwapRetryPolicy.contactSupport;
                expect(
                  result.failure!.fundsMovement,
                  RoutedSwapFundsMovement.uncertain,
                );
                expect(result.failure!.retryPolicy, policy);
                expect(result.failure!.isRetryable, isFalse);
                final history = awaited(
                  async,
                  manager.history(),
                ).entries.single;
                expect(
                  history.failure!.fundsMovement,
                  RoutedSwapFundsMovement.uncertain,
                );
                expect(history.failure!.retryPolicy, policy);
                unawaited(manager.dispose());
                async.flushMicrotasks();
              });
            },
          );
        }
      }
    }
  });
}
