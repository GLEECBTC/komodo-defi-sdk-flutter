import 'dart:async' show StreamController, Timer, unawaited;

import 'package:komodo_defi_local_auth/src/auth/auth_state.dart';
import 'package:komodo_defi_local_auth/src/trezor/trezor_connection_status.dart';
import 'package:komodo_defi_local_auth/src/trezor/trezor_exception.dart';
import 'package:komodo_defi_local_auth/src/trezor/trezor_initialization_state.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Manages Trezor hardware wallet initialization and operations
class TrezorRepository {
  /// Creates a new TrezorManager instance with the provided API client
  TrezorRepository(this._client);

  /// The API client for making RPC calls
  final ApiClient _client;

  /// Track active initialization streams
  final Map<int, StreamController<TrezorInitializationState>>
  _activeInitializations = {};

  /// Initialize a Trezor device for use with Komodo DeFi Framework
  ///
  /// Returns a stream that emits [TrezorInitializationState] updates throughout
  /// the initialization process. The caller should listen to this stream and
  /// respond to user input requirements (PIN/passphrase) by calling the
  /// appropriate methods ([providePin] or [providePassphrase]).
  ///
  /// Example usage:
  /// ```dart
  /// await for (final state in trezorRepository.initializeDevice()) {
  ///   switch (state.status) {
  ///     case AuthenticationStatus.pinRequired:
  ///       final pin = await getUserPin();
  ///       await trezorRepository.providePin(state.taskId!, pin);
  ///       break;
  ///     case AuthenticationStatus.passphraseRequired:
  ///       final passphrase = await getUserPassphrase();
  ///       await trezorRepository.providePassphrase(state.taskId!, passphrase);
  ///       break;
  ///     case AuthenticationStatus.completed:
  ///       print('Device initialized: ${state.deviceInfo}');
  ///       break;
  ///   }
  /// }
  /// ```
  Stream<TrezorInitializationState> initializeDevice({
    String? devicePubkey,
    Duration pollingInterval = const Duration(seconds: 1),
  }) async* {
    int? taskId;
    StreamController<TrezorInitializationState>? controller;
    // Ensure we can always cancel the timer even if the stream is cancelled
    // by the subscriber.
    Timer? statusTimer;

    try {
      yield const TrezorInitializationState(
        status: AuthenticationStatus.initializing,
        message: 'Starting Trezor initialization...',
      );

      final initResponse = await _client.rpc.trezor.init(
        devicePubkey: devicePubkey,
      );

      taskId = initResponse.taskId;
      controller = StreamController<TrezorInitializationState>();
      _activeInitializations[taskId] = controller;

      yield TrezorInitializationState(
        status: AuthenticationStatus.initializing,
        message: 'Initialization started, checking status...',
        taskId: taskId,
      );

      var isComplete = false;

      Future<void> pollStatus() async {
        if (isComplete || taskId == null) return;

        try {
          final statusResponse = await _client.rpc.trezor.status(
            taskId: taskId,
            forgetIfFinished: false,
          );

          final state = TrezorInitializationState.fromStatusResponse(
            statusResponse,
            taskId,
          );

          if (!controller!.isClosed) {
            controller.add(state);
          }

          // Check if we should stop polling
          if (state.status == AuthenticationStatus.completed ||
              state.status == AuthenticationStatus.error ||
              state.status == AuthenticationStatus.cancelled) {
            isComplete = true;
            statusTimer?.cancel();
            if (!controller.isClosed) {
              unawaited(controller.close());
            }
          }
        } catch (e) {
          if (!controller!.isClosed) {
            controller.addError(
              TrezorException('Status check failed', _errorDetail(e)),
            );
            await controller.close();
          }

          isComplete = true;
          statusTimer?.cancel();
        }
      }

      // Do not immediately emit the first status update to avoid race
      // conditions (i.e. KDF task not yet created). Use the provided polling
      // interval for the first status check.
      statusTimer = Timer.periodic(
        pollingInterval,
        (_) => unawaited(pollStatus()),
      );

      yield* controller.stream;
    } catch (e) {
      yield TrezorInitializationState(
        status: AuthenticationStatus.error,
        error: 'Initialization failed: $e',
        taskId: taskId,
      );
    } finally {
      // Always cancel the timer to avoid leaks if the subscriber cancels
      // the stream or if we exit early for any reason.
      statusTimer?.cancel();
      if (taskId != null) {
        _activeInitializations.remove(taskId);
        if (controller != null && !controller.isClosed) {
          unawaited(controller.close());
        }
      }
    }
  }

