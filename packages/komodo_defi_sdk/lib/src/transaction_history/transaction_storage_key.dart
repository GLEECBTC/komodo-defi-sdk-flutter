import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The parts of a persisted transaction key, as recovered by
/// [TransactionStorageKey.parse].
class TransactionKeyParts {
  /// Creates the decomposed form of a storage key.
  const TransactionKeyParts({
    required this.prefix,
    required this.timestampMicros,
    required this.idToken,
    required this.idTokenIsHashed,
  });

  /// `<walletToken>|<assetToken>|`, identifying one (wallet, asset) pair.
  final String prefix;

  /// The transaction timestamp encoded in the key, in microseconds.
  ///
  /// Clamped at write time, so this is an ordering value rather than an
  /// authoritative timestamp. The record body holds the exact value.
  final int timestampMicros;

  /// The trailing key segment: either the internal ID verbatim, or a digest of
  /// it when the ID exceeded the token budget.
  final String idToken;

  /// Whether [idToken] is a digest rather than the internal ID itself.
  final bool idTokenIsHashed;
}

/// Builds and decomposes the Hive keys used by the persisted transaction store.
///
/// The layout is fixed-width up to the trailing ID so that a key can be
/// decomposed with three `indexOf` calls, and so that no component can bleed
/// into the next:
///
/// ```text
/// <walletToken:20 hex>|<assetToken:20 hex>|<timestamp:16 digits>|<idToken>
/// ```
///
/// ## Why the length guard is not optional
///
/// `hive_ce` writes a String key as a single length byte followed by its UTF-8
/// bytes (`BinaryWriterImpl.writeKey`), and validates nothing. A key over 255
/// UTF-8 bytes therefore wraps its length prefix modulo 256, which misparses
/// the frame, fails its CRC, and - with the default `crashRecovery: true` -
/// makes Hive truncate the box file at that frame, discarding every record
/// written after it. The failure is silent and VM-only, because on web the key
/// goes into IndexedDB with no length byte at all.
///
/// [build] therefore refuses to emit an over-long key. With the fixed-width
/// prefix and the [maxIdTokenBytes] budget, the maximum is 249 bytes.
abstract final class TransactionStorageKey {
  /// Hive's hard limit on the UTF-8 length of a String key.
  static const int maxKeyBytes = 255;

  /// Longest internal ID retained verbatim in a key.
  ///
  /// Anything longer is replaced by [_hashedIdPrefix] plus a SHA-256 digest,
  /// which is 65 bytes. Real internal IDs are transaction hashes or KDF
  /// `internal_id` values, well inside this budget; the escape hatch exists so
  /// the 255-byte ceiling cannot be reached by a hostile or unusual ID.
  static const int maxIdTokenBytes = 190;

  /// Width of the wallet and asset tokens, in hex characters.
  static const int tokenLength = 20;

  /// Width of the encoded timestamp, in decimal digits.
  static const int timestampLength = 16;

  /// Separator between key components.
  ///
  /// Safe because both tokens are hex and the timestamp is decimal, so only the
  /// trailing ID can contain it - and by then all three separators have been
  /// consumed.
  static const String separator = '|';

  static const String _hashedIdPrefix = '#';

  /// Largest integer that survives dart2js exactly, i.e. 2^53 - 1.
  static const int _maxSafeInteger = 9007199254740991;

  /// Returns the opaque token identifying [walletId]'s storage namespace.
  ///
  /// Derived from [walletStorageNamespace] rather than [WalletId.compoundId]:
  /// the compound ID omits authentication options, so an HD and an Iguana
  /// session on the same seed would share a namespace.
  static String walletToken(WalletId walletId) =>
      tokenForNamespace(walletStorageNamespace(walletId));

  /// Returns the wallet token for an already-computed storage [namespace].
  ///
  /// Lets callers that hold namespaces rather than [WalletId]s - the
  /// wallet garbage collector, for one - compare against key prefixes.
  static String tokenForNamespace(String namespace) => _digest(namespace);

