import 'package:flutter/foundation.dart';

/// Cleanup status for legacy native wallet deletion.
enum LegacyWalletCleanupStatus {
  /// All targeted legacy artifacts were deleted.
  complete,

  /// Some legacy artifacts could not be deleted.
  partial,

  /// Cleanup was skipped because the platform is unsupported.
  skipped,
}

/// Result of deleting legacy native wallet artifacts.
@immutable
class LegacyWalletCleanupResult {
  /// Creates a cleanup result.
  const LegacyWalletCleanupResult({
    required this.status,
    required this.metadataDeleted,
    this.deletedSecureStorageKeys = const <String>[],
    this.failedSecureStorageKeys = const <String>[],
    this.warningMessage,
  });

  /// Cleanup completed successfully.
  const LegacyWalletCleanupResult.complete({
    required bool metadataDeleted,
    required List<String> deletedSecureStorageKeys,
  }) : this(
         status: LegacyWalletCleanupStatus.complete,
         metadataDeleted: metadataDeleted,
         deletedSecureStorageKeys: deletedSecureStorageKeys,
       );

  /// Cleanup completed only partially.
  const LegacyWalletCleanupResult.partial({
    required bool metadataDeleted,
    required List<String> deletedSecureStorageKeys,
    required List<String> failedSecureStorageKeys,
    required String warningMessage,
  }) : this(
         status: LegacyWalletCleanupStatus.partial,
         metadataDeleted: metadataDeleted,
         deletedSecureStorageKeys: deletedSecureStorageKeys,
         failedSecureStorageKeys: failedSecureStorageKeys,
         warningMessage: warningMessage,
       );

  /// Cleanup was skipped.
  const LegacyWalletCleanupResult.skipped({String? warningMessage})
    : this(
        status: LegacyWalletCleanupStatus.skipped,
        metadataDeleted: false,
        warningMessage: warningMessage,
      );

  /// Structured status for the cleanup operation.
  final LegacyWalletCleanupStatus status;

  /// Whether legacy database rows were deleted.
  final bool metadataDeleted;

  /// Secure-storage keys successfully deleted.
  final List<String> deletedSecureStorageKeys;

  /// Secure-storage keys that failed deletion.
  final List<String> failedSecureStorageKeys;

  /// Optional warning message for partial or skipped cleanup.
  final String? warningMessage;

  /// Whether cleanup completed without any warnings or failures.
  bool get isComplete => status == LegacyWalletCleanupStatus.complete;
}
