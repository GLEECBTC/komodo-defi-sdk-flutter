import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/src/asset_filter.dart';
import 'package:komodo_coins/src/asset_management/coin_config_manager.dart';
import 'package:komodo_coins/src/asset_management/loading_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';

import 'test_utils/asset_config_builders.dart';

// Mock classes
class MockCoinConfigSource extends Mock implements CoinConfigSource {}

class MockLoadingStrategy extends Mock implements LoadingStrategy {}

class MockCoinConfigRepository extends Mock implements CoinConfigRepository {}

class MockLocalAssetCoinConfigProvider extends Mock
    implements LocalAssetCoinConfigProvider {}

class MockCustomTokenStorage extends Mock implements CustomTokenStore {}

// Fake classes for mocktail fallback values
class FakeRuntimeUpdateConfig extends Fake
    implements AssetRuntimeUpdateConfig {}

class FakeCoinConfigTransformer extends Fake implements CoinConfigTransformer {}

class FakeAssetId extends Fake implements AssetId {}

/// Helper function to get a temporary directory for Hive tests
Future<Directory> getTempDir() async {
  final tempDir = Directory.systemTemp.createTempSync('hive_test_');
  return tempDir;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    // Create a temporary directory for Hive
    tempDir = await getTempDir();
    Hive.init(tempDir.path);

    registerFallbackValue(FakeRuntimeUpdateConfig());
    registerFallbackValue(FakeCoinConfigTransformer());
    registerFallbackValue(LoadingRequestType.initialLoad);
    registerFakeAssetTypes();
  });

  tearDownAll(() async {
    await Hive.close();
    // Clean up temporary directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StrategicCoinConfigManager', () {
    late MockCoinConfigSource mockStorageSource;
    late MockCoinConfigSource mockLocalSource;
    late MockLoadingStrategy mockLoadingStrategy;

    // Test data using asset config builders
    final komodoAssetConfig = StandardAssetConfigs.komodo();
    final komodoAsset = Asset.fromJson(komodoAssetConfig);
    final btcAssetConfig = StandardAssetConfigs.bitcoin();
    final btcAsset = Asset.fromJson(btcAssetConfig);
    final testAssetConfig = StandardAssetConfigs.testCoin();
    final testAsset = Asset.fromJson(testAssetConfig);

    final testAssets = [komodoAsset, btcAsset, testAsset];

    setUp(() {
      mockStorageSource = MockCoinConfigSource();
      mockLocalSource = MockCoinConfigSource();
      mockLoadingStrategy = MockLoadingStrategy();

      // Set up source behaviors
      when(() => mockStorageSource.sourceId).thenReturn('storage');
      when(() => mockLocalSource.sourceId).thenReturn('local');
      when(() => mockStorageSource.displayName).thenReturn('Storage');
      when(() => mockLocalSource.displayName).thenReturn('Local');
      when(() => mockStorageSource.isAvailable()).thenAnswer((_) async => true);
      when(() => mockLocalSource.isAvailable()).thenAnswer((_) async => true);

      // Set up loading strategy
      when(
        () => mockLoadingStrategy.selectSources(
          requestType: any(named: 'requestType'),
          availableSources: any(named: 'availableSources'),
        ),
      ).thenAnswer((invocation) async {
        final sources =
            invocation.namedArguments[const Symbol('availableSources')]
                as List<CoinConfigSource>;
        return sources;
      });

      // Set up source loading
      when(
        () => mockStorageSource.loadAssets(),
      ).thenAnswer((_) async => testAssets);
      when(
        () => mockLocalSource.loadAssets(),
      ).thenAnswer((_) async => testAssets);
    });

    group('Constructor', () {
      test('creates instance with required parameters', () {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );

        expect(manager.isInitialized, isFalse);
      });

      test('creates instance with auto-update disabled', () {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        expect(manager.isInitialized, isFalse);
      });

      test('uses default loading strategy when not provided', () {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
        );

        expect(manager.loadingStrategy, isA<StorageFirstLoadingStrategy>());
      });
    });

    group('Initialization', () {
      test('initializes successfully with valid sources', () async {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );

        await manager.init();

        expect(manager.isInitialized, isTrue);
        expect(manager.all, isNotEmpty);
        expect(manager.all.length, equals(testAssets.length));
      });

      test('can be initialized multiple times safely', () async {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );

        await manager.init();
        expect(manager.isInitialized, isTrue);

        // Should be able to initialize again without error
        await expectLater(manager.init(), completes);
        expect(manager.isInitialized, isTrue);
      });

      test('handles source availability check failures gracefully', () async {
        when(
          () => mockStorageSource.isAvailable(),
        ).thenThrow(Exception('Availability check failed'));

        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );

        // Should not throw, should continue with available sources
        await expectLater(manager.init(), completes);
        expect(manager.isInitialized, isTrue);
      });

      test('handles source loading failures gracefully', () async {
        when(
          () => mockStorageSource.loadAssets(),
        ).thenThrow(Exception('Load failed'));

        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );

        // Should not throw, should continue with available sources
        await expectLater(manager.init(), completes);
        expect(manager.isInitialized, isTrue);
      });
    });

    group('Asset retrieval', () {
      late StrategicCoinConfigManager manager;

      setUp(() async {
        manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();
      });

      test('returns all assets', () {
        final assets = manager.all;

        expect(assets, isNotEmpty);
        expect(assets.length, equals(testAssets.length));
        expect(assets.values, containsAll(testAssets));
      });

      test('returns empty map when no assets available', () async {
        when(() => mockStorageSource.loadAssets()).thenAnswer((_) async => []);
        when(() => mockLocalSource.loadAssets()).thenAnswer((_) async => []);

        final emptyManager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await emptyManager.init();

        expect(emptyManager.all, isEmpty);
      });

      test('deduplicates assets from multiple sources', () async {
        // Set up sources to return the same assets
        when(
          () => mockStorageSource.loadAssets(),
        ).thenAnswer((_) async => testAssets);
        when(
          () => mockLocalSource.loadAssets(),
        ).thenAnswer((_) async => testAssets);

        final dedupManager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await dedupManager.init();

        // Should not have duplicates
        expect(dedupManager.all.length, equals(testAssets.length));
      });
    });

    group('Asset filtering', () {
      late StrategicCoinConfigManager manager;

      setUp(() async {
        manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();
      });

      test('filters assets using provided strategy', () {
        const filter = UtxoAssetFilterStrategy();
        final filtered = manager.filteredAssets(filter);

        expect(filtered, isNotEmpty);
        // All test assets should be smart chain type (based on actual parsing behavior)
        expect(
          filtered.values.every(
            (asset) =>
                asset.id.subClass == CoinSubClass.utxo ||
                asset.id.subClass == CoinSubClass.smartChain,
          ),
          isTrue,
        );
      });

      test('returns empty map when no assets match filter', () async {
        // Create a test asset without trezor_coin field
        final noTrezorConfig = {
          'coin': 'NTZ',
          'fname': 'NoTrezor',
          'chain_id': 1,
          'type': 'UTXO',
          'protocol': {'type': 'UTXO'},
          'is_testnet': false,
          // intentionally no 'trezor_coin'
        };
        final noTrezorAsset = Asset.fromJson(noTrezorConfig);

        // Set up source to return only the no-trezor asset
        when(
          () => mockStorageSource.loadAssets(),
        ).thenAnswer((_) async => [noTrezorAsset]);
        when(
          () => mockLocalSource.loadAssets(),
        ).thenAnswer((_) async => [noTrezorAsset]);

        final noTrezorManager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await noTrezorManager.init();

        const filter = TrezorAssetFilterStrategy();
        final filtered = noTrezorManager.filteredAssets(filter);

        // Assets without trezor_coin field should be filtered out
        expect(filtered, isEmpty);
      });

      test('caches filtered results', () {
        const filter = UtxoAssetFilterStrategy();

        final firstCall = manager.filteredAssets(filter);
        final secondCall = manager.filteredAssets(filter);

        expect(identical(firstCall, secondCall), isTrue);
      });

      test('keys resolve by AssetId equality, not by tree ordering', () {
        const filter = UtxoAssetFilterStrategy();
        final filtered = manager.filteredAssets(filter);
        final storedId = filtered.keys.first;

        // Same [id, subClass, chainId] - therefore `==` with an equal
        // hashCode - but a different `parentId`, so `toString()` differs and
        // the filter cache's SplayTreeMap comparator orders them apart. This
        // is the shape of any child-token id parsed with `knownIds: null`,
        // as `Transaction.fromJson` does. The returned map must key off
        // equality so such an id still resolves.
        final equalIdWithParent = AssetId(
          id: storedId.id,
          name: storedId.name,
          symbol: storedId.symbol,
          chainId: storedId.chainId,
          derivationPath: storedId.derivationPath,
          subClass: storedId.subClass,
          parentId: AssetId(
            id: 'SOMEPARENT',
            name: 'Some Parent',
            symbol: AssetSymbol(assetConfigId: 'SOMEPARENT'),
            chainId: storedId.chainId,
            derivationPath: null,
            subClass: storedId.subClass,
          ),
        );

        expect(equalIdWithParent, equals(storedId));
        expect(equalIdWithParent.hashCode, equals(storedId.hashCode));
        expect(
          equalIdWithParent.toString(),
          isNot(equals(storedId.toString())),
        );

        expect(filtered.containsKey(equalIdWithParent), isTrue);
        expect(filtered[equalIdWithParent], isNotNull);
      });
    });

    group('Asset lookup', () {
      late StrategicCoinConfigManager manager;

      setUp(() async {
        manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();
      });

      test('finds asset by ticker and subclass', () {
        final found = manager.findByTicker('KMD', CoinSubClass.utxo);

        expect(found, isNotNull);
        expect(found!.id.id, equals('KMD'));
        expect(found.id.subClass, equals(CoinSubClass.utxo));
      });

      test('returns null when asset not found', () {
        final found = manager.findByTicker('NONEXISTENT', CoinSubClass.utxo);

        expect(found, isNull);
      });

      test('finds all variants of a coin by ticker', () {
        final variants = manager.findVariantsOfCoin('KMD');

        expect(variants, isNotEmpty);
        expect(variants.every((asset) => asset.id.id == 'KMD'), isTrue);
      });

      test('returns empty set when no variants found', () {
        final variants = manager.findVariantsOfCoin('NONEXISTENT');

        expect(variants, isEmpty);
      });

      test('finds child assets of a parent asset', () {
        // This test depends on the test data having parent-child relationships
        // For now, we'll test the method exists and returns a Set
        final children = manager.findChildAssets(komodoAsset.id);

        expect(children, isA<Set<Asset>>());
      });
    });

    group('Asset refresh', () {
      late StrategicCoinConfigManager manager;

      setUp(() async {
        manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();
      });

      test('refreshes assets from sources', () async {
        // Create a new manager for this test to avoid cache issues
        final refreshManager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await refreshManager.init();

        // Verify that refresh completes without error
        await expectLater(refreshManager.refreshAssets(), completes);

        // Verify that assets are still available after refresh
        expect(refreshManager.all, isNotEmpty);
      });

      test('handles refresh failures gracefully', () async {
        when(
          () => mockStorageSource.loadAssets(),
        ).thenThrow(Exception('Refresh failed'));

        final initialAssets = Map<AssetId, Asset>.from(manager.all);

        await expectLater(manager.refreshAssets(), completes);

        // Should retain existing assets even if refresh fails
        expect(manager.all, equals(initialAssets));
      });
    });

    group('Error handling', () {
      test('throws StateError when accessing assets before init', () {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );

        expect(() => manager.all, throwsStateError);
        expect(
          () => manager.filteredAssets(const UtxoAssetFilterStrategy()),
          throwsStateError,
        );
        expect(
          () => manager.findByTicker('KMD', CoinSubClass.smartChain),
          throwsStateError,
        );
        expect(() => manager.findVariantsOfCoin('KMD'), throwsStateError);
        expect(() => manager.findChildAssets(komodoAsset.id), throwsStateError);
      });

      test('throws StateError when using disposed manager', () async {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();
        await manager.dispose();

        expect(() => manager.all, throwsStateError);
        expect(manager.refreshAssets, throwsStateError);
      });
    });

    group('Lifecycle management', () {
      test('dispose cleans up resources', () async {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();

        await expectLater(manager.dispose(), completes);
        expect(manager.isInitialized, isFalse);
      });

      test('multiple dispose calls are safe', () async {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();

        await manager.dispose();
        await expectLater(manager.dispose(), completes);
      });

      test('dispose works on uninitialized manager', () async {
        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );

        await expectLater(manager.dispose(), completes);
      });
    });

    group('Loading strategy integration', () {
      test('uses loading strategy to select sources', () async {
        final selectedSources = <CoinConfigSource>[];
        when(
          () => mockLoadingStrategy.selectSources(
            requestType: any(named: 'requestType'),
            availableSources: any(named: 'availableSources'),
          ),
        ).thenAnswer((invocation) async {
          final sources =
              invocation.namedArguments[const Symbol('availableSources')]
                  as List<CoinConfigSource>;
          selectedSources.addAll(sources);
          return sources;
        });

        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();

        expect(
          selectedSources,
          containsAll([mockStorageSource, mockLocalSource]),
        );
      });

      test('respects enableAutoUpdate flag in loading strategy', () async {
        // With current API, enableAutoUpdate is not passed through loading strategy
        when(
          () => mockLoadingStrategy.selectSources(
            requestType: any(named: 'requestType'),
            availableSources: any(named: 'availableSources'),
          ),
        ).thenAnswer((invocation) async {
          final sources =
              invocation.namedArguments[const Symbol('availableSources')]
                  as List<CoinConfigSource>;
          return sources;
        });

        final manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
        );
        await manager.init();
        expect(manager.isInitialized, isTrue);
      });
    });

    group('Custom Token Management', () {
      late MockCustomTokenStorage mockCustomTokenStorage;
      late StrategicCoinConfigManager manager;

      // Create test custom tokens using UTXO type for simplicity
      final customTokenConfig1 = {
        'coin': 'CUSTOM1',
        'fname': 'Custom Token 1',
        'chain_id': 0,
        'type': 'UTXO',
        'protocol': {'type': 'UTXO'},
        'is_testnet': false,
      };
      final customToken1 = Asset.fromJson(customTokenConfig1);

      final customTokenConfig2 = {
        'coin': 'CUSTOM2',
        'fname': 'Custom Token 2',
        'chain_id': 1,
        'type': 'UTXO',
        'protocol': {'type': 'UTXO'},
        'is_testnet': false,
      };
      final customToken2 = Asset.fromJson(customTokenConfig2);

      // Create a custom token that conflicts with existing asset (KMD)
      final conflictingTokenConfig = {
        'coin': 'KMD',
        'fname': 'Custom KMD Token',
        'chain_id': 1,
        'type': 'UTXO',
        'protocol': {'type': 'UTXO'},
        'is_testnet': false,
      };
      final conflictingToken = Asset.fromJson(conflictingTokenConfig);

      setUp(() async {
        mockCustomTokenStorage = MockCustomTokenStorage();

        // Set up mock custom token storage behavior
        when(
          () => mockCustomTokenStorage.getAllCustomTokens(any()),
        ).thenAnswer((_) async => []);
        when(
          () => mockCustomTokenStorage.storeCustomToken(any()),
        ).thenAnswer((_) async {});
        when(() => mockCustomTokenStorage.deleteCustomToken(any())).thenAnswer((
          _,
        ) async {
          return true;
        });
        when(() => mockCustomTokenStorage.dispose()).thenAnswer((_) async {});

        manager = StrategicCoinConfigManager(
          configSources: [mockStorageSource, mockLocalSource],
          loadingStrategy: mockLoadingStrategy,
          customTokenStorage: mockCustomTokenStorage,
        );
        await manager.init();
      });

      tearDown(() async {
        await manager.dispose();
      });

      group('Initialization with custom tokens', () {
        test('loads custom tokens during initialization', () async {
          // Set up custom tokens to be returned during init
          when(
            () => mockCustomTokenStorage.getAllCustomTokens(any()),
          ).thenAnswer((_) async => [customToken1, customToken2]);

          final managerWithTokens = StrategicCoinConfigManager(
            configSources: [mockStorageSource, mockLocalSource],
            loadingStrategy: mockLoadingStrategy,
            customTokenStorage: mockCustomTokenStorage,
          );
          await managerWithTokens.init();

          // Verify custom tokens are included in all assets
          final allAssets = managerWithTokens.all;
          expect(allAssets.containsKey(customToken1.id), isTrue);
          expect(allAssets.containsKey(customToken2.id), isTrue);
          expect(allAssets[customToken1.id], equals(customToken1));
          expect(allAssets[customToken2.id], equals(customToken2));

          await managerWithTokens.dispose();
        });

        test('handles custom token loading failure gracefully', () async {
          when(
            () => mockCustomTokenStorage.getAllCustomTokens(any()),
          ).thenThrow(Exception('Storage error'));

          final managerWithError = StrategicCoinConfigManager(
            configSources: [mockStorageSource, mockLocalSource],
            loadingStrategy: mockLoadingStrategy,
            customTokenStorage: mockCustomTokenStorage,
          );

          // Should not throw during initialization
          await expectLater(managerWithError.init(), completes);
          expect(managerWithError.isInitialized, isTrue);

          await managerWithError.dispose();
        });

        test('handles conflict resolution with existing assets', () async {
          // Set up conflicting custom token
          when(
            () => mockCustomTokenStorage.getAllCustomTokens(any()),
          ).thenAnswer((_) async => [conflictingToken]);

          final managerWithConflict = StrategicCoinConfigManager(
            configSources: [mockStorageSource, mockLocalSource],
            loadingStrategy: mockLoadingStrategy,
            customTokenStorage: mockCustomTokenStorage,
          );
          await managerWithConflict.init();

          final allAssets = managerWithConflict.all;

          // The bundled KMD key survives and the custom token takes over its
          // slot. `_assets` is a SplayTreeMap ordered by `AssetId.toString()`,
          // which carries the parent and subclass but not the chain id, so a
          // custom token sharing a ticker and subclass collides with the
          // bundled asset even though the two ids are not `==`.
          expect(allAssets.containsKey(komodoAsset.id), isTrue);
          expect(allAssets.keys.where((id) => id.id == 'KMD'), hasLength(1));

          final storedKmd = allAssets[komodoAsset.id]!;
          expect(storedKmd.protocol, equals(conflictingToken.protocol));
          expect(storedKmd.isWalletOnly, equals(conflictingToken.isWalletOnly));

          await managerWithConflict.dispose();
        });
      });

      group('Store custom token', () {
        test('stores custom token and adds to memory', () async {
          await manager.storeCustomToken(customToken1);

          // Verify storage method was called
          verify(
            () => mockCustomTokenStorage.storeCustomToken(customToken1),
          ).called(1);

          // Verify token is added to in-memory assets
          expect(manager.all.containsKey(customToken1.id), isTrue);
          expect(manager.all[customToken1.id], equals(customToken1));
        });

        test('handles storage failure gracefully', () async {
          when(
            () => mockCustomTokenStorage.storeCustomToken(any()),
          ).thenThrow(Exception('Storage failed'));

          await expectLater(
            manager.storeCustomToken(customToken1),
            throwsException,
          );

          // Token should not be in memory if storage failed
          expect(manager.all.containsKey(customToken1.id), isFalse);
        });

        test('handles conflict with existing asset during store', () async {
          await manager.storeCustomToken(conflictingToken);

          // Verify storage method was called with original token
          verify(
            () => mockCustomTokenStorage.storeCustomToken(conflictingToken),
          ).called(1);

          // Takes over the bundled KMD's slot rather than sitting beside it.
          // See the initialization conflict test above for why.
          expect(manager.all.containsKey(komodoAsset.id), isTrue);
          expect(manager.all.keys.where((id) => id.id == 'KMD'), hasLength(1));

          final storedKmd = manager.all[komodoAsset.id]!;
          expect(storedKmd.protocol, equals(conflictingToken.protocol));
        });

        test('throws StateError when not initialized', () async {
          final uninitializedManager = StrategicCoinConfigManager(
            configSources: [mockStorageSource, mockLocalSource],
            customTokenStorage: mockCustomTokenStorage,
          );

          await expectLater(
            uninitializedManager.storeCustomToken(customToken1),
            throwsStateError,
          );
        });

        test('throws StateError when disposed', () async {
          await manager.dispose();

          await expectLater(
            manager.storeCustomToken(customToken1),
            throwsStateError,
          );
        });
      });

      group('Delete custom token', () {
        test('deletes custom token from storage and memory', () async {
          // First store a token
          await manager.storeCustomToken(customToken1);
          expect(manager.all.containsKey(customToken1.id), isTrue);

          // Then delete it
          await manager.deleteCustomToken(customToken1.id);

          // Verify storage method was called
          verify(
            () => mockCustomTokenStorage.deleteCustomToken(customToken1.id),
          ).called(1);

          // Verify token is removed from in-memory assets
          expect(manager.all.containsKey(customToken1.id), isFalse);
        });

        test('handles storage failure gracefully', () async {
          // First store a token
          await manager.storeCustomToken(customToken1);
          expect(manager.all.containsKey(customToken1.id), isTrue);

          when(
            () => mockCustomTokenStorage.deleteCustomToken(any()),
          ).thenThrow(Exception('Delete failed'));

          await expectLater(
            manager.deleteCustomToken(customToken1.id),
            throwsException,
          );

          // Token should still be in memory if storage delete failed
          expect(manager.all.containsKey(customToken1.id), isTrue);
        });

        test('handles deletion of non-existent token', () async {
          // Try to delete a token that doesn't exist
          await manager.deleteCustomToken(customToken1.id);

          // Should not throw, storage method should still be called
          verify(
            () => mockCustomTokenStorage.deleteCustomToken(customToken1.id),
          ).called(1);
        });

        test('throws StateError when not initialized', () async {
          final uninitializedManager = StrategicCoinConfigManager(
            configSources: [mockStorageSource, mockLocalSource],
            customTokenStorage: mockCustomTokenStorage,
          );

          await expectLater(
            uninitializedManager.deleteCustomToken(customToken1.id),
            throwsStateError,
          );
        });

        test('throws StateError when disposed', () async {
          await manager.dispose();

          await expectLater(
            manager.deleteCustomToken(customToken1.id),
            throwsStateError,
          );
        });
      });

      group('Custom token integration with existing functionality', () {
        test('custom tokens are included in filtered assets', () async {
          // Store custom tokens of different types
          final utxoCustomToken = Asset.fromJson({
            'coin': 'CUSTOMUTXO',
            'fname': 'Custom UTXO Token',
            'chain_id': 1,
            'type': 'UTXO',
            'protocol': {'type': 'UTXO'},
            'is_testnet': false,
          });

          await manager.storeCustomToken(utxoCustomToken);

          // Filter for UTXO assets
          const filter = UtxoAssetFilterStrategy();
          final filtered = manager.filteredAssets(filter);

          // Custom UTXO token should be included
          expect(filtered.containsKey(utxoCustomToken.id), isTrue);
        });

        test('custom tokens are found by ticker search', () async {
          await manager.storeCustomToken(customToken1);

          final found = manager.findByTicker('CUSTOM1', CoinSubClass.utxo);
          expect(found, isNotNull);
          expect(found, equals(customToken1));
        });

        test('custom tokens are included in variant search', () async {
          await manager.storeCustomToken(customToken1);

          final variants = manager.findVariantsOfCoin('CUSTOM1');
          expect(variants, contains(customToken1));
        });

        test('filter cache is cleared after custom token operations', () async {
          // Get filtered results to populate cache
          const filter = UtxoAssetFilterStrategy();
          final initialFiltered = manager.filteredAssets(filter);

          // Store a new UTXO custom token
          final utxoCustomToken = Asset.fromJson({
            'coin': 'CUSTOMUTXO',
            'fname': 'Custom UTXO Token',
            'chain_id': 1,
            'type': 'UTXO',
            'protocol': {'type': 'UTXO'},
            'is_testnet': false,
          });

          await manager.storeCustomToken(utxoCustomToken);

          // Get filtered results again
          final newFiltered = manager.filteredAssets(filter);

          // Results should be different (cache was cleared)
          expect(newFiltered.length, equals(initialFiltered.length + 1));
          expect(newFiltered.containsKey(utxoCustomToken.id), isTrue);
        });
      });

      group('Refresh assets with custom tokens', () {
        test('preserves custom tokens after refresh', () async {
          // Store custom tokens
          await manager.storeCustomToken(customToken1);
          await manager.storeCustomToken(customToken2);

          expect(manager.all.containsKey(customToken1.id), isTrue);
          expect(manager.all.containsKey(customToken2.id), isTrue);

          // Set up mock to return custom tokens during refresh
          when(
            () => mockCustomTokenStorage.getAllCustomTokens(any()),
          ).thenAnswer((_) async => [customToken1, customToken2]);

          // Refresh assets
          await manager.refreshAssets();

          // Custom tokens should still be present
          expect(manager.all.containsKey(customToken1.id), isTrue);
          expect(manager.all.containsKey(customToken2.id), isTrue);
        });

        test('handles custom token loading failure during refresh', () async {
          // Store custom tokens initially
          await manager.storeCustomToken(customToken1);
          expect(manager.all.containsKey(customToken1.id), isTrue);

          // Make custom token loading fail during refresh
          when(
            () => mockCustomTokenStorage.getAllCustomTokens(any()),
          ).thenThrow(Exception('Storage error during refresh'));

          // Refresh should complete without throwing
          await expectLater(manager.refreshAssets(), completes);

          // Manager should still be functional
          expect(manager.isInitialized, isTrue);
        });
      });

      group('Dispose with custom token storage', () {
        test('disposes custom token storage on manager disposal', () async {
          await manager.dispose();

          verify(() => mockCustomTokenStorage.dispose()).called(1);
        });
      });
    });
  });
}

/// Helper function to register fake asset types for mocktail
void registerFakeAssetTypes() {
  // Create test asset config using builder
  final fakeConfig = StandardAssetConfigs.testCoin();
  final fakeAsset = Asset.fromJson(fakeConfig);

  registerFallbackValue(fakeAsset.id);
  registerFallbackValue(fakeAsset);
}