  /// Returns the opaque token identifying [assetId].
  ///
  /// Hashes exactly the tuple behind `AssetId.props`, so two assets that
  /// compare equal always produce the same token and two that do not, never do.
  static String assetToken(AssetId assetId) => _digest(
    [
      assetId.id,
      assetId.subClass.formatted,
      assetId.chainId.formattedChainId,
    ].join(separator),
  );

  /// Returns the `<walletToken>|<assetToken>|` prefix for one (wallet, asset)
  /// pair. Every key for that pair starts with it, and no other pair's does.
  static String prefix(WalletId walletId, AssetId assetId) =>
      '${walletToken(walletId)}$separator${assetToken(assetId)}$separator';

  /// Returns the `<walletToken>|` prefix covering every asset for [walletId].
  static String walletPrefix(WalletId walletId) =>
      '${walletToken(walletId)}$separator';

  /// Encodes [timestamp] as a fixed-width, zero-padded decimal microsecond
  /// count.
  ///
  /// Decimal rather than a bit-inverted integer: dart2js `int` bitwise
  /// operations are 32-bit, so a 64-bit complement trick would silently corrupt
  /// on web. Values are clamped into `[0, 2^53 - 1]` so the encoding is exact
  /// on every platform; the range still reaches the year 287396.
  static String encodeTimestamp(DateTime timestamp) {
    final micros = timestamp.microsecondsSinceEpoch.clamp(0, _maxSafeInteger);
    return micros.toString().padLeft(timestampLength, '0');
  }

  /// Builds the key for one transaction.
  ///
  /// Throws [TransactionStorageException] if the result would exceed
  /// [maxKeyBytes], rather than letting Hive corrupt the box.
  static String build({
    required String prefix,
    required DateTime timestamp,
    required String internalId,
  }) {
    final key =
        '$prefix${encodeTimestamp(timestamp)}$separator'
        '${idTokenFor(internalId)}';
    final byteLength = utf8.encode(key).length;
    if (byteLength > maxKeyBytes) {
      throw TransactionStorageException(
        'Storage key is $byteLength bytes, over the $maxKeyBytes-byte limit',
      );
    }
    return key;
  }

  /// Decomposes a key built by [build]. Returns `null` if [key] is malformed.
  static TransactionKeyParts? parse(String key) {
    final walletEnd = key.indexOf(separator);
    if (walletEnd != tokenLength) return null;

    final assetEnd = key.indexOf(separator, walletEnd + 1);
    if (assetEnd != walletEnd + 1 + tokenLength) return null;

    final timestampEnd = key.indexOf(separator, assetEnd + 1);
    if (timestampEnd != assetEnd + 1 + timestampLength) return null;

    final micros = int.tryParse(key.substring(assetEnd + 1, timestampEnd));
    if (micros == null) return null;

    // Everything after the third separator is the ID token, which may itself
    // contain separators.
    final idToken = key.substring(timestampEnd + 1);
    if (idToken.isEmpty) return null;

    return TransactionKeyParts(
      prefix: key.substring(0, assetEnd + 1),
      timestampMicros: micros,
      idToken: idToken,
      idTokenIsHashed: idToken.startsWith(_hashedIdPrefix),
    );
  }

  /// Whether [key] belongs to the (wallet, asset) pair identified by [prefix].
  static bool hasPrefix(String key, String prefix) => key.startsWith(prefix);

  /// The token [build] embeds in the key for [internalId].
  ///
  /// An ID within [maxIdTokenBytes] is embedded verbatim; anything longer is
  /// replaced by a `#`-prefixed SHA-256 digest. Everything that stores or
  /// looks up by internal ID must normalise through this same function, or an
  /// overlong ID's row can never be found again once written.
  static String idTokenFor(String internalId) =>
      utf8.encode(internalId).length <= maxIdTokenBytes
      ? internalId
      : '$_hashedIdPrefix${sha256.convert(utf8.encode(internalId))}';

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, tokenLength);
}
