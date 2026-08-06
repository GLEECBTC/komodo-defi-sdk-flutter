// ignore_for_file: prefer_const_constructors, avoid_print

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
// ignore: unused_import
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A lightweight fake ApiClient that returns queued responses per method.
class FakeApiClient implements ApiClient {
  final Map<String, List<JsonMap Function(JsonMap request)>> _methodResponders =
      {};

  final List<JsonMap> calls = [];

  void enqueueResponder(
    String method,
    JsonMap Function(JsonMap request) responder,
  ) {
    _methodResponders
        .putIfAbsent(method, () => <JsonMap Function(JsonMap)>[])
        .add(responder);
  }

  void enqueueStaticResponse(String method, JsonMap response) {
    enqueueResponder(method, (_) => response);
  }

  @override
  FutureOr<JsonMap> executeRpc(JsonMap request) {
    calls.add(request);
    final method = request['method'] as String?;
    if (method == null) {
      throw StateError('Missing method in request: $request');
    }

    final queue = _methodResponders[method];
    if (queue == null || queue.isEmpty) {
      throw StateError('No responder queued for method $method');
    }

    final responder = queue.removeAt(0);
    return responder(request);
  }
}

/// Helpers to craft API-shaped responses quickly
JsonMap newTaskResponse({required int taskId}) => {
  'mmrpc': '2.0',
  'result': {'task_id': taskId},
};

JsonMap trezorStatusOk({required JsonMap deviceInfo}) => {
  'mmrpc': '2.0',
  'result': {'status': 'Ok', 'details': deviceInfo},
};

JsonMap trezorStatusError({required String error}) => {
  'mmrpc': '2.0',
  'result': {
    'status': 'Error',
    'details': {
      'error': error,
      'error_path': '',
      'error_trace': '',
      'error_type': 'TestError',
    },
  },
};

JsonMap trezorStatusInProgress(String? description) => {
  'mmrpc': '2.0',
  'result': {'status': 'InProgress', 'details': description},
};

JsonMap trezorStatusUserActionRequired(String description) => {
  'mmrpc': '2.0',
  'result': {'status': 'UserActionRequired', 'details': description},
};

JsonMap trezorCancelOk() => {'mmrpc': '2.0', 'result': 'success'};

JsonMap trezorUserActionOk() => {'mmrpc': '2.0', 'result': 'ok'};

JsonMap connectionStatusResponse(String status) => {
  'mmrpc': '2.0',
  'result': {'status': status},
};

