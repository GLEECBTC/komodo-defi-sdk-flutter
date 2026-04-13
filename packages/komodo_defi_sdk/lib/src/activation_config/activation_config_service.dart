import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

typedef JsonMap = Map<String, dynamic>;

enum ZhtlcRecurringSyncMode {
  recentTransactions,
  earliest,
  height,
  date;

  static ZhtlcRecurringSyncMode? tryParse(String? value) {
    switch (value) {
      case 'recent_transactions':
        return ZhtlcRecurringSyncMode.recentTransactions;
      case 'earliest':
        return ZhtlcRecurringSyncMode.earliest;
      case 'height':
        return ZhtlcRecurringSyncMode.height;
      case 'date':
        return ZhtlcRecurringSyncMode.date;
      default:
        return null;
    }
  }

  String get jsonValue => switch (this) {
    ZhtlcRecurringSyncMode.recentTransactions => 'recent_transactions',
    ZhtlcRecurringSyncMode.earliest => 'earliest',
    ZhtlcRecurringSyncMode.height => 'height',
    ZhtlcRecurringSyncMode.date => 'date',
  };
}

/// Persisted recurring sync policy for ZHTLC wallet activations.
class ZhtlcRecurringSyncPolicy {
  ZhtlcRecurringSyncPolicy._({
    required this.mode,
    this.height,
    this.unixTimestamp,
  }) : assert(switch (mode) {
         ZhtlcRecurringSyncMode.recentTransactions ||
         ZhtlcRecurringSyncMode.earliest =>
           height == null && unixTimestamp == null,
         ZhtlcRecurringSyncMode.height => height != null,
         ZhtlcRecurringSyncMode.date => unixTimestamp != null,
       }, 'Recurring sync policy data does not match its mode.');

  factory ZhtlcRecurringSyncPolicy.recentTransactions() =>
      ZhtlcRecurringSyncPolicy._(
        mode: ZhtlcRecurringSyncMode.recentTransactions,
      );

  factory ZhtlcRecurringSyncPolicy.earliest() =>
      ZhtlcRecurringSyncPolicy._(mode: ZhtlcRecurringSyncMode.earliest);

  factory ZhtlcRecurringSyncPolicy.height(int height) =>
      ZhtlcRecurringSyncPolicy._(
        mode: ZhtlcRecurringSyncMode.height,
        height: height,
      );

  factory ZhtlcRecurringSyncPolicy.date(int unixTimestamp) =>
      ZhtlcRecurringSyncPolicy._(
        mode: ZhtlcRecurringSyncMode.date,
        unixTimestamp: unixTimestamp,
      );

  factory ZhtlcRecurringSyncPolicy.fromJson(JsonMap json) {
    final mode = ZhtlcRecurringSyncMode.tryParse(
      json.valueOrNull<String>('mode'),
    );
    if (mode == null) {
      throw ArgumentError.value(
        json['mode'],
        'json.mode',
        'Unsupported recurring ZHTLC sync policy mode',
      );
    }

    return switch (mode) {
      ZhtlcRecurringSyncMode.recentTransactions =>
        ZhtlcRecurringSyncPolicy.recentTransactions(),
      ZhtlcRecurringSyncMode.earliest => ZhtlcRecurringSyncPolicy.earliest(),
      ZhtlcRecurringSyncMode.height => ZhtlcRecurringSyncPolicy.height(
        json.value<int>('height'),
      ),
      ZhtlcRecurringSyncMode.date => ZhtlcRecurringSyncPolicy.date(
        json.value<int>('unixTimestamp'),
      ),
    };
  }

  factory ZhtlcRecurringSyncPolicy.fromSyncParams(ZhtlcSyncParams syncParams) {
    if (syncParams.isEarliest) {
      return ZhtlcRecurringSyncPolicy.earliest();
    }
    if (syncParams.height != null) {
      return ZhtlcRecurringSyncPolicy.height(syncParams.height!);
    }
    if (syncParams.date != null) {
      return ZhtlcRecurringSyncPolicy.date(syncParams.date!);
    }
    throw ArgumentError.value(
      syncParams,
      'syncParams',
      'Unsupported ZHTLC sync params payload',
    );
  }

