import 'package:flutter/foundation.dart';

/// Metadata describing a legacy native wallet discovered on device.
@immutable
class LegacyWalletRecord {
  /// Creates a legacy wallet record.
  const LegacyWalletRecord({
    required this.walletId,
    required this.walletName,
    this.activatedCoins = const <String>[],
    this.isCurrentWallet = false,
    this.walletExtras = const <String, dynamic>{},
  });

  /// Stable legacy wallet identifier from the native wallet database.
  final String walletId;

  /// Original legacy wallet name used for secure-storage key lookup.
  final String walletName;

  /// Activated coin IDs stored for this legacy wallet.
  final List<String> activatedCoins;

  /// Whether this wallet is marked as the current wallet in legacy storage.
  final bool isCurrentWallet;

  /// Preserved legacy wallet-scoped extras from native DB/shared prefs state.
  final Map<String, dynamic> walletExtras;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is LegacyWalletRecord &&
        other.walletId == walletId &&
        other.walletName == walletName &&
        listEquals(other.activatedCoins, activatedCoins) &&
        other.isCurrentWallet == isCurrentWallet &&
        mapEquals(other.walletExtras, walletExtras);
  }

  @override
  int get hashCode => Object.hash(
    walletId,
    walletName,
    Object.hashAll(activatedCoins),
    isCurrentWallet,
    Object.hashAllUnordered(
      walletExtras.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() {
    return 'LegacyWalletRecord('
        'walletId: $walletId, '
        'walletName: $walletName, '
        'activatedCoins: $activatedCoins, '
        'isCurrentWallet: $isCurrentWallet, '
        'walletExtras: $walletExtras'
        ')';
  }
}
