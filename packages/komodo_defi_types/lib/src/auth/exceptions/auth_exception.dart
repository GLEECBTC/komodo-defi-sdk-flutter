import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

enum AuthExceptionType {
  /// Used for any incorrect password scenario (login, changing password, etc.)
  incorrectPassword,
  invalidBip39Mnemonic,
  walletAlreadyRunning,
  walletStartFailed,
  generalAuthError,
  unauthorized,
  alreadySignedIn,
  walletNotFound,
  walletAlreadyExists,
  registrationNotAllowed,
  internalError,
  apiConnectionError,

  /// Legacy wallet already has a migrated KDF counterpart.
  legacyWalletAlreadyMigrated,
}

class AuthException implements Exception {
  AuthException(this.message, {required this.type, this.details = const {}});

  // Common exception constructors convenience methods
  AuthException.notSignedIn()
    : this('Not signed in', type: AuthExceptionType.unauthorized);
  AuthException.notFound()
    : this('Not found', type: AuthExceptionType.walletNotFound);

  AuthException.legacyWalletAlreadyMigrated(String migratedWalletName)
    : this(
        'Legacy wallet already migrated',
        type: AuthExceptionType.legacyWalletAlreadyMigrated,
        details: {'migratedWalletName': migratedWalletName},
      );

  /// The error message.
  final String message;

  /// The error type.
  final AuthExceptionType type;

  /// The error details.
  final JsonMap? details;

  @override
  String toString() {
    return 'AuthException{type: $type, message: $message, details: $details}';
  }

  /// This method scans the log for matching error patterns and returns the
  ///  detected exceptions.
  ///
  /// Evaluate long-term performance scalability of this method.
  static List<AuthException> findExceptionsInLog(
    String log, {
    bool firstOnly = false,
  }) {
    final exceptions = <AuthException>[];
    for (final line in log.split('\n')) {
      exceptions.addAll(_findExceptionsInLine(line));
      if (firstOnly && exceptions.isNotEmpty) {
        break;
      }
    }
    return exceptions;
  }

  static List<AuthException> _findExceptionsInLine(String line) {
    final exceptions = <AuthException>[];

    // Convert the log line to lowercase for case-insensitive matching
    final lowerCaseLine = line.toLowerCase();

    for (final type in AuthExceptionType.values) {
      for (final pattern in AuthException._getMatchingPatterns(type)) {
        if (lowerCaseLine.contains(pattern.toLowerCase())) {
          exceptions.add(AuthException(line, type: type));
          break; // Stop searching after finding the first match for this type
        }
      }
    }

    return exceptions;
  }

  static List<String> _getMatchingPatterns(AuthExceptionType type) {
    switch (type) {
      case AuthExceptionType.incorrectPassword:
        return matchingPatterns[AuthExceptionType.incorrectPassword]!;
      case AuthExceptionType.walletAlreadyRunning:
        return matchingPatterns[AuthExceptionType.walletAlreadyRunning]!;
      case AuthExceptionType.walletStartFailed:
        return matchingPatterns[AuthExceptionType.walletStartFailed]!;
      case AuthExceptionType.walletNotFound:
        return matchingPatterns[AuthExceptionType.walletNotFound]!;
      case AuthExceptionType.walletAlreadyExists:
        return matchingPatterns[AuthExceptionType.walletAlreadyExists]!;
      case AuthExceptionType.registrationNotAllowed:
        return matchingPatterns[AuthExceptionType.registrationNotAllowed]!;
      case AuthExceptionType.apiConnectionError:
        return matchingPatterns[AuthExceptionType.apiConnectionError]!;
      // The following types don't originate from the API, so we return empty
      // arrays.
      case AuthExceptionType.generalAuthError:
      case AuthExceptionType.unauthorized:
      case AuthExceptionType.alreadySignedIn:
      case AuthExceptionType.internalError:
      case AuthExceptionType.invalidBip39Mnemonic:
      case AuthExceptionType.legacyWalletAlreadyMigrated:
        return [];
    }
  }

  static Map<AuthExceptionType, List<String>> get matchingPatterns => {
    AuthExceptionType.incorrectPassword: [
      'Incorrect wallet password',
      'Error generating or decrypting mnemonic',
      'HMAC',
      'Error decrypting mnemonic: HMAC error: MAC tag mismatch',
      'MAC tag mismatch',
      'Error decrypting mnemonic',
    ],
    AuthExceptionType.walletAlreadyRunning: ['Wallet is already running'],
    AuthExceptionType.walletStartFailed: ['Failed to start KDF'],
    AuthExceptionType.walletNotFound: [
      'Wallet does not exist',
      'No wallet found with the given name',
    ],
    AuthExceptionType.walletAlreadyExists: [
      'Wallet already exists',
      'A wallet with this name already exists',
    ],
    AuthExceptionType.registrationNotAllowed: ['wallet creation is disabled'],
    AuthExceptionType.apiConnectionError: [
      'Connection refused',
      'Connection timed out',
    ],
    // We don't include patterns for the following types as they don't
    // originate from the API.
    // AuthExceptionType.generalAuthError
    // AuthExceptionType.unauthorized
    // AuthExceptionType.alreadySignedIn
  };
}
