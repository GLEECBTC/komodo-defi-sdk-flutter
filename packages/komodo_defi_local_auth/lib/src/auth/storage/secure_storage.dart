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
  Future<void> deleteUser(String walletName) => withWalletRecordLock(
    () => _storage.delete(key: '$_userPrefix$walletName'),
  );

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
