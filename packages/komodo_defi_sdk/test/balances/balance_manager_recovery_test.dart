import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _InMemoryAssetHistoryStorage extends AssetHistoryStorage {
  final Map<String, Set<String>> _walletAssets = {};

  String _key(WalletId walletId) => walletId.pubkeyHash ?? walletId.name;

  @override
  Future<void> storeWalletAssets(
    WalletId walletId,
    Set<String> assetIds,
  ) async {
    _walletAssets[_key(walletId)] = Set<String>.from(assetIds);
  }

  @override
  Future<void> addAssetToWallet(WalletId walletId, String assetId) async {
    final current = await getWalletAssets(walletId);
    current.add(assetId);
    await storeWalletAssets(walletId, current);
  }

  @override
  Future<Set<String>> getWalletAssets(WalletId walletId) async {
    return Set<String>.from(_walletAssets[_key(walletId)] ?? <String>{});
  }

  @override
  Future<void> clearWalletAssets(WalletId walletId) async {
    _walletAssets.remove(_key(walletId));
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      Asset(
        id: AssetId(
          id: 'FALLBACK',
          name: 'Fallback',
          symbol: AssetSymbol(assetConfigId: 'FALLBACK'),
          chainId: AssetChainId(chainId: 1, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        ),
        protocol: TendermintProtocol.fromJson({
          'type': 'Tendermint',
          'rpc_urls': [
            {'url': 'http://localhost:26657'},
          ],
        }),
        isWalletOnly: false,
        signMessagePrefix: null,
      ),
    );
  });

  group('BalanceManager activation miss recovery', () {
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockPubkeyManager pubkeyManager;
    late _MockAssetLookup assetLookup;
    late _MockEventStreamingManager eventStreamingManager;
    late StreamController<KdfUser?> authChanges;
    late BalanceManager manager;
    late AssetId assetId;
    late Asset asset;
    late WalletId walletId;
    late int activationAttempts;

    setUp(() {
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      pubkeyManager = _MockPubkeyManager();
      assetLookup = _MockAssetLookup();
      eventStreamingManager = _MockEventStreamingManager();
      authChanges = StreamController<KdfUser?>.broadcast();

      walletId = const WalletId(
        name: 'recovery-wallet',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
      );

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer(
        (_) async => KdfUser(walletId: walletId, isBip39Seed: false),
      );

      assetId = AssetId(
        id: 'ATOM',
        name: 'Cosmos',
        symbol: AssetSymbol(assetConfigId: 'ATOM'),
        chainId: AssetChainId(chainId: 118, decimalsValue: 6),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      );
      asset = Asset(
        id: assetId,
        protocol: TendermintProtocol.fromJson({
          'type': 'Tendermint',
          'rpc_urls': [
            {'url': 'http://localhost:26657'},
          ],
        }),
        isWalletOnly: false,
        signMessagePrefix: null,
      );

      when(() => assetLookup.fromId(assetId)).thenReturn(asset);
      when(
        () => eventStreamingManager.subscribeToBalance(coin: assetId.id),
      ).thenThrow(StateError('streaming should not be used in this test'));

      when(
        () => pubkeyManager.watchPubkeys(asset),
      ).thenAnswer((_) => const Stream<AssetPubkeys>.empty());
      when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: assetId,
          keys: [
            PubkeyInfo(
              address: 'TTtRecoverExample',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo(
                total: Decimal.fromInt(5),
                spendable: Decimal.fromInt(5),
                unspendable: Decimal.zero,
              ),
              coinTicker: assetId.id,
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      activationAttempts = 0;
      when(
        () => activation.isAssetActive(assetId),
      ).thenAnswer((_) async => false);
      when(() => activation.activateAsset(any())).thenAnswer((_) async {
        activationAttempts += 1;
        if (activationAttempts == 1) {
          return ActivationResult.failure(assetId, 'initial activation miss');
        }
        return ActivationResult.success(assetId);
      });

      manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
        eventStreamingManager: eventStreamingManager,
        assetHistoryStorage: _InMemoryAssetHistoryStorage(),
      );
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    test('watchBalance emits activation error but recovers '
        'and emits a real balance', () async {
      final errors = <Object>[];
      final values = <BalanceInfo>[];
      final recovered = Completer<void>();

      final sub = manager
          .watchBalance(assetId)
          .listen(
            (balance) {
              values.add(balance);
              if (balance.spendable > Decimal.zero && !recovered.isCompleted) {
                recovered.complete();
              }
            },
            onError: (Object error, StackTrace _) {
              errors.add(error);
            },
          );

      await recovered.future.timeout(const Duration(seconds: 2));

      expect(
        errors.whereType<ActivationFailedException>(),
        isNotEmpty,
        reason: 'Initial activation miss should still be observable',
      );
      expect(
        values.any((b) => b.spendable == Decimal.zero),
        isTrue,
        reason: 'First-time wallet optimization may emit zero before recovery',
      );
      expect(values.last.spendable, Decimal.fromInt(5));

      await sub.cancel();
    });

    test(
      'single subscription receives recovered balance without re-subscribing',
      () async {
        final recovered = Completer<BalanceInfo>();

        final sub = manager.watchBalance(assetId).listen((balance) {
          if (balance.spendable > Decimal.zero && !recovered.isCompleted) {
            recovered.complete(balance);
          }
        }, onError: (_, __) {});

        final recoveredBalance = await recovered.future.timeout(
          const Duration(seconds: 2),
        );
        expect(recoveredBalance.spendable, Decimal.fromInt(5));
        expect(
          activationAttempts,
          greaterThanOrEqualTo(2),
          reason: 'Recovery should retry activation without new subscribers',
        );

        await sub.cancel();
      },
    );
  });
}