  /// Provide PIN when the device requests it
  ///
  /// The [pin] should be entered as it appears on your keyboard numpad,
  /// mapped according to the grid shown on the Trezor device.
  Future<void> providePin(int taskId, String pin) async {
    if (pin.isEmpty || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain only digits and cannot be empty.');
    }

    await _client.rpc.trezor.providePin(taskId: taskId, pin: pin);
  }

  /// Provide passphrase when the device requests it
  ///
  /// The [passphrase] acts like an additional word in your recovery seed.
  /// Use an empty string to access the default wallet without passphrase.
  Future<void> providePassphrase(int taskId, String passphrase) async {
    await _client.rpc.trezor.providePassphrase(
      taskId: taskId,
      passphrase: passphrase,
    );
  }

  /// Cancel an ongoing Trezor initialization
  Future<bool> cancelInitialization(int taskId) async {
    try {
      final response = await _client.rpc.trezor.cancel(taskId: taskId);

      // Close and remove the controller
      final controller = _activeInitializations.remove(taskId);
      if (controller != null && !controller.isClosed) {
        controller.add(
          TrezorInitializationState(
            status: AuthenticationStatus.cancelled,
            message: 'Initialization cancelled by user',
            taskId: taskId,
          ),
        );
        unawaited(controller.close());
      }

      return response.result == 'success';
    } catch (e) {
      throw TrezorException('Failed to cancel initialization', _errorDetail(e));
    }
  }

  /// Returns the current connection status as a parsed enum.
  Future<TrezorConnectionStatus> getConnectionStatus({
    String? devicePubkey,
  }) async {
    final response = await _client.rpc.trezor.connectionStatus(
      devicePubkey: devicePubkey,
    );
    return TrezorConnectionStatus.fromString(response.status);
  }

  /// Continuously polls the Trezor connection status and emits parsed enum updates.
  ///
  /// The stream immediately yields the current status, then continues to poll
  /// using [pollInterval]. If the status changes, a new value is emitted.
  /// The stream closes once a `Disconnected` status is observed. If
  /// [maxDuration] is provided, the stream will also end after the duration
  /// elapses by emitting `TrezorConnectionStatus.unreachable`. If `maxDuration`
  /// is null (default), the polling continues without a time limit.
  Stream<TrezorConnectionStatus> watchConnectionStatus({
    String? devicePubkey,
    Duration pollInterval = const Duration(seconds: 1),
    Duration? maxDuration,
  }) async* {
    TrezorConnectionStatus last;
    final stopwatch = maxDuration != null ? (Stopwatch()..start()) : null;

    try {
      last = await getConnectionStatus(devicePubkey: devicePubkey);
      yield last;
    } catch (e) {
      // If initial status check fails, treat as disconnected and end stream
      yield TrezorConnectionStatus.disconnected;
      return;
    }

    while (last.shouldContinueMonitoring &&
        (maxDuration == null || stopwatch!.elapsed < maxDuration)) {
      await Future<void>.delayed(pollInterval);
      try {
        final current = await getConnectionStatus(devicePubkey: devicePubkey);
        if (current != last) {
          last = current;
          yield current;
        }
      } catch (e) {
        yield TrezorConnectionStatus.disconnected;
        return;
      }
    }

    if (maxDuration != null && stopwatch!.elapsed >= maxDuration) {
      yield TrezorConnectionStatus.unreachable;
    }
  }

  /// Cancel all active initializations and clean up resources
  Future<void> dispose() async {
    final activeTaskIds = _activeInitializations.keys.toList();

    await Future.wait(
      activeTaskIds.map((taskId) async {
        try {
          await cancelInitialization(taskId);
        } catch (e) {
          // ignore: avoid_print
          print('Error cancelling Trezor task $taskId: $e');
        }
      }),
    );

    _activeInitializations.clear();
  }
}

/// A human-readable detail line for [TrezorException], preferring typed fields.
///
/// `GeneralErrorResponse.toString()` is deliberately reduced to its
/// `error_type` so that `error_data` - which can carry request payloads - never
/// reaches a log line. That makes it useless as a user-facing detail: a device
/// that reports "Device not ready" would surface as
/// `GeneralErrorResponse(errorType: ...)`.
///
/// So read the message off the typed field instead, exactly as
/// `error_response.dart` intends ("preserves stable error_type and error_data
/// fields instead of forcing callers to parse toString()"). `error_data` is
/// still never included.
String _errorDetail(Object error) {
  if (error is! GeneralErrorResponse) return error.toString();
  final message = error.error;
  if (message != null && message.isNotEmpty) return message;
  return error.errorType ?? error.toString();
}
