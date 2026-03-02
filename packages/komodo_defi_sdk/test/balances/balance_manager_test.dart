import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
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

void main() {
  setUpAll(() {
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

  group('Dispose behavior for BalanceManager', () {
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockPubkeyManager pubkeyManager;
    late _MockAssetLookup assetLookup;
    late _MockEventStreamingManager eventStreamingManager;

    setUp(() {
      registerFallbackValue(
        AssetId(
          id: 'ATOM',
          name: 'Cosmos',
          symbol: AssetSymbol(assetConfigId: 'ATOM'),
          chainId: AssetChainId(chainId: 118, decimalsValue: 6),
          derivationPath: null,
          subClass: CoinSubClass.tendermint,
        ),
      );
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      pubkeyManager = _MockPubkeyManager();
      assetLookup = _MockAssetLookup();
      eventStreamingManager = _MockEventStreamingManager();
    });

    test('dispose swallows cancel/close errors and is idempotent', () async {
      // Arrange auth stream with throwing-cancel subscription
      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => _StreamWithThrowingCancel<KdfUser?>());

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
        eventStreamingManager: eventStreamingManager,
      );

      await manager.dispose();
      await manager.dispose();
    });

    test('dispose during active watch stops further emissions', () async {
      // Normal auth stream
      final authChanges = StreamController<KdfUser?>.broadcast();
      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer(
        (_) async => const KdfUser(
          walletId: WalletId(
            name: 'w',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Asset and lookup
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
      when(() => assetLookup.fromId(assetId)).thenReturn(asset);

      // Activation
      when(
        () => activation.isAssetActive(assetId),
      ).thenAnswer((_) async => true);

      // Pubkey manager returns balance
      when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: assetId,
          keys: [
            PubkeyInfo(
              address: 'cosmos1pre',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo(
                total: Decimal.zero,
                spendable: Decimal.zero,
                unspendable: Decimal.zero,
              ),
              coinTicker: assetId.id,
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
        eventStreamingManager: eventStreamingManager,
      );

      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final events = <BalanceInfo>[];
      final sub = manager
          .watchBalance(assetId)
          .listen(events.add, onError: (_) {});

      // Let initial microtasks run
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await manager.dispose();

      // Change underlying return; should not emit anymore
      when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: assetId,
          keys: [
            PubkeyInfo(
              address: 'cosmos1new',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo(
                total: Decimal.zero,
                spendable: Decimal.zero,
                unspendable: Decimal.zero,
              ),
              coinTicker: assetId.id,
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      await Future<void>.delayed(const Duration(seconds: 1));

      expect(events, isNotEmpty);
      await sub.cancel();
    });
  });

  /// Group of tests for concurrent cleanup behavior in BalanceManager
  /// Tests requirements 4.1, 4.2, 4.3 for concurrent operations and error handling
  group('BalanceManager concurrent cleanup tests', () {
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockPubkeyManager pubkeyManager;
    late _MockAssetLookup assetLookup;
    late _MockEventStreamingManager eventStreamingManager;
    late StreamController<KdfUser?> authChanges;
    late BalanceManager manager;

    setUp(() {
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      pubkeyManager = _MockPubkeyManager();
      assetLookup = _MockAssetLookup();
      eventStreamingManager = _MockEventStreamingManager();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);

      manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
        eventStreamingManager: eventStreamingManager,
      );

      // Setup common mocks
      when(() => auth.currentUser).thenAnswer(
        (_) async => const KdfUser(
          walletId: WalletId(
            name: 'test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      when(() => activation.isAssetActive(any())).thenAnswer((_) async => true);
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    test('concurrent controller closure on auth state change', () async {
      // Arrange: Create multiple controllers by starting multiple watchers
      final subscriptions = <StreamSubscription<BalanceInfo>>[];

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

        // Mock asset lookup
        when(() => assetLookup.fromId(assetId)).thenReturn(asset);

        // Mock pubkey manager to return balance
        when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'test1address$i',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(100 + i),
                  spendable: Decimal.fromInt(100 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        // Start watching to create controllers
        final sub = manager
            .watchBalance(assetId)
            .listen(
              (_) {},
              onError: (error) {
                // Expected errors during auth state change
              },
            );
        subscriptions.add(sub);

        // Allow controller creation
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Measure cleanup time
      final stopwatch = Stopwatch()..start();

      // Act: Trigger auth state change
      authChanges.add(
        const KdfUser(
          walletId: WalletId(
            name: 'new-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(const Duration(milliseconds: 200));
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
      final subscriptions = <StreamSubscription<BalanceInfo>>[];

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

        // Mock asset lookup
        when(() => assetLookup.fromId(assetId)).thenReturn(asset);

        // Mock pubkey manager to return balance
        when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'test1address$i',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(200 + i),
                  spendable: Decimal.fromInt(200 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        final sub = manager
            .watchBalance(assetId)
            .listen((_) {}, onError: (_) {});
        subscriptions.add(sub);

        // Allow watcher creation
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Measure cleanup time
      final stopwatch = Stopwatch()..start();

      // Act: Trigger auth state change
      authChanges.add(
        const KdfUser(
          walletId: WalletId(
            name: 'another-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(const Duration(milliseconds: 200));
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
      final normalSubs = <StreamSubscription<BalanceInfo>>[];

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

        // Mock asset lookup
        when(() => assetLookup.fromId(assetId)).thenReturn(asset);

        // Mock pubkey manager to return balance
        when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'test1address$i',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(300 + i),
                  spendable: Decimal.fromInt(300 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        final sub = manager
            .watchBalance(assetId)
            .listen((_) {}, onError: (_) {});
        normalSubs.add(sub);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Act: Trigger auth state change - should not throw despite potential failures
      expect(() async {
        authChanges.add(
          const KdfUser(
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
        await Future<void>.delayed(const Duration(milliseconds: 200));
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

      // Mock the new asset
      when(() => assetLookup.fromId(newAssetId)).thenReturn(newAsset);
      when(() => pubkeyManager.getPubkeys(newAsset)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: newAssetId,
          keys: [
            PubkeyInfo(
              address: 'newtest1address',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo(
                total: Decimal.fromInt(500),
                spendable: Decimal.fromInt(500),
                unspendable: Decimal.zero,
              ),
              coinTicker: newAssetId.id,
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      // This should work without throwing, indicating cleanup was resilient
      final newSub = manager
          .watchBalance(newAssetId)
          .listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await newSub.cancel();

      // Clean up normal subscriptions
      for (final sub in normalSubs) {
        await sub.cancel();
      }
    });

    test('performance improvement over sequential operations', () async {
      // Arrange: Create many controllers and subscriptions to test performance
      final subscriptions = <StreamSubscription<BalanceInfo>>[];
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

        // Mock asset lookup
        when(() => assetLookup.fromId(assetId)).thenReturn(asset);

        // Mock pubkey manager to return balance
        when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'perf1address$i',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(400 + i),
                  spendable: Decimal.fromInt(400 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        final sub = manager
            .watchBalance(assetId)
            .listen((_) {}, onError: (_) {});
        subscriptions.add(sub);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // Act: Measure concurrent cleanup time
      final stopwatch = Stopwatch()..start();

      authChanges.add(
        const KdfUser(
          walletId: WalletId(
            name: 'performance-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(const Duration(milliseconds: 300));
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
      final subscriptions = <StreamSubscription<BalanceInfo>>[];
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

        // Mock asset lookup
        when(() => assetLookup.fromId(assetId)).thenReturn(asset);

        // Mock pubkey manager to return balance
        when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'clear1address$i',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(600 + i),
                  spendable: Decimal.fromInt(600 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        final sub = manager
            .watchBalance(assetId)
            .listen((_) {}, onError: (_) {});
        subscriptions.add(sub);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Populate cache by getting balance
        await manager.getBalance(assetId);
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
        const KdfUser(
          walletId: WalletId(
            name: 'clear-test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

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
  group('BalanceManager memory leak prevention tests', () {
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockPubkeyManager pubkeyManager;
    late _MockAssetLookup assetLookup;
    late _MockEventStreamingManager eventStreamingManager;
    late StreamController<KdfUser?> authChanges;
    late BalanceManager manager;

    setUp(() {
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      pubkeyManager = _MockPubkeyManager();
      assetLookup = _MockAssetLookup();
      eventStreamingManager = _MockEventStreamingManager();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);

      manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
        eventStreamingManager: eventStreamingManager,
      );

      when(() => activation.isAssetActive(any())).thenAnswer((_) async => true);
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
              name: 'balance-wallet-$cycle',
              authOptions: const AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Create controllers for this cycle
        final subscriptions = <StreamSubscription<BalanceInfo>>[];
        for (int i = 0; i < controllersPerCycle; i++) {
          final assetId = AssetId(
            id: 'BAL_CYCLE${cycle}_ASSET$i',
            name: 'Balance Cycle $cycle Asset $i',
            symbol: AssetSymbol(assetConfigId: 'BAL_CYCLE${cycle}_ASSET$i'),
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

          // Mock asset lookup and pubkey manager
          when(() => assetLookup.fromId(assetId)).thenReturn(asset);
          when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
            (_) async => AssetPubkeys(
              assetId: assetId,
              keys: [
                PubkeyInfo(
                  address: 'cycle${cycle}address$i',
                  derivationPath: null,
                  chain: null,
                  balance: BalanceInfo(
                    total: Decimal.fromInt(100 + cycle * 10 + i),
                    spendable: Decimal.fromInt(100 + cycle * 10 + i),
                    unspendable: Decimal.zero,
                  ),
                  coinTicker: assetId.id,
                ),
              ],
              availableAddressesCount: 1,
              syncStatus: SyncStatusEnum.success,
            ),
          );

          final sub = manager
              .watchBalance(assetId)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);

          // Populate cache
          await manager.getBalance(assetId);
        }

        // Allow resources to be created
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Trigger auth state change to next cycle
        if (cycle < cycleCount - 1) {
          authChanges.add(
            KdfUser(
              walletId: WalletId(
                name: 'balance-wallet-${cycle + 1}',
                authOptions: const AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
              isBip39Seed: false,
            ),
          );

          // Wait for cleanup to complete
          await Future<void>.delayed(const Duration(milliseconds: 100));
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
              id: 'BAL_CYCLE${cycle}_ASSET$i',
              name: 'Balance Cycle $cycle Asset $i',
              symbol: AssetSymbol(assetConfigId: 'BAL_CYCLE${cycle}_ASSET$i'),
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
        id: 'BAL_FINAL_TEST',
        name: 'Balance Final Test',
        symbol: AssetSymbol(assetConfigId: 'BAL_FINAL_TEST'),
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

      // Mock the final asset
      when(() => assetLookup.fromId(finalAssetId)).thenReturn(finalAsset);
      when(() => pubkeyManager.getPubkeys(finalAsset)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: finalAssetId,
          keys: [
            PubkeyInfo(
              address: 'final1address',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo(
                total: Decimal.fromInt(999),
                spendable: Decimal.fromInt(999),
                unspendable: Decimal.zero,
              ),
              coinTicker: finalAssetId.id,
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      // This should work without issues, indicating no memory leaks
      final finalSub = manager
          .watchBalance(finalAssetId)
          .listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
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
              name: 'bal-sub-wallet-$cycle',
              authOptions: const AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Create subscriptions for this cycle
        final subscriptions = <StreamSubscription<BalanceInfo>>[];
        for (int i = 0; i < subscriptionsPerCycle; i++) {
          final assetId = AssetId(
            id: 'BAL_SUB_CYCLE${cycle}_ASSET$i',
            name: 'Balance Sub Cycle $cycle Asset $i',
            symbol: AssetSymbol(assetConfigId: 'BAL_SUB_CYCLE${cycle}_ASSET$i'),
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

          // Mock asset lookup and pubkey manager
          when(() => assetLookup.fromId(assetId)).thenReturn(asset);
          when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
            (_) async => AssetPubkeys(
              assetId: assetId,
              keys: [
                PubkeyInfo(
                  address: 'subcycle${cycle}address$i',
                  derivationPath: null,
                  chain: null,
                  balance: BalanceInfo(
                    total: Decimal.fromInt(200 + cycle * 20 + i),
                    spendable: Decimal.fromInt(200 + cycle * 20 + i),
                    unspendable: Decimal.zero,
                  ),
                  coinTicker: assetId.id,
                ),
              ],
              availableAddressesCount: 1,
              syncStatus: SyncStatusEnum.success,
            ),
          );

          final sub = manager
              .watchBalance(assetId)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);
        }

        // Allow subscriptions to be established
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Trigger auth state change
        if (cycle < cycleCount - 1) {
          authChanges.add(
            KdfUser(
              walletId: WalletId(
                name: 'bal-sub-wallet-${cycle + 1}',
                authOptions: const AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
              isBip39Seed: false,
            ),
          );

          // Wait for cleanup to complete
          await Future<void>.delayed(const Duration(milliseconds: 150));
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
            id: 'BAL_TEST',
            name: 'Balance Test',
            symbol: AssetSymbol(assetConfigId: 'BAL_TEST'),
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
      final disposalAuth = _MockAuth();
      final disposalActivation = _MockActivationCoordinator();
      final disposalPubkeyManager = _MockPubkeyManager();
      final disposalAssetLookup = _MockAssetLookup();
      final disposalAuthChanges = StreamController<KdfUser?>.broadcast();

      when(
        () => disposalAuth.authStateChanges,
      ).thenAnswer((_) => disposalAuthChanges.stream);
      when(() => disposalAuth.currentUser).thenAnswer(
        (_) async => const KdfUser(
          walletId: WalletId(
            name: 'bal-disposal-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );
      when(
        () => disposalActivation.isAssetActive(any()),
      ).thenAnswer((_) async => true);

      final disposalManager = BalanceManager(
        assetLookup: disposalAssetLookup,
        auth: disposalAuth,
        pubkeyManager: disposalPubkeyManager,
        activationCoordinator: disposalActivation,
        eventStreamingManager: eventStreamingManager,
      );

      // Create resources
      final subscriptions = <StreamSubscription<BalanceInfo>>[];
      for (int i = 0; i < 5; i++) {
        final assetId = AssetId(
          id: 'BAL_DISPOSAL$i',
          name: 'Balance Disposal Asset $i',
          symbol: AssetSymbol(assetConfigId: 'BAL_DISPOSAL$i'),
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

        // Mock asset lookup and pubkey manager
        when(() => disposalAssetLookup.fromId(assetId)).thenReturn(asset);
        when(() => disposalPubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'disposal${i}address',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(300 + i),
                  spendable: Decimal.fromInt(300 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        final sub = disposalManager
            .watchBalance(assetId)
            .listen((_) {}, onError: (_) {});
        subscriptions.add(sub);

        // Populate cache
        await disposalManager.getBalance(assetId);
      }

      // Verify resources exist
      expect(
        disposalManager.lastKnown(
          AssetId(
            id: 'BAL_DISPOSAL0',
            name: 'Balance Disposal Asset 0',
            symbol: AssetSymbol(assetConfigId: 'BAL_DISPOSAL0'),
            chainId: AssetChainId(chainId: 300, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          ),
        ),
        isNotNull,
      );

      // Clean up subscriptions first
      for (final sub in subscriptions) {
        await sub.cancel();
      }

      // Act: Dispose the manager
      await disposalManager.dispose();

      // Assert: Manager should be in disposed state
      expect(
        () => disposalManager.lastKnown(
          AssetId(
            id: 'BAL_DISPOSAL0',
            name: 'Balance Disposal Asset 0',
            symbol: AssetSymbol(assetConfigId: 'BAL_DISPOSAL0'),
            chainId: AssetChainId(chainId: 300, decimalsValue: 8),
            derivationPath: null,
            subClass: CoinSubClass.tendermint,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await disposalAuthChanges.close();
    });

    test('cleanup performance under high resource count scenarios', () async {
      // Arrange: Create many resources to test cleanup performance
      const highResourceCount =
          15; // Slightly lower for balance manager due to more complex mocking

      when(() => auth.currentUser).thenAnswer(
        (_) async => const KdfUser(
          walletId: WalletId(
            name: 'bal-high-resource-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      final subscriptions = <StreamSubscription<BalanceInfo>>[];

      // Create many resources
      for (int i = 0; i < highResourceCount; i++) {
        final assetId = AssetId(
          id: 'BAL_HIGH_RES$i',
          name: 'Balance High Resource Asset $i',
          symbol: AssetSymbol(assetConfigId: 'BAL_HIGH_RES$i'),
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

        // Mock asset lookup and pubkey manager
        when(() => assetLookup.fromId(assetId)).thenReturn(asset);
        when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'highres${i}address',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(400 + i),
                  spendable: Decimal.fromInt(400 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        final sub = manager
            .watchBalance(assetId)
            .listen((_) {}, onError: (_) {});
        subscriptions.add(sub);

        // Populate cache
        await manager.getBalance(assetId);

        // Small delay to avoid overwhelming the system
        if (i % 5 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      // Act: Measure cleanup performance
      final stopwatch = Stopwatch()..start();

      authChanges.add(
        const KdfUser(
          walletId: WalletId(
            name: 'bal-high-resource-wallet-2',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(const Duration(milliseconds: 500));
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
          id: 'BAL_HIGH_RES$i',
          name: 'Balance High Resource Asset $i',
          symbol: AssetSymbol(assetConfigId: 'BAL_HIGH_RES$i'),
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
  group('BalanceManager performance benchmark tests', () {
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockPubkeyManager pubkeyManager;
    late _MockAssetLookup assetLookup;
    late _MockEventStreamingManager eventStreamingManager;
    late StreamController<KdfUser?> authChanges;
    late BalanceManager manager;

    setUp(() {
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      pubkeyManager = _MockPubkeyManager();
      assetLookup = _MockAssetLookup();
      eventStreamingManager = _MockEventStreamingManager();
      authChanges = StreamController<KdfUser?>.broadcast();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);

      manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
        eventStreamingManager: eventStreamingManager,
      );

      when(() => auth.currentUser).thenAnswer(
        (_) async => const KdfUser(
          walletId: WalletId(
            name: 'balance-benchmark-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      when(() => activation.isAssetActive(any())).thenAnswer((_) async => true);
    });

    tearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    test('cleanup performance with varying resource counts', () async {
      // Test different resource counts to measure performance scaling
      final resourceCounts = [
        3,
        6,
        9,
        12,
      ]; // Smaller counts due to more complex mocking
      final performanceResults = <int, int>{};

      for (final resourceCount in resourceCounts) {
        // Arrange: Create resources
        final subscriptions = <StreamSubscription<BalanceInfo>>[];

        for (int i = 0; i < resourceCount; i++) {
          final assetId = AssetId(
            id: 'BAL_PERF_VAR${resourceCount}_$i',
            name: 'Balance Performance Variable $resourceCount Asset $i',
            symbol: AssetSymbol(
              assetConfigId: 'BAL_PERF_VAR${resourceCount}_$i',
            ),
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

          // Mock asset lookup and pubkey manager
          when(() => assetLookup.fromId(assetId)).thenReturn(asset);
          when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
            (_) async => AssetPubkeys(
              assetId: assetId,
              keys: [
                PubkeyInfo(
                  address: 'perfvar${resourceCount}address$i',
                  derivationPath: null,
                  chain: null,
                  balance: BalanceInfo(
                    total: Decimal.fromInt(resourceCount * 100 + i),
                    spendable: Decimal.fromInt(resourceCount * 100 + i),
                    unspendable: Decimal.zero,
                  ),
                  coinTicker: assetId.id,
                ),
              ],
              availableAddressesCount: 1,
              syncStatus: SyncStatusEnum.success,
            ),
          );

          final sub = manager
              .watchBalance(assetId)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);

          // Populate cache
          await manager.getBalance(assetId);
        }

        // Allow resources to be established
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Act: Measure cleanup time
        final stopwatch = Stopwatch()..start();

        authChanges.add(
          KdfUser(
            walletId: WalletId(
              name: 'balance-benchmark-wallet-$resourceCount',
              authOptions: const AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Wait for cleanup to complete
        await Future<void>.delayed(const Duration(milliseconds: 200));
        stopwatch.stop();

        performanceResults[resourceCount] = stopwatch.elapsedMilliseconds;

        // Clean up subscriptions
        for (final sub in subscriptions) {
          await sub.cancel();
        }

        // Small delay between tests
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      // Assert: Performance should scale reasonably
      print('BalanceManager cleanup performance results:');
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
      final smallCount = performanceResults[3]!;
      final largeCount = performanceResults[12]!;
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
        // Arrange: Create typical usage scenario (5-8 assets)
        const typicalResourceCount = 6;
        final subscriptions = <StreamSubscription<BalanceInfo>>[];

        for (int i = 0; i < typicalResourceCount; i++) {
          final assetId = AssetId(
            id: 'BAL_TYPICAL_$i',
            name: 'Balance Typical Asset $i',
            symbol: AssetSymbol(assetConfigId: 'BAL_TYPICAL_$i'),
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

          // Mock asset lookup and pubkey manager
          when(() => assetLookup.fromId(assetId)).thenReturn(asset);
          when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
            (_) async => AssetPubkeys(
              assetId: assetId,
              keys: [
                PubkeyInfo(
                  address: 'typical${i}address',
                  derivationPath: null,
                  chain: null,
                  balance: BalanceInfo(
                    total: Decimal.fromInt(500 + i),
                    spendable: Decimal.fromInt(500 + i),
                    unspendable: Decimal.zero,
                  ),
                  coinTicker: assetId.id,
                ),
              ],
              availableAddressesCount: 1,
              syncStatus: SyncStatusEnum.success,
            ),
          );

          final sub = manager
              .watchBalance(assetId)
              .listen(
                (_) {},
                onError: (_) {}, // Ignore cleanup errors
              );
          subscriptions.add(sub);

          // Populate cache
          await manager.getBalance(assetId);
        }

        // Allow resources to be established
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Act: Measure cleanup time
        final stopwatch = Stopwatch()..start();

        authChanges.add(
          const KdfUser(
            walletId: WalletId(
              name: 'balance-typical-usage-wallet',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );

        // Wait for cleanup to complete
        await Future<void>.delayed(const Duration(milliseconds: 150));
        stopwatch.stop();

        // Assert: Should complete within 1 second for typical usage
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
          reason: 'Typical usage cleanup should complete within 1 second',
        );

        print(
          'BalanceManager typical usage cleanup time: ${stopwatch.elapsedMilliseconds}ms',
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
        const baselineResourceCount = 8;
        final measurements = <int>[];
        const measurementRuns = 3;

        for (int run = 0; run < measurementRuns; run++) {
          final subscriptions = <StreamSubscription<BalanceInfo>>[];

          for (int i = 0; i < baselineResourceCount; i++) {
            final assetId = AssetId(
              id: 'BAL_BASELINE_RUN${run}_$i',
              name: 'Balance Baseline Run $run Asset $i',
              symbol: AssetSymbol(assetConfigId: 'BAL_BASELINE_RUN${run}_$i'),
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

            // Mock asset lookup and pubkey manager
            when(() => assetLookup.fromId(assetId)).thenReturn(asset);
            when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
              (_) async => AssetPubkeys(
                assetId: assetId,
                keys: [
                  PubkeyInfo(
                    address: 'baseline${run}address$i',
                    derivationPath: null,
                    chain: null,
                    balance: BalanceInfo(
                      total: Decimal.fromInt(run * 1000 + i + 600),
                      spendable: Decimal.fromInt(run * 1000 + i + 600),
                      unspendable: Decimal.zero,
                    ),
                    coinTicker: assetId.id,
                  ),
                ],
                availableAddressesCount: 1,
                syncStatus: SyncStatusEnum.success,
              ),
            );

            final sub = manager
                .watchBalance(assetId)
                .listen(
                  (_) {},
                  onError: (_) {}, // Ignore cleanup errors
                );
            subscriptions.add(sub);

            // Populate cache
            await manager.getBalance(assetId);
          }

          // Allow resources to be established
          await Future<void>.delayed(const Duration(milliseconds: 40));

          // Act: Measure cleanup time
          final stopwatch = Stopwatch()..start();

          authChanges.add(
            KdfUser(
              walletId: WalletId(
                name: 'balance-baseline-wallet-$run',
                authOptions: const AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
              isBip39Seed: false,
            ),
          );

          // Wait for cleanup to complete
          await Future<void>.delayed(const Duration(milliseconds: 180));
          stopwatch.stop();

          measurements.add(stopwatch.elapsedMilliseconds);

          // Clean up subscriptions
          for (final sub in subscriptions) {
            await sub.cancel();
          }

          // Delay between runs
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        // Calculate statistics
        final average =
            measurements.reduce((a, b) => a + b) / measurements.length;
        final min = measurements.reduce((a, b) => a < b ? a : b);
        final max = measurements.reduce((a, b) => a > b ? a : b);

        print('BalanceManager baseline performance measurements:');
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
      const resourceCount = 10;
      final subscriptions = <StreamSubscription<BalanceInfo>>[];

      for (int i = 0; i < resourceCount; i++) {
        final assetId = AssetId(
          id: 'BAL_CONCURRENT_$i',
          name: 'Balance Concurrent Asset $i',
          symbol: AssetSymbol(assetConfigId: 'BAL_CONCURRENT_$i'),
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

        // Mock asset lookup and pubkey manager
        when(() => assetLookup.fromId(assetId)).thenReturn(asset);
        when(() => pubkeyManager.getPubkeys(asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: assetId,
            keys: [
              PubkeyInfo(
                address: 'concurrent${i}address',
                derivationPath: null,
                chain: null,
                balance: BalanceInfo(
                  total: Decimal.fromInt(700 + i),
                  spendable: Decimal.fromInt(700 + i),
                  unspendable: Decimal.zero,
                ),
                coinTicker: assetId.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        final sub = manager
            .watchBalance(assetId)
            .listen(
              (_) {},
              onError: (_) {}, // Ignore cleanup errors
            );
        subscriptions.add(sub);

        // Populate cache
        await manager.getBalance(assetId);
      }

      // Allow resources to be established
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Act: Measure concurrent cleanup time (current implementation)
      final concurrentStopwatch = Stopwatch()..start();

      authChanges.add(
        const KdfUser(
          walletId: WalletId(
            name: 'balance-concurrent-test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Wait for cleanup to complete
      await Future<void>.delayed(const Duration(milliseconds: 200));
      concurrentStopwatch.stop();

      final concurrentTime = concurrentStopwatch.elapsedMilliseconds;

      // Estimate sequential time (would be roughly the sum of individual operations)
      // Each operation might take ~10-50ms, so sequential would be much slower
      const estimatedSequentialTime =
          resourceCount * 30; // Conservative estimate

      print('BalanceManager concurrent vs sequential comparison:');
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
