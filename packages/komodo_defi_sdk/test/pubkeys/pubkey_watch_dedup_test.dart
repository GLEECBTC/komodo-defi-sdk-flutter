// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

/// Every publisher on the watcher stream must drop a snapshot subscribers
/// already hold.
///
/// This is not a micro-optimisation. The app's `CoinAddressesBloc` reads any
/// watcher payload as "these pubkeys were replaced": it blanks the coin page's
/// address list and revokes the GasFree custody attestation until a fresh
/// account-status round trip returns. `precachePubkeys` is called on every
/// balance event and used to broadcast unconditionally, so a wallet whose
/// addresses had not changed still cycled the coin page through its
/// "Checking gas-free availability" banner on a timer.
void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(
      AssetId(
        id: 'DUMMY',
        name: 'Dummy',
        symbol: AssetSymbol(assetConfigId: 'DUMMY'),
        chainId: AssetChainId(chainId: 0, decimalsValue: 0),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      ),
    );
  });

  group('watcher stream de-duplication', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late StreamController<KdfUser?> authChanges;
    late PubkeyManager manager;
    late Asset asset;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => activation.wasFreshlyActivated(any())).thenReturn(false);
      when(() => auth.currentUser).thenAnswer(
        (_) async => KdfUser(
          walletId: WalletId(
            name: 'test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      manager = PubkeyManager(client, auth, activation);

      asset = Asset(
        id: AssetId(
          id: 'ATOM',
          name: 'Cosmos',
          symbol: AssetSymbol(assetConfigId: 'ATOM'),
          chainId: AssetChainId(chainId: 118, decimalsValue: 6),
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
      );

      when(
        () => activation.isAssetActive(asset.id),
      ).thenAnswer((_) async => true);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final req =
            invocation.positionalArguments.first as Map<String, dynamic>;
        if (req['method'] == 'my_balance') {
          return <String, dynamic>{
            'address': 'cosmos1stable',
            'balance': '0',
            'unspendable_balance': '0',
            'coin': asset.id.id,
          };
        }
        return <String, dynamic>{'result': <String, dynamic>{}};
      });
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    test(
      'precachePubkeys does not re-broadcast an unchanged snapshot',
      () async {
        final emitted = <AssetPubkeys>[];
        final subscription = manager.watchPubkeys(asset).listen(emitted.add);
        addTearDown(subscription.cancel);

        // Let the watcher hydrate and publish its first fresh snapshot.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(emitted, isNotEmpty);
        final settled = emitted.length;

        // A balance event triggers this on an unchanged address set.
        await manager.precachePubkeys(asset);
        await manager.precachePubkeys(asset);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          emitted.length,
          settled,
          reason: 'an identical snapshot must not reach subscribers again',
        );
      },
    );

    test('precachePubkeys still broadcasts a changed snapshot', () async {
      final emitted = <AssetPubkeys>[];
      final subscription = manager.watchPubkeys(asset).listen(emitted.add);
      addTearDown(subscription.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final settled = emitted.length;

      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final req =
            invocation.positionalArguments.first as Map<String, dynamic>;
        if (req['method'] == 'my_balance') {
          return <String, dynamic>{
            'address': 'cosmos1moved',
            'balance': '0',
            'unspendable_balance': '0',
            'coin': asset.id.id,
          };
        }
        return <String, dynamic>{'result': <String, dynamic>{}};
      });

      await manager.refreshPubkeys(asset);
      await manager.precachePubkeys(asset);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(emitted.length, greaterThan(settled));
      expect(emitted.last.keys.single.address, 'cosmos1moved');
    });
  });
}
