// lib/src/auth/secure_storage.dart

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_local_auth/src/auth/wallet_catalog_lock.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

abstract class Storage {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class SecureLocalStorage {
  factory SecureLocalStorage() => _instance;
  SecureLocalStorage._()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: false,
        ),
      );

  @visibleForTesting
  SecureLocalStorage.withStorage(this._storage);

  static final SecureLocalStorage _instance = SecureLocalStorage._();

  final FlutterSecureStorage _storage;

  static const _userPrefix = 'user_';
  static const String _lastActiveWalletNameKey = 'lastActiveWalletName';
  static const _provisioningPrefix = 'wallet_provisioning_';

  /// Non-secret reservation, used only while the caller holds the catalog lock.
  Future<JsonMap?> getProvisioning(String walletName) async {
    final encoded = await _storage.read(key: '$_provisioningPrefix$walletName');
    return encoded == null ? null : jsonFromString(encoded);
  }

  /// A failed/ambiguous write must not be followed by wallet creation.
  Future<void> saveProvisioning(String walletName, JsonMap reservation) async {
    final key = '$_provisioningPrefix$walletName';
    final encoded = reservation.toJsonString();
    await _storage.write(key: key, value: encoded);
    if (await _storage.read(key: key) != encoded) {
      throw StateError('Wallet provisioning could not be persisted');
    }
  }

  Future<void> deleteProvisioning(String walletName) =>
      _storage.delete(key: '$_provisioningPrefix$walletName');

  /// Save user data
  Future<void> saveUser(KdfUser user) =>
      withWalletRecordLock(() => _writeUser(user));

  /// Atomically transforms the latest record across local SDK instances and
  /// browser tabs. The synchronous callback must not enter another storage,
  /// auth or catalog operation. Returning the existing record avoids a write.
  Future<KdfUser?> updateUser(
    String walletName,
    KdfUser? Function(KdfUser? current) transform,
  ) => withWalletRecordLock(() async {
    final current = await getUser(walletName);
    final updated = transform(current);
    if (updated != null && !identical(updated, current)) {
      await _writeUser(updated);
    }
    return updated;
  });

  Future<void> _writeUser(KdfUser user) async {
    final jsonString = user.toJson().toJsonString();
    await _storage.write(
      key: '$_userPrefix${user.walletId.name}',
      value: jsonString,
    );
  }

  /// Get user data
  Future<KdfUser?> getUser(String walletName) async {
    final jsonString = await _storage.read(key: '$_userPrefix$walletName');
    if (jsonString == null) return null;
    return KdfUser.fromJson(jsonFromString(jsonString));
  }

  /// Delete user data
  Future<void> deleteUser(String walletName) => withWalletRecordLock(() async {
    await _storage.delete(key: '$_userPrefix$walletName');
    await deleteProvisioning(walletName);
  });

  /// Save the last active wallet name
  Future<void> saveLastActiveWalletName(String? walletName) async {
    if (walletName == null) {
      await _storage.delete(key: _lastActiveWalletNameKey);
    } else {
      await _storage.write(key: _lastActiveWalletNameKey, value: walletName);
    }
  }

  /// Get the last active wallet name
  Future<String?> getLastActiveWalletName() async {
    return _storage.read(key: _lastActiveWalletNameKey);
  }

  /// Clears all secure storage
  Future<void> clearSecureStorage() => withWalletRecordLock(_storage.deleteAll);
}
