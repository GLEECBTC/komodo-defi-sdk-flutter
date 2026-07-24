import 'dart:async';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockEventStreamingService extends Mock
    implements KdfEventStreamingService {}

void main() {
  const coin = 'USDT-TRC20';

  late _MockApiClient client;
  late _MockEventStreamingService service;
  late StreamController<KdfEvent> events;
  late StreamController<KdfEventDisconnection> disconnections;
  late EventStreamingManager manager;
  late int enableCount;
  late int disableCount;
  late List<String> operationLog;
  Completer<void>? disableGate;

  setUp(() {
    client = _MockApiClient();
    service = _MockEventStreamingService();
    events = StreamController<KdfEvent>.broadcast(sync: true);
    disconnections = StreamController<KdfEventDisconnection>.broadcast(
      sync: true,
    );
    enableCount = 0;
    disableCount = 0;
    operationLog = <String>[];
    disableGate = null;

    when(() => service.events).thenAnswer((_) => events.stream);
    when(() => service.disconnections).thenAnswer((_) => disconnections.stream);
    when(() => service.firstByteReceived).thenAnswer((_) async {});
    when(() => service.isConnected).thenReturn(true);
    when(() => service.connectIfNeeded()).thenAnswer((_) {});
    when(() => service.disconnect()).thenAnswer((_) async {
      operationLog.add('transport_disconnect');
      disconnections.add(
        const KdfEventDisconnection(KdfEventDisconnectionKind.manual),
      );
    });

    when(() => client.executeRpc(any())).thenAnswer((invocation) async {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      final method = request['method'] as String;
      if (method == 'stream::gasless_trace::enable') {
        enableCount++;
        operationLog.add('enable');
      } else if (method == 'stream::disable') {
        disableCount++;
        operationLog.add('disable');
        await disableGate?.future;
      }
      return switch (method) {
        'stream::gasless_trace::enable' => {
          'mmrpc': '2.0',
          'result': {
            'streamer_id':
                'GASLESS_TRACE:'
                '${(request['params'] as Map<String, dynamic>)['coin']}',
          },
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
    final gate = disableGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await manager.dispose();
    await events.close();
    await disconnections.close();
  });

  test('GasFree subscription filters typed events by coin', () async {
    final subscription = await manager.subscribeToGaslessTrace(coin: coin);
    // A clean runtime has no application event before stream::enable. The
    // transport readiness acknowledgement must be sufficient.
    expect(enableCount, 1);
    verify(() => service.connectIfNeeded()).called(1);

    final received = <KdfEvent>[];
    subscription.onData(received.add);

    events
      ..add(
        const GaslessTraceEvent(
          coin: coin,
          traceId: 'trace-1',
          state: GaslessTraceEventState.submitted,
        ),
      )
      ..add(
        const GaslessTraceEvent(
          coin: 'OTHER-TRC20',
          traceId: 'trace-1',
          state: GaslessTraceEventState.submitted,
        ),
      )
      ..add(
        const GaslessTraceErrorEvent(
          coin: coin,
          traceId: 'trace-1',
          error: 'provider unavailable',
        ),
      );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(2));
    expect(received.first, isA<GaslessTraceEvent>());
    expect(received.last, isA<GaslessTraceErrorEvent>());
    expect(enableCount, 1);

    await subscription.cancel();
    expect(disableCount, 1);
  });

  test(
    'disconnect invalidates the old generation and re-enable is isolated',
    () async {
      final first = await manager.subscribeToGaslessTrace(coin: coin);
      final invalidated = Completer<Object>();
      first.onError((Object error) {
        if (!invalidated.isCompleted) invalidated.complete(error);
      });

      disconnections.add(
        const KdfEventDisconnection(
          KdfEventDisconnectionKind.transportRegistrationsDropped,
        ),
      );
      expect(await invalidated.future, isA<StateError>());
      expect(manager.isStreamActive('gasless_trace:$coin'), isFalse);

      final replacement = await manager.subscribeToGaslessTrace(coin: coin);
      expect(manager.isStreamActive('gasless_trace:$coin'), isTrue);
      expect(enableCount, 2);

      // Canceling a handle from the disconnected generation must not
      // decrement or disable the replacement registration.
      await first.cancel();
      expect(manager.isStreamActive('gasless_trace:$coin'), isTrue);
      expect(disableCount, 0);

      await replacement.cancel();
      expect(manager.isStreamActive('gasless_trace:$coin'), isFalse);
      expect(disableCount, 1);
    },
  );

  test(
    'Web-style disconnect cleans old registration before replacement enable',
    () async {
      final first = await manager.subscribeToGaslessTrace(coin: coin);
      first.onError((Object _) {});
      operationLog.clear();
      disableGate = Completer<void>();

      disconnections.add(
        const KdfEventDisconnection(
          KdfEventDisconnectionKind.transportRegistrationsMayPersist,
        ),
      );
      final replacementFuture = manager.subscribeToGaslessTrace(coin: coin);
      var replacementCompleted = false;
      unawaited(
        replacementFuture.then<void>((_) => replacementCompleted = true),
      );

      await Future<void>.delayed(Duration.zero);
      expect(operationLog, ['disable']);
      expect(replacementCompleted, isFalse);

      disableGate!.complete();
      final replacement = await replacementFuture;
      expect(operationLog, ['disable', 'enable']);
      expect(enableCount, 2);

      await first.cancel();
      expect(disableCount, 1);
      await replacement.cancel();
      expect(disableCount, 2);
    },
  );

  test(
    'managed disconnect disables before transport close and gates replacements',
    () async {
      final first = await manager.subscribeToGaslessTrace(coin: coin);
      first.onError((Object _) {});
      operationLog.clear();
      disableGate = Completer<void>();

      final disconnect = manager.disconnect();
      final replacementFuture = manager.subscribeToGaslessTrace(coin: coin);
      var replacementCompleted = false;
      unawaited(
        replacementFuture.then<void>((_) => replacementCompleted = true),
      );

      await Future<void>.delayed(Duration.zero);
      expect(operationLog, ['disable']);
      expect(replacementCompleted, isFalse);

      disableGate!.complete();
      await disconnect;
      expect(operationLog, ['disable', 'transport_disconnect']);

      final replacement = await replacementFuture;
      expect(operationLog, ['disable', 'transport_disconnect', 'enable']);

      // The invalidated handle cannot disable the new registration.
      await first.cancel();
      expect(disableCount, 1);
      await replacement.cancel();
      expect(disableCount, 2);
    },
  );
}
