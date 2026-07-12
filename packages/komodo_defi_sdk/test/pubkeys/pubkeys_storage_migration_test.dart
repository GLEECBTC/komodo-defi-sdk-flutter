import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/pubkeys/hive_pubkeys_adapters.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pubkeys_migration_');
    Hive.init(directory.path);
    registerPubkeysAdapters();
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('v1 migration conservatively retains every legacy address', () async {
    const wallet = WalletId(
      name: 'wallet',
      pubkeyHash: 'hash',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    );
    setLegacyPubkeysSchema(LegacyPubkeysSchema.v1);
    final legacy = await Hive.openBox<LegacyHiveAssetPubkeysRecord>(
      'pubkeys_cache_v1',
    );
    await legacy.put(
      '${wallet.compoundId}|USDT-TRC20',
      LegacyHiveAssetPubkeysRecord(
        available: 2,
        sync: SyncStatusEnum.success.toString(),
        keys: [
          LegacyHiveStoredPubkey(
            address: 'TPrimary',
            derivationPath: "m/44'/195'/0'/0/0",
            chain: 'external',
            spendable: '0',
            unspendable: '0',
          ),
          LegacyHiveStoredPubkey(
            address: 'TPreviouslyUsedButEmpty',
            derivationPath: "m/44'/195'/0'/0/1",
            chain: 'external',
            spendable: '0',
            unspendable: '0',
          ),
        ],
      ),
    );
    await legacy.close();

    final stored = await HivePubkeysStorage().listForWallet(wallet);
    final addresses = stored['USDT-TRC20']!['addresses'] as List<dynamic>;

    expect(addresses, hasLength(2));
    expect(
      addresses.map((item) => (item as Map)['address']),
      containsAll(['TPrimary', 'TPreviouslyUsedButEmpty']),
    );
    expect(
      addresses.every((item) => (item as Map)['ever_funded'] == true),
      isTrue,
    );
  });
}
