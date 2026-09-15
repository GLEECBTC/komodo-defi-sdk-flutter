import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:mutex/mutex.dart';

/// Internal injectable key boundary; applications do not handle cache keys.
// ignore: one_member_abstracts
abstract interface class HistoryCacheKeyProvider {
  /// Returns the persisted 32-byte key, creating it securely when absent.
  Future<List<int>> loadOrCreate(String cacheName);
}

/// Protects a random cache key using the platform's secure storage.
///
/// A missing key replaces only reconstructible cache data. Failed reads and
/// malformed keys throw, so callers cannot silently start plaintext storage.
class SecureHistoryCacheKeyProvider implements HistoryCacheKeyProvider {
  /// Uses platform secure storage unless a test implementation is supplied.
  SecureHistoryCacheKeyProvider({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;
  static final _mutex = Mutex();

  @override
  Future<List<int>> loadOrCreate(String cacheName) => _mutex.protect(() async {
    final storageKey =
        'komodo_tx_history_key_v2.'
        '${sha256.convert(utf8.encode(cacheName))}';
    final stored = await _storage.read(key: storageKey);
    if (stored != null) {
      try {
        final bytes = base64Decode(stored);
        if (bytes.length == 32) return bytes;
      } on FormatException {
        // Do not propagate a FormatException retaining the key as its source.
      }
      throw StateError('Transaction history cache key is unreadable');
    }
    final bytes = Hive.generateSecureKey();
    final encoded = base64Encode(bytes);
    await _storage.write(key: storageKey, value: encoded);
    if (await _storage.read(key: storageKey) != encoded) {
      throw StateError('Transaction history cache key could not be persisted');
    }
    return bytes;
  });
}
