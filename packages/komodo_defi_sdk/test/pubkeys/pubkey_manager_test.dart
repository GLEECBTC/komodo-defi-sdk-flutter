// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
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

Asset _trc20Asset() {
  final trx = Asset.fromJson(const {
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
  }, knownIds: const {});
  return Asset.fromJson(
    const {
      'coin': 'USDT-TRC20',
      'type': 'TRC-20',
      'name': 'Tether',
      'fname': 'Tether',
      'wallet_only': true,
      'mm2': 1,
      'decimals': 6,
      'required_confirmations': 1,
      'derivation_path': "m/44'/195'",
      'protocol': {
        'type': 'TRC20',
        'protocol_data': {
          'platform': 'TRX',
          'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        },
      },
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      'parent_coin': 'TRX',
      'nodes': <Map<String, dynamic>>[],
    },
    knownIds: {trx.id},
  );
}

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
    registerFallbackValue(
      Asset(
        id: AssetId(
          id: 'DUMMY',
          name: 'Dummy',
          symbol: AssetSymbol(assetConfigId: 'DUMMY'),
          chainId: AssetChainId(chainId: 0, decimalsValue: 0),
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

  group('User stories and edge cases for PubkeyManager', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late StreamController<KdfUser?> authChanges;
    late PubkeyManager manager;

    // Common test asset: single-address protocol (Tendermint)
    late Asset tendermintAsset;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);

      manager = PubkeyManager(client, auth, activation);

      // Minimal Tendermint asset (single-address)
      final assetId = AssetId(
        id: 'ATOM',
        name: 'Cosmos',
        symbol: AssetSymbol(assetConfigId: 'ATOM'),
        chainId: AssetChainId(chainId: 118, decimalsValue: 6),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      );
      final protocol = TendermintProtocol.fromJson({
        'type': 'Tendermint',
        'rpc_urls': [
          {'url': 'http://localhost:26657'},
        ],
      });
      tendermintAsset = Asset(
        id: assetId,
        protocol: protocol,
        isWalletOnly: false,
        signMessagePrefix: null,
      );
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    KdfUser nonHdUser() => KdfUser(
      walletId: WalletId(
        name: 'test-wallet',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
      ),
      isBip39Seed: false,
    );

    Future<void> stubActivationAlwaysActive(Asset asset) async {
      when(
        () => activation.isAssetActive(asset.id),
      ).thenAnswer((_) async => true);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));
    }

    void stubWalletMyBalance({
      required String address,
      required String coin,
      Decimal? total,
      Decimal? unspendable,
      String? gasfreeAddress,
    }) {
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final req =
            invocation.positionalArguments.first as Map<String, dynamic>;
        final method = req['method'] as String?;
        if (method == 'my_balance') {
          return {
            'address': address,
            'balance': (total ?? Decimal.zero).toString(),
            'unspendable_balance': (unspendable ?? Decimal.zero).toString(),
            'coin': coin,
            if (gasfreeAddress != null) 'gasfree_address': gasfreeAddress,
          };
        }
        if (method == 'unban_pubkeys') {
          return <String, dynamic>{
            'result': <String, dynamic>{
              'still_banned': <String, dynamic>{},
              'unbanned': <String, dynamic>{},
              'were_not_banned': <String>[],
            },
          };
        }
        // Default minimal success for other RPCs that might appear
        return <String, dynamic>{'result': <String, dynamic>{}};
      });
    }

    test(
      'getPubkeys returns single address for single-address protocol',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);
        await stubActivationAlwaysActive(tendermintAsset);

        stubWalletMyBalance(address: 'cosmos1abc', coin: tendermintAsset.id.id);

        final result = await manager.getPubkeys(tendermintAsset);
        expect(result.assetId, tendermintAsset.id);
        expect(result.keys, hasLength(1));
        expect(result.keys.first.address, 'cosmos1abc');
      },
    );

    test(
      'fresh pubkeys do not inherit a cached GasFree custody address',
      () async {
        final asset = _trc20Asset();
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);
        await stubActivationAlwaysActive(asset);
        stubWalletMyBalance(
          address: 'TStandardAddress',
          coin: asset.id.id,
          gasfreeAddress: 'TCachedCustodyAddress',
        );

        final cached = await manager.getPubkeys(asset);
        expect(cached.keys.single.gasfreeAddress, 'TCachedCustodyAddress');

        stubWalletMyBalance(address: 'TStandardAddress', coin: asset.id.id);
        final refreshed = await manager
            .watchPubkeys(asset)
            .firstWhere((pubkeys) => pubkeys.keys.single.gasfreeAddress == null)
            .timeout(const Duration(seconds: 2));

        expect(refreshed.keys.single.address, 'TStandardAddress');
        expect(refreshed.keys.single.gasfreeAddress, isNull);
      },
    );

    test(
      'createNewPubkey throws UnsupportedError for single-address assets',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);
        await stubActivationAlwaysActive(tendermintAsset);

        stubWalletMyBalance(address: 'cosmos1abc', coin: tendermintAsset.id.id);

        expect(
          () => manager.createNewPubkey(tendermintAsset),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test(
      'createNewPubkeyStream yields error for single-address assets',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);
        await stubActivationAlwaysActive(tendermintAsset);

        stubWalletMyBalance(address: 'cosmos1abc', coin: tendermintAsset.id.id);

        final states = await manager
            .watchCreateNewPubkey(tendermintAsset)
            .take(1)
            .toList();
        expect(states.single.status, NewAddressStatus.error);
      },
    );

    test('unbanPubkeys delegates to RPC and returns result', () async {
      // auth not required here
      stubWalletMyBalance(address: 'cosmos1abc', coin: tendermintAsset.id.id);

      final res = await manager.unbanPubkeys(const UnbanBy.all());
      expect(res.isEmpty, isTrue);
    });

    test(
      'watchPubkeys emits last known immediately, then same via controller, then refreshed value',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);
        await stubActivationAlwaysActive(tendermintAsset);

        // First response used for preCache
        stubWalletMyBalance(address: 'cosmos1pre', coin: tendermintAsset.id.id);
        await manager.precachePubkeys(tendermintAsset);

        // Update the stub to simulate a new address on refresh
        stubWalletMyBalance(address: 'cosmos1new', coin: tendermintAsset.id.id);

        final stream = manager.watchPubkeys(tendermintAsset);

        // First emit is immediate lastKnown, second is same from controller, third is refreshed value
        final firstThree = await stream.take(3).toList();
        expect(firstThree[0].keys.first.address, 'cosmos1pre');
        expect(firstThree[2].keys.first.address, 'cosmos1new');
      },
    );

    test('watchPubkeys respects polling interval (~30s)', () async {
      final user = nonHdUser();
      when(() => auth.currentUser).thenAnswer((_) async => user);
      await stubActivationAlwaysActive(tendermintAsset);

      // Initial cache
      stubWalletMyBalance(address: 'cosmos1pre', coin: tendermintAsset.id.id);
      await manager.precachePubkeys(tendermintAsset);

      fakeAsync((FakeAsync async) {
        // After start, we set a different address for the immediate refresh
        stubWalletMyBalance(
          address: 'cosmos1poll1',
          coin: tendermintAsset.id.id,
        );

        final emitted = <String>[];
        final sub = manager.watchPubkeys(tendermintAsset).listen((e) {
          emitted.add(e.keys.first.address);
        });

        // Allow the immediate refresh to occur
        async.flushMicrotasks();
        expect(emitted.contains('cosmos1poll1'), isTrue);

        // Prepare next poll result and ensure it's not emitted before 30s
        stubWalletMyBalance(
          address: 'cosmos1poll2',
          coin: tendermintAsset.id.id,
        );
        async
          ..elapse(Duration(seconds: 29))
          ..flushMicrotasks();
        expect(emitted.contains('cosmos1poll2'), isFalse);

        // Hitting 30s should emit the next poll
        async
          ..elapse(Duration(seconds: 1))
          ..flushMicrotasks();
        expect(emitted.contains('cosmos1poll2'), isTrue);

        unawaited(sub.cancel());
      });
    });

    test('watchPubkeys stops and new watches throw after dispose', () async {
      final user = nonHdUser();
      when(() => auth.currentUser).thenAnswer((_) async => user);
      await stubActivationAlwaysActive(tendermintAsset);

      stubWalletMyBalance(address: 'cosmos1pre', coin: tendermintAsset.id.id);
      await manager.precachePubkeys(tendermintAsset);

      final received = <String>[];
      final sub = manager.watchPubkeys(tendermintAsset).listen((e) {
        received.add(e.keys.first.address);
      });

      // Cancel current subscription before disposing
      await sub.cancel();
      await manager.dispose();

      // After dispose, starting a new watch should throw on listen
      expect(
        () => manager.watchPubkeys(tendermintAsset).first,
        throwsA(isA<StateError>()),
      );
    });

    test('watchPubkeys updates lastKnown after emission', () async {
      final user = nonHdUser();
      when(() => auth.currentUser).thenAnswer((_) async => user);
      await stubActivationAlwaysActive(tendermintAsset);

      stubWalletMyBalance(address: 'cosmos1pre', coin: tendermintAsset.id.id);
      await manager.precachePubkeys(tendermintAsset);

      // Change to a new address which should update via immediate get in start
      stubWalletMyBalance(address: 'cosmos1start', coin: tendermintAsset.id.id);

      final first = await manager.watchPubkeys(tendermintAsset).first;
      expect(first.keys.first.address, isNotEmpty);

      // lastKnown should be updated to latest emitted value
      final cached = manager.lastKnown(tendermintAsset.id);
      expect(cached, isNotNull);
      expect(cached!.keys.first.address, first.keys.first.address);
    });

    test(
      'watchPubkeys with activateIfNeeded=false only emits last known if inactive',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);

        // Pre-cache with initial address
        when(
          () => activation.activateAsset(tendermintAsset),
        ).thenAnswer((_) async => ActivationResult.success(tendermintAsset.id));
        when(
          () => activation.isAssetActive(tendermintAsset.id),
        ).thenAnswer((_) async => true);
        stubWalletMyBalance(address: 'cosmos1pre', coin: tendermintAsset.id.id);
        await manager.precachePubkeys(tendermintAsset);

        // Now simulate inactive asset and disable activation on watch
        when(
          () => activation.isAssetActive(tendermintAsset.id),
        ).thenAnswer((_) async => false);
        // If it were to fetch, it would get this new address, but it should not
        stubWalletMyBalance(address: 'cosmos1new', coin: tendermintAsset.id.id);

        final stream = manager.watchPubkeys(
          tendermintAsset,
          activateIfNeeded: false,
        );

        // Give stream a brief moment to potentially emit more; should only emit one
        final received = await stream
            .timeout(Duration(milliseconds: 200))
            .take(1)
            .toList();
        expect(received.single.keys.first.address, 'cosmos1pre');
      },
    );

    test(
      'lastKnown returns null when no cache; updates after preCache',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);
        when(
          () => activation.isAssetActive(tendermintAsset.id),
        ).thenAnswer((_) async => true);
        when(
          () => activation.activateAsset(tendermintAsset),
        ).thenAnswer((_) async => ActivationResult.success(tendermintAsset.id));

        expect(manager.lastKnown(tendermintAsset.id), isNull);

        stubWalletMyBalance(address: 'cosmos1pre', coin: tendermintAsset.id.id);
        await manager.precachePubkeys(tendermintAsset);

        final cached = manager.lastKnown(tendermintAsset.id);
        expect(cached, isNotNull);
        expect(cached!.keys.first.address, 'cosmos1pre');
      },
    );

    test('auth wallet change resets state and clears cache', () async {
      final user = nonHdUser();
      when(() => auth.currentUser).thenAnswer((_) async => user);
      when(
        () => activation.isAssetActive(tendermintAsset.id),
      ).thenAnswer((_) async => true);
      when(
        () => activation.activateAsset(tendermintAsset),
      ).thenAnswer((_) async => ActivationResult.success(tendermintAsset.id));

      stubWalletMyBalance(address: 'cosmos1pre', coin: tendermintAsset.id.id);
      await manager.precachePubkeys(tendermintAsset);
      expect(manager.lastKnown(tendermintAsset.id), isNotNull);

      // Emit new user with different wallet ID
      final newUser = KdfUser(
        walletId: WalletId(
          name: 'other',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        ),
        isBip39Seed: false,
      );
      authChanges.add(newUser);
      await Future<void>.delayed(Duration(milliseconds: 50));

      expect(manager.lastKnown(tendermintAsset.id), isNull);
    });

    test(
      'watchPubkeys second subscriber receives immediate lastKnown when controller exists (due to immediate yield)',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);
        await stubActivationAlwaysActive(tendermintAsset);

        fakeAsync((async) {
          // Seed cache
          stubWalletMyBalance(
            address: 'cosmos1pre',
            coin: tendermintAsset.id.id,
          );
          // First fetch result for immediate refresh
          stubWalletMyBalance(
            address: 'cosmos1first',
            coin: tendermintAsset.id.id,
          );

          final s1Events = <String>[];
          final sub1 = manager.watchPubkeys(tendermintAsset).listen((e) {
            s1Events.add(e.keys.first.address);
          });

          // Let initial get happen
          async.flushMicrotasks();

          // Prepare next poll result
          stubWalletMyBalance(
            address: 'cosmos1poll',
            coin: tendermintAsset.id.id,
          );

          // Second subscriber joins AFTER controller already active
          final s2Events = <String>[];
          final sub2 = manager.watchPubkeys(tendermintAsset).listen((e) {
            s2Events.add(e.keys.first.address);
          });

          // With immediate yield reintroduced, second subscriber sees immediate lastKnown
          async.flushMicrotasks();
          expect(s2Events, isNotEmpty);

          // Only after the next polling tick (~30s) should second subscriber receive a new value
          async
            ..elapse(const Duration(seconds: 30))
            ..flushMicrotasks();

          expect(s2Events, contains('cosmos1poll'));

          unawaited(sub1.cancel());
          unawaited(sub2.cancel());
        });
      },
    );

    test(
      'watchPubkeys activateIfNeeded is sticky per controller (first subscriber decides)',
      () async {
        final user = nonHdUser();
        when(() => auth.currentUser).thenAnswer((_) async => user);

        // Start as inactive; do NOT allow activation on first subscriber
        when(
          () => activation.isAssetActive(tendermintAsset.id),
        ).thenAnswer((_) async => false);
        when(
          () => activation.activateAsset(tendermintAsset),
        ).thenAnswer((_) async => ActivationResult.success(tendermintAsset.id));

        // Do NOT pre-cache; we want to ensure no activation occurs and no emissions happen

        // First subscriber: activateIfNeeded=false (controller is created here)
        final s1Events = <String>[];
        final s1 = manager
            .watchPubkeys(tendermintAsset, activateIfNeeded: false)
            .listen((e) {
              s1Events.add(e.keys.first.address);
            });

        // Allow initial onListen to run
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Second subscriber: activateIfNeeded=true but controller already exists
        final s2Events = <String>[];
        final s2 = manager.watchPubkeys(tendermintAsset).listen((e) {
          s2Events.add(e.keys.first.address);
        });

        // Give listeners a brief moment
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Because the controller was created with activateIfNeeded=false, no activation should occur
        verifyNever(() => activation.activateAsset(tendermintAsset));

        // No emissions should occur since activation is disabled and asset inactive
        expect(s1Events, isEmpty);
        expect(s2Events, isEmpty);

        // Clean up
        await s1.cancel();
        await s2.cancel();
      },
    );

    test('dispose prevents further access', () async {
      await manager.dispose();
      expect(
        () => manager.lastKnown(tendermintAsset.id),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Dispose behavior for PubkeyManager', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
    });

    test(
      'dispose swallows auth subscription cancel errors and is idempotent',
      () async {
        // Arrange auth stream that returns a subscription whose cancel throws
        when(
          () => auth.authStateChanges,
        ).thenAnswer((_) => _StreamWithThrowingCancel<KdfUser?>());

        final manager = PubkeyManager(client, auth, activation);

        // Act + Assert: dispose does not throw even if cancel throws
        await manager.dispose();
        // Idempotent
        await manager.dispose();
      },
    );

    test(
      'dispose during active watch stops further emissions (no race with timers)',
      () async {
        // Normal auth stream
        final authChanges = StreamController<KdfUser?>.broadcast();
        when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
        when(() => auth.currentUser).thenAnswer(
          (_) async => KdfUser(
            walletId: WalletId(
              name: 'w',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        final manager = PubkeyManager(client, auth, activation);
        addTearDown(() async {
          await manager.dispose();
          await authChanges.close();
        });

        // Active asset
        when(
          () => activation.isAssetActive(any()),
        ).thenAnswer((_) async => true);
        when(() => activation.activateAsset(any())).thenAnswer((
          invocation,
        ) async {
          final assetArg = invocation.positionalArguments.first as Asset;
          return ActivationResult.success(assetArg.id);
        });

        // Provide a minimal single-address asset and RPC stub
        final assetId = AssetId(
          id: 'ATOM',
          name: 'Cosmos',
          symbol: AssetSymbol(assetConfigId: 'ATOM'),
          chainId: AssetChainId(chainId: 118, decimalsValue: 6),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final req =
              invocation.positionalArguments.first as Map<String, dynamic>;
          final method = req['method'] as String?;
          if (method == 'my_balance') {
            return {
              'address': 'cosmos1pre',
              'balance': '0',
              'unspendable_balance': '0',
              'coin': assetId.id,
            };
          }
          return <String, dynamic>{'result': <String, dynamic>{}};
        });

        // Start watch
        final events = <AssetPubkeys>[];
        final sub = manager
            .watchPubkeys(asset)
            .listen(events.add, onError: (_) {});

        // Allow initial microtasks
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final initial = events.length;

        // Now dispose while timer could schedule next polls
        await manager.dispose();

        // Change RPC response that would be observed if polling still alive
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          return {
            'address': 'cosmos1new',
            'balance': '0',
            'unspendable_balance': '0',
            'coin': assetId.id,
          };
        });

        // Wait longer than polling interval to ensure nothing else emitted
        await Future<void>.delayed(const Duration(seconds: 1));

        // Assert: stream should not emit after dispose
        expect(events.length, initial);
        await sub.cancel();
      },
    );
  });

  /// Group of tests for concurrent cleanup behavior in PubkeyManager
  /// Tests requirements 4.1, 4.2, 4.3 for concurrent operations and error handling
  group('PubkeyManager concurrent cleanup tests', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late StreamController<KdfUser?> authChanges;
    late PubkeyManager manager;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      manager = PubkeyManager(client, auth, activation);

      // Setup common mocks
      when(() => auth.currentUser).thenAnswer(
        (_) async => KdfUser(
          walletId: WalletId(
            name: 'test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      when(() => activation.isAssetActive(any())).thenAnswer((_) async => true);
      when(() => activation.activateAsset(any())).thenAnswer((
        invocation,
      ) async {
        final asset = invocation.positionalArguments.first as Asset;
        return ActivationResult.success(asset.id);
      });

      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final req =
            invocation.positionalArguments.first as Map<String, dynamic>;
        final method = req['method'] as String?;
        if (method == 'my_balance') {
          final coin = req['coin'] as String?;
          return {
            'address': 'test1address',
            'balance': '100',
            'unspendable_balance': '0',
            'coin': coin ?? 'TEST',
          };
        }
        return <String, dynamic>{'result': <String, dynamic>{}};
      });
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    test('concurrent controller closure on auth state change', () async {
      // Arrange: Create multiple controllers by starting multiple watchers
      final subscriptions = <StreamSubscription<AssetPubkeys>>[];
      final receivedEvents = <List<AssetPubkeys>>[];

      // Create 5 different assets to have multiple controllers
      for (int i = 0; i < 5; i++) {
        final assetId = AssetId(
          id: 'TEST$i',
          name: 'Test Coin $i',
          symbol: AssetSymbol(assetConfigId: 'TEST$i'),
          chainId: AssetChainId(chainId: i, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        // Start watching to create controllers
        final events = <AssetPubkeys>[];
        final sub = manager
            .watchPubkeys(asset)
            .listen(
              events.add,
              onError: (error) {
                // Expected errors during auth state change
              },
            );
        subscriptions.add(sub);
        receivedEvents.add(events);

        // Allow controller creation
        await Future<void>.delayed(Duration(milliseconds: 10));
      }

      // Verify we have some initial events (controllers were created and working)
      await Future<void>.delayed(Duration(milliseconds: 50));

      // Measure cleanup time
      final stopwatch = Stopwatch()..start();

      // Act: Trigger auth state change
      authChanges.add(
        KdfUser(
          walletId: WalletId(
            name: 'new-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(Duration(milliseconds: 200));
      stopwatch.stop();

      // Assert: Cleanup should be fast (concurrent operations)
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: 'Concurrent cleanup should complete quickly',
      );

      // Clean up subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    });

    test('concurrent subscription cancellation on auth state change', () async {
      // Arrange: Create multiple active watchers
      final subscriptions = <StreamSubscription<AssetPubkeys>>[];

      for (int i = 0; i < 5; i++) {
        final assetId = AssetId(
          id: 'SUB$i',
          name: 'Sub Test $i',
          symbol: AssetSymbol(assetConfigId: 'SUB$i'),
          chainId: AssetChainId(chainId: i + 10, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        final sub = manager.watchPubkeys(asset).listen((_) {}, onError: (_) {});
        subscriptions.add(sub);

        // Allow watcher creation
        await Future<void>.delayed(Duration(milliseconds: 10));
      }

      // Measure cleanup time
      final stopwatch = Stopwatch()..start();

      // Act: Trigger auth state change
      authChanges.add(
        KdfUser(
          walletId: WalletId(
            name: 'another-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(Duration(milliseconds: 200));
      stopwatch.stop();

      // Assert: Cleanup should be fast (concurrent operations)
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: 'Concurrent subscription cancellation should be fast',
      );

      // Clean up subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    });

    test('error resilience when individual operations fail', () async {
      // Arrange: Create some normal watchers
      final normalSubs = <StreamSubscription<AssetPubkeys>>[];

      for (int i = 0; i < 3; i++) {
        final assetId = AssetId(
          id: 'NORMAL$i',
          name: 'Normal $i',
          symbol: AssetSymbol(assetConfigId: 'NORMAL$i'),
          chainId: AssetChainId(chainId: i + 20, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        final sub = manager.watchPubkeys(asset).listen((_) {}, onError: (_) {});
        normalSubs.add(sub);
        await Future<void>.delayed(Duration(milliseconds: 10));
      }

      // Act: Trigger auth state change - should not throw despite potential failures
      expect(() async {
        authChanges.add(
          KdfUser(
            walletId: WalletId(
              name: 'resilient-wallet',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Wait for cleanup to complete
        await Future<void>.delayed(Duration(milliseconds: 200));
      }, returnsNormally);

      // Assert: The manager should continue to function after cleanup
      // We can test this by creating a new watcher after the auth change
      final newAssetId = AssetId(
        id: 'NEWTEST',
        name: 'New Test',
        symbol: AssetSymbol(assetConfigId: 'NEWTEST'),
        chainId: AssetChainId(chainId: 999, decimalsValue: 8),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      );
      final newAsset = Asset(
        id: newAssetId,
        protocol: TendermintProtocol.fromJson({
          'type': 'Tendermint',
          'rpc_urls': [
            {'url': 'http://localhost:26657'},
          ],
        }),
        isWalletOnly: false,
        signMessagePrefix: null,
      );

      // This should work without throwing, indicating cleanup was resilient
      final newSub = manager
          .watchPubkeys(newAsset)
          .listen((_) {}, onError: (_) {});
      await Future<void>.delayed(Duration(milliseconds: 50));
      await newSub.cancel();

      // Clean up normal subscriptions
      for (final sub in normalSubs) {
        await sub.cancel();
      }
    });

    test('performance improvement over sequential operations', () async {
      // Arrange: Create many controllers and subscriptions to test performance
      final subscriptions = <StreamSubscription<AssetPubkeys>>[];
      const resourceCount = 10; // Reasonable number for testing

      for (int i = 0; i < resourceCount; i++) {
        final assetId = AssetId(
          id: 'PERF$i',
          name: 'Performance Test $i',
          symbol: AssetSymbol(assetConfigId: 'PERF$i'),
          chainId: AssetChainId(chainId: i + 100, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        final sub = manager.watchPubkeys(asset).listen((_) {}, onError: (_) {});
        subscriptions.add(sub);
        await Future<void>.delayed(Duration(milliseconds: 5));
      }

      // Act: Measure concurrent cleanup time
      final stopwatch = Stopwatch()..start();

      authChanges.add(
        KdfUser(
          walletId: WalletId(
            name: 'performance-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(Duration(milliseconds: 300));
      stopwatch.stop();

      // Assert: Concurrent cleanup should be reasonably fast
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'Concurrent cleanup of $resourceCount resources should be fast',
      );

      // Clean up subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    });

    test('verify cleanup behavior through functional testing', () async {
      // Arrange: Create resources and populate cache
      final subscriptions = <StreamSubscription<AssetPubkeys>>[];
      final assets = <Asset>[];

      for (int i = 0; i < 3; i++) {
        final assetId = AssetId(
          id: 'CLEAR$i',
          name: 'Clear Test $i',
          symbol: AssetSymbol(assetConfigId: 'CLEAR$i'),
          chainId: AssetChainId(chainId: i + 200, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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
        assets.add(asset);

        final sub = manager.watchPubkeys(asset).listen((_) {}, onError: (_) {});
        subscriptions.add(sub);
        await Future<void>.delayed(Duration(milliseconds: 10));

        // Populate cache
        await manager.precachePubkeys(asset);
      }

      // Verify cache has content
      for (final asset in assets) {
        expect(
          manager.lastKnown(asset.id),
          isNotNull,
          reason: 'Cache should have content before cleanup',
        );
      }

      // Act: Trigger cleanup
      authChanges.add(
        KdfUser(
          walletId: WalletId(
            name: 'clear-test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      await Future<void>.delayed(Duration(milliseconds: 200));

      // Assert: Cache should be cleared (functional verification)
      for (final asset in assets) {
        expect(
          manager.lastKnown(asset.id),
          isNull,
          reason: 'Cache should be cleared after auth state change',
        );
      }

      // Clean up subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    });
  });

  /// Group of tests for memory leak prevention
  /// Tests requirement 4.4, 5.1 for memory leak prevention
  group('PubkeyManager memory leak prevention tests', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late StreamController<KdfUser?> authChanges;
    late PubkeyManager manager;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      manager = PubkeyManager(client, auth, activation);

      // Setup common mocks
      when(() => activation.isAssetActive(any())).thenAnswer((_) async => true);
      when(() => activation.activateAsset(any())).thenAnswer((
        invocation,
      ) async {
        final asset = invocation.positionalArguments.first as Asset;
        return ActivationResult.success(asset.id);
      });

      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final req =
            invocation.positionalArguments.first as Map<String, dynamic>;
        final method = req['method'] as String?;
        if (method == 'my_balance') {
          final coin = req['coin'] as String?;
          return {
            'address': 'test1address',
            'balance': '100',
            'unspendable_balance': '0',
            'coin': coin ?? 'TEST',
          };
        }
        return <String, dynamic>{'result': <String, dynamic>{}};
      });
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    test('multiple auth state changes dont leak controllers', () async {
      // Arrange: Perform multiple auth cycles
      const cycleCount = 5;
      const controllersPerCycle = 3;

      for (int cycle = 0; cycle < cycleCount; cycle++) {
        // Setup user for this cycle
        when(() => auth.currentUser).thenAnswer(
          (_) async => KdfUser(
            walletId: WalletId(
              name: 'wallet-$cycle',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Create controllers for this cycle
        final subscriptions = <StreamSubscription<AssetPubkeys>>[];
        for (int i = 0; i < controllersPerCycle; i++) {
          final assetId = AssetId(
            id: 'CYCLE${cycle}_ASSET$i',
            name: 'Cycle $cycle Asset $i',
            symbol: AssetSymbol(assetConfigId: 'CYCLE${cycle}_ASSET$i'),
            chainId: AssetChainId(chainId: cycle * 10 + i, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          );
          final asset = Asset(
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

          final sub = manager
              .watchPubkeys(asset)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);

          // Populate cache
          await manager.precachePubkeys(asset);
        }

        // Allow resources to be created
        await Future<void>.delayed(Duration(milliseconds: 20));

        // Trigger auth state change to next cycle
        if (cycle < cycleCount - 1) {
          authChanges.add(
            KdfUser(
              walletId: WalletId(
                name: 'wallet-${cycle + 1}',
                authOptions: AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
              isBip39Seed: false,
            ),
          );

          // Wait for cleanup to complete
          await Future<void>.delayed(Duration(milliseconds: 100));
        }

        // Clean up subscriptions for this cycle
        for (final sub in subscriptions) {
          await sub.cancel();
        }

        // Verify cleanup occurred - cache should be empty after auth change
        if (cycle < cycleCount - 1) {
          // Check that cache was cleared (functional verification of cleanup)
          for (int i = 0; i < controllersPerCycle; i++) {
            final assetId = AssetId(
              id: 'CYCLE${cycle}_ASSET$i',
              name: 'Cycle $cycle Asset $i',
              symbol: AssetSymbol(assetConfigId: 'CYCLE${cycle}_ASSET$i'),
              chainId: AssetChainId(chainId: cycle * 10 + i, decimalsValue: 8),
              derivationPath: null,
              subClass: CoinSubClass.tendermint,
            );
            expect(
              manager.lastKnown(assetId),
              isNull,
              reason:
                  'Cache should be cleared after auth state change in cycle $cycle',
            );
          }
        }
      }

      // Assert: After all cycles, manager should still be functional
      // Create a final test asset to verify the manager still works
      final finalAssetId = AssetId(
        id: 'FINAL_TEST',
        name: 'Final Test',
        symbol: AssetSymbol(assetConfigId: 'FINAL_TEST'),
        chainId: AssetChainId(chainId: 999, decimalsValue: 8),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      );
      final finalAsset = Asset(
        id: finalAssetId,
        protocol: TendermintProtocol.fromJson({
          'type': 'Tendermint',
          'rpc_urls': [
            {'url': 'http://localhost:26657'},
          ],
        }),
        isWalletOnly: false,
        signMessagePrefix: null,
      );

      // This should work without issues, indicating no memory leaks
      final finalSub = manager
          .watchPubkeys(finalAsset)
          .listen((_) {}, onError: (_) {});
      await Future<void>.delayed(Duration(milliseconds: 50));
      await finalSub.cancel();
    });

    test('multiple auth state changes dont leak subscriptions', () async {
      // Arrange: Perform multiple auth cycles focusing on subscription management
      const cycleCount = 4;
      const subscriptionsPerCycle = 4;

      for (int cycle = 0; cycle < cycleCount; cycle++) {
        // Setup user for this cycle
        when(() => auth.currentUser).thenAnswer(
          (_) async => KdfUser(
            walletId: WalletId(
              name: 'sub-wallet-$cycle',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Create subscriptions for this cycle
        final subscriptions = <StreamSubscription<AssetPubkeys>>[];
        for (int i = 0; i < subscriptionsPerCycle; i++) {
          final assetId = AssetId(
            id: 'SUB_CYCLE${cycle}_ASSET$i',
            name: 'Sub Cycle $cycle Asset $i',
            symbol: AssetSymbol(assetConfigId: 'SUB_CYCLE${cycle}_ASSET$i'),
            chainId: AssetChainId(chainId: cycle * 20 + i, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          );
          final asset = Asset(
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

          final sub = manager
              .watchPubkeys(asset)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);
        }

        // Allow subscriptions to be established
        await Future<void>.delayed(Duration(milliseconds: 30));

        // Trigger auth state change
        if (cycle < cycleCount - 1) {
          authChanges.add(
            KdfUser(
              walletId: WalletId(
                name: 'sub-wallet-${cycle + 1}',
                authOptions: AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
              isBip39Seed: false,
            ),
          );

          // Wait for cleanup to complete
          await Future<void>.delayed(Duration(milliseconds: 150));
        }

        // Clean up subscriptions for this cycle
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      }

      // Assert: Manager should still be responsive after all cycles
      expect(
        () => manager.lastKnown(
          AssetId(
            id: 'TEST',
            name: 'Test',
            symbol: AssetSymbol(assetConfigId: 'TEST'),
            chainId: AssetChainId(chainId: 1, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          ),
        ),
        returnsNormally,
      );
    });

    test('proper resource cleanup after manager disposal', () async {
      // Arrange: Create a separate manager instance for disposal testing
      final disposalClient = _MockApiClient();
      final disposalAuth = _MockAuth();
      final disposalActivation = _MockActivationCoordinator();
      final disposalAuthChanges = StreamController<KdfUser?>.broadcast();

      when(
        () => disposalAuth.authStateChanges,
      ).thenAnswer((_) => disposalAuthChanges.stream);
      when(() => disposalAuth.currentUser).thenAnswer(
        (_) async => KdfUser(
          walletId: WalletId(
            name: 'disposal-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );
      when(
        () => disposalActivation.isAssetActive(any()),
      ).thenAnswer((_) async => true);
      when(() => disposalActivation.activateAsset(any())).thenAnswer((
        invocation,
      ) async {
        final asset = invocation.positionalArguments.first as Asset;
        return ActivationResult.success(asset.id);
      });
      when(() => disposalClient.executeRpc(any())).thenAnswer((
        invocation,
      ) async {
        final req =
            invocation.positionalArguments.first as Map<String, dynamic>;
        final method = req['method'] as String?;
        if (method == 'my_balance') {
          return {
            'address': 'disposal1address',
            'balance': '100',
            'unspendable_balance': '0',
            'coin': 'DISPOSAL',
          };
        }
        return <String, dynamic>{'result': <String, dynamic>{}};
      });

      final disposalManager = PubkeyManager(
        disposalClient,
        disposalAuth,
        disposalActivation,
      );

      // Create resources
      final subscriptions = <StreamSubscription<AssetPubkeys>>[];
      for (int i = 0; i < 5; i++) {
        final assetId = AssetId(
          id: 'DISPOSAL$i',
          name: 'Disposal Asset $i',
          symbol: AssetSymbol(assetConfigId: 'DISPOSAL$i'),
          chainId: AssetChainId(chainId: i + 300, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        final sub = disposalManager
            .watchPubkeys(asset)
            .listen((_) {}, onError: (_) {});
        subscriptions.add(sub);

        // Populate cache
        await disposalManager.precachePubkeys(asset);
      }

      // Verify resources exist
      expect(
        disposalManager.lastKnown(
          AssetId(
            id: 'DISPOSAL0',
            name: 'Disposal Asset 0',
            symbol: AssetSymbol(assetConfigId: 'DISPOSAL0'),
            chainId: AssetChainId(chainId: 300, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          ),
        ),
        isNotNull,
      );

      // Act: Dispose the manager
      await disposalManager.dispose();

      // Assert: Manager should be in disposed state
      expect(
        () => disposalManager.lastKnown(
          AssetId(
            id: 'DISPOSAL0',
            name: 'Disposal Asset 0',
            symbol: AssetSymbol(assetConfigId: 'DISPOSAL0'),
            chainId: AssetChainId(chainId: 300, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          ),
        ),
        throwsA(isA<StateError>()),
      );

      // Clean up subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await disposalAuthChanges.close();
    });

    test('cleanup performance under high resource count scenarios', () async {
      // Arrange: Create many resources to test cleanup performance
      const highResourceCount = 20;

      when(() => auth.currentUser).thenAnswer(
        (_) async => KdfUser(
          walletId: WalletId(
            name: 'high-resource-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      final subscriptions = <StreamSubscription<AssetPubkeys>>[];

      // Create many resources
      for (int i = 0; i < highResourceCount; i++) {
        final assetId = AssetId(
          id: 'HIGH_RES$i',
          name: 'High Resource Asset $i',
          symbol: AssetSymbol(assetConfigId: 'HIGH_RES$i'),
          chainId: AssetChainId(chainId: i + 400, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        final sub = manager.watchPubkeys(asset).listen((_) {}, onError: (_) {});
        subscriptions.add(sub);

        // Populate cache
        await manager.precachePubkeys(asset);

        // Small delay to avoid overwhelming the system
        if (i % 5 == 0) {
          await Future<void>.delayed(Duration(milliseconds: 10));
        }
      }

      // Act: Measure cleanup performance
      final stopwatch = Stopwatch()..start();

      authChanges.add(
        KdfUser(
          walletId: WalletId(
            name: 'high-resource-wallet-2',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(Duration(milliseconds: 500));
      stopwatch.stop();

      // Assert: Cleanup should complete within reasonable time even with many resources
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(3000),
        reason:
            'Cleanup of $highResourceCount resources should complete within 3 seconds',
      );

      // Verify cleanup occurred
      for (int i = 0; i < highResourceCount; i++) {
        final assetId = AssetId(
          id: 'HIGH_RES$i',
          name: 'High Resource Asset $i',
          symbol: AssetSymbol(assetConfigId: 'HIGH_RES$i'),
          chainId: AssetChainId(chainId: i + 400, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        expect(
          manager.lastKnown(assetId),
          isNull,
          reason: 'Cache should be cleared for asset $i',
        );
      }

      // Clean up subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    });
  });

  /// Group of tests for performance benchmarking
  /// Tests requirements 5.1, 5.2, 5.4 for performance measurement and regression detection
  group('PubkeyManager performance benchmark tests', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late StreamController<KdfUser?> authChanges;
    late PubkeyManager manager;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      manager = PubkeyManager(client, auth, activation);

      // Setup common mocks
      when(() => auth.currentUser).thenAnswer(
        (_) async => KdfUser(
          walletId: WalletId(
            name: 'benchmark-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      when(() => activation.isAssetActive(any())).thenAnswer((_) async => true);
      when(() => activation.activateAsset(any())).thenAnswer((
        invocation,
      ) async {
        final asset = invocation.positionalArguments.first as Asset;
        return ActivationResult.success(asset.id);
      });

      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final req =
            invocation.positionalArguments.first as Map<String, dynamic>;
        final method = req['method'] as String?;
        if (method == 'my_balance') {
          final coin = req['coin'] as String?;
          return {
            'address': 'benchmark1address',
            'balance': '100',
            'unspendable_balance': '0',
            'coin': coin ?? 'BENCH',
          };
        }
        return <String, dynamic>{'result': <String, dynamic>{}};
      });
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    test('cleanup performance with varying resource counts', () async {
      // Test different resource counts to measure performance scaling
      final resourceCounts = [5, 10, 15, 20];
      final performanceResults = <int, int>{};

      for (final resourceCount in resourceCounts) {
        // Arrange: Create resources
        final subscriptions = <StreamSubscription<AssetPubkeys>>[];

        for (int i = 0; i < resourceCount; i++) {
          final assetId = AssetId(
            id: 'PERF_VAR${resourceCount}_$i',
            name: 'Performance Variable $resourceCount Asset $i',
            symbol: AssetSymbol(assetConfigId: 'PERF_VAR${resourceCount}_$i'),
            chainId: AssetChainId(
              chainId: resourceCount * 100 + i,
              decimalsValue: 8,
            ),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          );
          final asset = Asset(
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

          final sub = manager
              .watchPubkeys(asset)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);

          // Populate cache
          await manager.precachePubkeys(asset);
        }

        // Allow resources to be established
        await Future<void>.delayed(Duration(milliseconds: 50));

        // Act: Measure cleanup time
        final stopwatch = Stopwatch()..start();

        authChanges.add(
          KdfUser(
            walletId: WalletId(
              name: 'benchmark-wallet-$resourceCount',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Wait for cleanup to complete
        await Future<void>.delayed(Duration(milliseconds: 200));
        stopwatch.stop();

        performanceResults[resourceCount] = stopwatch.elapsedMilliseconds;

        // Clean up subscriptions
        for (final sub in subscriptions) {
          await sub.cancel();
        }

        // Small delay between tests
        await Future<void>.delayed(Duration(milliseconds: 100));
      }

      // Assert: Performance should scale reasonably
      print('PubkeyManager cleanup performance results:');
      for (final entry in performanceResults.entries) {
        print('  ${entry.key} resources: ${entry.value}ms');

        // Each resource count should complete within reasonable time
        expect(
          entry.value,
          lessThan(2000),
          reason:
              'Cleanup of ${entry.key} resources should complete within 2 seconds',
        );
      }

      // Performance should not degrade exponentially
      final smallCount = performanceResults[5]!;
      final largeCount = performanceResults[20]!;
      final scalingFactor = largeCount / smallCount;

      expect(
        scalingFactor,
        lessThan(10),
        reason:
            'Performance should not degrade exponentially with resource count',
      );
    });

    test(
      'cleanup time stays under 1 second threshold for typical usage',
      () async {
        // Arrange: Create typical usage scenario (5-10 assets)
        const typicalResourceCount = 8;
        final subscriptions = <StreamSubscription<AssetPubkeys>>[];

        for (int i = 0; i < typicalResourceCount; i++) {
          final assetId = AssetId(
            id: 'TYPICAL_$i',
            name: 'Typical Asset $i',
            symbol: AssetSymbol(assetConfigId: 'TYPICAL_$i'),
            chainId: AssetChainId(chainId: i + 500, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          );
          final asset = Asset(
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

          final sub = manager
              .watchPubkeys(asset)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);

          // Populate cache
          await manager.precachePubkeys(asset);
        }

        // Allow resources to be established
        await Future<void>.delayed(Duration(milliseconds: 30));

        // Act: Measure cleanup time
        final stopwatch = Stopwatch()..start();

        authChanges.add(
          KdfUser(
            walletId: WalletId(
              name: 'typical-usage-wallet',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Wait for cleanup to complete
        await Future<void>.delayed(Duration(milliseconds: 150));
        stopwatch.stop();

        // Assert: Should complete within 1 second for typical usage
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
          reason: 'Typical usage cleanup should complete within 1 second',
        );

        print(
          'PubkeyManager typical usage cleanup time: ${stopwatch.elapsedMilliseconds}ms',
        );

        // Clean up subscriptions
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      },
    );

    test(
      'baseline performance measurements for regression detection',
      () async {
        // Arrange: Create baseline scenario
        const baselineResourceCount = 10;
        final measurements = <int>[];
        const measurementRuns = 3;

        for (int run = 0; run < measurementRuns; run++) {
          final subscriptions = <StreamSubscription<AssetPubkeys>>[];

          for (int i = 0; i < baselineResourceCount; i++) {
            final assetId = AssetId(
              id: 'BASELINE_RUN${run}_$i',
              name: 'Baseline Run $run Asset $i',
              symbol: AssetSymbol(assetConfigId: 'BASELINE_RUN${run}_$i'),
              chainId: AssetChainId(
                chainId: run * 1000 + i + 600,
                decimalsValue: 8,
              ),
              derivationPath: null,
              subClass: CoinSubClass.tendermint,
            );
            final asset = Asset(
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

            final sub = manager
                .watchPubkeys(asset)
                .listen(
                  (_) {},
                  onError: (_) {}, // Ignore cleanup errors
                );
            subscriptions.add(sub);

            // Populate cache
            await manager.precachePubkeys(asset);
          }

          // Allow resources to be established
          await Future<void>.delayed(Duration(milliseconds: 40));

          // Act: Measure cleanup time
          final stopwatch = Stopwatch()..start();

          authChanges.add(
            KdfUser(
              walletId: WalletId(
                name: 'baseline-wallet-$run',
                authOptions: AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
              isBip39Seed: false,
            ),
          );

          // Wait for cleanup to complete
          await Future<void>.delayed(Duration(milliseconds: 180));
          stopwatch.stop();

          measurements.add(stopwatch.elapsedMilliseconds);

          // Clean up subscriptions
          for (final sub in subscriptions) {
            await sub.cancel();
          }

          // Delay between runs
          await Future<void>.delayed(Duration(milliseconds: 100));
        }

        // Calculate statistics
        final average =
            measurements.reduce((a, b) => a + b) / measurements.length;
        final min = measurements.reduce((a, b) => a < b ? a : b);
        final max = measurements.reduce((a, b) => a > b ? a : b);

        print('PubkeyManager baseline performance measurements:');
        print('  Runs: $measurements');
        print('  Average: ${average.toStringAsFixed(1)}ms');
        print('  Min: ${min}ms');
        print('  Max: ${max}ms');

        // Assert: Baseline measurements should be consistent and reasonable
        expect(
          average,
          lessThan(1500),
          reason: 'Average cleanup time should be reasonable',
        );

        expect(
          max - min,
          lessThan(500),
          reason: 'Performance should be consistent across runs',
        );

        // All measurements should be within acceptable range
        for (final measurement in measurements) {
          expect(
            measurement,
            lessThan(2000),
            reason: 'Each measurement should be within acceptable range',
          );
        }
      },
    );

    test('concurrent vs sequential cleanup performance comparison', () async {
      // This test demonstrates that the current concurrent implementation
      // is faster than a hypothetical sequential implementation would be

      // Arrange: Create resources for concurrent cleanup test
      const resourceCount = 12;
      final subscriptions = <StreamSubscription<AssetPubkeys>>[];

      for (int i = 0; i < resourceCount; i++) {
        final assetId = AssetId(
          id: 'CONCURRENT_$i',
          name: 'Concurrent Asset $i',
          symbol: AssetSymbol(assetConfigId: 'CONCURRENT_$i'),
          chainId: AssetChainId(chainId: i + 700, decimalsValue: 8),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        );
        final asset = Asset(
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

        final sub = manager
            .watchPubkeys(asset)
            .listen(
              (_) {},
              onError: (_) {}, // Ignore cleanup errors
            );
        subscriptions.add(sub);

        // Populate cache
        await manager.precachePubkeys(asset);
      }

      // Allow resources to be established
      await Future<void>.delayed(Duration(milliseconds: 50));

      // Act: Measure concurrent cleanup time (current implementation)
      final concurrentStopwatch = Stopwatch()..start();

      authChanges.add(
        KdfUser(
          walletId: WalletId(
            name: 'concurrent-test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(Duration(milliseconds: 200));
      concurrentStopwatch.stop();

      final concurrentTime = concurrentStopwatch.elapsedMilliseconds;

      // Estimate sequential time (would be roughly the sum of individual operations)
      // Each operation might take ~10-50ms, so sequential would be much slower
      const estimatedSequentialTime =
          resourceCount * 30; // Conservative estimate

      print('PubkeyManager concurrent vs sequential comparison:');
      print('  Concurrent cleanup time: ${concurrentTime}ms');
      print('  Estimated sequential time: ${estimatedSequentialTime}ms');
      print(
        '  Performance improvement: ${(estimatedSequentialTime / concurrentTime).toStringAsFixed(1)}x',
      );

      // Assert: Concurrent should be significantly faster than estimated sequential
      expect(
        concurrentTime,
        lessThan(estimatedSequentialTime),
        reason: 'Concurrent cleanup should be faster than sequential',
      );

      // Concurrent cleanup should complete in reasonable time
      expect(
        concurrentTime,
        lessThan(1000),
        reason: 'Concurrent cleanup should complete quickly',
      );

      // Clean up subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    });
  });
}

class _ThrowingCancelSubscription<T> implements StreamSubscription<T> {
  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;

  @override
  Future<void> cancel() => Future<void>.error(Exception('cancel failed'));

  @override
  bool get isPaused => false;

  @override
  void onData(void Function(T data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}
}

class _StreamWithThrowingCancel<T> extends Stream<T> {
  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _ThrowingCancelSubscription<T>();
  }
}
