import 'package:flutter/foundation.dart';
import 'package:komodo_legacy_wallet_migration/src/models/legacy_wallet_record.dart';

/// Secrets read from a legacy native wallet during migration.
@immutable
class LegacyWalletSecrets {
  /// Creates a legacy wallet secrets payload.
  const LegacyWalletSecrets({
    required this.sourceWallet,
    required this.seedPhrase,
    required this.secureStorageKeysToDelete,
    this.genericStorageKeysToDelete = const <String>[],
    this.sharedPreferencesKeysToDelete = const <String>[],
    this.requestedZhtlcCoinIds = const <String>[],
    this.legacyZhtlcSyncType,
    this.legacyZhtlcSyncStartDate,
    this.walletExtras = const <String, dynamic>{},
  });

  /// Legacy wallet resolved from the native metadata store.
  final LegacyWalletRecord sourceWallet;

  /// Plaintext seed phrase read directly from legacy secure storage.
  final String seedPhrase;

  /// Per-wallet secure-storage keys that should be deleted after import.
  final List<String> secureStorageKeysToDelete;

  /// Generic session keys that can be deleted on a best-effort basis.
  final List<String> genericStorageKeysToDelete;

  /// Shared-preferences keys that can be deleted after import.
  final List<String> sharedPreferencesKeysToDelete;

  /// Requested but not yet fully activated legacy ZHTLC coin ids.
  final List<String> requestedZhtlcCoinIds;

  /// Raw legacy ZHTLC sync type stored by the native app.
  final String? legacyZhtlcSyncType;

  /// Raw legacy ZHTLC sync start date stored by the native app.
  final DateTime? legacyZhtlcSyncStartDate;

  /// Preserved legacy wallet-scoped extras.
  final Map<String, dynamic> walletExtras;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is LegacyWalletSecrets &&
        other.sourceWallet == sourceWallet &&
        other.seedPhrase == seedPhrase &&
        listEquals(
          other.secureStorageKeysToDelete,
          secureStorageKeysToDelete,
        ) &&
        listEquals(
          other.genericStorageKeysToDelete,
          genericStorageKeysToDelete,
        ) &&
        listEquals(
          other.sharedPreferencesKeysToDelete,
          sharedPreferencesKeysToDelete,
        ) &&
        listEquals(other.requestedZhtlcCoinIds, requestedZhtlcCoinIds) &&
        other.legacyZhtlcSyncType == legacyZhtlcSyncType &&
        other.legacyZhtlcSyncStartDate == legacyZhtlcSyncStartDate &&
        mapEquals(other.walletExtras, walletExtras);
  }

  @override
  int get hashCode => Object.hash(
    sourceWallet,
    seedPhrase,
    Object.hashAll(secureStorageKeysToDelete),
    Object.hashAll(genericStorageKeysToDelete),
    Object.hashAll(sharedPreferencesKeysToDelete),
    Object.hashAll(requestedZhtlcCoinIds),
    legacyZhtlcSyncType,
    legacyZhtlcSyncStartDate,
    Object.hashAllUnordered(
      walletExtras.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() {
    return 'LegacyWalletSecrets('
        'sourceWallet: $sourceWallet, '
        'seedPhrase: [redacted], '
        'secureStorageKeysToDelete: $secureStorageKeysToDelete, '
        'genericStorageKeysToDelete: $genericStorageKeysToDelete, '
        'sharedPreferencesKeysToDelete: $sharedPreferencesKeysToDelete, '
        'requestedZhtlcCoinIds: $requestedZhtlcCoinIds, '
        'legacyZhtlcSyncType: $legacyZhtlcSyncType, '
        'legacyZhtlcSyncStartDate: $legacyZhtlcSyncStartDate, '
        'walletExtras: $walletExtras'
        ')';
  }
}
