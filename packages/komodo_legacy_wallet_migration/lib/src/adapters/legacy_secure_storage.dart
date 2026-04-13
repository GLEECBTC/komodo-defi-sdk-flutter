import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal secure-storage interface for legacy native wallet migration.
abstract interface class LegacySecureStorage {
  /// Reads the raw value stored under [key].
  Future<String?> read(String key);

  /// Deletes the value stored under [key].
  Future<void> delete(String key);
}

/// `flutter_secure_storage` adapter used by the production migration service.
class FlutterLegacySecureStorage implements LegacySecureStorage {
  /// Creates a secure-storage adapter.
  FlutterLegacySecureStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The current app/plugin version still needs this option so legacy
            // migration opens the same Android secure-storage backend.
            // ignore: deprecated_member_use
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }
}
