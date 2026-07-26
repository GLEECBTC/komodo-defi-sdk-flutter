import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web/web.dart' as web;

/// Returns raw GasFree key names without asking flutter_secure_storage to
/// decrypt unrelated application entries.
///
/// Its web `readAll` implementation silently omits values that cannot be
/// decrypted. Enumerating matching raw names first lets the repository read
/// every discovered journal through its contains/read/contains guard and fail
/// closed if ciphertext is present but unreadable.
Future<Set<String>> discoverSecureStorageKeysWithPrefix(
  FlutterSecureStorage storage,
  String prefix, {
  required int maxKeys,
}) async {
  if (maxKeys < 1) {
    throw ArgumentError.value(maxKeys, 'maxKeys', 'Must be positive');
  }
  final options = storage.webOptions;
  final backingStorage = options.useSessionStorage
      ? web.window.sessionStorage
      : web.window.localStorage;
  final secureStoragePrefix = '${options.publicKey}.';
  final fullyQualifiedPrefix = '$secureStoragePrefix$prefix';
  final matches = <String>{};

  for (var index = 0; index < backingStorage.length; index++) {
    final key = backingStorage.key(index);
    if (key == null || !key.startsWith(fullyQualifiedPrefix)) continue;
    matches.add(key.substring(secureStoragePrefix.length));
    if (matches.length > maxKeys) {
      throw StateError('GasFree legacy journal discovery limit exceeded');
    }
  }
  return matches;
}
