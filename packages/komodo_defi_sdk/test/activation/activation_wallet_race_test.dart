import 'dart:async';

import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockAssetHistory extends Mock implements AssetHistoryStorage {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockBalanceManager extends Mock implements IBalanceManager {}

class _MockConfigService extends Mock implements ActivationConfigService {}

class _MockAssetsUpdateManager extends Mock
    implements KomodoAssetsUpdateManager {}

class _MockActivatedAssetsCache extends Mock implements ActivatedAssetsCache {}

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

void main() {
  const walletA = KdfUser(
    walletId: WalletId(
      name: 'wallet-a',
      pubkeyHash: 'hash-a',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: true,
  );
  const walletB = KdfUser(
    walletId: WalletId(
      name: 'wallet-b',
      pubkeyHash: 'hash-b',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: true,
  );
  final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(asset);
    registerFallbackValue(walletA.walletId);
  });

  for (final scenario in [
    'success',
    'switch',
    'reset',
    'degraded',
    'sign_out_back_in',
    'degraded_then_other_hash',
    'enriched_then_other_hash',
    'metadata_switch',
    'strategy_error_switch',
    'status_lookup_switch',
  ]) {
    test(
      'activation completion preserves wallet scope during $scenario',
      () async {
        final client = _MockApiClient();
        final auth = _MockAuth();
        final history = _MockAssetHistory();
        final lookup = _MockAssetLookup();
        final balances = _MockBalanceManager();
        final config = _MockConfigService();
        final updates = _MockAssetsUpdateManager();
        final cache = _MockActivatedAssetsCache();
        final changes = StreamController<KdfUser?>.broadcast(sync: true);
        final started = Completer<void>();
        final response = Completer<Map<String, dynamic>>();
        final nameOnly = walletA.copyWith(
          walletId: WalletId.fromName(
            walletA.walletId.name,
            walletA.walletId.authOptions,
          ),
        );
        var current = scenario == 'enriched_then_other_hash'
            ? nameOnly
            : walletA;
        final metadataStarted = Completer<void>();
        final metadataGate = Completer<void>();
        final statusGate = Completer<Set<AssetId>>();
        var identityReads = 0;
        final storedWallets = <WalletId>[];
        when(() => auth.currentUser).thenAnswer((_) async {
          identityReads++;
          return current;
        });
        when(() => auth.authStateChanges).thenAnswer((_) => changes.stream);
        when(() => lookup.fromId(asset.id)).thenReturn(asset);
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => <AssetId>{});
        when(cache.getActivatedAssetIds).thenAnswer((_) {
          if (scenario == 'status_lookup_switch') {
            started.complete();
            return statusGate.future;
          }
          return Future.value(<AssetId>{});
        });
        when(() => history.addAssetToWallet(any(), any())).thenAnswer((
          call,
        ) async {
          storedWallets.add(call.positionalArguments.first as WalletId);
          if (scenario == 'metadata_switch') {
            metadataStarted.complete();
            await metadataGate.future;
          }
        });
        when(() => balances.precacheBalance(any())).thenAnswer((_) async {});
        when(() => client.executeRpc(any())).thenAnswer((_) {
          if (!started.isCompleted) started.complete();
          return response.future;
        });
        final manager = ActivationManager(
          client,
          auth,
          history,
          lookup,
          balances,
          config,
          updates,
          cache,
        );
        addTearDown(() async {
          await manager.dispose();
          await changes.close();
        });
        final pending = manager.activateAsset(asset).toList();
        // Install the matcher before finishing a rejected stream.
        final completesSuccessfully =
            scenario == 'degraded' || scenario == 'success';
        final completed = completesSuccessfully
            ? pending.then<void>((events) {
                expect(events.last.isSuccess, isTrue);
              })
            : expectLater(
                pending,
                throwsA(isA<WalletChangedDisconnectException>()),
              );
        await started.future;
        if (scenario == 'degraded') {
          current = nameOnly;
          changes.add(current);
        } else if (scenario == 'degraded_then_other_hash' ||
            scenario == 'enriched_then_other_hash') {
          current = scenario == 'degraded_then_other_hash' ? nameOnly : walletA;
          changes.add(current);
          current = walletA.copyWith(
            walletId: WalletId(
              name: walletA.walletId.name,
              pubkeyHash: walletB.walletId.pubkeyHash,
              authOptions: walletA.walletId.authOptions,
            ),
          );
          changes.add(current);
        } else if (scenario == 'sign_out_back_in') {
          changes
            ..add(null)
            ..add(walletA);
        } else if (scenario != 'success' && scenario != 'metadata_switch') {
          current = walletB;
          if (scenario == 'reset') manager.resetActivationSessionState();
          // Other switch cases deliberately delay the auth event.
        }
        if (scenario == 'status_lookup_switch') {
          statusGate.complete({asset.id});
        } else if (scenario == 'strategy_error_switch') {
          response.completeError(StateError('Activation RPC failed'));
        } else {
          response.complete({
            'mmrpc': '2.0',
            'result': {
              'current_block': 1,
              'wallet_balance': {
                'wallet_type': 'iguana',
                'accounts': <Map<String, dynamic>>[],
              },
              'nfts_infos': <String, dynamic>{},
            },
          });
        }
        if (scenario == 'metadata_switch') {
          await metadataStarted.future;
          current = walletB;
          metadataGate.complete();
        }
        await completed;
        if (completesSuccessfully) {
          expect(
            identityReads,
            lessThanOrEqualTo(6),
            reason: 'Do not re-read wallet identity for local progress events',
          );
          expect(storedWallets, [walletA.walletId]);
          expect(manager.activationStateOf(asset.id)?.isActive, isTrue);
        } else {
          expect(
            storedWallets,
            scenario == 'metadata_switch' ? [walletA.walletId] : isEmpty,
          );
          expect(manager.activationStateOf(asset.id), isNull);
          expect(manager.wasFreshlyActivated(asset.id), isFalse);
          verifyNever(() => balances.precacheBalance(any()));
        }
      },
    );
  }
  for (final switchWallet in [false, true]) {
    test(
      'coordinator first auth event '
      '${switchWallet ? 'B isolates pending A' : 'A preserves pending A'}',
      () async {
        final client = _MockApiClient();
        final auth = _MockAuth();
        final history = _MockAssetHistory();
        final lookup = _MockAssetLookup();
        final balances = _MockBalanceManager();
        final config = _MockConfigService();
        final updates = _MockAssetsUpdateManager();
        final cache = _MockActivatedAssetsCache();
        final changes = StreamController<KdfUser?>.broadcast(sync: true);
        final firstStarted = Completer<void>();
        final secondStarted = Completer<void>();
        final firstResponse = Completer<Map<String, dynamic>>();
        final storedWallets = <WalletId>[];
        var current = walletA;
        var activationCalls = 0;
        var available = false;
        final response = <String, dynamic>{
          'mmrpc': '2.0',
          'result': {
            'current_block': 1,
            'wallet_balance': {
              'wallet_type': 'iguana',
              'accounts': <Map<String, dynamic>>[],
            },
            'nfts_infos': <String, dynamic>{},
          },
        };
        when(() => auth.currentUser).thenAnswer((_) async => current);
        when(() => auth.authStateChanges).thenAnswer((_) => changes.stream);
        when(() => lookup.fromId(asset.id)).thenReturn(asset);
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => available ? {asset.id} : <AssetId>{});
        when(() => history.addAssetToWallet(any(), any())).thenAnswer((
          call,
        ) async {
          storedWallets.add(call.positionalArguments.first as WalletId);
        });
        when(() => balances.precacheBalance(any())).thenAnswer((_) async {});
        when(() => client.executeRpc(any())).thenAnswer((_) async {
          activationCalls++;
          if (activationCalls == 1) {
            firstStarted.complete();
            return firstResponse.future;
          }
          secondStarted.complete();
          available = true;
          return response;
        });
        final manager = ActivationManager(
          client,
          auth,
          history,
          lookup,
          balances,
          config,
          updates,
          cache,
        );
        final coordinator = SharedActivationCoordinator(manager, auth);
        addTearDown(() async {
          if (!firstResponse.isCompleted) firstResponse.complete(response);
          await coordinator.dispose();
          await manager.dispose();
          await changes.close();
        });
        final first = coordinator.activateAsset(asset);
        final firstResult = switchWallet
            ? expectLater(first, throwsA(isA<StateError>()))
            : first.then<void>((result) => expect(result.isSuccess, isTrue));
        await firstStarted.future;
        // The stream intentionally emitted nothing until the RPC was in flight.
        current = switchWallet ? walletB : walletA;
        changes.add(current);
        if (switchWallet) {
          await firstResult;
          final second = coordinator.activateAsset(asset);
          await secondStarted.future.timeout(const Duration(seconds: 2));
          expect((await second).isSuccess, isTrue);
        } else {
          available = true;
        }
        firstResponse.complete(response);
        await firstResult;
        await Future<void>.delayed(Duration.zero);
        expect(activationCalls, switchWallet ? 2 : 1);
        expect(storedWallets, [current.walletId]);
        expect(manager.activationStateOf(asset.id)?.isActive, isTrue);
      },
    );
  }
  for (final emitFirstAuthEvent in [true, false]) {
    test(
      'late initial identity cannot reset wallet B after '
      '${emitFirstAuthEvent ? 'its first auth event' : 'a concurrent capture'}',
      () async {
        final client = _MockApiClient();
        final auth = _MockAuth();
        final history = _MockAssetHistory();
        final lookup = _MockAssetLookup();
        final balances = _MockBalanceManager();
        final config = _MockConfigService();
        final updates = _MockAssetsUpdateManager();
        final cache = _MockActivatedAssetsCache();
        final changes = StreamController<KdfUser?>.broadcast(sync: true);
        final firstReadStarted = Completer<void>();
        final firstIdentity = Completer<KdfUser?>();
        var identityReads = 0;
        final storedWallets = <WalletId>[];
        when(() => auth.currentUser).thenAnswer((_) {
          if (identityReads++ == 0) {
            firstReadStarted.complete();
            return firstIdentity.future;
          }
          return Future.value(walletB);
        });
        when(() => auth.authStateChanges).thenAnswer((_) => changes.stream);
        when(() => lookup.fromId(asset.id)).thenReturn(asset);
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => <AssetId>{});
        when(() => history.addAssetToWallet(any(), any())).thenAnswer((
          call,
        ) async {
          storedWallets.add(call.positionalArguments.first as WalletId);
        });
        when(() => balances.precacheBalance(any())).thenAnswer((_) async {});
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => {
            'mmrpc': '2.0',
            'result': {
              'current_block': 1,
              'wallet_balance': {
                'wallet_type': 'iguana',
                'accounts': <Map<String, dynamic>>[],
              },
              'nfts_infos': <String, dynamic>{},
            },
          },
        );
        final manager = ActivationManager(
          client,
          auth,
          history,
          lookup,
          balances,
          config,
          updates,
          cache,
        );
        addTearDown(() async {
          if (!firstIdentity.isCompleted) firstIdentity.complete(walletA);
          await manager.dispose();
          await changes.close();
        });
        final staleActivation = expectLater(
          manager.activateAsset(asset).toList(),
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        await firstReadStarted.future;
        // Initial null -> B does not advance the session generation. A late
        // read must still lose to the identity this manager has now accepted.
        if (emitFirstAuthEvent) changes.add(walletB);
        expect(
          (await manager.activateAsset(asset).toList()).last.isSuccess,
          isTrue,
        );
        expect(manager.activationStateOf(asset.id)?.isActive, isTrue);
        firstIdentity.complete(walletA);
        await staleActivation;
        expect(manager.activationStateOf(asset.id)?.isActive, isTrue);
        expect(manager.wasFreshlyActivated(asset.id), isTrue);
        expect(storedWallets, [walletB.walletId]);
        verify(() => client.executeRpc(any())).called(1);
      },
    );
  }
}
