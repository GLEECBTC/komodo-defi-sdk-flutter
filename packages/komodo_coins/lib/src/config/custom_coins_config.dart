import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show JsonList, JsonMap;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Process-wide registry and persistent store for the user's custom coins /
/// coins-config override.
///
/// Two independent overrides are supported:
///
/// * **KDF coins** — the raw `coins` list passed to mm2/KDF at startup. When
///   set, the parsed list ([kdfCoinsListOrNull]) replaces the default coins
///   data fetched for the framework.
/// * **Coins config** — the enriched `coins_config.json`-shaped map consumed by
///   the SDK's asset registry. When set, a [FileCoinConfigProvider] backed by
///   [coinsConfigSource] becomes the authoritative coin-config source.
///
/// The override is persisted (Hive — IndexedDB on web, a file box on native) so
/// it survives an app restart, which is **required** for a change to take
/// effect: the coins data is only read when KDF starts and the asset registry
/// is built during SDK initialization.
///
/// This is intentionally a singleton consulted from several SDK layers
/// (`KdfStartupConfig`, `StartupCoinsProvider`, `KomodoAssetsUpdateManager`).
/// It is populated once by the SDK bootstrap before any of those run.
class CustomCoinsConfig {
  CustomCoinsConfig._();

  /// The shared singleton instance.
  static final CustomCoinsConfig instance = CustomCoinsConfig._();

  static final Logger _log = Logger('CustomCoinsConfig');

  static const String _boxName = 'kdf_custom_coins_config';
  static const String _kdfCoinsKey = 'kdf_coins';
  static const String _coinsConfigKey = 'coins_config';
  static const String _defaultAppName = 'komodo_coins';

  CustomCoinsFileSource? _kdfCoins;
  CustomCoinsFileSource? _coinsConfig;
  JsonList? _kdfCoinsList;
  bool _loaded = false;

  /// The configured KDF-coins override source, if any.
  CustomCoinsFileSource? get kdfCoinsSource => _kdfCoins;

  /// The configured coins-config override source, if any.
  CustomCoinsFileSource? get coinsConfigSource => _coinsConfig;

  /// Whether a custom KDF-coins file is configured.
  bool get hasKdfCoinsOverride => _kdfCoins != null;

  /// Whether a custom coins-config file is configured.
  bool get hasCoinsConfigOverride => _coinsConfig != null;

  /// The pre-parsed raw coins list for mm2 startup, or `null` when no KDF-coins
  /// override is configured.
  JsonList? get kdfCoinsListOrNull => _kdfCoinsList;

  /// Loads the persisted override into memory (and pre-parses the KDF-coins
  /// file) so it is ready before KDF starts and the asset registry is built.
  ///
  /// Idempotent: only the first successful call performs IO. Failures are
  /// logged and swallowed so a corrupt override never blocks startup.
  Future<void> load({String? appStoragePath, String? appName}) async {
    if (_loaded) return;
    try {
      final box = await _openBox(
        appStoragePath: appStoragePath,
        appName: appName,
      );
      _kdfCoins = CustomCoinsFileSource.fromJson(
        _decode(box.get(_kdfCoinsKey)),
      );
      _coinsConfig = CustomCoinsFileSource.fromJson(
        _decode(box.get(_coinsConfigKey)),
      );
      await _parseKdfCoins();
      if (_kdfCoins != null || _coinsConfig != null) {
        _log.info(
          'Loaded custom coins override '
          '(kdfCoins: ${_kdfCoins?.displayLabel ?? 'none'}, '
          'coinsConfig: ${_coinsConfig?.displayLabel ?? 'none'})',
        );
      }
    } catch (e, s) {
      _log.warning('Failed to load custom coins override', e, s);
    } finally {
      _loaded = true;
    }
  }

