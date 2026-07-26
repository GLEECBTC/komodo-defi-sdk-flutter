import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Native flutter_secure_storage has no bounded, key-only enumeration API.
///
/// `readAll` would decrypt unrelated application secrets before filtering and
/// platform implementations do not share fail-closed corruption semantics.
/// Known keys and persisted aliases remain available through ordinary reads;
/// broad legacy discovery is intentionally unsupported until a GasFree-only
/// key manifest or native platform channel exists.
Future<Set<String>> discoverSecureStorageKeysWithPrefix(
  FlutterSecureStorage _,
  String _, {
  required int maxKeys,
}) {
  if (maxKeys < 1) {
    throw ArgumentError.value(maxKeys, 'maxKeys', 'Must be positive');
  }
  return Future.value(const <String>{});
}
