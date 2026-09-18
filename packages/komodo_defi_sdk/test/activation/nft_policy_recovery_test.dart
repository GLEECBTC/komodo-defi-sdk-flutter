import 'dart:async';

import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/runtime_auth_fixture.dart';

class _Client extends Mock implements ApiClient {}

class _Auth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _History extends Mock implements AssetHistoryStorage {}

class _Lookup extends Mock implements IAssetLookup {}

class _Assets extends Mock implements AssetManager {}

class _Balances extends Mock implements IBalanceManager {}

class _Config extends Mock implements ActivationConfigService {}

class _Updates extends Mock implements KomodoAssetsUpdateManager {}

class _Cache extends Mock implements ActivatedAssetsCache {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  for (final switchSession in [false, true]) {
    final behavior = switchSession
        ? 'expires with the runtime session'
        : 'retains its original provider parameters';
    test('NFT recovery $behavior', () async {
      final client = _Client();
      final auth = _Auth();
      final history = _History();
      final lookup = _Lookup();
      final cache = _Cache();
      final policy = ActivationPolicy();
      final nft = Asset.fromJson(const {
        'coin': 'NFT_ETH',
        'type': 'ERC-20',
        'name': 'Ethereum NFTs',
        'fname': 'Ethereum NFTs',
        'chain_id': 1,
        'nodes': <Map<String, dynamic>>[],
        'swap_contract_address': 'contract',
        'fallback_swap_contract': 'fallback',
        'protocol': {
          'type': 'NFT',
          'protocol_data': {'platform': 'ETH'},
        },
      });
      final user = KdfUser(
        walletId: WalletId.fromName(
          'NFT wallet',
          const AuthOptions(derivationMethod: DerivationMethod.iguana),
        ),
        isBip39Seed: true,
      );
      final enabled = <AssetId>{};
      when(() => auth.currentUser).thenAnswer((_) async => user);
      when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
      when(() => lookup.fromId(nft.id)).thenReturn(nft);
      when(cache.getActivatedAssetIds).thenAnswer((_) async => {...enabled});
      when(
        () => cache.getActivatedAssetIds(
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((_) async => {...enabled});
      final manager = ActivationManager(
        client,
        auth,
        history,
        lookup,
        _Balances(),
        _Config(),
        _Updates(),
        cache,
        activationPolicy: policy,
      );
      final service = NftActivationService(
        client,
        _Assets(),
        cache,
        auth: auth,
        activationManager: manager,
        activationPolicy: policy,
      );
      addTearDown(manager.dispose);
      addTearDown(policy.dispose);
      final disableStarted = Completer<void>();
      final disabling = Completer<void>();
      final recovered = Completer<void>();
      final enableRequests = <Map<String, dynamic>>[];
      when(() => client.executeRpc(any())).thenAnswer((call) async {
        final request = call.positionalArguments.single as Map<String, dynamic>;
        if (request['method'] == 'disable_coin') {
          disableStarted.complete();
          await disabling.future;
          enabled.remove(nft.id);
          return {'result': 'success'};
        }
        expect(request['method'], 'enable_nft');
        enableRequests.add(request);
        enabled.add(nft.id);
        if (enableRequests.length == 2) recovered.complete();
        return {
          'mmrpc': '2.0',
          'result': {'nfts': <String, dynamic>{}, 'platform_coin': 'ETH'},
        };
      });
      final params = NftActivationParams(
        requiredConfirmations: 11,
        provider: const NftProvider(
          type: 'Moralis',
          info: NftProviderInfo(
            url: 'https://example.test/nft-provider',
            komodoProxy: false,
          ),
        ),
      );
      await service.enableNft(nft, activationParams: params);
      policy.update(
        ActivationPolicySnapshot(
          status: ActivationPolicyStatus.ready,
          blockedAssets: {nft.id},
        ),
      );
      await disableStarted.future.timeout(const Duration(seconds: 1));
      policy.update(
        ActivationPolicySnapshot(status: ActivationPolicyStatus.ready),
      );
      if (switchSession) {
        auth.runtimeSessions.invalidate();
        auth.runtimeSessions.observe(user);
      }
      disabling.complete();
      if (switchSession) {
        await Future<void>.delayed(Duration.zero);
        expect(enableRequests, hasLength(1));
      } else {
        await recovered.future.timeout(const Duration(seconds: 1));
        expect(enabled, {nft.id});
        expect(enableRequests, hasLength(2));
        for (final request in enableRequests) {
          expect(
            (request['params'] as Map)['activation_params'],
            params.toRpcParams(),
          );
        }
      }
      verifyZeroInteractions(history);
    });
  }
}
