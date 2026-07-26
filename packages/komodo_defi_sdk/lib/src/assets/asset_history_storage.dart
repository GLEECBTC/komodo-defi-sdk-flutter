// NB! This should be moved to a separate package for wallet persistence
// which will cache wallet data to return

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Persists activated-asset history for one complete wallet context.
class AssetHistoryStorage {
  static const _storagePrefix = 'wallet_assets_v2_';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  /// Store assets used by a wallet
  Future<void> storeWalletAssets(
    WalletId walletId,
    Set<String> assetIds,
  ) async {
    final key = _getStorageKey(walletId);
    await _storage.write(key: key, value: assetIds.join(','));
  }

  /// Add a single asset to wallet's history
  Future<void> addAssetToWallet(WalletId walletId, String assetId) async {
    final assets = await getWalletAssets(walletId);
    assets.add(assetId);
    await storeWalletAssets(walletId, assets);
  }

  /// Get all assets previously used by a wallet
  Future<Set<String>> getWalletAssets(WalletId walletId) async {
    final key = _getStorageKey(walletId);
    final value = await _storage.read(key: key);
    if (value == null || value.isEmpty) return {};
    return value.split(',').toSet();
  }

  /// Whether an unscoped history record exists for this legacy identity.
  ///
  /// Its asset IDs are deliberately not imported because the old key omitted
  /// authentication options. Callers can use this presence signal to avoid
  /// treating an upgraded wallet as provably new while they refresh live data.
  Future<bool> hasAmbiguousLegacyHistory(WalletId walletId) async {
    final key = _getLegacyStorageKey(walletId);
    final value = await _storage.read(key: key);
    if (value != null) return true;

    // Web secure storage can return null when a present value is unreadable.
    // Presence is enough to disable new-wallet shortcuts safely.
    return _storage.containsKey(key: key);
  }

  /// Clear wallet's asset history
  Future<void> clearWalletAssets(WalletId walletId) async {
    final key = _getStorageKey(walletId);
    await _storage.delete(key: key);
  }

  String _getStorageKey(WalletId walletId) =>
      '$_storagePrefix${walletStorageNamespace(walletId)}';

  String _getLegacyStorageKey(WalletId walletId) =>
      'wallet_assets_${walletId.pubkeyHash ?? walletId.name}';
}
