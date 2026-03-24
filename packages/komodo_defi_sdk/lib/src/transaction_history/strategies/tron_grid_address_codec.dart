import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show sha256;

/// True if [s] is non-empty and contains only ASCII hex digits.
bool _isAsciiHex(String s) => s.isNotEmpty && _asciiHexOnly.hasMatch(s);

final RegExp _asciiHexOnly = RegExp(r'^[0-9a-fA-F]+$');

const String _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Compares two TRON addresses after normalising to lowercase hex (`41` + 20
/// bytes) so Base58Check pubkeys match TRONGrid hex in `raw_data`.
bool tronAddressesEqual(String a, String b) =>
    normalizeTronAddressToHex(a) == normalizeTronAddressToHex(b);

/// Lowercase hex `41…` (42 chars) for a TRON address in hex or Base58Check.
String normalizeTronAddressToHex(String address) {
  if (address.isEmpty) return address;

  if (address.length == 42 &&
      address.startsWith('41') &&
      _isAsciiHex(address)) {
    return address.toLowerCase();
  }

  if (address.startsWith('T') || address.startsWith('4')) {
    final hex = _base58CheckPayloadToHex(address);
    if (hex != null) return hex.toLowerCase();
  }

  return address.toLowerCase();
}

/// Returns [address] in Base58Check when it is 42-char hex; else unchanged.
String tronAddressForDisplay(String address) {
  if (address.isEmpty) return address;
  if (address.length == 42 &&
      address.toLowerCase().startsWith('41') &&
      _isAsciiHex(address)) {
    return _hex41ToBase58Check(address);
  }
  return address;
}

String? _base58CheckPayloadToHex(String base58) {
  try {
    var value = BigInt.zero;
    for (var i = 0; i < base58.length; i++) {
      final digit = _base58Alphabet.indexOf(base58[i]);
      if (digit < 0) return null;
      value = value * BigInt.from(58) + BigInt.from(digit);
    }

    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';

    var leadingOnes = 0;
    for (var i = 0; i < base58.length && base58[i] == '1'; i++) {
      leadingOnes++;
    }
    hex = '00' * leadingOnes + hex;

    if (hex.length < 50) return null;
    return hex.substring(0, 42);
  } on Object {
    return null;
  }
}

String _hex41ToBase58Check(String hex) {
  try {
    final cleanHex = hex.replaceFirst(RegExp('^0x'), '').toLowerCase();
    if (cleanHex.length != 42 || !cleanHex.startsWith('41')) return hex;

    final addressBytes = _hexToBytes(cleanHex);
    final hash1 = sha256.convert(addressBytes).bytes;
    final hash2 = sha256.convert(hash1).bytes;
    final checksum = hash2.sublist(0, 4);

    final full = Uint8List(addressBytes.length + 4)
      ..setAll(0, addressBytes)
      ..setAll(addressBytes.length, checksum);

    return _bytesToBase58(full);
  } on Object {
    return hex;
  }
}

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

String _bytesToBase58(Uint8List bytes) {
  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) + BigInt.from(b);
  }

  final sb = StringBuffer();
  while (value > BigInt.zero) {
    final remainder = (value % BigInt.from(58)).toInt();
    value = value ~/ BigInt.from(58);
    sb.write(_base58Alphabet[remainder]);
  }

  for (final b in bytes) {
    if (b != 0) break;
    sb.write('1');
  }

  return sb.toString().split('').reversed.join();
}
