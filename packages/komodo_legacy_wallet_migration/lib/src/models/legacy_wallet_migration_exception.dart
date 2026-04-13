import 'package:flutter/foundation.dart';

/// Error types produced by legacy native wallet migration.
enum LegacyWalletMigrationExceptionType {
  /// The runtime cannot access the legacy native wallet storage layout.
  unsupportedPlatform,

  /// The requested legacy wallet could not be found in storage.
  walletNotFound,

  /// The provided password did not match the legacy wallet secrets.
  incorrectPassword,

  /// A storage access operation failed.
  storageAccessError,
}

/// Exception thrown by the legacy native wallet migration service.
@immutable
class LegacyWalletMigrationException implements Exception {
  /// Creates a legacy wallet migration exception.
  const LegacyWalletMigrationException(
    this.message, {
    required this.type,
  });

  /// Creates an unsupported-platform error.
  const LegacyWalletMigrationException.unsupportedPlatform()
    : this(
        'Legacy native wallet migration is not supported on this platform.',
        type: LegacyWalletMigrationExceptionType.unsupportedPlatform,
      );

  /// Creates a wallet-not-found error for [walletId].
  const LegacyWalletMigrationException.walletNotFound(String walletId)
    : this(
        'Legacy wallet not found: $walletId',
        type: LegacyWalletMigrationExceptionType.walletNotFound,
      );

  /// Creates an incorrect-password error.
  const LegacyWalletMigrationException.incorrectPassword()
    : this(
        'Incorrect legacy wallet password.',
        type: LegacyWalletMigrationExceptionType.incorrectPassword,
      );

  /// Creates a storage-access error.
  const LegacyWalletMigrationException.storageAccessError([String? message])
    : this(
        message ?? 'Failed to access legacy wallet storage.',
        type: LegacyWalletMigrationExceptionType.storageAccessError,
      );

  /// Human-readable error message.
  final String message;

  /// Structured error type for callers that need specific handling.
  final LegacyWalletMigrationExceptionType type;

  @override
  String toString() {
    return 'LegacyWalletMigrationException('
        'type: $type, '
        'message: $message'
        ')';
  }
}
