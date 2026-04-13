import 'package:shared_preferences/shared_preferences.dart';

/// Minimal shared-preferences interface for legacy native wallet migration.
abstract interface class LegacySharedPreferencesStore {
  /// Reads the raw value stored under [key].
  Future<Object?> read(String key);

  /// Deletes the value stored under [key].
  Future<void> delete(String key);
}

/// `shared_preferences` adapter used by the production migration service.
class FlutterLegacySharedPreferencesStore
    implements LegacySharedPreferencesStore {
  Future<SharedPreferences> _instance() => SharedPreferences.getInstance();

  @override
  Future<Object?> read(String key) async {
    final prefs = await _instance();
    await prefs.reload();
    return prefs.get(key);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await _instance();
    await prefs.remove(key);
  }
}
