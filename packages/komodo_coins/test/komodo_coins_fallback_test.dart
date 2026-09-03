import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/komodo_coins.dart' show KomodoAssetsUpdateManager;
import 'package:komodo_coins/src/update_management/update_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';

import 'test_utils/asset_config_builders.dart';

// Mock classes
class MockRuntimeUpdateConfigRepository extends Mock
    implements AssetRuntimeUpdateConfigRepository {}

class MockCoinConfigRepository extends Mock implements CoinConfigRepository {}

class MockCoinConfigTransformer extends Mock implements CoinConfigTransformer {}

class MockCoinConfigDataFactory extends Mock implements CoinConfigDataFactory {}

class MockLocalAssetCoinConfigProvider extends Mock
    implements LocalAssetCoinConfigProvider {}

class MockLocalAssetFallbackProvider extends Mock
    implements LocalAssetCoinConfigProvider {}

class MockGithubCoinConfigProvider extends Mock
    implements GithubCoinConfigProvider {}

class MockUpdateStrategy extends Mock implements UpdateStrategy {}

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
    // Initialize Hive for testing
    tempDir = await getTempDir();
    Hive.init(tempDir.path);

    registerFallbackValue(FakeRuntimeUpdateConfig());
    registerFallbackValue(FakeCoinConfigTransformer());
    registerFallbackValue(UpdateRequestType.backgroundUpdate);
    registerFallbackValue(MockCoinConfigRepository());
    registerFakeAssetTypes();
  });

  tearDownAll(() async {
    await Hive.close();
    // Clean up temporary directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('KomodoCoins Fallback to Local Assets', () {
    late MockRuntimeUpdateConfigRepository mockConfigRepository;
    late MockCoinConfigTransformer mockTransformer;
    late MockCoinConfigDataFactory mockDataFactory;
    late MockCoinConfigRepository mockRepo;
    late MockLocalAssetCoinConfigProvider mockLocalProvider;
    late MockLocalAssetFallbackProvider mockFallbackProvider;
    late MockGithubCoinConfigProvider mockRemoteProvider;
    late MockUpdateStrategy mockUpdateStrategy;

    // Test data using asset config builders
    final testAssetConfig = StandardAssetConfigs.komodo();
    final testAsset = Asset.fromJson(testAssetConfig);

    const bundledCommitHash = 'abc123def456789012345678901234567890abcd';
    const latestCommitHash = 'def456abc789012345678901234567890abcdef';

    setUp(() {
      mockConfigRepository = MockRuntimeUpdateConfigRepository();
      mockTransformer = MockCoinConfigTransformer();
      mockDataFactory = MockCoinConfigDataFactory();
      mockRepo = MockCoinConfigRepository();
      mockLocalProvider = MockLocalAssetCoinConfigProvider();
      mockFallbackProvider = MockLocalAssetFallbackProvider();
      mockRemoteProvider = MockGithubCoinConfigProvider();
      mockUpdateStrategy = MockUpdateStrategy();

      // Set up runtime config
      const runtimeConfig = AssetRuntimeUpdateConfig(
        bundledCoinsRepoCommit: bundledCommitHash,
      );

      when(
        () => mockConfigRepository.tryLoad(),
      ).thenAnswer((_) async => runtimeConfig);

      // Set up factory - use different providers for asset manager vs update manager
      when(
        () => mockDataFactory.createRepository(any(), any()),
      ).thenReturn(mockRepo);
      var localProviderCallCount = 0;
      when(
        () => mockDataFactory.createLocalProvider(any(), mockTransformer),
      ).thenAnswer((_) {
        localProviderCallCount++;
        if (localProviderCallCount == 1) {
          return mockLocalProvider; // First call for asset manager
        } else {
          return mockFallbackProvider; // Second call for update manager fallback
        }
      });

      // Set up transformer
      when(() => mockTransformer.apply(any())).thenReturn(testAssetConfig);

      // Set up repository with remote provider
      when(() => mockRepo.coinConfigProvider).thenReturn(mockRemoteProvider);
      when(() => mockRepo.updateCoinConfig()).thenAnswer((_) async {});

      // Set up update strategy
      when(
        () => mockUpdateStrategy.updateInterval,
      ).thenReturn(const Duration(hours: 6));
      when(
        () => mockUpdateStrategy.shouldUpdate(
          requestType: any(named: 'requestType'),
          repository: any(named: 'repository'),
        ),
      ).thenAnswer((_) => Future.value(true));
      when(
        () => mockUpdateStrategy.executeUpdate(
          requestType: any(named: 'requestType'),
          repository: any(named: 'repository'),
        ),
      ).thenAnswer(
        (_) async => const UpdateResult(
          success: true,
          updatedAssetCount: 1,
          newCommitHash: latestCommitHash,
        ),
      );

      // Set up local provider responses
      when(
        () => mockLocalProvider.getAssets(),
      ).thenAnswer((_) async => [testAsset]);
      when(
        () => mockLocalProvider.getLatestCommit(),
      ).thenAnswer((_) async => bundledCommitHash);

      // Set up fallback provider responses (for update manager)
      when(
        () => mockFallbackProvider.getAssets(),
      ).thenAnswer((_) async => [testAsset]);
      when(
        () => mockFallbackProvider.getLatestCommit(),
      ).thenAnswer((_) async => bundledCommitHash);
    });

    group('when storage does not exist', () {
      setUp(() {
        when(
          () => mockRepo.updatedAssetStorageExists(),
        ).thenAnswer((_) async => false);
      });

      test(
        'uses local assets and sets correct commit hash when remote update fails',
        () async {
          // Set up remote provider to fail
          when(
            () => mockRemoteProvider.getAssets(),
          ).thenThrow(Exception('Network error'));
          when(
            () => mockRemoteProvider.getLatestCommit(),
          ).thenThrow(Exception('Network error'));

          final coins = KomodoAssetsUpdateManager(
            configRepository: mockConfigRepository,
            transformer: mockTransformer,
            dataFactory: mockDataFactory,
            updateStrategy: mockUpdateStrategy,
          );

          await coins.init();

          // Verify assets are loaded from local provider
          expect(coins.all.length, 1);
          expect(coins.all[testAsset.id], equals(testAsset));

          // Verify commit hash comes from local provider (bundled commit)
          final currentCommit = await coins.getCurrentCommitHash();
          expect(currentCommit, equals(bundledCommitHash));

          verify(() => mockLocalProvider.getAssets()).called(greaterThan(0));
        },
      );

      test(
        'keeps application view transforms out of persistence wiring',
        () async {
          final persistenceTransformer = MockCoinConfigTransformer();
          when(
            () => mockDataFactory.createLocalProvider(
              any(),
              persistenceTransformer,
            ),
          ).thenReturn(mockFallbackProvider);

          final coins = KomodoAssetsUpdateManager(
            configRepository: mockConfigRepository,
            transformer: mockTransformer,
            persistenceTransformer: persistenceTransformer,
            dataFactory: mockDataFactory,
            enableAutoUpdate: false,
          );

          await coins.init();

          verify(
            () => mockDataFactory.createRepository(any(), mockTransformer),
          ).called(1);
          verify(
            () =>
                mockDataFactory.createRepository(any(), persistenceTransformer),
          ).called(1);
          verify(
            () => mockDataFactory.createLocalProvider(any(), mockTransformer),
          ).called(1);
          verify(
            () => mockDataFactory.createLocalProvider(
              any(),
              persistenceTransformer,
            ),
          ).called(1);
          await coins.dispose();
        },
      );

      test('uses local assets when remote update times out', () async {
        // Set up remote provider to timeout
        when(() => mockRemoteProvider.getAssets()).thenAnswer(
          (_) => Future<List<Asset>>.delayed(
            const Duration(seconds: 30),
          ).then((_) => [testAsset]),
        );
        when(() => mockRemoteProvider.getLatestCommit()).thenAnswer(
          (_) => Future<String>.delayed(
            const Duration(seconds: 30),
          ).then((_) => latestCommitHash),
        );

        final coins = KomodoAssetsUpdateManager(
          configRepository: mockConfigRepository,
          transformer: mockTransformer,
          dataFactory: mockDataFactory,
          updateStrategy: mockUpdateStrategy,
        );

        await coins.init();

        // Should use local assets immediately, not wait for timeout
        expect(coins.all.length, 1);
        expect(coins.all[testAsset.id], equals(testAsset));

        // Commit hash should be from bundled assets
        final currentCommit = await coins.getCurrentCommitHash();
        expect(currentCommit, equals(bundledCommitHash));

        verify(() => mockLocalProvider.getAssets()).called(greaterThan(0));
      });

      test('uses local assets when remote returns invalid data', () async {
        // Set up remote provider to return invalid data
        when(
          () => mockRemoteProvider.getAssets(),
        ).thenAnswer((_) async => <Asset>[]);
        when(
          () => mockRemoteProvider.getLatestCommit(),
        ).thenAnswer((_) async => '');

        final coins = KomodoAssetsUpdateManager(
          configRepository: mockConfigRepository,
          transformer: mockTransformer,
          dataFactory: mockDataFactory,
          updateStrategy: mockUpdateStrategy,
        );

        await coins.init();

        // Should fall back to local assets
        expect(coins.all.length, 1);
        expect(coins.all[testAsset.id], equals(testAsset));

        // Commit hash should be from bundled assets
        final currentCommit = await coins.getCurrentCommitHash();
        expect(currentCommit, equals(bundledCommitHash));

        verify(() => mockLocalProvider.getAssets()).called(greaterThan(0));
      });
    });

    group('when storage exists but remote update fails', () {
      setUp(() {
        when(
          () => mockRepo.updatedAssetStorageExists(),
        ).thenAnswer((_) async => true);
        when(() => mockRepo.getAssets()).thenAnswer((_) async => [testAsset]);
        when(
          () => mockRepo.getCurrentCommit(),
        ).thenAnswer((_) async => bundledCommitHash);
        when(() => mockRepo.isLatestCommit()).thenAnswer((_) async => false);
      });

      test('updates stored assets when remote succeeds', () async {
        // Set up successful remote update
        when(
          () => mockRemoteProvider.getAssets(),
        ).thenAnswer((_) async => [testAsset]);
        when(
          () => mockRemoteProvider.getLatestCommit(),
        ).thenAnswer((_) async => latestCommitHash);
        when(() => mockRepo.updateCoinConfig()).thenAnswer((_) async {});
        when(
          () => mockRepo.getCurrentCommit(),
        ).thenAnswer((_) async => latestCommitHash);

        final coins = KomodoAssetsUpdateManager(
          configRepository: mockConfigRepository,
          transformer: mockTransformer,
          dataFactory: mockDataFactory,
          updateStrategy: mockUpdateStrategy,
        );

        await coins.init();

        // Trigger update manually and wait for completion via stream
        final expectation = expectLater(
          coins.updateStream,
          emits(
            isA<UpdateResult>().having((r) => r.success, 'success', isTrue),
          ),
        );

        // Trigger the update manually
        await coins.updateNow();

        await expectation;

        expect(coins.all.length, 1);
        verify(() => mockRepo.getAssets()).called(greaterThan(0));
      });

      test(
        'falls back to local assets when remote update fails after storage load',
        () async {
          // Set up remote provider to fail during update
          when(
            () => mockRemoteProvider.getAssets(),
          ).thenThrow(Exception('Update failed'));
          when(
            () => mockRemoteProvider.getLatestCommit(),
          ).thenThrow(Exception('Update failed'));
          when(
            () => mockRepo.updateCoinConfig(),
          ).thenThrow(Exception('Update failed'));

          // Mock the fallback scenario - storage gets cleared, then local provider is used
          when(() => mockRepo.deleteAllAssets()).thenAnswer((_) async {});

          final coins = KomodoAssetsUpdateManager(
            configRepository: mockConfigRepository,
            transformer: mockTransformer,
            dataFactory: mockDataFactory,
            updateStrategy: mockUpdateStrategy,
          );

          await coins.init();

          // Should still have assets loaded from storage initially
          expect(coins.all.length, 1);
          expect(coins.all[testAsset.id], equals(testAsset));

          // Current commit should be available
          final currentCommit = await coins.getCurrentCommitHash();
          expect(currentCommit, equals(bundledCommitHash));

          verify(() => mockRepo.getAssets()).called(1);
        },
      );
    });

    group('static fetchAndTransformCoinsList fallback behavior', () {
      test('falls back to local assets when storage fails', () async {
        // Set up repository to fail
        when(
          () => mockRepo.updatedAssetStorageExists(),
        ).thenThrow(Exception('Storage error'));
        when(() => mockRepo.getAssets()).thenThrow(Exception('Storage error'));

        // Mock the static method dependencies
        when(() => mockConfigRepository.tryLoad()).thenAnswer(
          (_) async => const AssetRuntimeUpdateConfig(
            bundledCoinsRepoCommit: bundledCommitHash,
          ),
        );

        // This test would require mocking static dependencies, which is complex
        // Instead, let's test the integration through the instance method
        final coins = KomodoAssetsUpdateManager(
          configRepository: mockConfigRepository,
          transformer: mockTransformer,
          dataFactory: mockDataFactory,
          enableAutoUpdate:
              false, // Disable auto-update to test static behavior
        );

        await coins.init();

        final configs = coins.all.values
            .map((asset) => asset.protocol.config)
            .toList();
        expect(configs.length, 1);
        expect(configs.first['coin'], 'KMD');
      });

      test(
        'clears storage and retries when fetchAndTransformCoinsList fails',
        () async {
          // Set up repository to fail initially, then succeed
          var callCount = 0;
          when(() => mockRepo.updatedAssetStorageExists()).thenAnswer((
            _,
          ) async {
            callCount++;
            if (callCount == 1) {
              throw Exception('Initial failure');
            }
            return false; // No storage, use local assets
          });

          when(() => mockRepo.deleteAllAssets()).thenAnswer((_) async {});

          final coins = KomodoAssetsUpdateManager(
            configRepository: mockConfigRepository,
            transformer: mockTransformer,
            dataFactory: mockDataFactory,
            enableAutoUpdate: false,
          );

          await coins.init();

          expect(coins.all.length, 1);
          verify(() => mockLocalProvider.getAssets()).called(greaterThan(0));
        },
      );
    });

    group('commit hash consistency', () {
      test('commit hash is never empty when using local assets', () async {
        when(
          () => mockRepo.updatedAssetStorageExists(),
        ).thenAnswer((_) async => false);
        when(
          () => mockRemoteProvider.getAssets(),
        ).thenThrow(Exception('Remote error'));
        when(
          () => mockRemoteProvider.getLatestCommit(),
        ).thenThrow(Exception('Remote error'));

        final coins = KomodoAssetsUpdateManager(
          configRepository: mockConfigRepository,
          transformer: mockTransformer,
          dataFactory: mockDataFactory,
        );

        await coins.init();

        final currentCommit = await coins.getCurrentCommitHash();
        expect(currentCommit, isNotNull);
        expect(currentCommit, isNotEmpty);
        expect(currentCommit, equals(bundledCommitHash));

        final latestCommit = await coins.getLatestCommitHash();
        expect(latestCommit, isNotNull);
        expect(latestCommit, isNotEmpty);
        expect(latestCommit, equals(bundledCommitHash));
      });

      test(
        'commit hash switches from bundled to latest after successful update',
        () async {
          when(
            () => mockRepo.updatedAssetStorageExists(),
          ).thenAnswer((_) async => false);
          when(
            () => mockRemoteProvider.getAssets(),
          ).thenAnswer((_) async => [testAsset]);
          when(
            () => mockRemoteProvider.getLatestCommit(),
          ).thenAnswer((_) async => latestCommitHash);
          when(
            () => mockRepo.upsertAssets(any(), any()),
          ).thenAnswer((_) async {});

          final coins = KomodoAssetsUpdateManager(
            configRepository: mockConfigRepository,
            transformer: mockTransformer,
            dataFactory: mockDataFactory,
            updateStrategy: mockUpdateStrategy,
          );

          await coins.init();

          // Initially should use bundled commit
          final currentCommit = await coins.getCurrentCommitHash();
          expect(currentCommit, equals(bundledCommitHash));

          // Trigger update manually and wait for completion via stream
          final expectation = expectLater(
            coins.updateStream,
            emits(
              isA<UpdateResult>().having((r) => r.success, 'success', isTrue),
            ),
          );

          // Trigger the update manually
          await coins.updateNow();

          await expectation;

          final latestCommit = await coins.getLatestCommitHash();
          expect(latestCommit, equals(latestCommitHash));
        },
      );

      test('commit hash remains bundled when update is disabled', () async {
        when(
          () => mockRepo.updatedAssetStorageExists(),
        ).thenAnswer((_) async => false);

        final coins = KomodoAssetsUpdateManager(
          configRepository: mockConfigRepository,
          transformer: mockTransformer,
          dataFactory: mockDataFactory,
          enableAutoUpdate: false, // Updates disabled
        );

        await coins.init();

        final currentCommit = await coins.getCurrentCommitHash();
        expect(currentCommit, equals(bundledCommitHash));

        final latestCommit = await coins.getLatestCommitHash();
        expect(latestCommit, equals(bundledCommitHash));

        // Remote provider should not be called for updates
        verifyNever(() => mockRemoteProvider.getAssets());
        verifyNever(() => mockRepo.upsertAssets(any(), any()));
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
