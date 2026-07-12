import 'dart:math';

import 'package:characters/characters.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Enum representing different types of password validation errors
enum PasswordValidationError {
  containsPassword,
  tooShort,
  missingDigit,
  missingLowercase,
  missingUppercase,
  missingSpecialCharacter,
  consecutiveCharacters,
  none;

  bool get isValid => this == PasswordValidationError.none;
}

// ignore: one_member_abstracts
abstract class SecurityUtils {
  static String generatePasswordSecure(
    int length, {
    bool extendedSpecialCharacters = false,
  }) {
    var result = '';
    while (!SecurityUtils.checkPasswordRequirements(result).isValid) {
      result = _generateSecurePassword(
        length,
        extendedSpecialCharacters: extendedSpecialCharacters,
      );
    }

    return result;
  }

  /// /// Validates password according to KDF password policy
  ///
  /// Password requirements:
  /// - At least 8 characters long
  /// - Can't contain the word "password"
  /// - At least 1 digit
  /// - At least 1 lowercase character
  /// - At least 1 uppercase character
  /// - At least 1 special character
  /// - No same character 3 times in a row
  static PasswordValidationError checkPasswordRequirements(String password) {
    // Use Unicode-aware character counting
    if (password.characters.length < 8) {
      return PasswordValidationError.tooShort;
    }

    if (password.toLowerCase().contains(
      RegExp('password', caseSensitive: false, unicode: true),
    )) {
      return PasswordValidationError.containsPassword;
    }

    // Check for digits (any numerical digit in any script)
    if (!RegExp(r'.*\p{N}.*', unicode: true).hasMatch(password)) {
      return PasswordValidationError.missingDigit;
    }

    // Check for lowercase (any lowercase letter in any script)
    if (!RegExp(r'.*\p{Ll}.*', unicode: true).hasMatch(password)) {
      return PasswordValidationError.missingLowercase;
    }

    // Check for uppercase (any uppercase letter in any script)
    if (!RegExp(r'.*\p{Lu}.*', unicode: true).hasMatch(password)) {
      return PasswordValidationError.missingUppercase;
    }

    // Check for special characters
    if (!RegExp(r'.*[^\p{L}\p{N}].*', unicode: true).hasMatch(password)) {
      return PasswordValidationError.missingSpecialCharacter;
    }

    // Unicode-aware check for consecutive repeated characters using Characters class
    final charactersList = password.characters.toList();
    for (var i = 0; i < charactersList.length - 2; i++) {
      if (charactersList[i] == charactersList[i + 1] &&
          charactersList[i] == charactersList[i + 2]) {
        return PasswordValidationError.consecutiveCharacters;
      }
    }

    return PasswordValidationError.none;
  }

  static String _generateSecurePassword(
    int length, {
    bool extendedSpecialCharacters = false,
  }) {
    const upperCaseLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lowerCaseLetters = 'abcdefghijklmnopqrstuvwxyz';
    const digits = '0123456789';

    // Standard special characters that are generally safe in most contexts,
    // including JSON
    const specialCharacters = '@';
    // const specialCharacters = r"*.!@#$%^(){}:;',.?/~`_+-=|";

    const extendedSpecial = r'~`$^*+=<>?';

    final allCharacters =
        upperCaseLetters +
        lowerCaseLetters +
        digits +
        specialCharacters +
        (extendedSpecialCharacters ? extendedSpecial : '');

    // Ensure the password length is at least 8 characters
    if (length < 8) {
      throw ArgumentError('Password length must be at least 8 characters.');
    }

    // Random number generator
    final random = Random.secure();

    // Pick one character from each category to ensure password strength
    final password = <String>[
      upperCaseLetters[random.nextInt(upperCaseLetters.length)],
      lowerCaseLetters[random.nextInt(lowerCaseLetters.length)],
      digits[random.nextInt(digits.length)],
      specialCharacters[random.nextInt(specialCharacters.length)],
      if (extendedSpecialCharacters)
        extendedSpecial[random.nextInt(extendedSpecial.length)],
    ];

    // Fill the rest of the password length with random characters from the pool
    for (var i = password.length; i < length; i++) {
      password.add(allCharacters[random.nextInt(allCharacters.length)]);
    }

    // Shuffle the password to ensure randomness
    password.shuffle(random);

    // Join the list into a string and return it
    return password.join();
  }
}

const _redactedLogValue = '<redacted>';

const _sensitiveLogKeys = <String>{
  'access_key',
  'access_token',
  'api_key',
  'api_secret',
  'api_token',
  'authorization',
  'authorization_context',
  'bearer_token',
  'cookie',
  'expected_authorization',
  'gasless_authorization',
  'id_token',
  'mnemonic',
  'passphrase',
  'password',
  'pin',
  'plaintext_mnemonic',
  'private_key',
  'private_keys',
  'privkey',
  'refresh_token',
  'rpc_password',
  'seed',
  'secret',
  'secret_key',
  'set_cookie',
  'sig',
  'signature',
  'signed_authorization',
  'signed_payload',
  'signed_transaction',
  'spend_key',
  'tx_hex',
  'userpass',
  'view_key',
  'wallet_password',
  'wif',
};

bool _isSensitiveLogKey(Object? key) {
  final snakeCaseKey = key.toString().trim().replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)}',
  );
  final normalized = snakeCaseKey.toLowerCase().replaceAll('-', '_');
  return _sensitiveLogKeys.contains(normalized) ||
      normalized == 'address' ||
      normalized.endsWith('_address') ||
      normalized == 'pubkey' ||
      normalized.endsWith('_pubkey') ||
      normalized.endsWith('_pubkey_hash') ||
      normalized.endsWith('_password') ||
      normalized.endsWith('_passphrase') ||
      normalized.endsWith('_private_key') ||
      normalized.endsWith('_secret') ||
      normalized.endsWith('_signature');
}

Object? _censorForLogging(Object? value, {Object? key}) {
  if (key != null && _isSensitiveLogKey(key)) return _redactedLogValue;
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _censorForLogging(entry.value, key: entry.key),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final element in value) _censorForLogging(element)];
  }
  return value;
}

extension CensoredJsonMap on JsonMap {
  /// Returns a recursively redacted copy safe for diagnostic logging.
  ///
  /// Secret-bearing containers such as `signed_authorization` are removed as a
  /// whole, and nested maps/lists are traversed without mutating the RPC object
  /// that will be sent to KDF.
  JsonMap censored() => _censorForLogging(this)! as JsonMap;
}

/// Wrapper for sensitive strings that should never reveal their value when
/// implicitly stringified (e.g. in logs via interpolation).
class SensitiveString {
  const SensitiveString(this.value);

  final String value;

  @override
  String toString() => '[REDACTED]';
}

/// JSON converter for [SensitiveString] that preserves the raw string in
/// serialized JSON while restoring it as a [SensitiveString] on deserialization.
class SensitiveStringConverter
    implements JsonConverter<SensitiveString?, String?> {
  const SensitiveStringConverter();

  @override
  SensitiveString? fromJson(String? json) =>
      json == null ? null : SensitiveString(json);

  @override
  String? toJson(SensitiveString? object) => object?.value;
}

// Example Test
void main() {
  final password = SecurityUtils.generatePasswordSecure(24);
  final extendedPassword = SecurityUtils.generatePasswordSecure(
    24,
    extendedSpecialCharacters: true,
  );

  // ignore: avoid_print
  print('Password: $password');
  // ignore: avoid_print
  print('Extended Password: $extendedPassword');
}
