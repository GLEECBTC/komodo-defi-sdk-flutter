import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:pointycastle/export.dart';

/// Authenticated encryption for the transaction history cache.
///
/// Hive's own [HiveAesCipher] is AES-256-CBC with PKCS7 padding and no
/// authentication tag. The frame CRC-32 that sits around a record is not a
/// substitute: CRC-32 is affine, so an edit to the ciphertext can be corrected
/// in the checksum without knowing anything secret, and Hive's web backend
/// writes no CRC at all. A modified record therefore decrypted into plausible
/// bytes rather than being rejected.
///
/// GCM authenticates. A record altered by a byte flip or a truncation, or
/// sealed under a different key, fails its tag check and the read throws
/// instead of returning attacker-shaped data.
///
/// The tag covers the ciphertext and nothing else, so it does not by itself
/// distinguish one record in this box from another: a ciphertext moved to a
/// different disk key still authenticates. What rejects that is the plaintext
/// envelope, whose `orderKey` both read paths in `HiveTransactionStorage`
/// compare against the key it was read under. Relocation is caught there, not
/// here. Restoring an *older* ciphertext under its own key is not caught by
/// either, and would need the disk key and a version bound in as associated
/// data - which Hive's cipher interface does not pass through. The exposure is
/// a stale history view for someone who already has write access to the app's
/// private storage, where deleting the cache is equally available.
///
/// Layout is `nonce || ciphertext || tag`: a 12-byte random nonce, then the
/// ciphertext, then the 16-byte tag GCM appends when the record is finalised.
///
/// This does not address where the key lives. On web the key provider still
/// keeps it in browser storage, so a complete copy of origin storage recovers
/// it and, with it, every wallet's history on that device. That is a property
/// of the single shared box, whose retention index is rebuilt from every
/// record at open time regardless of which wallet is signed in, and it needs a
/// storage redesign rather than a different cipher.
class HistoryCacheGcmCipher implements HiveCipher {
  /// Wraps the 32-byte [key] in AES-256-GCM.
  HistoryCacheGcmCipher(List<int> key) {
    if (key.length != 32 || key.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError(
        'The encryption key has to be a 32 byte (256 bit) array.',
      );
    }
    _key = KeyParameter(Uint8List.fromList(key));

    // Domain-separated from Hive's own CRC over the same bytes, so a cache
    // written by the previous CBC cipher cannot be mistaken for one of ours.
    //
    // On the VM backend Hive seeds each frame's CRC with this value, so a
    // legacy cache is rejected as the box opens and the storage rebuilds it.
    // The web backend writes no CRC and never asks for this, so there the
    // legacy records instead fail their GCM tag one at a time and are evicted
    // as unreadable. Different route, same outcome: nothing from the old cache
    // is ever decoded.
    _keyCrc = _crc32(
      Uint8List.fromList(sha256.convert([...utf8Label, ...key]).bytes),
    );
  }

  /// Separates this scheme's key hash from the one Hive's CBC cipher computes.
  static const utf8Label = <int>[
    // 'komodo-history-gcm-v1'
    107, 111, 109, 111, 100, 111, 45, 104, 105, 115, 116, 111, 114, 121, //
    45, 103, 99, 109, 45, 118, 49,
  ];

  /// Bytes of random nonce written in front of every record.
  static const nonceLength = 12;

  /// Bytes of authentication tag written after every record.
  static const tagLength = 16;

  static final Random _nonceRandom = Random.secure();

  late final KeyParameter _key;
  late final int _keyCrc;

  /// Reused across records. Every call re-initialises it and runs to
  /// completion synchronously, so no two records ever share a state.
  final GCMBlockCipher _cipher = GCMBlockCipher(AESEngine());

  static final Uint8List _noAssociatedData = Uint8List(0);

  @override
  int calculateKeyCrc() => _keyCrc;

  @override
  int maxEncryptedSize(Uint8List inp) => inp.length + nonceLength + tagLength;

  @override
  int encrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) {
    final nonce = _generateNonce();
    out.setRange(outOff, outOff + nonceLength, nonce);

    _cipher
      ..reset()
      ..init(
        true,
        AEADParameters(_key, tagLength * 8, nonce, _noAssociatedData),
      );

    final bodyOff = outOff + nonceLength;
    var written = _cipher.processBytes(inp, inpOff, inpLength, out, bodyOff);
    written += _cipher.doFinal(out, bodyOff + written);
    return nonceLength + written;
  }

  @override
  int decrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) {
    if (inpLength < nonceLength + tagLength) {
      throw ArgumentError('Encrypted history record is too short to be valid');
    }
    final nonce = Uint8List.sublistView(inp, inpOff, inpOff + nonceLength);

    _cipher
      ..reset()
      ..init(
        false,
        AEADParameters(
          _key,
          tagLength * 8,
          Uint8List.fromList(nonce),
          _noAssociatedData,
        ),
      );

    // Throws InvalidCipherTextException from doFinal when the tag does not
    // match. The caller treats a throwing read as an unusable record, which is
    // the intended outcome: a tampered record is dropped, never returned.
    final written = _cipher.processBytes(
      inp,
      inpOff + nonceLength,
      inpLength - nonceLength,
      out,
      outOff,
    );
    return written + _cipher.doFinal(out, outOff + written);
  }

  Uint8List _generateNonce() {
    final nonce = Uint8List(nonceLength);
    for (var i = 0; i < nonceLength; i++) {
      nonce[i] = _nonceRandom.nextInt(256);
    }
    return nonce;
  }

  /// CRC-32 over [bytes], matching the polynomial Hive stores in box headers.
  static int _crc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
