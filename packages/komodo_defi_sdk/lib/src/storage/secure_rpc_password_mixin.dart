import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

// TODO! Move storage to a separate package. The RPC method package has a
// similar class for storing data in secure storage.
// TODO: Document the steps needed to use secure storage on each platform for
// apps using this package.
/// Mixin for storing and retrieving the RPC password with secure storage.
/// Falls back to `SharedPreferences` if secure storage fails, but only in
/// non-release modes.
mixin class SecureRpcPasswordMixin {
  static const _rpcPasswordKey = 'rpc_password';

  /// Secure storage instance.
  FlutterSecureStorage? _secureStorage;

  // TODO: See if a lighterweight alternative to shared preferences can be used.
  /// Shared preferences for fallback.
  SharedPreferences? _sharedPreferences;

  /// Initializes the storage, attempting to use secure storage.
  Future<void> _initializeStorage() async {
    try {
      // Try to initialize secure storage
      _secureStorage = FlutterSecureStorage(
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
        aOptions: _getAndroidOptions(),
      );
      // Test secure storage by reading a key (may throw exception if not supported)
      await _secureStorage!.read(key: _rpcPasswordKey);
    } catch (e) {
      // If secure storage fails, fallback to shared preferences in non-release mode
      if (!kReleaseMode) {
        _sharedPreferences = await SharedPreferences.getInstance();
      } else {
        rethrow; // Re-throw the error in release mode
      }
    }
  }

  /// Retrieves the stored RPC password from secure storage or shared
  /// preferences if in fallback mode.
  Future<String?> getRpcPassword() async {
    await _initializeStorage();

    if (_secureStorage != null) {
      // Try to get the password from secure storage
      return _secureStorage!.read(key: _rpcPasswordKey);
    } else if (_sharedPreferences != null) {
      // Fallback to shared preferences if secure storage fails
      return _sharedPreferences!.getString(_rpcPasswordKey);
    }

    return null; // If neither storage is available, return null
  }

  /// Stores a new RPC password in secure storage or shared preferences if in
  /// fallback mode.
  Future<void> setRpcPassword(String password) async {
    await _initializeStorage();

    if (_secureStorage != null) {
      await _secureStorage!.write(key: _rpcPasswordKey, value: password);
    } else if (_sharedPreferences != null) {
      await _sharedPreferences!.setString(_rpcPasswordKey, password);
    }
  }

  /// Generates and stores a new RPC password if one doesn't exist.
  /// Returns the existing or newly generated password.
  Future<String> ensureRpcPassword() async {
    var password = await getRpcPassword();

    if (password == null) {
      password = _generateSecurePassword();
      await setRpcPassword(password);
    }
    return password;
  }

  /// Deletes the stored RPC password from secure storage or shared preferences
  /// if in fallback mode.
  Future<void> deleteRpcPassword() async {
    await _initializeStorage();

    if (_secureStorage != null) {
      await _secureStorage!.delete(key: _rpcPasswordKey);
    } else if (_sharedPreferences != null) {
      await _sharedPreferences!.remove(_rpcPasswordKey);
    }
  }

  /// Generates a secure random password.
  /// You may want to replace this with your actual password generation logic.
  String _generateSecurePassword() => SecurityUtils.generatePasswordSecure(32);

  /// Android-specific options for secure storage.
  AndroidOptions _getAndroidOptions() => const AndroidOptions(
    encryptedSharedPreferences: true,
    // A Keystore/decryption error must be surfaced. Automatically wiping
    // the shared secure-storage preferences can erase an unresolved
    // GasFree journal and make a blind resubmission appear safe.
    resetOnError: false,
  );
}
