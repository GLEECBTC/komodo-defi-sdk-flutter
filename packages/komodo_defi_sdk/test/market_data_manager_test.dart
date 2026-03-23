import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_sdk/src/market_data/market_data_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockPrimaryRepository extends Mock implements CexRepository {}

class MockFallbackRepository extends Mock implements CexRepository {}

class MockRepositorySelectionStrategy extends Mock
    implements RepositorySelectionStrategy {}

void main() {
  group('CexMarketDataManager', () {
    AssetId asset(String id) => AssetId(
      id: id,
      name: id,
      symbol: AssetSymbol(assetConfigId: id),
      chainId: AssetChainId(chainId: 0),
      derivationPath: null,
      subClass: CoinSubClass.utxo,
    );

    setUp(() {
      // Register fallbacks for mocktail
      registerFallbackValue(asset('BTC'));
      registerFallbackValue(Stablecoin.usdt);
      registerFallbackValue(PriceRequestType.currentPrice);
      registerFallbackValue(<CexRepository>[]);
    });

    test('uses CexRepository when available', () async {
      final fallback = MockPrimaryRepository();
      final manager = CexMarketDataManager(
        priceRepositories: [fallback],
        selectionStrategy: DefaultRepositorySelectionStrategy(),
      );

      when(fallback.getCoinList).thenAnswer(
        (_) async => [
          const CexCoin(
            id: 'BTC',
            symbol: 'BTC',
            name: 'BTC',
            currencies: {'USDT'},
            source: 'fallback',
          ),
        ],
      );
      when(
        () => fallback.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => fallback.getCoinFiatPrice(asset('BTC')),
      ).thenAnswer((_) async => Decimal.parse('3.0'));

      await manager.init();
      final price = await manager.fiatPrice(asset('BTC'));
      expect(price, Decimal.parse('3.0'));
      verify(() => fallback.getCoinFiatPrice(asset('BTC'))).called(1);
    });

    test(
      'priceIfKnown keeps last-known current price after live cache clear',
      () async {
        final repo = MockPrimaryRepository();
        final manager = CexMarketDataManager(
          priceRepositories: [repo],
          selectionStrategy: DefaultRepositorySelectionStrategy(),
          cacheClearInterval: const Duration(milliseconds: 20),
        );

        when(repo.getCoinList).thenAnswer((_) async => []);
        when(
          () => repo.supports(any(), any(), any()),
        ).thenAnswer((_) async => true);
        when(
          () => repo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenAnswer((_) async => Decimal.parse('100.0'));

        await manager.init();

        // Seed current-price caches.
        final seededPrice = await manager.maybeFiatPrice(asset('BTC'));
        expect(seededPrice, equals(Decimal.parse('100.0')));
        expect(
          manager.priceIfKnown(asset('BTC')),
          equals(Decimal.parse('100.0')),
        );

        // Wait long enough for the periodic live cache clear to run.
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Live cache is rotated, but last-known current price should still
        // be returned.
        expect(
          manager.priceIfKnown(asset('BTC')),
          equals(Decimal.parse('100.0')),
        );

        // Refresh from repository and ensure last-known cache updates.
        when(
          () => repo.getCoinFiatPrice(
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenAnswer((_) async => Decimal.parse('120.0'));

        final refreshedPrice = await manager.maybeFiatPrice(asset('BTC'));
        expect(refreshedPrice, equals(Decimal.parse('120.0')));
        expect(
          manager.priceIfKnown(asset('BTC')),
          equals(Decimal.parse('120.0')),
        );

        await manager.dispose();
      },
    );

    test('fiatPrice uses fallback when primary repository fails', () async {
      final primaryRepo = MockPrimaryRepository();
      final fallbackRepo = MockFallbackRepository();
      final mockStrategy = MockRepositorySelectionStrategy();

      final manager = CexMarketDataManager(
        priceRepositories: [primaryRepo, fallbackRepo],
        selectionStrategy: mockStrategy,
      );

      // Setup repository coin lists
      when(primaryRepo.getCoinList).thenAnswer((_) async => []);
      when(fallbackRepo.getCoinList).thenAnswer((_) async => []);

      // Ensure repositories are considered for attempts
      when(
        () => primaryRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => fallbackRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);

      // Setup strategy to return primary repo first
      when(
        () => mockStrategy.selectRepository(
          assetId: any(named: 'assetId'),
          fiatCurrency: any(named: 'fiatCurrency'),
          requestType: any(named: 'requestType'),
          availableRepositories: any(named: 'availableRepositories'),
        ),
      ).thenAnswer((_) async => primaryRepo);

      // Primary repo fails, fallback succeeds
      when(
        () => primaryRepo.getCoinFiatPrice(
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenThrow(Exception('Primary repo down'));

      when(
        () => fallbackRepo.getCoinFiatPrice(
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async => Decimal.parse('50000.0'));

      await manager.init();

      // Test
      final price = await manager.fiatPrice(asset('BTC'));

      // Verify
      expect(price, equals(Decimal.parse('50000')));
      verify(() => primaryRepo.getCoinFiatPrice(asset('BTC'))).called(1);
      verify(() => fallbackRepo.getCoinFiatPrice(asset('BTC'))).called(1);

      await manager.dispose();
    });

    test('maybeFiatPrice returns null when all repositories fail', () async {
      final primaryRepo = MockPrimaryRepository();
      final fallbackRepo = MockFallbackRepository();
      final mockStrategy = MockRepositorySelectionStrategy();

      final manager = CexMarketDataManager(
        priceRepositories: [primaryRepo, fallbackRepo],
        selectionStrategy: mockStrategy,
      );

      // Setup repository coin lists
      when(primaryRepo.getCoinList).thenAnswer((_) async => []);
      when(fallbackRepo.getCoinList).thenAnswer((_) async => []);

      // Ensure repositories are considered for attempts
      when(
        () => primaryRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => fallbackRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);

      // Setup strategy to return primary repo first
      when(
        () => mockStrategy.selectRepository(
          assetId: any(named: 'assetId'),
          fiatCurrency: any(named: 'fiatCurrency'),
          requestType: any(named: 'requestType'),
          availableRepositories: any(named: 'availableRepositories'),
        ),
      ).thenAnswer((_) async => primaryRepo);

      // All repos fail
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

      await manager.init();

      // Test
      final price = await manager.maybeFiatPrice(asset('BTC'));

      // Verify
      expect(price, isNull);

      await manager.dispose();
    });

    test('repository health tracking works across multiple calls', () async {
      final primaryRepo = MockPrimaryRepository();
      final fallbackRepo = MockFallbackRepository();
      final mockStrategy = MockRepositorySelectionStrategy();

      final manager = CexMarketDataManager(
        priceRepositories: [primaryRepo, fallbackRepo],
        selectionStrategy: mockStrategy,
      );

      // Setup repository coin lists
      when(primaryRepo.getCoinList).thenAnswer((_) async => []);
      when(fallbackRepo.getCoinList).thenAnswer((_) async => []);

      // Ensure repositories are considered for attempts
      when(
        () => primaryRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => fallbackRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);

      // Setup strategy to return primary repo first
      when(
        () => mockStrategy.selectRepository(
          assetId: any(named: 'assetId'),
          fiatCurrency: any(named: 'fiatCurrency'),
          requestType: any(named: 'requestType'),
          availableRepositories: any(named: 'availableRepositories'),
        ),
      ).thenAnswer((_) async => primaryRepo);

      // Primary repo always fails
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

      await manager.init();

      // Make multiple calls to trigger health tracking
      for (int i = 0; i < 4; i++) {
        final price = await manager.maybeFiatPrice(asset('BTC'));
        expect(price, equals(Decimal.parse('50000')));
      }

      await manager.dispose();
    });

    test('priceChange24h uses fallback functionality', () async {
      final primaryRepo = MockPrimaryRepository();
      final fallbackRepo = MockFallbackRepository();
      final mockStrategy = MockRepositorySelectionStrategy();

      final manager = CexMarketDataManager(
        priceRepositories: [primaryRepo, fallbackRepo],
        selectionStrategy: mockStrategy,
      );

      // Setup repository coin lists
      when(primaryRepo.getCoinList).thenAnswer((_) async => []);
      when(fallbackRepo.getCoinList).thenAnswer((_) async => []);

      // Ensure repositories are considered for attempts
      when(
        () => primaryRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => fallbackRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);

      // Setup strategy to return primary repo first
      when(
        () => mockStrategy.selectRepository(
          assetId: any(named: 'assetId'),
          fiatCurrency: any(named: 'fiatCurrency'),
          requestType: PriceRequestType.priceChange,
          availableRepositories: any(named: 'availableRepositories'),
        ),
      ).thenAnswer((_) async => primaryRepo);

      // Primary repo fails, fallback succeeds
      when(
        () => primaryRepo.getCoin24hrPriceChange(
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenThrow(Exception('Primary repo down'));

      when(
        () => fallbackRepo.getCoin24hrPriceChange(
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async => Decimal.parse('0.05'));

      await manager.init();

      // Test
      final change = await manager.priceChange24h(asset('BTC'));

      // Verify
      expect(change, equals(Decimal.parse('0.05')));
      verify(() => fallbackRepo.getCoin24hrPriceChange(asset('BTC'))).called(1);

      await manager.dispose();
    });

    test('fiatPriceHistory uses fallback functionality', () async {
      final primaryRepo = MockPrimaryRepository();
      final fallbackRepo = MockFallbackRepository();
      final mockStrategy = MockRepositorySelectionStrategy();

      final manager = CexMarketDataManager(
        priceRepositories: [primaryRepo, fallbackRepo],
        selectionStrategy: mockStrategy,
      );

      // Setup repository coin lists
      when(primaryRepo.getCoinList).thenAnswer((_) async => []);
      when(fallbackRepo.getCoinList).thenAnswer((_) async => []);

      // Ensure repositories are considered for attempts
      when(
        () => primaryRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => fallbackRepo.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);

      final testDates = [DateTime.utc(2023), DateTime.utc(2023, 1, 2)];

      // Setup strategy to return primary repo first
      when(
        () => mockStrategy.selectRepository(
          assetId: any(named: 'assetId'),
          fiatCurrency: any(named: 'fiatCurrency'),
          requestType: PriceRequestType.priceHistory,
          availableRepositories: any(named: 'availableRepositories'),
        ),
      ).thenAnswer((_) async => primaryRepo);

      // Primary repo fails, fallback succeeds
      when(
        () => primaryRepo.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenThrow(Exception('Primary repo down'));

      when(
        () => fallbackRepo.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer(
        (_) async => {
          testDates[0]: Decimal.parse('45000.0'),
          testDates[1]: Decimal.parse('46000.0'),
        },
      );

      await manager.init();

      // Test
      final history = await manager.fiatPriceHistory(asset('BTC'), testDates);

      // Verify
      expect(history.length, equals(2));
      expect(history[testDates[0]], equals(Decimal.parse('45000')));
      expect(history[testDates[1]], equals(Decimal.parse('46000')));

      verify(
        () => fallbackRepo.getCoinFiatPrices(asset('BTC'), testDates),
      ).called(1);

      await manager.dispose();
    });
  });
}
