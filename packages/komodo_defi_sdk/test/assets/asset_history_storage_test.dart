import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _walletHash = '0123456789abcdef0123456789abcdef01234567';

WalletId _wallet({
  String name = 'wallet',
  String? pubkeyHash = _walletHash,
  DerivationMethod derivationMethod = DerivationMethod.hdWallet,
  bool allowWeakPassword = false,
  PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
}) {
  return WalletId(
    name: name,
    pubkeyHash: pubkeyHash,
    authOptions: AuthOptions(
      derivationMethod: derivationMethod,
      allowWeakPassword: allowWeakPassword,
      privKeyPolicy: privKeyPolicy,
    ),
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('isolates history across derivation methods', () async {
    final storage = AssetHistoryStorage();
    final hdWallet = _wallet();
    final iguanaWallet = _wallet(derivationMethod: DerivationMethod.iguana);

    await storage.storeWalletAssets(hdWallet, {'HD-ASSET'});
    await storage.storeWalletAssets(iguanaWallet, {'IGUANA-ASSET'});

    expect(await storage.getWalletAssets(hdWallet), {'HD-ASSET'});
    expect(await storage.getWalletAssets(iguanaWallet), {'IGUANA-ASSET'});
  });

  test('isolates signing policy but shares password-policy changes', () async {
    final storage = AssetHistoryStorage();
    final contextWallet = _wallet();
    final trezorWallet = _wallet(
      privKeyPolicy: const PrivateKeyPolicy.trezor(),
    );
    final weakPasswordWallet = _wallet(allowWeakPassword: true);
    final walletConnectA = _wallet(
      privKeyPolicy: const PrivateKeyPolicy.walletConnect('session-a'),
    );
    final walletConnectB = _wallet(
      privKeyPolicy: const PrivateKeyPolicy.walletConnect('session-b'),
    );

    await storage.storeWalletAssets(contextWallet, {'CONTEXT'});
    await storage.storeWalletAssets(trezorWallet, {'TREZOR'});
    await storage.storeWalletAssets(walletConnectA, {'SESSION-A'});
    await storage.storeWalletAssets(walletConnectB, {'SESSION-B'});

    expect(await storage.getWalletAssets(contextWallet), {'CONTEXT'});
    expect(await storage.getWalletAssets(trezorWallet), {'TREZOR'});
    expect(await storage.getWalletAssets(weakPasswordWallet), {'CONTEXT'});
    expect(await storage.getWalletAssets(walletConnectA), {'SESSION-A'});
    expect(await storage.getWalletAssets(walletConnectB), {'SESSION-B'});
  });

  test('does not import ambiguous legacy history', () async {
    FlutterSecureStorage.setMockInitialValues({
      'wallet_assets_$_walletHash': 'BTC,KMD',
    });
    final storage = AssetHistoryStorage();
    final wallet = _wallet();

    expect(await storage.hasAmbiguousLegacyHistory(wallet), isTrue);
    expect(await storage.getWalletAssets(wallet), isEmpty);

    await storage.storeWalletAssets(wallet, {'TRX'});

    expect(await storage.getWalletAssets(wallet), {'TRX'});
    expect(await storage.hasAmbiguousLegacyHistory(wallet), isTrue);
    expect(
      (await const FlutterSecureStorage()
          .readAll())['wallet_assets_$_walletHash'],
      'BTC,KMD',
    );
  });

  test('reports no ambiguous history for a fresh wallet context', () async {
    expect(
      await AssetHistoryStorage().hasAmbiguousLegacyHistory(_wallet()),
      isFalse,
    );
  });

  test('normalizes public-key hash casing in the namespace', () async {
    final storage = AssetHistoryStorage();
    final uppercaseWallet = _wallet(pubkeyHash: _walletHash.toUpperCase());
    final lowercaseWallet = _wallet();

    await storage.storeWalletAssets(uppercaseWallet, {'TRX'});

    expect(await storage.getWalletAssets(lowercaseWallet), {'TRX'});
  });

  test('retains enriched wallet history across display-name changes', () async {
    final storage = AssetHistoryStorage();
    final originalName = _wallet();
    final renamed = _wallet(name: 'renamed-wallet');

    await storage.storeWalletAssets(originalName, {'TRX'});

    expect(await storage.getWalletAssets(renamed), {'TRX'});
  });

  test('keeps name-only wallet histories separate', () async {
    final storage = AssetHistoryStorage();
    final first = _wallet(name: 'first', pubkeyHash: null);
    final second = _wallet(name: 'second', pubkeyHash: null);

    await storage.storeWalletAssets(first, {'FIRST'});
    await storage.storeWalletAssets(second, {'SECOND'});

    expect(await storage.getWalletAssets(first), {'FIRST'});
    expect(await storage.getWalletAssets(second), {'SECOND'});
  });

  test('clearing one context leaves other contexts untouched', () async {
    final storage = AssetHistoryStorage();
    final hdWallet = _wallet();
    final trezorWallet = _wallet(
      privKeyPolicy: const PrivateKeyPolicy.trezor(),
    );

    await storage.storeWalletAssets(hdWallet, {'HD-ASSET'});
    await storage.storeWalletAssets(trezorWallet, {'TREZOR-ASSET'});
    await storage.clearWalletAssets(hdWallet);

    expect(await storage.getWalletAssets(hdWallet), isEmpty);
    expect(await storage.getWalletAssets(trezorWallet), {'TREZOR-ASSET'});
  });
}
