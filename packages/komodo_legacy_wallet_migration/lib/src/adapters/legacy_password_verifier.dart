import 'package:dargon2_flutter/dargon2_flutter.dart';

/// Verifies a legacy native wallet password against the stored seed hash.
// ignore: one_member_abstracts
abstract interface class LegacyPasswordVerifier {
  /// Returns `true` when [password] matches the legacy [encodedHash].
  Future<bool> verifySeedPassword({
    required String password,
    required String encodedHash,
  });
}

/// Argon2id-based verifier for legacy native wallet seed passwords.
class Argon2LegacyPasswordVerifier implements LegacyPasswordVerifier {
  /// Creates an Argon2-based verifier.
  const Argon2LegacyPasswordVerifier();

  @override
  Future<bool> verifySeedPassword({
    required String password,
    required String encodedHash,
  }) async {
    try {
      return await argon2.verifyHashString(
        password,
        encodedHash,
        type: Argon2Type.id,
      );
    } on Object {
      return false;
    }
  }
}
