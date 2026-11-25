import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Persists the local wallet behind a Trezor session: its generated password,
/// kept separately from the device's user-entered passphrase, and its name
/// when it differs from the built-in one.
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
  static const _walletNameKey = 'trezor_wallet_name';

  final FlutterSecureStorage _storage;
  final String Function(int length) _generatePassword;

  Future<String?> readPassword() => _storage.read(key: _passwordKey);

  /// The local wallet name, or null for the built-in one.
  Future<String?> readWalletName() => _storage.read(key: _walletNameKey);

  /// The saved password, generating and saving one if there is none.
  Future<String> getOrCreatePassword() async {
    final saved = await readPassword();
    if (saved != null) return saved;
    final password = generatePassword();
    await _storage.write(key: _passwordKey, value: password);
    return password;
  }

  String generatePassword() => _generatePassword(16);

  /// Replaces the saved name and password with those of [walletName].
  Future<void> saveWallet(String walletName, String password) async {
    await _storage.write(key: _walletNameKey, value: walletName);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _walletNameKey);
  }
}