  final ZhtlcRecurringSyncMode mode;
  final int? height;
  final int? unixTimestamp;

  JsonMap toJson() => <String, dynamic>{
    'mode': mode.jsonValue,
    if (height != null) 'height': height,
    if (unixTimestamp != null) 'unixTimestamp': unixTimestamp,
  };

  ZhtlcSyncParams toSyncParams({DateTime? now}) {
    return switch (mode) {
      ZhtlcRecurringSyncMode.recentTransactions => ZhtlcSyncParams.date(
        (now ?? DateTime.now())
                .toUtc()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch ~/
            1000,
      ),
      ZhtlcRecurringSyncMode.earliest => ZhtlcSyncParams.earliest(),
      ZhtlcRecurringSyncMode.height => ZhtlcSyncParams.height(height!),
      ZhtlcRecurringSyncMode.date => ZhtlcSyncParams.date(unixTimestamp!),
    };
  }
}

/// Simple key-value store abstraction for persisting activation configs.
abstract class KeyValueStore {
  Future<JsonMap?> get(String key);
  Future<void> set(String key, JsonMap value);
}

/// In-memory key-value store default implementation.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, JsonMap> _store = {};

  @override
  Future<JsonMap?> get(String key) async => _store[key];

  @override
  Future<void> set(String key, JsonMap value) async {
    _store[key] = value;
  }
}

/// Repository abstraction for typed activation configs.
abstract class ActivationConfigRepository {
  Future<TConfig?> getConfig<TConfig>(WalletId walletId, AssetId id);
  Future<void> saveConfig<TConfig>(
    WalletId walletId,
    AssetId id,
    TConfig config,
  );
}

/// Minimal ZHTLC user configuration.
class ZhtlcUserConfig {
  ZhtlcUserConfig({
    required this.zcashParamsPath,
    this.scanBlocksPerIteration = 1000,
    this.scanIntervalMs = 0,
    this.taskStatusPollingIntervalMs,
    this.recurringSyncPolicy,
    this.syncParams,
  });

  final String zcashParamsPath;
  final int scanBlocksPerIteration;
  final int scanIntervalMs;
  final int? taskStatusPollingIntervalMs;
  final ZhtlcRecurringSyncPolicy? recurringSyncPolicy;

  /// Optional, accepted for backward compatibility. Not persisted.
  /// If provided to saveZhtlcConfig, it will be applied as a one-shot
  /// sync override for the next activation and then discarded.
  final ZhtlcSyncParams? syncParams;
  // Sync params are supplied one-shot via ActivationConfigService when the
  // user requests an immediate resync. Recurring sync behavior is persisted
  // separately via [recurringSyncPolicy].

  ZhtlcUserConfig copyWith({
    String? zcashParamsPath,
    int? scanBlocksPerIteration,
    int? scanIntervalMs,
    int? taskStatusPollingIntervalMs,
    ZhtlcRecurringSyncPolicy? recurringSyncPolicy,
    bool clearRecurringSyncPolicy = false,
    ZhtlcSyncParams? syncParams,
    bool clearSyncParams = false,
  }) {
    return ZhtlcUserConfig(
      zcashParamsPath: zcashParamsPath ?? this.zcashParamsPath,
      scanBlocksPerIteration:
          scanBlocksPerIteration ?? this.scanBlocksPerIteration,
      scanIntervalMs: scanIntervalMs ?? this.scanIntervalMs,
      taskStatusPollingIntervalMs:
          taskStatusPollingIntervalMs ?? this.taskStatusPollingIntervalMs,
      recurringSyncPolicy: clearRecurringSyncPolicy
          ? null
          : recurringSyncPolicy ?? this.recurringSyncPolicy,
      syncParams: clearSyncParams ? null : syncParams ?? this.syncParams,
    );
  }

