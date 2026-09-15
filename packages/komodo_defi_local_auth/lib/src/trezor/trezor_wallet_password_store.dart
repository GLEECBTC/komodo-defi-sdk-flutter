import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Persists the generated local wallet password separately from the device's
/// user-entered passphrase.
class TrezorWalletPasswordStore {
  TrezorWalletPasswordStore({
    FlutterSecureStorage? storage,
    String Function(int length)? passwordGenerator,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: false),
           ),
       _generatePassword =
           passwordGenerator ?? SecurityUtils.generatePasswordSecure;

  static const _passwordKey = 'trezor_wallet_password';

  final FlutterSecureStorage _storage;
  final String Function(int length) _generatePassword;

  Future<String> getPassword({required bool isNewUser}) async {
    final existing = await _storage.read(key: _passwordKey);
    if (!isNewUser) {
      if (existing == null) {
        throw AuthException(
          'Authentication failed for Trezor wallet',
          type: AuthExceptionType.generalAuthError,
        );
      }
      return existing;
    }

    if (existing != null) return existing;

    final newPassword = _generatePassword(16);
    await _storage.write(key: _passwordKey, value: newPassword);
    return newPassword;
  }

  Future<void> clear() => _storage.delete(key: _passwordKey);
}
