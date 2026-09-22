@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/history_cache_cipher.dart';

/// The point of moving the history cache off AES-CBC is that a modified record
/// is now refused rather than decrypted. These tests assert the refusal, not
/// just the round trip - a cipher that only round-trips is exactly what was
/// there before.
void main() {
  final key = List<int>.generate(32, (i) => i * 7 % 256);
  final otherKey = List<int>.generate(32, (i) => (i * 7 + 1) % 256);

  late HistoryCacheGcmCipher cipher;

  setUp(() => cipher = HistoryCacheGcmCipher(key));

  Uint8List seal(HistoryCacheGcmCipher with_, Uint8List plain) {
    final out = Uint8List(with_.maxEncryptedSize(plain));
    final length = with_.encrypt(plain, 0, plain.length, out, 0);
    return Uint8List.sublistView(out, 0, length);
  }

  Uint8List open(HistoryCacheGcmCipher with_, Uint8List sealed) {
    final out = Uint8List(sealed.length);
    final length = with_.decrypt(sealed, 0, sealed.length, out, 0);
    return Uint8List.sublistView(out, 0, length);
  }

  final plain = Uint8List.fromList(
    // A realistic envelope shape: JSON-ish, longer than one AES block.
    '{"orderKey":"KMD:0000000191","accessedAt":1758300000000}'.codeUnits,
  );

  group('HistoryCacheGcmCipher', () {
    test('returns exactly what it was given', () {
      expect(open(cipher, seal(cipher, plain)), equals(plain));
    });

    test('round-trips an empty payload', () {
      final empty = Uint8List(0);
      expect(open(cipher, seal(cipher, empty)), equals(empty));
    });

    test('never reuses a nonce', () {
      final nonces = <String>{};
      for (var i = 0; i < 64; i++) {
        final sealed = seal(cipher, plain);
        nonces.add(
          Uint8List.sublistView(
            sealed,
            0,
            HistoryCacheGcmCipher.nonceLength,
          ).join(','),
        );
      }
      expect(nonces, hasLength(64));
    });

    test('refuses a record whose ciphertext was edited', () {
      final sealed = seal(cipher, plain);
      // A byte inside the ciphertext body, past the nonce and before the tag.
      final target = HistoryCacheGcmCipher.nonceLength + 3;
      sealed[target] ^= 0x01;

      expect(() => open(cipher, sealed), throwsA(isA<Object>()));
    });

    test('refuses a record whose tag was edited', () {
      final sealed = seal(cipher, plain);
      sealed[sealed.length - 1] ^= 0x01;

      expect(() => open(cipher, sealed), throwsA(isA<Object>()));
    });

    test('refuses a record whose nonce was edited', () {
      final sealed = seal(cipher, plain);
      sealed[0] ^= 0x01;

      expect(() => open(cipher, sealed), throwsA(isA<Object>()));
    });

    test('refuses a truncated record', () {
      final sealed = seal(cipher, plain);
      final cut = Uint8List.sublistView(sealed, 0, sealed.length - 1);

      expect(() => open(cipher, cut), throwsA(isA<Object>()));
    });

    test('refuses a record shorter than a nonce and tag', () {
      final runt = Uint8List(HistoryCacheGcmCipher.nonceLength);

      expect(() => open(cipher, runt), throwsA(isA<ArgumentError>()));
    });

    test('refuses a record sealed under a different key', () {
      final sealed = seal(HistoryCacheGcmCipher(otherKey), plain);

      expect(() => open(cipher, sealed), throwsA(isA<Object>()));
    });

    test('reserves enough room for the nonce and tag', () {
      final sealed = seal(cipher, plain);

      expect(sealed.length, cipher.maxEncryptedSize(plain));
      expect(
        sealed.length - plain.length,
        HistoryCacheGcmCipher.nonceLength + HistoryCacheGcmCipher.tagLength,
      );
    });

    test('rejects a key that is not 32 bytes', () {
      expect(
        () => HistoryCacheGcmCipher(List<int>.filled(16, 0)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('key CRC', () {
    test('is stable for the same key', () {
      expect(
        HistoryCacheGcmCipher(key).calculateKeyCrc(),
        HistoryCacheGcmCipher(key).calculateKeyCrc(),
      );
    });

    test('differs between keys', () {
      expect(
        HistoryCacheGcmCipher(key).calculateKeyCrc(),
        isNot(HistoryCacheGcmCipher(otherKey).calculateKeyCrc()),
      );
    });

    // Hive compares this against the value in an existing box header. If the
    // two schemes agreed on a key's CRC, a cache written by the old CBC cipher
    // would be accepted and then fed to GCM, and the open path would have to
    // discover the mismatch by failing to decrypt instead of by rejecting the
    // header. Separating the CRC is what makes the old cache rebuild cleanly.
    test('does not collide with the CBC cipher over the same key', () {
      expect(
        HistoryCacheGcmCipher(key).calculateKeyCrc(),
        isNot(HiveAesCipher(key).calculateKeyCrc()),
      );
    });
  });
}
