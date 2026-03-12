import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Base exception for activation-related errors
class ActivationFailedException implements Exception {
  const ActivationFailedException({
    required this.assetId,
    required this.message,
    this.errorCode,
    this.originalError,
  });

  final AssetId assetId;
  final String message;
  final String? errorCode;
  final Object? originalError;

  @override
  String toString() {
    final buffer = StringBuffer('ActivationFailedException: ');
    buffer.write('Asset ${assetId.name} activation failed');
    if (errorCode != null) {
      buffer.write(' (code: $errorCode)');
    }
    buffer.write(': $message');
    return buffer.toString();
  }
}

/// Exception thrown when asset activation times out
class ActivationTimeoutException extends ActivationFailedException {
  const ActivationTimeoutException({
    required super.assetId,
    required super.message,
    super.errorCode,
    super.originalError,
  });

  @override
  String toString() {
    return 'ActivationTimeoutException: Asset ${assetId.name} activation timed out: $message';
  }
}

/// Exception thrown when asset activation is not supported
class ActivationNotSupportedException extends ActivationFailedException {
  const ActivationNotSupportedException({
    required super.assetId,
    required super.message,
    super.errorCode,
    super.originalError,
  });

  @override
  String toString() {
    return 'ActivationNotSupportedException: Asset ${assetId.name} activation not supported: $message';
  }
}

/// Exception thrown when asset activation fails due to network issues
class ActivationNetworkException extends ActivationFailedException {
  const ActivationNetworkException({
    required super.assetId,
    required super.message,
    super.errorCode,
    super.originalError,
  });

  @override
  String toString() {
    return 'ActivationNetworkException: Asset ${assetId.name} activation failed due to network issues: $message';
  }
}

/// Exception thrown when an activation is cancelled by caller or lifecycle.
class ActivationCancelledException extends ActivationFailedException {
  const ActivationCancelledException({
    required super.assetId,
    required super.message,
    super.errorCode = 'ACTIVATION_CANCELLED',
    super.originalError,
  });

  @override
  String toString() {
    return 'ActivationCancelledException: Asset ${assetId.name} activation cancelled: $message';
  }
}
