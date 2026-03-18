import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

part 'trezor_initialization_state.freezed.dart';

/// Represents the current state of Trezor initialization
@freezed
abstract class TrezorInitializationState with _$TrezorInitializationState {
  const factory TrezorInitializationState({
    required AuthenticationStatus status,
    String? message,
    TrezorDeviceInfo? deviceInfo,
    String? error,
    int? taskId,
  }) = _TrezorInitializationState;

  const TrezorInitializationState._();

  /// Maps API status response to domain state
  factory TrezorInitializationState.fromStatusResponse(
    TrezorStatusResponse response,
    int taskId,
  ) {
    switch (response.status) {
      case 'Ok':
        final deviceInfo = response.deviceInfo;
        if (deviceInfo != null) {
          return TrezorInitializationState(
            status: AuthenticationStatus.completed,
            message: 'Trezor device initialized successfully',
            deviceInfo: deviceInfo,
            taskId: taskId,
          );
        } else {
          return TrezorInitializationState(
            status: AuthenticationStatus.error,
            error: 'Invalid response: missing device info',
            taskId: taskId,
          );
        }
      case 'Error':
        final errorInfo = response.errorInfo;
        return TrezorInitializationState(
          status: AuthenticationStatus.error,
          error: exceptionMessage(errorInfo) ?? 'Unknown error occurred',
          taskId: taskId,
        );
      case 'InProgress':
        final description = response.progressDescription;
        return TrezorInitializationState.fromInProgressDescription(
          description,
          taskId,
        );
      case 'UserActionRequired':
        final description = response.progressDescription;
        return TrezorInitializationState.fromUserActionRequired(
          description,
          taskId,
        );
      default:
        return TrezorInitializationState(
          status: AuthenticationStatus.error,
          error: 'Unknown status: ${response.status}',
          taskId: taskId,
        );
    }
  }

  /// Maps in-progress descriptions to appropriate states
  factory TrezorInitializationState.fromInProgressDescription(
    String? description,
    int taskId,
  ) {
    if (description == null) {
      return TrezorInitializationState(
        status: AuthenticationStatus.initializing,
        message: 'Initializing Trezor device...',
        taskId: taskId,
      );
    }

    final descriptionLower = description.toLowerCase();

    if (descriptionLower.contains('waiting') &&
        descriptionLower.contains('connect')) {
      return TrezorInitializationState(
        status: AuthenticationStatus.waitingForDevice,
        message: 'Waiting for Trezor device to be connected',
        taskId: taskId,
      );
    }

    if (descriptionLower.contains('follow') &&
        descriptionLower.contains('instructions')) {
      return TrezorInitializationState(
        status: AuthenticationStatus.waitingForDeviceConfirmation,
        message: 'Please follow the instructions on your Trezor device',
        taskId: taskId,
      );
    }

    return TrezorInitializationState(
      status: AuthenticationStatus.initializing,
      message: description,
      taskId: taskId,
    );
  }

  /// Maps user action requirements to appropriate states
  factory TrezorInitializationState.fromUserActionRequired(
    String? description,
    int taskId,
  ) {
    if (description == null) {
      return TrezorInitializationState(
        status: AuthenticationStatus.initializing,
        message: 'User action required',
        taskId: taskId,
      );
    }

    if (description == 'EnterTrezorPin') {
      return TrezorInitializationState(
        status: AuthenticationStatus.pinRequired,
        message: 'Please enter your Trezor PIN',
        taskId: taskId,
      );
    }

    if (description == 'EnterTrezorPassphrase') {
      return TrezorInitializationState(
        status: AuthenticationStatus.passphraseRequired,
        message: 'Please enter your Trezor passphrase',
        taskId: taskId,
      );
    }

    return TrezorInitializationState(
      status: AuthenticationStatus.initializing,
      message: description,
      taskId: taskId,
    );
  }

  AuthenticationState toAuthenticationState() {
    return AuthenticationState(
      status: status,
      message: message,
      taskId: taskId,
      error: error,
    );
  }
}