  /// Persists the provided override(s) and updates the in-memory state.
  ///
  /// Only non-null parameters are changed; pass [CustomCoinsConfig.clear] to
  /// remove an override. The change is persisted immediately but only takes
  /// effect on the next app start.
  Future<void> setOverrides({
    CustomCoinsFileSource? kdfCoins,
    CustomCoinsFileSource? coinsConfig,
    String? appStoragePath,
    String? appName,
  }) async {
    // Validate both files before persisting anything so a malformed file fails
    // fast (and surfaces to the caller) rather than being persisted. This is
    // especially important for the coins config: at startup it is the sole,
    // authoritative source with no fallback, so a malformed persisted file
    // would otherwise break SDK initialization before the UI (and the reset
    // control) is reachable.
    final newKdfCoinsList = kdfCoins != null
        ? await _parseKdfCoinsSource(kdfCoins)
        : _kdfCoinsList;
    if (coinsConfig != null) {
      await _validateCoinsConfigSource(coinsConfig);
    }

    final box = await _openBox(
      appStoragePath: appStoragePath,
      appName: appName,
    );
    if (kdfCoins != null) {
      await box.put(_kdfCoinsKey, jsonEncode(kdfCoins.toJson()));
      _kdfCoins = kdfCoins;
      _kdfCoinsList = newKdfCoinsList;
    }
    if (coinsConfig != null) {
      await box.put(_coinsConfigKey, jsonEncode(coinsConfig.toJson()));
      _coinsConfig = coinsConfig;
    }
    _loaded = true;
  }

  /// Removes all custom overrides, reverting to the bundled configuration.
  ///
  /// Takes effect on the next app start.
  Future<void> clear({String? appStoragePath, String? appName}) async {
    try {
      final box = await _openBox(
        appStoragePath: appStoragePath,
        appName: appName,
      );
      await box.delete(_kdfCoinsKey);
      await box.delete(_coinsConfigKey);
    } catch (e, s) {
      _log.warning('Failed to clear custom coins override', e, s);
    } finally {
      _kdfCoins = null;
      _coinsConfig = null;
      _kdfCoinsList = null;
    }
  }

  /// Validates that [source] is a parseable coins-config file that yields at
  /// least one asset. Throws a [FormatException] otherwise.
  ///
  /// This guards against persisting an override that would brick startup, since
  /// the coins-config override is the sole authoritative source (no fallback).
  Future<void> _validateCoinsConfigSource(CustomCoinsFileSource source) async {
    final assets = await FileCoinConfigProvider(source).getAssets();
    if (assets.isEmpty) {
      throw const FormatException(
        'Custom coins config did not yield any assets. Ensure the file is a '
        'valid coins_config.json mapping coin tickers to their configuration.',
      );
    }
  }

  Future<void> _parseKdfCoins() async {
    final source = _kdfCoins;
    _kdfCoinsList = source == null ? null : await _parseKdfCoinsSource(source);
  }

  /// Reads and parses a KDF coins file into the raw coins list expected by mm2.
  ///
  /// Individual non-object entries are skipped (with a warning) rather than
  /// failing the whole file, mirroring the per-coin tolerance elsewhere in the
  /// loading pipeline. Throws a [FormatException] only when the file is not a
  /// JSON array, or when it contains no usable coin objects at all.
  Future<JsonList> _parseKdfCoinsSource(CustomCoinsFileSource source) async {
    final content = await CustomCoinsFileReader.read(source);
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      throw FormatException(
        'Custom KDF coins file must be a JSON array of coin objects '
        '(got ${decoded.runtimeType}).',
      );
    }

    final coins = <JsonMap>[];
    var skipped = 0;
    for (final dynamic e in decoded) {
      if (e is! Map) {
        skipped++;
        continue;
      }
      coins.add(JsonMap.from(e));
    }
    if (skipped > 0) {
      _log.warning(
        'Skipped $skipped malformed '
        '${skipped == 1 ? 'entry' : 'entries'} in custom KDF coins file.',
      );
    }
    if (coins.isEmpty) {
      throw const FormatException(
        'Custom KDF coins file did not contain any coin objects.',
      );
    }
    return JsonList.of(coins);
  }

  JsonMap? _decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? JsonMap.from(decoded) : null;
    } catch (e, s) {
      _log.warning('Failed to decode persisted custom coins override', e, s);
      return null;
    }
  }

  Future<Box<dynamic>> _openBox({
    String? appStoragePath,
    String? appName,
  }) async {
    final resolvedAppName = appName ?? _defaultAppName;
    final storagePath = await _resolveStoragePath(
      appStoragePath: appStoragePath,
      appName: resolvedAppName,
    );
    await KomodoCoinUpdater.ensureInitialized(storagePath);
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return Hive.openBox<dynamic>(_boxName);
  }

  static Future<String> _resolveStoragePath({
    required String appName,
    String? appStoragePath,
  }) async {
    if (kIsWeb) {
      // Web: appName acts as a logical storage bucket (IndexedDB).
      return appName;
    }
    final basePath =
        appStoragePath ?? (await getApplicationDocumentsDirectory()).path;
    return p.join(basePath, appName);
  }
}