  JsonMap toJson() => {
    'zcashParamsPath': zcashParamsPath,
    'scanBlocksPerIteration': scanBlocksPerIteration,
    'scanIntervalMs': scanIntervalMs,
    if (taskStatusPollingIntervalMs != null)
      'taskStatusPollingIntervalMs': taskStatusPollingIntervalMs,
    if (recurringSyncPolicy != null)
      'recurringSyncPolicy': recurringSyncPolicy!.toJson(),
  };

  static ZhtlcUserConfig fromJson(JsonMap json) => ZhtlcUserConfig(
    zcashParamsPath: json.value<String>('zcashParamsPath'),
    scanBlocksPerIteration:
        json.valueOrNull<int>('scanBlocksPerIteration') ?? 1000,
    scanIntervalMs: json.valueOrNull<int>('scanIntervalMs') ?? 0,
    taskStatusPollingIntervalMs: json.valueOrNull<int>(
      'taskStatusPollingIntervalMs',
    ),
    recurringSyncPolicy:
        json.valueOrNull<JsonMap>('recurringSyncPolicy') == null
        ? null
        : ZhtlcRecurringSyncPolicy.fromJson(
            json.value<JsonMap>('recurringSyncPolicy'),
          ),
  );
}

/// Simple mapper for typed configs. Extend when adding more protocols.
abstract class ActivationConfigMapper {
  static JsonMap encode(Object config) {
    if (config is ZhtlcUserConfig) return config.toJson();
    throw UnsupportedError('Unsupported config type: ${config.runtimeType}');
  }

  static T decode<T>(JsonMap json) {
    if (T == ZhtlcUserConfig) return ZhtlcUserConfig.fromJson(json) as T;
    throw UnsupportedError('Unsupported type for decode: $T');
  }
}

/// Wrapper class for storing activation configs in Hive.
/// This replaces the problematic Map<String, String> storage approach
/// and provides type safety while using the encode/decode functions.
class HiveActivationConfigWrapper extends HiveObject {
  /// Creates a wrapper from a wallet ID and a map of asset IDs to configurations
  /// [walletId] The wallet ID this configuration belongs to
  /// [configs] The map of asset IDs to configurations
  HiveActivationConfigWrapper({required this.walletId, required this.configs});

  /// Creates a wrapper from individual config components
  /// [walletId] The wallet ID this configuration belongs to
  /// [configs] The map of asset IDs to configurations
  factory HiveActivationConfigWrapper.fromComponents({
    required WalletId walletId,
    required Map<String, Object> configs,
  }) {
    final encodedConfigs = <String, String>{};
    configs.forEach((assetId, config) {
      final json = ActivationConfigMapper.encode(config);
      encodedConfigs[assetId] = jsonEncode(json);
    });
    return HiveActivationConfigWrapper(
      walletId: walletId,
      configs: encodedConfigs,
    );
  }

  /// The wallet ID this configuration belongs to
  @HiveField(0)
  final WalletId walletId;

  /// Map of asset ID to JSON-encoded configuration strings
  @HiveField(1)
  final Map<String, String> configs;

  /// Gets a decoded configuration by asset ID and type
  TConfig? getConfig<TConfig>(String assetId) {
    final encodedConfig = configs[assetId];
    if (encodedConfig == null) return null;

    final json = jsonDecode(encodedConfig) as JsonMap;
    return ActivationConfigMapper.decode<TConfig>(json);
  }

  /// Sets a configuration by asset ID
  HiveActivationConfigWrapper setConfig(String assetId, Object config) {
    final json = ActivationConfigMapper.encode(config);
    final newConfigs = Map<String, String>.from(configs);
    newConfigs[assetId] = jsonEncode(json);

    return HiveActivationConfigWrapper(walletId: walletId, configs: newConfigs);
  }

