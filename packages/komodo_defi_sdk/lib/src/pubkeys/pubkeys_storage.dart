import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/pubkeys/hive_pubkeys_adapters.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Storage interface for persisting pubkeys between sessions
abstract class PubkeysStorage {
  /// [everFundedAddresses] flags addresses ever observed holding funds, so
  /// the TRON gasless phantom-address filter can keep used-then-emptied
  /// addresses across restarts.
  Future<void> savePubkeys(
    WalletId walletId,
    String assetTicker,
    AssetPubkeys pubkeys, {
    Set<String> everFundedAddresses,
  });

  /// Returns a map of assetTicker -> stored pubkeys JSON for the wallet
  Future<Map<String, Map<String, dynamic>>> listForWallet(WalletId walletId);
}

class HivePubkeysStorage implements PubkeysStorage {
  // v4 uses new adapter ids and migrates every legacy address conservatively.
  static const _boxName = 'pubkeys_cache_v4';
  Box<HiveAssetPubkeysRecord>? _box;
  bool _migrationComplete = false;

  Future<Box<HiveAssetPubkeysRecord>> _openBox() async {
    registerPubkeysAdapters();
    if (_box != null) return _box!;
    _box = await Hive.openBox<HiveAssetPubkeysRecord>(_boxName);
    if (!_migrationComplete) {
      await _migrateLegacyBoxes(_box!);
      _migrationComplete = true;
    }
    return _box!;
  }

  Future<void> _migrateLegacyBoxes(
    Box<HiveAssetPubkeysRecord> destination,
  ) async {
    const legacyBoxes = <(String, LegacyPubkeysSchema)>[
      ('pubkeys_cache_v1', LegacyPubkeysSchema.v1),
      ('pubkeys_cache_v3', LegacyPubkeysSchema.v3),
    ];
    for (final (boxName, schema) in legacyBoxes) {
      if (!await Hive.boxExists(boxName)) continue;
      setLegacyPubkeysSchema(schema);
      final legacy = await Hive.openBox<LegacyHiveAssetPubkeysRecord>(boxName);
      try {
        for (final key in legacy.keys.whereType<String>()) {
          final oldRecord = legacy.get(key);
          if (oldRecord == null) continue;
          final incoming = HiveAssetPubkeysRecord(
            available: oldRecord.available,
            sync: oldRecord.sync,
            keys: oldRecord.keys.map((item) => item.toCurrent()).toList(),
          );
          final current = destination.get(key);
          await destination.put(
            key,
            current == null ? incoming : _mergeRecords(current, incoming),
          );
        }
      } finally {
        await legacy.close();
      }
    }
  }

  HiveAssetPubkeysRecord _mergeRecords(
    HiveAssetPubkeysRecord current,
    HiveAssetPubkeysRecord incoming,
  ) {
    final byAddress = <String, HiveStoredPubkey>{
      for (final key in current.keys) key.address: key,
    };
    for (final migrated in incoming.keys) {
      final existing = byAddress[migrated.address];
      byAddress[migrated.address] = existing == null
          ? migrated
          : HiveStoredPubkey(
              address: existing.address,
              derivationPath:
                  existing.derivationPath ?? migrated.derivationPath,
              chain: existing.chain ?? migrated.chain,
              spendable: existing.spendable,
              unspendable: existing.unspendable,
              gasfreeAddress:
                  existing.gasfreeAddress ?? migrated.gasfreeAddress,
              everFunded: true,
            );
    }
    return HiveAssetPubkeysRecord(
      available: current.available > incoming.available
          ? current.available
          : incoming.available,
      sync: current.sync,
      keys: byAddress.values.toList(),
    );
  }

  String _keyFor(WalletId walletId, String assetTicker) =>
      '${walletId.compoundId}|$assetTicker';

  @override
  Future<void> savePubkeys(
    WalletId walletId,
    String assetTicker,
    AssetPubkeys pubkeys, {
    Set<String> everFundedAddresses = const {},
  }) async {
    final box = await _openBox();
    final record = HiveAssetPubkeysRecord.fromDomain(
      pubkeys,
      everFundedAddresses: everFundedAddresses,
    );
    await box.put(_keyFor(walletId, assetTicker), record);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> listForWallet(
    WalletId walletId,
  ) async {
    final box = await _openBox();
    final prefix = '${walletId.compoundId}|';
    final result = <String, Map<String, dynamic>>{};
    for (final key in box.keys.whereType<String>()) {
      if (!key.startsWith(prefix)) continue;
      final record = box.get(key);
      if (record == null) continue;
      // Build map structure to mirror the expected hydration format
      // used by PubkeyManager._hydrateFromStorage* for fast hydration
      result[key.substring(prefix.length)] = {
        'available': record.available,
        'sync': record.sync,
        'addresses': record.keys
            .map(
              (k) => {
                'address': k.address,
                'gasfree_address': k.gasfreeAddress,
                'derivation_path': k.derivationPath,
                'chain': k.chain,
                'ever_funded': k.everFunded,
                'balance': {
                  'spendable': k.spendable,
                  'unspendable': k.unspendable,
                },
              },
            )
            .toList(),
      };
    }
    return result;
  }
}
