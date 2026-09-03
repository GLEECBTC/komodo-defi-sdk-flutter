import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/pubkeys/hive_pubkeys_adapters.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _walletHash = '0123456789abcdef0123456789abcdef01234567';
const _assetTicker = 'USDT-TRC20';

WalletId _wallet({
  String name = 'wallet',
  DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  bool allowWeakPassword = false,
  PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
}) {
  return WalletId(
    name: name,
    pubkeyHash: _walletHash,
    authOptions: AuthOptions(
      derivationMethod: derivationMethod,
      allowWeakPassword: allowWeakPassword,
      privKeyPolicy: privKeyPolicy,
    ),
  );
}

AssetPubkeys _pubkeys(
  String address, {
  String? derivationPath = "m/44'/195'/0'/0/0",
}) {
  final assetId = AssetId(
    id: _assetTicker,
    name: 'Tether',
    symbol: AssetSymbol(assetConfigId: _assetTicker),
    chainId: AssetChainId(chainId: 0, decimalsValue: 6),
    derivationPath: "m/44'/195'",
    subClass: CoinSubClass.trc20,
  );
  return AssetPubkeys(
    assetId: assetId,
    keys: [
      PubkeyInfo(
        address: address,
        derivationPath: derivationPath,
        chain: 'external',
        balance: BalanceInfo(
          total: null,
          spendable: Decimal.zero,
          unspendable: Decimal.zero,
        ),
        coinTicker: _assetTicker,
      ),
    ],
    availableAddressesCount: 1,
    syncStatus: SyncStatusEnum.success,
  );
}

List<dynamic> _addresses(Map<String, Map<String, dynamic>> stored) =>
    stored[_assetTicker]!['addresses'] as List<dynamic>;

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

  test(
    'legacy records require fresh address confirmation before migration',
    () async {
      final wallet = _wallet();
      final otherContext = _wallet(derivationMethod: DerivationMethod.iguana);
      setLegacyPubkeysSchema(LegacyPubkeysSchema.v1);
      final legacy = await Hive.openBox<LegacyHiveAssetPubkeysRecord>(
        'pubkeys_cache_v1',
      );
      await legacy.put(
        '${wallet.compoundId}|$_assetTicker',
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

      final storage = HivePubkeysStorage();

      expect(await storage.listForWallet(wallet), isEmpty);
      expect(await storage.listForWallet(otherContext), isEmpty);

      await storage.savePubkeys(wallet, _assetTicker, _pubkeys('TPrimary'));

      final addresses = _addresses(await storage.listForWallet(wallet));
      expect(addresses, hasLength(1));
      expect((addresses.single as Map)['address'], 'TPrimary');
      expect((addresses.single as Map)['ever_funded'], isTrue);
      expect(
        addresses.map((item) => (item as Map)['address']),
        isNot(contains('TPreviouslyUsedButEmpty')),
      );
    },
  );

  test('isolates the same wallet identity across derivation methods', () async {
    final storage = HivePubkeysStorage();
    final hdWallet = _wallet();
    final iguanaWallet = _wallet(derivationMethod: DerivationMethod.iguana);

    await storage.savePubkeys(hdWallet, _assetTicker, _pubkeys('THdAddress'));
    await storage.savePubkeys(
      iguanaWallet,
      _assetTicker,
      _pubkeys('TIguanaAddress', derivationPath: null),
    );

    expect(
      (_addresses(await storage.listForWallet(hdWallet)).single
          as Map)['address'],
      'THdAddress',
    );
    expect(
      (_addresses(await storage.listForWallet(iguanaWallet)).single
          as Map)['address'],
      'TIguanaAddress',
    );
  });

  test('isolates signing policy but shares password-policy changes', () async {
    final storage = HivePubkeysStorage();
    final contextWallet = _wallet();
    final trezorWallet = _wallet(
      privKeyPolicy: const PrivateKeyPolicy.trezor(),
    );
    final weakPasswordWallet = _wallet(allowWeakPassword: true);

    await storage.savePubkeys(
      contextWallet,
      _assetTicker,
      _pubkeys('TContextAddress'),
    );
    await storage.savePubkeys(
      trezorWallet,
      _assetTicker,
      _pubkeys('TTrezorAddress'),
    );

    expect(
      (_addresses(await storage.listForWallet(contextWallet)).single
          as Map)['address'],
      'TContextAddress',
    );
    expect(
      (_addresses(await storage.listForWallet(trezorWallet)).single
          as Map)['address'],
      'TTrezorAddress',
    );
    expect(
      (_addresses(await storage.listForWallet(weakPasswordWallet)).single
          as Map)['address'],
      'TContextAddress',
    );
  });

  test(
    'retains an enriched wallet cache across display-name changes',
    () async {
      final storage = HivePubkeysStorage();
      final originalName = _wallet();
      final renamed = _wallet(name: 'renamed-wallet');

      await storage.savePubkeys(
        originalName,
        _assetTicker,
        _pubkeys('TRenamedWalletAddress'),
      );

      expect(
        (_addresses(await storage.listForWallet(renamed)).single
            as Map)['address'],
        'TRenamedWalletAddress',
      );
    },
  );
}