  /// Removes a configuration by asset ID
  HiveActivationConfigWrapper removeConfig(String assetId) {
    final newConfigs = Map<String, String>.from(configs);
    newConfigs.remove(assetId);

    return HiveActivationConfigWrapper(walletId: walletId, configs: newConfigs);
  }

  /// Checks if a configuration exists for the given asset ID
  bool hasConfig(String assetId) => configs.containsKey(assetId);

  /// Gets all asset IDs that have configurations
  List<String> getAssetIds() => configs.keys.toList();
}

class JsonActivationConfigRepository implements ActivationConfigRepository {
  JsonActivationConfigRepository(this.store);
  final KeyValueStore store;

  String _key(WalletId walletId, AssetId id) =>
      'activation_config:${walletId.compoundId}:${id.id}';

  @override
  Future<TConfig?> getConfig<TConfig>(WalletId walletId, AssetId id) async {
    final data = await store.get(_key(walletId, id));
    if (data == null) return null;
    return ActivationConfigMapper.decode<TConfig>(data);
  }

  @override
  Future<void> saveConfig<TConfig>(
    WalletId walletId,
    AssetId id,
    TConfig config,
  ) async {
    final json = ActivationConfigMapper.encode(config as Object);
    await store.set(_key(walletId, id), json);
  }
}

typedef WalletIdResolver = Future<WalletId?> Function();

/// Service orchestrating retrieval/request of activation configs.
class ActivationConfigService {
  ActivationConfigService(
    this.repo, {
    required WalletIdResolver walletIdResolver,
    Stream<KdfUser?>? authStateChanges,
  }) : _walletIdResolver = walletIdResolver {
    // Listen to auth state changes to clear one-shot params on sign-out
    _authStateSubscription = authStateChanges?.listen((user) {
      if (user == null) {
        // User signed out, clear all one-shot params
        _oneShotSyncParams.clear();
      } else {
        // User signed in or changed, clear one-shot params for previous wallet
        // if it was different from the current one
        if (_lastWalletId != null && _lastWalletId != user.walletId) {
          clearOneShotSyncParamsForWallet(_lastWalletId!);
        }
        _lastWalletId = user.walletId;
      }
    });
  }

  final ActivationConfigRepository repo;
  final WalletIdResolver _walletIdResolver;
  StreamSubscription<KdfUser?>? _authStateSubscription;
  WalletId? _lastWalletId;

  // One-shot sync params coordinator. Not persisted; cleared after use.
  final Map<_WalletAssetKey, ZhtlcSyncParams?> _oneShotSyncParams = {};

  Future<WalletId> _requireActiveWallet() async {
    final walletId = await _walletIdResolver();
    if (walletId == null) {
      throw StateError('Attempted to access activation config with no wallet');
    }
    return walletId;
  }

  Future<ZhtlcUserConfig?> getSavedZhtlc(AssetId id) async {
    final walletId = await _requireActiveWallet();
    return repo.getConfig<ZhtlcUserConfig>(walletId, id);
  }

  Future<ZhtlcUserConfig?> getZhtlcOrRequest(
    AssetId id, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final walletId = await _requireActiveWallet();
    final key = _WalletAssetKey(walletId, id);

    final existing = await repo.getConfig<ZhtlcUserConfig>(walletId, id);
    if (existing != null) return existing;

    final completer = Completer<ZhtlcUserConfig?>();
    _awaitingControllers[key] = completer;
    try {
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      if (result == null) return null;
      if (result.syncParams != null) {
        _oneShotSyncParams[key] = result.syncParams;
      }
      final normalizedConfig = _normalizeConfigForPersistence(result);
      await repo.saveConfig(walletId, id, normalizedConfig);
      return normalizedConfig;
    } finally {
      _awaitingControllers.remove(key);
    }
  }

  Future<void> saveZhtlcConfig(AssetId id, ZhtlcUserConfig config) async {
    final walletId = await _requireActiveWallet();
    final oneShotSyncParams = config.syncParams;
    final normalizedConfig = _normalizeConfigForPersistence(config);
    if (oneShotSyncParams != null) {
      _oneShotSyncParams[_WalletAssetKey(walletId, id)] = oneShotSyncParams;
    }
    await repo.saveConfig(walletId, id, normalizedConfig);
  }

