import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';

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
///
/// Uses pointycastle's pure-Dart Argon2 implementation, which is compatible
/// with all Dart platforms including Flutter Web WASM.
class Argon2LegacyPasswordVerifier implements LegacyPasswordVerifier {
  /// Creates an Argon2-based verifier.
  const Argon2LegacyPasswordVerifier();

  @override
  Future<bool> verifySeedPassword({
    required String password,
    required String encodedHash,
  }) async {
    try {
      final parsed = _parsePhcEncodedHash(encodedHash);
      if (parsed == null) return false;

      final params = Argon2Parameters(
        parsed.type,
        parsed.salt,
        desiredKeyLength: parsed.hash.length,
        iterations: parsed.timeCost,
        memory: parsed.memoryCost,
        lanes: parsed.parallelism,
        version: parsed.version,
      );

      final generator = Argon2BytesGenerator()..init(params);
      final derived = generator.process(
        Uint8List.fromList(utf8.encode(password)),
      );

      return _constantTimeEquals(derived, parsed.hash);
    } on Object {
      return false;
    }
  }

  /// Parses the PHC string format used by Argon2 reference implementations.
  ///
  /// Format:
  /// `$argon2<type>$v=<ver>$m=<mem>,t=<time>,p=<par>$<salt>$<hash>`
  static _ParsedArgon2Hash? _parsePhcEncodedHash(String encoded) {
    final parts = encoded.split(r'$');
    // Expect ['', 'argon2id', 'v=19', 'm=...,t=...,p=...', '<salt>', '<hash>']
    if (parts.length < 6) return null;

    final int type;
    switch (parts[1]) {
      case 'argon2d':
        type = Argon2Parameters.ARGON2_d;
      case 'argon2i':
        type = Argon2Parameters.ARGON2_i;
      case 'argon2id':
        type = Argon2Parameters.ARGON2_id;
      default:
        return null;
    }

    final versionMatch = RegExp(r'^v=(\d+)$').firstMatch(parts[2]);
    if (versionMatch == null) return null;
    final version = int.parse(versionMatch.group(1)!);

    final paramsMatch =
        RegExp(r'^m=(\d+),t=(\d+),p=(\d+)$').firstMatch(parts[3]);
    if (paramsMatch == null) return null;
    final memoryCost = int.parse(paramsMatch.group(1)!);
    final timeCost = int.parse(paramsMatch.group(2)!);
    final parallelism = int.parse(paramsMatch.group(3)!);

    final salt = _decodeUnpaddedBase64(parts[4]);
    final hash = _decodeUnpaddedBase64(parts[5]);
    if (salt == null || hash == null) return null;

    return _ParsedArgon2Hash(
      type: type,
      version: version,
      memoryCost: memoryCost,
      timeCost: timeCost,
      parallelism: parallelism,
      salt: salt,
      hash: hash,
    );
  }

  static Uint8List? _decodeUnpaddedBase64(String input) {
    try {
      final padded = switch (input.length % 4) {
        2 => '$input==',
        3 => '$input=',
        _ => input,
      };
      return base64Decode(padded);
    } on Object {
      return null;
    }
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

class _ParsedArgon2Hash {
  const _ParsedArgon2Hash({
    required this.type,
    required this.version,
    required this.memoryCost,
    required this.timeCost,
    required this.parallelism,
    required this.salt,
    required this.hash,
  });

  final int type;
  final int version;
  final int memoryCost;
  final int timeCost;
  final int parallelism;
  final Uint8List salt;
  final Uint8List hash;
}
