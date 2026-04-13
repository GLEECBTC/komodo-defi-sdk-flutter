import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('ZhtlcRecurringSyncPolicy', () {
    test('recentTransactions resolves to a runtime date sync param', () {
      final policy = ZhtlcRecurringSyncPolicy.recentTransactions();
      final now = DateTime.utc(2026, 4, 10, 12);
      final syncParams = policy.toSyncParams(now: now);

      expect(syncParams.isEarliest, isFalse);
      expect(syncParams.height, isNull);
      expect(
        syncParams.date,
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('serializes and deserializes date policies', () {
      final policy = ZhtlcRecurringSyncPolicy.date(1775659200);

      final decoded = ZhtlcRecurringSyncPolicy.fromJson(policy.toJson());

      expect(decoded.mode, ZhtlcRecurringSyncMode.date);
      expect(decoded.unixTimestamp, 1775659200);
    });
  });

  group('ActivationConfigService', () {
    test('saveZhtlcConfig persists recurring policy and stores one-shot '
        'sync params', () async {
      final walletId = WalletId.fromName(
        'Test Wallet',
        const AuthOptions(derivationMethod: DerivationMethod.iguana),
      );
      final assetId = AssetId(
        id: 'ARRR',
        name: 'Pirate Chain',
        symbol: AssetSymbol(assetConfigId: 'ARRR'),
        chainId: AssetChainId(chainId: 777, decimalsValue: 8),
        derivationPath: null,
        subClass: CoinSubClass.zhtlc,
      );
      final service = ActivationConfigService(
        JsonActivationConfigRepository(InMemoryKeyValueStore()),
        walletIdResolver: () async => walletId,
      );

      await service.saveZhtlcConfig(
        assetId,
        ZhtlcUserConfig(
          zcashParamsPath: '/zcash-params',
          syncParams: ZhtlcSyncParams.height(123456),
        ),
      );

      final savedConfig = await service.getSavedZhtlc(assetId);
      final oneShotSync = await service.takeOneShotSyncParams(assetId);
      final consumedSync = await service.takeOneShotSyncParams(assetId);

      expect(savedConfig, isNotNull);
      expect(savedConfig?.syncParams, isNull);
      expect(savedConfig?.zcashParamsPath, '/zcash-params');
      expect(
        savedConfig?.recurringSyncPolicy?.mode,
        ZhtlcRecurringSyncMode.height,
      );
      expect(savedConfig?.recurringSyncPolicy?.height, 123456);
      expect(oneShotSync?.height, 123456);
      expect(consumedSync, isNull);
    });
  });
}