  Future<void> submitZhtlc(AssetId id, ZhtlcUserConfig config) async {
    final walletId = await _walletIdResolver();
    if (walletId == null) return;
    _awaitingControllers[_WalletAssetKey(walletId, id)]?.complete(config);
  }

  /// Sets a one-shot sync params value for the next activation of [id].
  /// This is not persisted and will be consumed and cleared on activation.
  Future<void> setOneShotSyncParams(
    AssetId id,
    ZhtlcSyncParams? syncParams,
  ) async {
    final walletId = await _requireActiveWallet();
    _oneShotSyncParams[_WalletAssetKey(walletId, id)] = syncParams;
  }

  /// Returns and clears any pending one-shot sync params for [id].
  Future<ZhtlcSyncParams?> takeOneShotSyncParams(AssetId id) async {
    final walletId = await _requireActiveWallet();
    final key = _WalletAssetKey(walletId, id);
    final value = _oneShotSyncParams.remove(key);
    return value;
  }

  ZhtlcUserConfig _normalizeConfigForPersistence(ZhtlcUserConfig config) {
    final recurringSyncPolicy =
        config.recurringSyncPolicy ??
        (config.syncParams == null
            ? null
            : ZhtlcRecurringSyncPolicy.fromSyncParams(config.syncParams!));

    return config.copyWith(
      recurringSyncPolicy: recurringSyncPolicy,
      clearSyncParams: true,
    );
  }

  /// Clears all one-shot sync params for the specified wallet.
  /// This should be called when a user signs out to prevent stale one-shot
  /// params from being applied on the next activation after re-login.
  void clearOneShotSyncParamsForWallet(WalletId walletId) {
    _oneShotSyncParams.removeWhere((key, _) => key.walletId == walletId);
  }

  /// Disposes of the service and cleans up resources.
  void dispose() {
    _authStateSubscription?.cancel();
    _authStateSubscription = null;
  }

  final Map<_WalletAssetKey, Completer<ZhtlcUserConfig?>> _awaitingControllers =
      {};
}

@immutable
class _WalletAssetKey {
  const _WalletAssetKey(this.walletId, this.assetId);

  final WalletId walletId;
  final AssetId assetId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _WalletAssetKey &&
        other.walletId == walletId &&
        other.assetId == assetId;
  }

  @override
  int get hashCode => Object.hash(walletId, assetId);
}

/// UI helper for building configuration forms.
class ActivationSettingDescriptor {
  ActivationSettingDescriptor({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.defaultValue,
    this.helpText,
  });

  final String key;
  final String label;
  final String type; // 'path' | 'number' | 'string' | 'boolean' | 'select'
  final bool required;
  final Object? defaultValue;
  final String? helpText;
}

extension AssetIdActivationSettings on AssetId {
  List<ActivationSettingDescriptor> activationSettings() {
    switch (subClass) {
      case CoinSubClass.zhtlc:
        return [
          ActivationSettingDescriptor(
            key: 'zcashParamsPath',
            label: 'Zcash parameters path',
            type: 'path',
            required: true,
            helpText: 'Folder containing Zcash parameters',
          ),
          ActivationSettingDescriptor(
            key: 'scanBlocksPerIteration',
            label: 'Blocks per scan iteration',
            type: 'number',
            defaultValue: 1000,
          ),
          ActivationSettingDescriptor(
            key: 'scanIntervalMs',
            label: 'Scan interval (ms)',
            type: 'number',
            defaultValue: 0,
          ),
          ActivationSettingDescriptor(
            key: 'taskStatusPollingIntervalMs',
            label: 'Task status polling interval (ms)',
            type: 'number',
            defaultValue: 500,
            helpText: 'Delay between status polls while monitoring activation',
          ),
        ];
      default:
        return const [];
    }
  }
}
