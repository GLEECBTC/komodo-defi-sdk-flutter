import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/activation_config/hive_activation_config_repository.dart';
import 'package:komodo_defi_sdk/src/pubkeys/hive_pubkeys_adapters.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/hive_transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import '../transaction_history/transaction_fixtures.dart';

/// The wallet-scoped stores must forget a wallet when it is deleted.
///
/// `AuthService.deleteWallet` issues the KDF RPC and clears secure storage and
/// nothing else, so every derived cache used to outlive the wallet it
/// described. These are the per-store purges that
/// `bootstrap`'s wallet-deletion listener drives.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('purge_');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  group('HiveTransactionStorage.purgeWallet', () {
    test('removes only the deleted wallet, and durably', () async {
      final deleted = testWallet(pubkeyHash: 'aaaa');
      final kept = testWallet(pubkeyHash: 'bbbb');
      final asset = testAssetId();

      final storage = HiveTransactionStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'deleted-tx'),
      ], deleted);
      await storage.storeTransactions([
        testTransaction(internalId: 'kept-tx'),
      ], kept);

      await storage.purgeWallet(deleted);
      await storage.close();

      final reopened = HiveTransactionStorage();
      expect((await reopened.getTransactions(asset, deleted)).total, 0);
      expect(
        (await reopened.getTransactions(
          asset,
          kept,
        )).transactions.single.internalId,
        'kept-tx',
      );
    });

    test('purges every asset for the wallet', () async {
      final wallet = testWallet();
      final usdt = testAssetId();
      final kmd = testAssetId(id: 'KMD', subClass: CoinSubClass.smartChain);

      final storage = HiveTransactionStorage();
      await storage.storeTransactions([
        testTransaction(internalId: 'usdt-tx'),
        testTransaction(internalId: 'kmd-tx', assetId: kmd),
      ], wallet);

      await storage.purgeWallet(wallet);

      expect((await storage.getTransactions(usdt, wallet)).total, 0);
      expect((await storage.getTransactions(kmd, wallet)).total, 0);
    });
  });

  group('HivePubkeysStorage.purgeWallet', () {
    AssetPubkeys pubkeysFor(String address) => AssetPubkeys(
      assetId: testAssetId(),
      keys: [
        PubkeyInfo(
          address: address,
          derivationPath: "m/44'/195'/0'/0/0",
          chain: 'external',
          balance: BalanceInfo.zero(),
          coinTicker: 'USDT-TRC20',
        ),
      ],
      availableAddressesCount: 1,
      syncStatus: SyncStatusEnum.success,
    );

    test('removes only the deleted wallet', () async {
      final deleted = testWallet(pubkeyHash: 'aaaa');
      final kept = testWallet(pubkeyHash: 'bbbb');

      final storage = HivePubkeysStorage();
      await storage.savePubkeys(deleted, 'USDT-TRC20', pubkeysFor('deleted-1'));
      await storage.savePubkeys(kept, 'USDT-TRC20', pubkeysFor('kept-1'));

      await storage.purgeWallet(deleted);

      expect(await storage.listForWallet(deleted), isEmpty);
      expect(await storage.listForWallet(kept), isNotEmpty);
    });

    test('removes legacy compound-id records too', () async {
      // The migration retains legacy keys until a fresh KDF response confirms
      // them, so purging only the namespaced keyspace would leave the deleted
      // wallet's addresses behind.
      final wallet = testWallet();
      final box = await Hive.openBox<HiveAssetPubkeysRecord>(
        'pubkeys_cache_v4',
      );
      await box.put(
        '${wallet.compoundId}|USDT-TRC20',
        HiveAssetPubkeysRecord(available: 1, sync: 'success', keys: const []),
      );

      final storage = HivePubkeysStorage();
      await storage.savePubkeys(wallet, 'USDT-TRC20', pubkeysFor('addr-1'));
      await storage.purgeWallet(wallet);

      expect(
        box.keys.where((key) => key.toString().contains('USDT-TRC20')),
        isEmpty,
      );
    });

    test('purging an unknown wallet is a no-op', () async {
      final storage = HivePubkeysStorage();
      await storage.savePubkeys(
        testWallet(),
        'USDT-TRC20',
        pubkeysFor('addr-1'),
      );

      await storage.purgeWallet(testWallet(pubkeyHash: 'never-existed'));

      expect(await storage.listForWallet(testWallet()), isNotEmpty);
    });

    test('a rename does not save a wallet from being purged', () async {
      // walletStorageNamespace keys enriched identities by pubkey hash and
      // ignores the display name, so these are the same wallet. Deleting one
      // must not leave the other's addresses on disk under a stale name.
      final wallet = testWallet(name: 'old name', pubkeyHash: 'abc123');
      final renamed = testWallet(name: 'new name', pubkeyHash: 'abc123');

      final storage = HivePubkeysStorage();
      await storage.savePubkeys(wallet, 'USDT-TRC20', pubkeysFor('addr-1'));

      await storage.purgeWallet(renamed);

      expect(await storage.listForWallet(wallet), isEmpty);
    });
  });

  group('activation config purgeWallet', () {
    final asset = testAssetId();

    test('the Hive repository forgets the deleted wallet', () async {
      final deleted = testWallet(pubkeyHash: 'aaaa');
      final kept = testWallet(pubkeyHash: 'bbbb');
      final repo = HiveActivationConfigRepository();

      await repo.saveConfig(deleted, asset, _config('deleted'));
      await repo.saveConfig(kept, asset, _config('kept'));

      await repo.purgeWallet(deleted);

      expect(await repo.getConfig<ZhtlcUserConfig>(deleted, asset), isNull);
      expect(
        (await repo.getConfig<ZhtlcUserConfig>(kept, asset))?.zcashParamsPath,
        'kept',
      );
    });

    test('the JSON repository forgets every asset for the wallet', () async {
      final deleted = testWallet(pubkeyHash: 'aaaa');
      final kept = testWallet(pubkeyHash: 'bbbb');
      final other = testAssetId(id: 'KMD', subClass: CoinSubClass.smartChain);
      final repo = JsonActivationConfigRepository(InMemoryKeyValueStore());

      await repo.saveConfig(deleted, asset, _config('deleted-usdt'));
      await repo.saveConfig(deleted, other, _config('deleted-kmd'));
      await repo.saveConfig(kept, asset, _config('kept'));

      await repo.purgeWallet(deleted);

      expect(await repo.getConfig<ZhtlcUserConfig>(deleted, asset), isNull);
      expect(await repo.getConfig<ZhtlcUserConfig>(deleted, other), isNull);
      expect(
        (await repo.getConfig<ZhtlcUserConfig>(kept, asset))?.zcashParamsPath,
        'kept',
      );
    });
  });
}

ZhtlcUserConfig _config(String marker) =>
    ZhtlcUserConfig(zcashParamsPath: marker);
