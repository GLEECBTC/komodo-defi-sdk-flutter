import 'dart:convert' show jsonDecode, jsonEncode;

/// Encodes a `{address: fingerprint}` map for transaction history `fromId`.
///
/// Always JSON-encodes so address keys are preserved (see strategy docs).
String encodeTronGridCursorMap(Map<String, String> cursors) =>
    jsonEncode(cursors);

/// Decodes a cursor string from transaction history `fromId`.
///
/// JSON objects become per-address maps. A bare non-JSON string is stored under
/// `''` as a wildcard fingerprint for single-address continuation.
Map<String, String> decodeTronGridCursorMap(String? fromId) {
  if (fromId == null || fromId.isEmpty) return {};

  if (fromId.startsWith('{')) {
    try {
      final decoded = jsonDecode(fromId);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } on FormatException catch (_) {
      // Not valid JSON; treat as a bare fingerprint.
    }
  }

  return {'': fromId};
}
