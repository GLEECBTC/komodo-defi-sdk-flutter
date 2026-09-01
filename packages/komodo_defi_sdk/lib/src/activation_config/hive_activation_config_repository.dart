import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/activation_config/hive_adapters.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

const _walletIdAdapterTypeId = 220;

/// Type adapter for persisting [WalletId] keys inside Hive boxes.
class WalletIdAdapter extends TypeAdapter<WalletId> {
  @override
  int get typeId => _walletIdAdapterTypeId;

  @override
  WalletId read(BinaryReader reader) {
    final json = jsonDecode(reader.readString()) as Map<String, dynamic>;
    return WalletId.fromJson(json);
  }

  @override
  void write(BinaryWriter writer, WalletId obj) {
    writer.writeString(jsonEncode(obj.toJson()));
  }
}

/// Hive-backed activation configuration repository using wrapper class.
/// This replaces the problematic Map&lt;String, String&gt; storage approach
/// and provides type safety while using the encode/decode functions.
class HiveActivationConfigRepository implements ActivationConfigRepository {
  /// Creates a new [HiveActivationConfigRepository].
  /// [hive] is the Hive instance to use.
  /// [boxName] is the name of the Hive box to use.
  HiveActivationConfigRepository({
    HiveInterface? hive,
    String boxName = 'activation_configs',
  }) : _hive = hive ?? Hive,
       _boxName = boxName;

  final HiveInterface _hive;
  final String _boxName;
  Box<HiveActivationConfigWrapper>? _box;
  Future<Box<HiveActivationConfigWrapper>>? _boxOpening;

  Future<Box<HiveActivationConfigWrapper>> _openBox() {
    if (_box != null) return Future.value(_box!);
    if (_boxOpening != null) return _boxOpening!;
    _boxOpening = () async {
      // Register adapters
      if (!_hive.isAdapterRegistered(_walletIdAdapterTypeId)) {
        _hive.registerAdapter(WalletIdAdapter());
      }
      registerActivationConfigAdapters();

      final box = await _hive.openBox<HiveActivationConfigWrapper>(_boxName);
      _box = box;
      return box;
    }();
    return _boxOpening!;
  }

  @override
  Future<TConfig?> getConfig<TConfig>(WalletId walletId, AssetId id) async {
    final box = await _openBox();
    final wrapper = box.get(walletId.compoundId);
    if (wrapper == null) return null;
    return wrapper.getConfig<TConfig>(id.id);
  }

  @override
  Future<void> saveConfig<TConfig>(
    WalletId walletId,
    AssetId id,
    TConfig config,
  ) async {
    final box = await _openBox();
    final existing = box.get(walletId.compoundId);

    final updatedWrapper =
        (existing ??
                HiveActivationConfigWrapper(walletId: walletId, configs: {}))
            .setConfig(id.id, config as Object);

    await box.put(walletId.compoundId, updatedWrapper);
  }

  @override
  Future<void> purgeWallet(WalletId walletId) async {
    final box = await _openBox();
    await box.delete(walletId.compoundId);
  }
}
