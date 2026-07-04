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
  // v3: HiveStoredPubkey gained a trailing `everFunded` field; the prior box
  // is orphaned rather than migrated (established pattern for this cache).
  static const _boxName = 'pubkeys_cache_v3';
  Box<HiveAssetPubkeysRecord>? _box;
  Future<Box<HiveAssetPubkeysRecord>> _openBox() async {
    registerPubkeysAdapters();
    if (_box != null) return _box!;
    _box = await Hive.openBox<HiveAssetPubkeysRecord>(_boxName);
    return _box!;
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