void main() {
  group('TrezorRepository.initializeDevice', () {
    test(
      'emits initializing, then mapped status updates, and completes on Ok',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        const taskId = 42;
        final deviceInfo = {
          'device_id': 'dev-123',
          'device_pubkey': 'pub-abc',
          'type': 'trezor',
          'model': 'T',
          'device_name': 'MyTrezor',
        };

        // init -> task id
        client
          ..enqueueStaticResponse(
            'task::init_trezor::init',
            newTaskResponse(taskId: taskId),
          )
          // status polls sequence
          ..enqueueStaticResponse(
            'task::init_trezor::status',
            trezorStatusInProgress('Waiting to connect the device'),
          )
          ..enqueueStaticResponse(
            'task::init_trezor::status',
            trezorStatusUserActionRequired('EnterTrezorPin'),
          )
          ..enqueueStaticResponse(
            'task::init_trezor::status',
            trezorStatusInProgress('Follow the instructions on device'),
          )
          ..enqueueStaticResponse(
            'task::init_trezor::status',
            trezorStatusOk(deviceInfo: deviceInfo),
          );

        final events = <TrezorInitializationState>[];
        final stream = repo.initializeDevice(
          pollingInterval: Duration(milliseconds: 5),
        );

        await stream.forEach(events.add);

        // Verify sequence
        expect(events.length, greaterThanOrEqualTo(5));
        expect(events[0].status, AuthenticationStatus.initializing);
        expect(events[0].message, contains('Starting'));

        expect(events[1].status, AuthenticationStatus.initializing);
        expect(events[1].message, contains('Initialization started'));
        expect(events[1].taskId, taskId);

        // Mapped states from our status responses
        // Waiting to connect -> waitingForDevice
        expect(
          events.map((e) => e.status),
          contains(AuthenticationStatus.waitingForDevice),
        );
        // EnterTrezorPin -> pinRequired
        expect(
          events.map((e) => e.status),
          contains(AuthenticationStatus.pinRequired),
        );
        // Follow instructions -> waitingForDeviceConfirmation
        expect(
          events.map((e) => e.status),
          contains(AuthenticationStatus.waitingForDeviceConfirmation),
        );

        // Completed with device info
        final completed = events.last;
        expect(completed.status, AuthenticationStatus.completed);
        expect(completed.deviceInfo, isNotNull);
        expect(completed.deviceInfo!.deviceId, equals('dev-123'));
        expect(completed.deviceInfo!.devicePubkey, equals('pub-abc'));
      },
    );

    test('adds stream error when status returns Error', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      const taskId = 7;

      client
        ..enqueueStaticResponse(
          'task::init_trezor::init',
          newTaskResponse(taskId: taskId),
        )
        ..enqueueStaticResponse(
          'task::init_trezor::status',
          trezorStatusError(error: 'Device not ready'),
        );

      final completer = Completer<void>();
      var sawError = false;
      final sub = repo
          .initializeDevice(pollingInterval: Duration(milliseconds: 5))
          .listen(
            (_) {},
            onError: (Object err, _) {
              expect(err, isA<TrezorException>());
              expect(err.toString(), contains('Status check failed'));
              expect(err.toString(), contains('Device not ready'));
              sawError = true;
              completer.complete();
            },
          );

      await completer.future;
      await sub.cancel();
      expect(sawError, isTrue);
    });

    test('adds stream error if status throws', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      const taskId = 99;
      client
        ..enqueueStaticResponse(
          'task::init_trezor::init',
          newTaskResponse(taskId: taskId),
        )
        // Make the status call throw by not enqueueing any responder and intercepting
        ..enqueueResponder('task::init_trezor::status', (_) {
          throw Exception('Network down');
        });

      final stream = repo.initializeDevice(
        pollingInterval: Duration(milliseconds: 5),
      );

      final completer = Completer<void>();
      var sawStreamError = false;
      final sub = stream.listen(
        (_) {},
        onError: (Object error, _) {
          expect(error, isA<TrezorException>());
          sawStreamError = true;
        },
        onDone: completer.complete,
      );

      await completer.future;
      await sub.cancel();
      expect(sawStreamError, isTrue);
    });
  });

  group('TrezorRepository input validation', () {
    test('providePin throws on empty or non-digit input', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      expect(() => repo.providePin(1, ''), throwsA(isA<ArgumentError>()));
      expect(() => repo.providePin(1, '12a3'), throwsA(isA<ArgumentError>()));
    });

    test('providePin forwards valid request', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      client.enqueueStaticResponse(
        'task::init_trezor::user_action',
        trezorUserActionOk(),
      );
      await repo.providePin(10, '1234');
      expect(client.calls.last['method'], 'task::init_trezor::user_action');
    });

    test('providePassphrase forwards request', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      client.enqueueStaticResponse(
        'task::init_trezor::user_action',
        trezorUserActionOk(),
      );
      await repo.providePassphrase(10, '');
      expect(client.calls.last['method'], 'task::init_trezor::user_action');
    });
  });

  group('TrezorRepository.cancelInitialization', () {
    test('emits cancelled state and returns true (no poll race)', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      const taskId = 5;
      client
        ..enqueueStaticResponse(
          'task::init_trezor::init',
          newTaskResponse(taskId: taskId),
        )
        // Immediate status poll now occurs; provide a benign response
        ..enqueueStaticResponse(
          'task::init_trezor::status',
          trezorStatusInProgress('Waiting to connect the device'),
        )
        ..enqueueStaticResponse('task::init_trezor::cancel', trezorCancelOk());

      final received = <TrezorInitializationState>[];
      final sub = repo
          .initializeDevice(pollingInterval: Duration(hours: 1))
          .listen(received.add);

      // Wait a tick to ensure we have a task id in stream
      await Future<void>.delayed(Duration(milliseconds: 10));

      final cancelled = await repo.cancelInitialization(taskId);
      expect(cancelled, isTrue);

      // Allow stream to receive the cancelled event
      await Future<void>.delayed(Duration(milliseconds: 5));
      await sub.cancel();

      expect(
        received.map((e) => e.status),
        contains(AuthenticationStatus.cancelled),
      );
    });
  });

  group('TrezorRepository connection status', () {
    test('getConnectionStatus maps API status strings to enum', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      client.enqueueStaticResponse(
        'trezor_connection_status',
        connectionStatusResponse('connected'),
      );
      expect(
        await repo.getConnectionStatus(),
        TrezorConnectionStatus.connected,
      );

      client.enqueueStaticResponse(
        'trezor_connection_status',
        connectionStatusResponse('busy'),
      );
      expect(await repo.getConnectionStatus(), TrezorConnectionStatus.busy);

      client.enqueueStaticResponse(
        'trezor_connection_status',
        connectionStatusResponse('unreachable'),
      );
      expect(
        await repo.getConnectionStatus(),
        TrezorConnectionStatus.unreachable,
      );
    });

    test(
      'watchConnectionStatus emits on change and stops on disconnected',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        // Initial + 3 polls
        client
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('busy'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('busy'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('disconnected'),
          );

        final statuses = <TrezorConnectionStatus>[];
        await repo
            .watchConnectionStatus(
              pollInterval: Duration(milliseconds: 5),
              maxDuration: Duration(seconds: 1),
            )
            .forEach(statuses.add);

        expect(statuses, [
          TrezorConnectionStatus.connected, // initial
          TrezorConnectionStatus.busy, // change
          TrezorConnectionStatus.connected, // change
          TrezorConnectionStatus.disconnected, // stream ends after this
        ]);
      },
    );

    test('watchConnectionStatus stops polling when listener cancels', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      // Initial + many polls queued (should not be consumed after cancel)
      client.enqueueStaticResponse(
        'trezor_connection_status',
        connectionStatusResponse('connected'),
      );
      for (var i = 0; i < 20; i++) {
        client.enqueueStaticResponse(
          'trezor_connection_status',
          connectionStatusResponse('connected'),
        );
      }

      final firstEvent = Completer<void>();
      late StreamSubscription<TrezorConnectionStatus> sub;
      sub = repo
          .watchConnectionStatus(
            pollInterval: Duration(milliseconds: 15),
            maxDuration: Duration(seconds: 1),
          )
          .listen((_) async {
            if (!firstEvent.isCompleted) {
              firstEvent.complete();
              await sub.cancel();
            }
          });

      await firstEvent.future;

      final callsAfterCancel = client.calls
          .where((c) => c['method'] == 'trezor_connection_status')
          .length;

      // Wait longer than one polling interval; there should be no further calls
      await Future<void>.delayed(Duration(milliseconds: 60));

      final callsLater = client.calls
          .where((c) => c['method'] == 'trezor_connection_status')
          .length;
      expect(callsLater, callsAfterCancel);
    });

    test(
      'watchConnectionStatus makes no further polls after disconnected',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        // Initial + change + disconnected, followed by extra responses that
        // should never be consumed
        client
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('busy'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('disconnected'),
          );
        for (var i = 0; i < 5; i++) {
          client.enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          );
        }

        final statuses = <TrezorConnectionStatus>[];
        await repo
            .watchConnectionStatus(
              pollInterval: Duration(milliseconds: 10),
              maxDuration: Duration(seconds: 1),
            )
            .forEach(statuses.add);

        // Expect exactly the three statuses including the terminal one
        expect(statuses, [
          TrezorConnectionStatus.connected,
          TrezorConnectionStatus.busy,
          TrezorConnectionStatus.disconnected,
        ]);

        // Ensure only 3 RPC calls were made (initial + 2 polls)
        final callCount = client.calls
            .where((c) => c['method'] == 'trezor_connection_status')
            .length;
        expect(callCount, 3);
      },
    );

    test(
      'watchConnectionStatus yields unreachable after maxDuration timeout',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        // Initial connected, then stay connected until timeout
        client.enqueueStaticResponse(
          'trezor_connection_status',
          connectionStatusResponse('connected'),
        );
        // A few polls during the short duration
        for (var i = 0; i < 5; i++) {
          client.enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          );
        }

        final statuses = <TrezorConnectionStatus>[];
        await repo
            .watchConnectionStatus(
              pollInterval: Duration(milliseconds: 10),
              maxDuration: Duration(milliseconds: 35),
            )
            .forEach(statuses.add);

        expect(statuses.first, TrezorConnectionStatus.connected);
        expect(statuses.last, TrezorConnectionStatus.unreachable);
      },
    );

    test(
      'watchConnectionStatus emits disconnected and returns on error',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        client
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          )
          ..enqueueResponder(
            'trezor_connection_status',
            (_) => throw Exception('RPC failure'),
          );

        final statuses = <TrezorConnectionStatus>[];
        await repo
            .watchConnectionStatus(
              pollInterval: Duration(milliseconds: 5),
              maxDuration: Duration(seconds: 1),
            )
            .forEach(statuses.add);

        expect(statuses, [
          TrezorConnectionStatus.connected,
          TrezorConnectionStatus.disconnected,
        ]);
      },
    );
  });

  group('TrezorRepository.dispose', () {
    test('cancels active initializations', () async {
      final client = FakeApiClient();
      final repo = TrezorRepository(client);

      const taskId = 77;
      client
        ..enqueueStaticResponse(
          'task::init_trezor::init',
          newTaskResponse(taskId: taskId),
        )
        // Immediate status poll now occurs; provide a benign response
        ..enqueueStaticResponse(
          'task::init_trezor::status',
          trezorStatusInProgress('Waiting to connect the device'),
        )
        ..enqueueStaticResponse('task::init_trezor::cancel', trezorCancelOk());

      final sub = repo
          .initializeDevice(pollingInterval: Duration(hours: 1))
          .listen((_) {});

      // Give time for init to complete and task to be registered
      await Future<void>.delayed(Duration(milliseconds: 5));

      // Dispose should cancel the active initialization via RPC
      await repo.dispose();

      // Ensure the cancel call was invoked
      expect(
        client.calls.where((c) => c['method'] == 'task::init_trezor::cancel'),
        isNotEmpty,
      );

      await sub.cancel();
    });
  });

  group('TrezorRepository immediate poll and timer lifecycle', () {
    test(
      'watchConnectionStatus with null maxDuration does not yield unreachable and continues until disconnected',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        client
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('busy'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('busy'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('connected'),
          )
          ..enqueueStaticResponse(
            'trezor_connection_status',
            connectionStatusResponse('disconnected'),
          );

        final statuses = <TrezorConnectionStatus>[];
        await repo
            .watchConnectionStatus(
              pollInterval: Duration(milliseconds: 5),
              // maxDuration omitted (null)
            )
            .forEach(statuses.add);

        expect(statuses.last, isNot(TrezorConnectionStatus.unreachable));
        expect(statuses.last, TrezorConnectionStatus.disconnected);
      },
    );
    test(
      'initializeDevice does not poll immediately when interval is long',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        const taskId = 123;
        client
          ..enqueueStaticResponse(
            'task::init_trezor::init',
            newTaskResponse(taskId: taskId),
          )
          ..enqueueStaticResponse(
            'task::init_trezor::status',
            trezorStatusInProgress('Waiting to connect the device'),
          );

        final events = <TrezorInitializationState>[];
        final sub = repo
            .initializeDevice(pollingInterval: Duration(hours: 1))
            .listen(events.add);

        // Give a short time; no poll should occur yet due to long interval
        await Future<void>.delayed(Duration(milliseconds: 15));
        await sub.cancel();

        // Only the initial two initializing events should be present
        expect(events.length, 2);
        expect(events[0].status, AuthenticationStatus.initializing);
        expect(events[1].status, AuthenticationStatus.initializing);
        final statusCalls = client.calls
            .where((c) => c['method'] == 'task::init_trezor::status')
            .length;
        expect(statusCalls, 0);
      },
    );

    test(
      'timer is cancelled when stream is cancelled (no further polls)',
      () async {
        final client = FakeApiClient();
        final repo = TrezorRepository(client);

        const taskId = 456;
        client
          ..enqueueStaticResponse(
            'task::init_trezor::init',
            newTaskResponse(taskId: taskId),
          )
          // Provide many status responses so if the timer were not cancelled,
          // additional polls would succeed and be counted.
          ..enqueueStaticResponse(
            'task::init_trezor::status',
            trezorStatusInProgress('Waiting to connect the device'),
          );
        for (var i = 0; i < 10; i++) {
          client.enqueueStaticResponse(
            'task::init_trezor::status',
            trezorStatusInProgress('Waiting to connect the device'),
          );
        }

        late StreamSubscription<TrezorInitializationState> sub;
        final firstEvent = Completer<void>();
        sub = repo
            .initializeDevice(pollingInterval: Duration(milliseconds: 30))
            .listen((event) async {
              if (event.status == AuthenticationStatus.waitingForDevice &&
                  !firstEvent.isCompleted) {
                firstEvent.complete();
                await sub.cancel();
              }
            });

        await firstEvent.future;

        final callsAfterCancel = client.calls
            .where((c) => c['method'] == 'task::init_trezor::status')
            .length;

        // Wait longer than one polling interval; there should be no further calls
        await Future<void>.delayed(Duration(milliseconds: 80));
        final callsLater = client.calls
            .where((c) => c['method'] == 'task::init_trezor::status')
            .length;

        expect(callsLater, callsAfterCancel);
      },
    );
  });
}
