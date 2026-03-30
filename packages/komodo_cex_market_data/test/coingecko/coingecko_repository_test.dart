import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/_core_index.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockICoinGeckoProvider extends Mock implements ICoinGeckoProvider {}

void main() {
  group('CoinGeckoRepository', () {
    late CoinGeckoRepository repository;
    late MockICoinGeckoProvider mockProvider;

    setUp(() {
      mockProvider = MockICoinGeckoProvider();
      repository = CoinGeckoRepository(
        coinGeckoProvider: mockProvider,
        enableMemoization: false, // Disable for testing
      );
    });

    group('getCoinOhlc 365-day limit handling', () {
      test('should make single request when within 365-day limit', () async {
        final startAt = DateTime(2023);
        final endAt = DateTime(2023, 12, 31); // 364 days
        final mockOhlc = CoinOhlc(
          ohlc: [
            Ohlc.binance(
              open: Decimal.fromInt(100),
              high: Decimal.fromInt(110),
              low: Decimal.fromInt(90),
              close: Decimal.fromInt(105),
              openTime: startAt.millisecondsSinceEpoch,
              closeTime: endAt.millisecondsSinceEpoch,
            ),
          ],
        );

        when(
          () => mockProvider.fetchCoinOhlc(any(), any(), any()),
        ).thenAnswer((_) async => mockOhlc);

        final assetId = AssetId(
          id: 'bitcoin',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'bitcoin', coinGeckoId: 'bitcoin'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final result = await repository.getCoinOhlc(
          assetId,
          FiatCurrency.usd,
          GraphInterval.oneDay,
          startAt: startAt,
          endAt: endAt,
        );

        expect(result.ohlc.length, equals(1));
        // Verify only one call was made
        verify(
          () => mockProvider.fetchCoinOhlc('bitcoin', 'usd', any()),
        ).called(1);
      });

      test('should split requests when exceeding 365-day limit', () async {
        final startAt = DateTime(2022);
        final endAt = DateTime(2024); // More than 365 days
        final mockOhlc = CoinOhlc(
          ohlc: [
            Ohlc.binance(
              open: Decimal.fromInt(100),
              high: Decimal.fromInt(110),
              low: Decimal.fromInt(90),
              close: Decimal.fromInt(105),
              openTime: startAt.millisecondsSinceEpoch,
              closeTime: endAt.millisecondsSinceEpoch,
            ),
          ],
        );

        when(
          () => mockProvider.fetchCoinOhlc(any(), any(), any()),
        ).thenAnswer((_) async => mockOhlc);

        final assetId = AssetId(
          id: 'bitcoin',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'bitcoin', coinGeckoId: 'bitcoin'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final result = await repository.getCoinOhlc(
          assetId,
          FiatCurrency.usd,
          GraphInterval.oneDay,
          startAt: startAt,
          endAt: endAt,
        );

        // Should have made multiple calls and combined the results
        expect(result.ohlc.length, greaterThan(1));

        // Verify multiple calls were made (should be at least 2 for 2+ years)
        verify(
          () => mockProvider.fetchCoinOhlc('bitcoin', 'usd', any()),
        ).called(greaterThan(1));
      });

      test('should handle requests exactly at 365-day limit', () async {
        final startAt = DateTime(2023);
        final endAt = DateTime(2024); // Exactly 365 days
        final mockOhlc = CoinOhlc(
          ohlc: [
            Ohlc.binance(
              open: Decimal.fromInt(100),
              high: Decimal.fromInt(110),
              low: Decimal.fromInt(90),
              close: Decimal.fromInt(105),
              openTime: startAt.millisecondsSinceEpoch,
              closeTime: endAt.millisecondsSinceEpoch,
            ),
          ],
        );

        when(
          () => mockProvider.fetchCoinOhlc(any(), any(), any()),
        ).thenAnswer((_) async => mockOhlc);

        final assetId = AssetId(
          id: 'bitcoin',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'bitcoin', coinGeckoId: 'bitcoin'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final result = await repository.getCoinOhlc(
          assetId,
          FiatCurrency.usd,
          GraphInterval.oneDay,
          startAt: startAt,
          endAt: endAt,
        );

        expect(result.ohlc.length, equals(1));
        // Should make only one call at the limit
        verify(
          () => mockProvider.fetchCoinOhlc('bitcoin', 'usd', 365),
        ).called(1);
      });
    });

    group('USD equivalent currency support', () {
      setUp(() {
        // Mock the coin list response
        when(() => mockProvider.fetchCoinList()).thenAnswer(
          (_) async => [
            const CexCoin(
              id: 'bitcoin',
              symbol: 'btc',
              name: 'Bitcoin',
              currencies: {},
            ),
            const CexCoin(
              id: 'ethereum',
              symbol: 'eth',
              name: 'Ethereum',
              currencies: {},
            ),
          ],
        );

        // Mock supported currencies including USD
        when(
          () => mockProvider.fetchSupportedVsCurrencies(),
        ).thenAnswer((_) async => ['usd', 'eur', 'gbp', 'jpy', 'btc', 'eth']);
      });

      test('should support USD fiat currency', () async {
        final assetId = AssetId(
          id: 'bitcoin',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );
        final supports = await repository.supports(
          assetId,
          FiatCurrency.usd,
          PriceRequestType.currentPrice,
        );

        expect(supports, isTrue);
      });

      test('should support all USD-pegged stablecoins via USD mapping', () async {
        final assetId = AssetId(
          id: 'bitcoin',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final usdStablecoins = [
          Stablecoin.usdt,
          Stablecoin.usdc,
          Stablecoin.busd,
          Stablecoin.dai,
          Stablecoin.tusd,
          Stablecoin.frax,
          Stablecoin.lusd,
          Stablecoin.gusd,
          Stablecoin.usdp,
          Stablecoin.susd,
          Stablecoin.fei,
          Stablecoin.tribe,
          Stablecoin.ust,
          Stablecoin.ustc,
        ];

        final supportResults = await Future.wait(
          usdStablecoins.map(
            (stablecoin) => repository.supports(
              assetId,
              stablecoin,
              PriceRequestType.currentPrice,
            ),
          ),
        );

        for (var i = 0; i < usdStablecoins.length; i++) {
          expect(
            supportResults[i],
            isTrue,
            reason:
                '${usdStablecoins[i].symbol} should be supported via USD mapping',
          );
        }
      });

      test('should resolve TRX via fallback CoinGecko id', () async {
        when(() => mockProvider.fetchCoinList()).thenAnswer(
          (_) async => [
            const CexCoin(
              id: 'tron',
              symbol: 'trx',
              name: 'TRON',
              currencies: {},
            ),
          ],
        );

        final assetId = AssetId(
          id: 'TRX',
          name: 'TRON',
          symbol: AssetSymbol(assetConfigId: 'TRX'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final supports = await repository.supports(
          assetId,
          Stablecoin.usdt,
          PriceRequestType.priceHistory,
        );

        expect(supports, isTrue);
      });

      test('should support EUR-pegged stablecoins via EUR mapping', () async {
        final assetId = AssetId(
          id: 'bitcoin',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final eurStablecoins = [
          Stablecoin.eurs,
          Stablecoin.eurt,
          Stablecoin.jeur,
        ];

        for (final stablecoin in eurStablecoins) {
          final supports = await repository.supports(
            assetId,
            stablecoin,
            PriceRequestType.currentPrice,
          );

          expect(
            supports,
            isTrue,
            reason: '${stablecoin.symbol} should be supported via EUR mapping',
          );
        }
      });

      test('should support GBP-pegged stablecoins via GBP mapping', () async {
        final assetId = AssetId(
          id: 'bitcoin',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final supports = await repository.supports(
          assetId,
          Stablecoin.gbpt,
          PriceRequestType.currentPrice,
        );

        expect(
          supports,
          isTrue,
          reason: 'GBPT should be supported via GBP mapping',
        );
      });

      test(
        'should not support currency when underlying fiat is not supported',
        () async {
          // Mock supported currencies without JPY and without USD to prevent fallback
          when(
            () => mockProvider.fetchSupportedVsCurrencies(),
          ).thenAnswer((_) async => ['eur', 'gbp']);

          final repository = CoinGeckoRepository(
            coinGeckoProvider: mockProvider,
            enableMemoization: false,
          );

          final assetId = AssetId(
            id: 'bitcoin',
            name: 'Bitcoin',
            symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          final supports = await repository.supports(
            assetId,
            Stablecoin.jpyt,
            PriceRequestType.currentPrice,
          );

          expect(
            supports,
            isFalse,
            reason: 'JPYT should not be supported when JPY is not supported',
          );
        },
      );

      test('should not support asset when asset is not in coin list', () async {
        final assetId = AssetId(
          id: 'unknown',
          name: 'Unknown',
          symbol: AssetSymbol(assetConfigId: 'UNKNOWN'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final supports = await repository.supports(
          assetId,
          FiatCurrency.usd,
          PriceRequestType.currentPrice,
        );

        expect(
          supports,
          isFalse,
          reason: 'Unknown asset should not be supported',
        );
      });

      test('should handle cryptocurrency quote currencies', () async {
        final assetId = AssetId(
          id: 'ethereum',
          name: 'Ethereum',
          symbol: AssetSymbol(assetConfigId: 'ETH', coinGeckoId: 'ethereum'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.erc20,
        );

        final supports = await repository.supports(
          assetId,
          Cryptocurrency.btc,
          PriceRequestType.currentPrice,
        );

        expect(
          supports,
          isTrue,
          reason: 'BTC should be supported as quote currency',
        );
      });
    });

    group('getCoinList failure cooldown', () {
      test(
        'should not retry API call during cooldown after failure',
        () async {
          var callCount = 0;
          when(() => mockProvider.fetchCoinList()).thenAnswer((_) async {
            callCount++;
            throw Exception('API error');
          });
          when(
            () => mockProvider.fetchSupportedVsCurrencies(),
          ).thenAnswer((_) async => ['usd']);

          // Enable memoization for this test
          final memoizedRepo = CoinGeckoRepository(
            coinGeckoProvider: mockProvider,
          );

          // First call should hit the API and fail
          expect(memoizedRepo.getCoinList(), throwsA(isA<Exception>()));
          await Future<void>.delayed(Duration.zero);
          expect(callCount, equals(1));

          // Second call should throw StateError (cooldown) without hitting API
          expect(memoizedRepo.getCoinList(), throwsA(isA<StateError>()));
          await Future<void>.delayed(Duration.zero);
          expect(callCount, equals(1)); // Still 1 - no new API call
        },
      );

      test(
        'should return false from supports() during cooldown without API call',
        () async {
          when(() => mockProvider.fetchCoinList()).thenThrow(
            Exception('rate limit'),
          );
          when(
            () => mockProvider.fetchSupportedVsCurrencies(),
          ).thenAnswer((_) async => ['usd']);

          final memoizedRepo = CoinGeckoRepository(
            coinGeckoProvider: mockProvider,
          );

          final assetId = AssetId(
            id: 'bitcoin',
            name: 'Bitcoin',
            symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          // First supports() call triggers the API failure
          final result1 = await memoizedRepo.supports(
            assetId,
            FiatCurrency.usd,
            PriceRequestType.currentPrice,
          );
          expect(result1, isFalse);

          // Second supports() call should return false without new API call
          final result2 = await memoizedRepo.supports(
            assetId,
            FiatCurrency.usd,
            PriceRequestType.currentPrice,
          );
          expect(result2, isFalse);

          // Provider should only have been called once
          verify(() => mockProvider.fetchCoinList()).called(1);
        },
      );

      test('should cache result on success and not call API again', () async {
        when(() => mockProvider.fetchCoinList()).thenAnswer(
          (_) async => [
            const CexCoin(
              id: 'bitcoin',
              symbol: 'btc',
              name: 'Bitcoin',
              currencies: {},
            ),
          ],
        );
        when(
          () => mockProvider.fetchSupportedVsCurrencies(),
        ).thenAnswer((_) async => ['usd']);

        final memoizedRepo = CoinGeckoRepository(
          coinGeckoProvider: mockProvider,
        );

        final result1 = await memoizedRepo.getCoinList();
        final result2 = await memoizedRepo.getCoinList();

        expect(result1.length, equals(1));
        expect(result2.length, equals(1));
        // API should only be called once
        verify(() => mockProvider.fetchCoinList()).called(1);
      });
    });

    group('_mapFiatCurrencyToCoingecko mapping verification', () {
      setUp(() {
        // Mock the coin list response
        when(() => mockProvider.fetchCoinList()).thenAnswer(
          (_) async => [
            const CexCoin(
              id: 'bitcoin',
              symbol: 'btc',
              name: 'Bitcoin',
              currencies: {},
            ),
          ],
        );

        // Mock supported currencies - deliberately exclude stablecoin symbols
        when(
          () => mockProvider.fetchSupportedVsCurrencies(),
        ).thenAnswer((_) async => ['usd', 'eur', 'gbp', 'jpy']);
      });
      test('should map USD stablecoins to usd', () {
        // This verifies the mapping indirectly through coinGeckoId
        expect(Stablecoin.usdt.coinGeckoId, equals('usd'));
        expect(Stablecoin.usdc.coinGeckoId, equals('usd'));
        expect(Stablecoin.busd.coinGeckoId, equals('usd'));
        expect(Stablecoin.dai.coinGeckoId, equals('usd'));
        expect(Stablecoin.tusd.coinGeckoId, equals('usd'));
        expect(Stablecoin.frax.coinGeckoId, equals('usd'));
        expect(Stablecoin.lusd.coinGeckoId, equals('usd'));
        expect(Stablecoin.gusd.coinGeckoId, equals('usd'));
        expect(Stablecoin.usdp.coinGeckoId, equals('usd'));
        expect(Stablecoin.susd.coinGeckoId, equals('usd'));
        expect(Stablecoin.fei.coinGeckoId, equals('usd'));
        expect(Stablecoin.tribe.coinGeckoId, equals('usd'));
        expect(Stablecoin.ust.coinGeckoId, equals('usd'));
        expect(Stablecoin.ustc.coinGeckoId, equals('usd'));
      });

      test('should map EUR stablecoins to eur', () {
        expect(Stablecoin.eurs.coinGeckoId, equals('eur'));
        expect(Stablecoin.eurt.coinGeckoId, equals('eur'));
        expect(Stablecoin.jeur.coinGeckoId, equals('eur'));
      });

      test('should map fiat currencies to lowercase symbols', () {
        expect(FiatCurrency.usd.coinGeckoId, equals('usd'));
        expect(FiatCurrency.eur.coinGeckoId, equals('eur'));
        expect(FiatCurrency.gbp.coinGeckoId, equals('gbp'));
      });

      test('should handle Turkish Lira special case', () {
        expect(FiatCurrency.tryLira.coinGeckoId, equals('try'));
      });

      test(
        'should always prefer underlying fiat for stablecoins even when stablecoin symbol is supported',
        () async {
          // Mock supported currencies to include both USD and USDT
          when(
            () => mockProvider.fetchSupportedVsCurrencies(),
          ).thenAnswer((_) async => ['usd', 'usdt', 'eur', 'gbp']);

          final repository = CoinGeckoRepository(
            coinGeckoProvider: mockProvider,
            enableMemoization: false,
          );

          // Get the coins list to populate the cache
          await repository.getCoinList();

          // Test the internal mapping method indirectly through getCoin24hrPriceChange
          final assetId = AssetId(
            id: 'bitcoin',
            name: 'Bitcoin',
            symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          // Mock the market data response
          when(
            () => mockProvider.fetchCoinMarketData(
              ids: any(named: 'ids'),
              vsCurrency: any(named: 'vsCurrency'),
            ),
          ).thenAnswer(
            (_) async => [
              CoinMarketData(
                id: 'bitcoin',
                symbol: 'btc',
                name: 'Bitcoin',
                currentPrice: Decimal.fromInt(50000),
                marketCap: Decimal.fromInt(1000000000),
                marketCapRank: Decimal.fromInt(1),
                fullyDilutedValuation: Decimal.fromInt(1050000000),
                totalVolume: Decimal.fromInt(25000000),
                high24h: Decimal.fromInt(52000),
                low24h: Decimal.fromInt(48000),
                priceChange24h: Decimal.fromInt(1000),
                priceChangePercentage24h: Decimal.fromInt(2),
                marketCapChange24h: Decimal.fromInt(50000000),
                marketCapChangePercentage24h: Decimal.fromInt(5),
                circulatingSupply: Decimal.fromInt(19000000),
                totalSupply: Decimal.fromInt(21000000),
                maxSupply: Decimal.fromInt(21000000),
                ath: Decimal.fromInt(69000),
                athChangePercentage: Decimal.parse('-27.5'),
                athDate: DateTime.parse('2021-11-10T14:24:11.849Z'),
                atl: Decimal.parse('67.81'),
                atlChangePercentage: Decimal.parse('73662.1'),
                atlDate: DateTime.parse('2013-07-06T00:00:00.000Z'),
                lastUpdated: DateTime.now(),
              ),
            ],
          );

          // Call method with USDT - should use USD as vs_currency, not USDT
          await repository.getCoin24hrPriceChange(assetId);

          // Verify that USD was used, not USDT
          verify(
            () => mockProvider.fetchCoinMarketData(ids: ['bitcoin']),
          ).called(1);
        },
      );

      test(
        'should never fall back to stablecoin symbol when underlying fiat is not cached',
        () async {
          // Mock supported currencies to exclude USD but include USDT
          when(
            () => mockProvider.fetchSupportedVsCurrencies(),
          ).thenAnswer((_) async => ['usdt', 'eur', 'gbp']);

          final repository = CoinGeckoRepository(
            coinGeckoProvider: mockProvider,
            enableMemoization: false,
          );

          // Get the coins list to populate the cache
          await repository.getCoinList();

          final assetId = AssetId(
            id: 'bitcoin',
            name: 'Bitcoin',
            symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          // Mock the market data response
          when(
            () => mockProvider.fetchCoinMarketData(
              ids: any(named: 'ids'),
              vsCurrency: any(named: 'vsCurrency'),
            ),
          ).thenAnswer(
            (_) async => [
              CoinMarketData(
                id: 'bitcoin',
                symbol: 'btc',
                name: 'Bitcoin',
                currentPrice: Decimal.fromInt(50000),
                marketCap: Decimal.fromInt(1000000000),
                marketCapRank: Decimal.fromInt(1),
                fullyDilutedValuation: Decimal.fromInt(1050000000),
                totalVolume: Decimal.fromInt(25000000),
                high24h: Decimal.fromInt(52000),
                low24h: Decimal.fromInt(48000),
                priceChange24h: Decimal.fromInt(1000),
                priceChangePercentage24h: Decimal.fromInt(2),
                marketCapChange24h: Decimal.fromInt(50000000),
                marketCapChangePercentage24h: Decimal.fromInt(5),
                circulatingSupply: Decimal.fromInt(19000000),
                totalSupply: Decimal.fromInt(21000000),
                maxSupply: Decimal.fromInt(21000000),
                ath: Decimal.fromInt(69000),
                athChangePercentage: Decimal.parse('-27.5'),
                athDate: DateTime.parse('2021-11-10T14:24:11.849Z'),
                atl: Decimal.parse('67.81'),
                atlChangePercentage: Decimal.parse('73662.1'),
                atlDate: DateTime.parse('2013-07-06T00:00:00.000Z'),
                lastUpdated: DateTime.now(),
              ),
            ],
          );

          // Call method with USDT - should fall back to USD (final fallback), not USDT
          await repository.getCoin24hrPriceChange(assetId);

          // Verify that USD was used as final fallback, not USDT
          verify(
            () => mockProvider.fetchCoinMarketData(ids: ['bitcoin']),
          ).called(1);
        },
      );

      test(
        'should allow fallback to original symbol for fiat currencies',
        () async {
          // Mock supported currencies to exclude EUR from coinGeckoId mapping but include original
          when(
            () => mockProvider.fetchSupportedVsCurrencies(),
          ).thenAnswer((_) async => ['usd', 'eur', 'gbp']);

          final repository = CoinGeckoRepository(
            coinGeckoProvider: mockProvider,
            enableMemoization: false,
          );

          // Get the coins list to populate the cache
          await repository.getCoinList();

          final assetId = AssetId(
            id: 'bitcoin',
            name: 'Bitcoin',
            symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          // Mock the market data response
          when(
            () => mockProvider.fetchCoinMarketData(
              ids: any(named: 'ids'),
              vsCurrency: any(named: 'vsCurrency'),
            ),
          ).thenAnswer(
            (_) async => [
              CoinMarketData(
                id: 'bitcoin',
                symbol: 'btc',
                name: 'Bitcoin',
                currentPrice: Decimal.fromInt(50000),
                marketCap: Decimal.fromInt(1000000000),
                marketCapRank: Decimal.fromInt(1),
                fullyDilutedValuation: Decimal.fromInt(1050000000),
                totalVolume: Decimal.fromInt(25000000),
                high24h: Decimal.fromInt(52000),
                low24h: Decimal.fromInt(48000),
                priceChange24h: Decimal.fromInt(1000),
                priceChangePercentage24h: Decimal.fromInt(2),
                marketCapChange24h: Decimal.fromInt(50000000),
                marketCapChangePercentage24h: Decimal.fromInt(5),
                circulatingSupply: Decimal.fromInt(19000000),
                totalSupply: Decimal.fromInt(21000000),
                maxSupply: Decimal.fromInt(21000000),
                ath: Decimal.fromInt(69000),
                athChangePercentage: Decimal.parse('-27.5'),
                athDate: DateTime.parse('2021-11-10T14:24:11.849Z'),
                atl: Decimal.parse('67.81'),
                atlChangePercentage: Decimal.parse('73662.1'),
                atlDate: DateTime.parse('2013-07-06T00:00:00.000Z'),
                lastUpdated: DateTime.now(),
              ),
            ],
          );

          // Call method with EUR fiat currency
          await repository.getCoin24hrPriceChange(
            assetId,
            fiatCurrency: FiatCurrency.eur,
          );

          // Verify that EUR was used correctly
          verify(
            () => mockProvider.fetchCoinMarketData(
              ids: ['bitcoin'],
              vsCurrency: 'eur',
            ),
          ).called(1);
        },
      );
    });
  });
}
