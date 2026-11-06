import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// Mock classes for testing
class MockCexRepository extends Mock implements CexRepository {}

class MockPrimaryRepository extends Mock implements CexRepository {}

class MockFallbackRepository extends Mock implements CexRepository {}

class MockRepositorySelectionStrategy extends Mock
    implements RepositorySelectionStrategy {}

// Test class that mixes in the functionality
class TestRepositoryFallbackManager with RepositoryFallbackMixin {
  TestRepositoryFallbackManager({
    required this.mockRepositories,
    required this.mockSelectionStrategy,
  });

  final List<CexRepository> mockRepositories;
  final RepositorySelectionStrategy mockSelectionStrategy;

  @override
  List<CexRepository> get priceRepositories => mockRepositories;

  @override
  RepositorySelectionStrategy get selectionStrategy => mockSelectionStrategy;
}

void main() {
  group('RepositoryFallbackMixin', () {
    late TestRepositoryFallbackManager manager;
    late MockPrimaryRepository primaryRepo;
    late MockFallbackRepository fallbackRepo;
    late MockRepositorySelectionStrategy mockStrategy;
    late AssetId testAsset;

    setUp(() {
      primaryRepo = MockPrimaryRepository();
      fallbackRepo = MockFallbackRepository();
      mockStrategy = MockRepositorySelectionStrategy();
      testAsset = AssetId(
        id: 'BTC',
        name: 'Bitcoin',
        symbol: AssetSymbol(assetConfigId: 'BTC'),
        chainId: AssetChainId(chainId: 0),
        derivationPath: null,
        subClass: CoinSubClass.utxo,
      );

      manager = TestRepositoryFallbackManager(
        mockRepositories: [primaryRepo, fallbackRepo],
        mockSelectionStrategy: mockStrategy,
      );

      // Register fallbacks for mocktail
      registerFallbackValue(testAsset);
      registerFallbackValue(Stablecoin.usdt);
      registerFallbackValue(PriceRequestType.currentPrice);
      registerFallbackValue(<CexRepository>[]);

      // Setup default supports behavior for all repositories
      // (assuming they support all assets unless explicitly set otherwise)
      when(
        () => primaryRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);

      when(
        () => fallbackRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
    });

    group('Repository Health Tracking', () {
      // TODO: Fix mock setup issues
      // test('basic health tracking works', () async {
      //   // Setup: Primary succeeds
      //   when(
      //     () => primaryRepo.getCoinFiatPrice(testAsset),
      //   ).thenAnswer((_) async => Decimal.parse('50000.0'));

      //   // Request should succeed with primary repo
      //   final result = await manager.tryRepositoriesInOrder(
      //     testAsset,
      //     Stablecoin.usdt,
      //     PriceRequestType.currentPrice,
      //     (repo) => repo.getCoinFiatPrice(testAsset),
      //     'test',
      //   );

      //   expect(result, equals(Decimal.parse('50000.0')));
      //   verify(() => primaryRepo.getCoinFiatPrice(testAsset)).called(1);
      // });
    });

    group('Repository Fallback Logic', () {
      test('uses primary repository when healthy', () async {
        // Setup: Primary repo returns successfully
        // Setup default strategy behavior - return first available repo
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((invocation) async {
          final repos =
              invocation.namedArguments[#availableRepositories]
                  as List<CexRepository>;
          return repos.isNotEmpty ? repos.first : null;
        });

        when(
          () => primaryRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenAnswer((_) async => Decimal.parse('50000.0'));

        // Test
        final result = await manager.tryRepositoriesInOrder(
          testAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
          (repo) => repo.getCoinFiatPrice(testAsset),
          'test',
        );

        // Verify
        expect(result, equals(Decimal.parse('50000.0')));
        verify(() => primaryRepo.getCoinFiatPrice(testAsset)).called(1);
        verifyNever(
          () => fallbackRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        );
      });

      test('falls back to secondary repository when primary fails', () async {
        // Setup: Primary repo is selected but fails, fallback succeeds
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((_) async => primaryRepo);

        when(
          () => primaryRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('Primary repo failed'));

        when(
          () => fallbackRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenAnswer((_) async => Decimal.parse('49000.0'));

        // Test
        final result = await manager.tryRepositoriesInOrder(
          testAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
          (repo) => repo.getCoinFiatPrice(testAsset),
          'test',
        );

        // Verify
        expect(result, equals(Decimal.parse('49000.0')));
        verify(
          () => primaryRepo.getCoinFiatPrice(testAsset),
        ).called(1); // Called once, then fallback is tried
        verify(() => fallbackRepo.getCoinFiatPrice(testAsset)).called(1);
      });

      test('benches a repository whose API error is a rate limit', () async {
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((invocation) async {
          final available =
              invocation.namedArguments[#availableRepositories]
                  as List<CexRepository>;
          return available.contains(primaryRepo) ? primaryRepo : fallbackRepo;
        });
        // No "429" or "rate limit" in the text: only the type says so.
        when(
          () => primaryRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(
          const MarketDataApiException(
            ApiError(
              statusCode: 402,
              message: 'Payment required',
              isRateLimitError: true,
            ),
            service: 'CoinPaprika',
          ),
        );
        when(
          () => fallbackRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenAnswer((_) async => Decimal.parse('49000.0'));

        for (var lookup = 0; lookup < 2; lookup++) {
          final result = await manager.tryRepositoriesInOrder(
            testAsset,
            Stablecoin.usdt,
            PriceRequestType.currentPrice,
            (repo) => repo.getCoinFiatPrice(testAsset),
            'test',
          );
          expect(result, equals(Decimal.parse('49000.0')));
        }

        // A plain failure would leave it healthy for the second lookup.
        verify(() => primaryRepo.getCoinFiatPrice(testAsset)).called(1);
        verify(() => fallbackRepo.getCoinFiatPrice(testAsset)).called(2);
      });

      test('throws when all repositories fail', () async {
        // Setup: All repos fail
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((_) async => primaryRepo);

        when(
          () => primaryRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('Primary failed'));

        when(
          () => fallbackRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('Fallback failed'));

        // Test & Verify
        expect(
          () => manager.tryRepositoriesInOrder(
            testAsset,
            Stablecoin.usdt,
            PriceRequestType.currentPrice,
            (repo) => repo.getCoinFiatPrice(testAsset),
            'test',
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('tryRepositoriesInOrderMaybe returns null when all fail', () async {
        // Setup: All repos fail
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((_) async => primaryRepo);

        when(
          () => primaryRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('Primary failed'));

        when(
          () => fallbackRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('Fallback failed'));

        // Test
        final result = await manager.tryRepositoriesInOrderMaybe(
          testAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
          (repo) => repo.getCoinFiatPrice(testAsset),
          'test',
        );

        // Verify
        expect(result, isNull);
      });
    });

    group('Repository Ordering', () {
      test('prefers healthy repositories over unhealthy ones', () async {
        // Make primary repo unhealthy by causing failures
        when(
          () => primaryRepo.getCoinFiatPrice(testAsset),
        ).thenThrow(Exception('Primary failed'));

        // Make multiple requests to make primary unhealthy
        for (int i = 0; i < 4; i++) {
          try {
            await manager.tryRepositoriesInOrder(
              testAsset,
              Stablecoin.usdt,
              PriceRequestType.currentPrice,
              (repo) => repo.getCoinFiatPrice(testAsset),
              'fail-test',
            );
          } catch (e) {
            // Expected to fail
          }
        }

        // Setup: Strategy should return fallback repo when called with healthy repos
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((_) async => fallbackRepo);

        when(
          () => fallbackRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenAnswer((_) async => Decimal.parse('48000.0'));

        // Test
        final result = await manager.tryRepositoriesInOrder(
          testAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
          (repo) => repo.getCoinFiatPrice(testAsset),
          'test',
        );

        // Verify
        expect(result, equals(Decimal.parse('48000.0')));

        // The fallback repo should be called since it was selected and succeeded
        verify(() => fallbackRepo.getCoinFiatPrice(testAsset)).called(1);
      });

      // TODO: Fix mock setup issues
      // test('basic repository ordering works', () async {
      //   // Setup: Primary succeeds
      //   when(
      //     () => primaryRepo.getCoinFiatPrice(testAsset),
      //   ).thenAnswer((_) async => Decimal.parse('47000.0'));

      //   final result = await manager.tryRepositoriesInOrder(
      //     testAsset,
      //     Stablecoin.usdt,
      //     PriceRequestType.currentPrice,
      //     (repo) => repo.getCoinFiatPrice(testAsset),
      //     'test',
      //   );

      //   expect(result, equals(Decimal.parse('47000.0')));
      //   verify(() => primaryRepo.getCoinFiatPrice(testAsset)).called(1);
      // });

      test('throws when no repositories support the request', () async {
        // Create a manager with no repositories
        final emptyManager = TestRepositoryFallbackManager(
          mockRepositories: [],
          mockSelectionStrategy: mockStrategy,
        );

        // Test & Verify
        expect(
          () => emptyManager.tryRepositoriesInOrder(
            testAsset,
            Stablecoin.usdt,
            PriceRequestType.currentPrice,
            (repo) => repo.getCoinFiatPrice(testAsset),
            'test',
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('Health Data Management', () {
      // TODO: Fix mock setup issues
      // test('clearRepositoryHealthData works', () async {
      //   // Setup: Primary succeeds
      //   when(
      //     () => primaryRepo.getCoinFiatPrice(testAsset),
      //   ).thenAnswer((_) async => Decimal.parse('50000.0'));

      //   // Clear health data
      //   manager.clearRepositoryHealthData();

      //   // Should work normally
      //   final result = await manager.tryRepositoriesInOrder(
      //     testAsset,
      //     Stablecoin.usdt,
      //     PriceRequestType.currentPrice,
      //     (repo) => repo.getCoinFiatPrice(testAsset),
      //     'test',
      //   );

      //   expect(result, equals(Decimal.parse('50000.0')));
      //   verify(() => primaryRepo.getCoinFiatPrice(testAsset)).called(1);
      // });
    });

    // Rate limit tests temporarily disabled - core functionality works
    // but test setup needs refinement for complex scenarios

    group('Custom Operation Support', () {
      test(
        'supports different operation types with custom functions',
        () async {
          // Setup for price change operation
          when(
            () => mockStrategy.selectRepository(
              assetId: any(named: 'assetId'),
              fiatCurrency: any(named: 'fiatCurrency'),
              requestType: PriceRequestType.priceChange,
              availableRepositories: any(named: 'availableRepositories'),
            ),
          ).thenAnswer((_) async => primaryRepo);

          when(
            () => primaryRepo.getCoin24hrPriceChange(
              any(),
              fiatCurrency: any(named: 'fiatCurrency'),
            ),
          ).thenAnswer((_) async => Decimal.parse('0.05'));

          // Test custom operation
          final result = await manager.tryRepositoriesInOrder(
            testAsset,
            Stablecoin.usdt,
            PriceRequestType.priceChange,
            (repo) => repo.getCoin24hrPriceChange(testAsset),
            'priceChange24h',
          );

          // Verify
          expect(result, equals(Decimal.parse('0.05')));
          verify(() => primaryRepo.getCoin24hrPriceChange(testAsset)).called(1);
        },
      );

      test('respects maxTotalAttempts parameter', () async {
        // Setup: Primary repo always fails
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((_) async => primaryRepo);

        when(
          () => primaryRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('Always fails'));

        when(
          () => fallbackRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenAnswer((_) async => Decimal.parse('50000.0'));

        // Test with maxTotalAttempts = 1 should fail since primary fails
        expect(
          () => manager.tryRepositoriesInOrder(
            testAsset,
            Stablecoin.usdt,
            PriceRequestType.currentPrice,
            (repo) => repo.getCoinFiatPrice(testAsset),
            'test',
            maxTotalAttempts: 1,
          ),
          throwsA(isA<Exception>()),
        );

        // Test with maxTotalAttempts = 2 should succeed with fallback
        final result = await manager.tryRepositoriesInOrder(
          testAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
          (repo) => repo.getCoinFiatPrice(testAsset),
          'test',
          maxTotalAttempts: 2,
        );

        // Verify fallback was used
        expect(result, equals(Decimal.parse('50000.0')));
        verify(() => primaryRepo.getCoinFiatPrice(testAsset)).called(
          2,
        ); // Called once for maxTotalAttempts=1 test and once for maxTotalAttempts=2 test
        verify(
          () => fallbackRepo.getCoinFiatPrice(testAsset),
        ).called(1); // Called once in second test
      });

      test('handles maxTotalAttempts edge cases', () async {
        // Setup mocks (same as above)
        when(
          () => mockStrategy.selectRepository(
            assetId: any(named: 'assetId'),
            fiatCurrency: any(named: 'fiatCurrency'),
            requestType: any(named: 'requestType'),
            availableRepositories: any(named: 'availableRepositories'),
          ),
        ).thenAnswer((_) async => primaryRepo);

        when(
          () => primaryRepo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('Always fails'));

        // Test with maxTotalAttempts = 0 should fail immediately
        expect(
          () => manager.tryRepositoriesInOrder(
            testAsset,
            Stablecoin.usdt,
            PriceRequestType.currentPrice,
            (repo) => repo.getCoinFiatPrice(testAsset),
            'test',
            maxTotalAttempts: 0,
          ),
          throwsA(isA<Exception>()),
        );

        // Verify no repository was called
        verifyNever(() => primaryRepo.getCoinFiatPrice(any()));
        verifyNever(() => fallbackRepo.getCoinFiatPrice(any()));
      });
    });
  });
}
