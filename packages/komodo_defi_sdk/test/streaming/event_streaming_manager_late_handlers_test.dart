import 'dart:async';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockEventStreamingService extends Mock
    implements KdfEventStreamingService {}

/// Runs [body] in its own error zone and returns what escaped it as uncaught.
///
/// A subscription with no error handler reports to the zone that created it,
/// so [body] has to be the code that subscribes.
Future<List<Object>> _uncaughtErrorsFrom(Future<void> Function() body) async {
  final uncaught = <Object>[];
  final finished = Completer<void>();
  unawaited(
    runZonedGuarded(() async {
      try {
        await body();
        await pumpEventQueue();
        finished.complete();
      } catch (error, stackTrace) {
        finished.completeError(error, stackTrace);
      }
    }, (error, _) => uncaught.add(error)),
  );
  await finished.future;
  return uncaught;
}

void main() {
  const coin = 'KMD';

  late _MockApiClient client;
  late _MockEventStreamingService service;
  late StreamController<BalanceEvent> balanceEvents;
  late StreamController<KdfEventDisconnection> disconnections;
  late EventStreamingManager manager;

  setUp(() {
    client = _MockApiClient();
    service = _MockEventStreamingService();
    balanceEvents = StreamController<BalanceEvent>.broadcast(sync: true);
    disconnections = StreamController<KdfEventDisconnection>.broadcast(
      sync: true,
    );

    when(() => service.balanceEvents).thenAnswer((_) => balanceEvents.stream);
    when(() => service.disconnections).thenAnswer((_) => disconnections.stream);
    when(() => service.firstByteReceived).thenAnswer((_) async {});
    when(() => service.isConnected).thenReturn(true);
    when(() => service.connectIfNeeded()).thenAnswer((_) {});
    when(() => service.disconnect()).thenAnswer((_) async {
      disconnections.add(
        const KdfEventDisconnection(KdfEventDisconnectionKind.manual),
      );
    });
    when(() => client.executeRpc(any())).thenAnswer((invocation) async {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      return switch (request['method']) {
        'stream::balance::enable' => {
          'mmrpc': '2.0',
          'result': {'streamer_id': 'BALANCE:$coin'},
        },
        'stream::disable' => {
          'mmrpc': '2.0',
          'result': {'result': 'Success'},
        },
        _ => throw StateError('Unexpected RPC request: $request'),
      };
    });

    manager = EventStreamingManager(client: client, eventService: service);
  });

  tearDown(() async {
    await manager.dispose();
    await balanceEvents.close();
    await disconnections.close();
  });

  final invalidations = <String, Future<void> Function()>{
    'sign-out disconnect': () => manager.disconnect(),
    'transport disconnection': () async => disconnections.add(
      const KdfEventDisconnection(
        KdfEventDisconnectionKind.transportRegistrationsDropped,
      ),
    ),
  };

  for (final MapEntry(key: name, value: invalidate) in invalidations.entries) {
    group('a $name', () {
      test('reaches handlers set before it', () async {
        final seen = <Object>[];
        final uncaught = await _uncaughtErrorsFrom(() async {
          final subscription = await manager.subscribeToBalance(coin: coin);
          subscription
            ..onError(seen.add)
            ..onDone(() => seen.add('done'));
          await invalidate();
          await pumpEventQueue();
          await subscription.cancel();
        });

        expect(uncaught, isEmpty);
        expect(seen, [isA<StateError>(), 'done']);
      });

      test('reaches handlers set after it, without escaping first', () async {
        final seen = <Object>[];
        final uncaught = await _uncaughtErrorsFrom(() async {
          final subscription = await manager.subscribeToBalance(coin: coin);
          // Callers can only set handlers once their `await` resumes, and the
          // balance watcher first awaits a wallet check that queues on auth.
          await invalidate();
          await pumpEventQueue();
          subscription
            ..onData((_) => seen.add('data'))
            ..onError(seen.add)
            ..onDone(() => seen.add('done'));
          await pumpEventQueue();
          await subscription.cancel();
        });

        expect(uncaught, isEmpty);
        expect(seen, [isA<StateError>(), 'done']);
      });

      test(
        'ends a subscription with no error handler without escaping',
        () async {
          var isDone = false;
          final uncaught = await _uncaughtErrorsFrom(() async {
            final subscription = await manager.subscribeToBalance(coin: coin);
            subscription
              ..onData((_) {})
              ..onDone(() => isDone = true);
            await invalidate();
            await pumpEventQueue();
            await subscription.cancel();
          });

          expect(uncaught, isEmpty);
          expect(isDone, isTrue);
        },
      );

      test(
        'is dropped when the caller cancels before setting a handler',
        () async {
          final uncaught = await _uncaughtErrorsFrom(() async {
            final subscription = await manager.subscribeToBalance(coin: coin);
            await invalidate();
            await pumpEventQueue();
            await subscription.cancel();
          });

          expect(uncaught, isEmpty);
        },
      );
    });
  }

  group('a held invalidation', () {
    test('waits for an error or done handler, not a data handler', () async {
      final seen = <Object>[];
      final uncaught = await _uncaughtErrorsFrom(() async {
        final subscription = await manager.subscribeToBalance(coin: coin);
        await manager.disconnect();
        subscription.onData((_) => seen.add('data'));
        await pumpEventQueue();
        subscription
          ..onError(seen.add)
          ..onDone(() => seen.add('done'));
        await pumpEventQueue();
        await subscription.cancel();
      });

      expect(uncaught, isEmpty);
      expect(seen, [isA<StateError>(), 'done']);
    });

    test('completes asFuture with the invalidation', () async {
      Object? outcome;
      final uncaught = await _uncaughtErrorsFrom(() async {
        final subscription = await manager.subscribeToBalance(coin: coin);
        await manager.disconnect();
        await pumpEventQueue();
        try {
          await subscription.asFuture<void>().timeout(
            const Duration(seconds: 2),
          );
        } on Object catch (error) {
          outcome = error;
        }
        await subscription.cancel();
      });

      expect(uncaught, isEmpty);
      expect(outcome, isA<StateError>());
    });
  });
}
