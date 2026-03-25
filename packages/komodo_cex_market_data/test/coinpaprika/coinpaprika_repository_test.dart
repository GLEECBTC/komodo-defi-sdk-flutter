import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/_core_index.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fixtures/mock_helpers.dart';
import 'fixtures/test_constants.dart';
import 'fixtures/test_fixtures.dart';
import 'fixtures/verification_helpers.dart';

void main() {
  setUpAll(MockHelpers.registerFallbackValues);

  group('CoinPaprikaRepository', () {
    late MockCoinPaprikaProvider mockProvider;
    late CoinPaprikaRepository repository;

    setUp(() {
      mockProvider = MockCoinPaprikaProvider();
      repository = CoinPaprikaRepository(
        coinPaprikaProvider: mockProvider,
        enableMemoization: false, // Disable for testing
      );

      MockHelpers.setupMockProvider(mockProvider);
    });

    group('getCoinList', () {
      test('returns list of active coins with supported currencies', () async {
        // Arrange
        MockHelpers.setupProviderCoinListResponse(
          mockProvider,
          coins: TestData.allCoins,
        );

        // Act
        final result = await repository.getCoinList();

        // Assert
        expect(result, hasLength(2)); // Only active coins
        expect(result[0].id, equals(TestConstants.bitcoinCoinId));
        expect(result[0].symbol, equals(TestConstants.bitcoinSymbol));
        expect(result[0].name, equals(TestConstants.bitcoinName));
        expect(result[0].currencies, contains('usd'));
        expect(result[0].currencies, contains('btc'));
        expect(result[0].currencies, contains('eur'));

        expect(result[1].id, equals(TestConstants.ethereumCoinId));
        expect(result[1].symbol, equals(TestConstants.ethereumSymbol));
        expect(result[1].name, equals(TestConstants.ethereumName));

        VerificationHelpers.verifyFetchCoinList(mockProvider);
      });

      test('handles provider errors gracefully', () async {
        // Arrange
        MockHelpers.setupProviderErrors(
          mockProvider,
          coinListError: Exception('API error'),
        );

        // Act & Assert
        await expectLater(
          () => repository.getCoinList(),
          throwsA(isA<Exception>()),
        );
        VerificationHelpers.verifyFetchCoinList(mockProvider);
      });
    });

    group('resolveTradingSymbol', () {
      test('returns coinPaprikaId when available', () {
        // Act
        final result = repository.resolveTradingSymbol(TestData.bitcoinAsset);

        // Assert
        expect(result, equals(TestConstants.bitcoinCoinId));
      });

      test('throws ArgumentError when coinPaprikaId is missing', () async {
        // Act & Assert
        await expectLater(
          () => repository.resolveTradingSymbol(TestData.unsupportedAsset),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('canHandleAsset', () {
      test('returns true when coinPaprikaId is available', () {
        // Act
        final result = repository.canHandleAsset(TestData.bitcoinAsset);

        // Assert
        expect(result, isTrue);
      });

      test('returns false when coinPaprikaId is missing', () {
        // Act
        final result = repository.canHandleAsset(TestData.unsupportedAsset);

        // Assert
        expect(result, isFalse);
      });
    });

    group('getCoinFiatPrice', () {
      test('returns current price from markets endpoint', () async {
        // Arrange
        MockHelpers.setupProviderTickerResponse(mockProvider);

        // Act
        final result = await repository.getCoinFiatPrice(TestData.bitcoinAsset);

        // Assert
        expect(result, equals(TestData.bitcoinPriceDecimal));
        VerificationHelpers.verifyFetchCoinTicker(
          mockProvider,
          expectedCoinId: TestConstants.bitcoinCoinId,
          expectedQuotes: [Stablecoin.usdt],
        );
      });

      test('throws exception when no market data available', () async {
        // Arrange
        MockHelpers.setupEmptyQuotesScenario(mockProvider);

        // Act & Assert
        expect(
          () => repository.getCoinFiatPrice(TestData.bitcoinAsset),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('getCoinOhlc', () {
      test('returns OHLC data within API plan limits', () async {
        // Arrange
        final mockOhlcData = [TestFixtures.createMockOhlc()];
        MockHelpers.setupProviderOhlcResponse(
          mockProvider,
          ohlcData: mockOhlcData,
        );

        final now = DateTime.now();
        final startAt = now.subtract(const Duration(hours: 12));
        final endAt = now.subtract(
          const Duration(hours: 1),
        ); // Within 24h limit

        // Act
        final result = await repository.getCoinOhlc(
          TestData.bitcoinAsset,
          Stablecoin.usdt,
          GraphInterval.oneHour,
          startAt: startAt,
          endAt: endAt,
        );

        // Assert
        expect(result.ohlc, hasLength(1));
        expect(
          result.ohlc.first.openDecimal,
          equals(TestData.bitcoinPriceDecimal),
        );
        expect(result.ohlc.first.highDecimal, equals(Decimal.fromInt(52000)));
        expect(result.ohlc.first.lowDecimal, equals(Decimal.fromInt(44000)));
        expect(
          result.ohlc.first.closeDecimal,
          equals(TestData.bitcoinPriceDecimal),
        );

        VerificationHelpers.verifyFetchHistoricalOhlc(mockProvider);
      });

      test(
        'throws ArgumentError for requests exceeding 24h without start/end dates',
        () async {
          // Act - should not throw since default period is 24h (within limit)
          final result = await repository.getCoinOhlc(
            TestData.bitcoinAsset,
            Stablecoin.usdt,
            GraphInterval.oneHour,
            // No startAt/endAt - defaults to 24h which is within limit
          );

          // Assert - should get empty result, not throw error
          expect(result.ohlc, isEmpty);
        },
      );

      test(
        'splits requests to fetch all available data when exceeding plan limits',
        () async {
          // Arrange
          MockHelpers.setupBatchingScenario(
            mockProvider,
            apiPlan: const CoinPaprikaApiPlan.business(),
          );

          final now = DateTime.now();
          final requestedStart = now.subtract(
            const Duration(days: 200),
          ); // Within 365-day limit
          final endAt = now;

          final result = await repository.getCoinOhlc(
            TestData.bitcoinAsset,
            Stablecoin.usdt,
            GraphInterval.oneDay,
            startAt: requestedStart,
            endAt: endAt,
          );

          // Assert - should contain data from all batches
          expect(result.ohlc, isNotEmpty);
          expect(
            result.ohlc.length,
            greaterThanOrEqualTo(2),
          ); // Multiple batches should return combined data

          // Verify that multiple provider calls were made for batching (200 days should trigger multiple batches)
          VerificationHelpers.verifyMultipleProviderCalls(mockProvider, 0);
        },
      );

      test(
        'returns empty OHLC when entire requested range is before cutoff',
        () async {
          // Arrange
          MockHelpers.setupApiPlan(
            mockProvider,
            const CoinPaprikaApiPlan.free(),
          );

          // Request data from 400 days ago to 390 days ago (both before cutoff)
          final requestedStart = DateTime.now().subtract(
            const Duration(days: 400),
          );
          final requestedEnd = DateTime.now().subtract(
            const Duration(days: 390),
          );

          // Act
          final result = await repository.getCoinOhlc(
            TestData.bitcoinAsset,
            Stablecoin.usdt,
            GraphInterval.oneDay,
            startAt: requestedStart,
            endAt: requestedEnd,
          );

          // Assert - should return empty OHLC without making provider calls
          expect(result.ohlc, isEmpty);

          // Verify no provider calls were made since effective range is invalid
          VerificationHelpers.verifyNoFetchHistoricalOhlcCalls(mockProvider);
        },
      );

      test(
        'fetches all available data by splitting requests when part of range is before cutoff',
        () async {
          // Arrange
          MockHelpers.setupApiPlan(
            mockProvider,
            const CoinPaprikaApiPlan.free(),
          );

          final mockOhlcData = [
            TestFixtures.createMockOhlc(
              timeOpen: DateTime.now().subtract(const Duration(days: 100)),
              timeClose: DateTime.now().subtract(const Duration(days: 99)),
            ),
          ];
          MockHelpers.setupProviderOhlcResponse(
            mockProvider,
            ohlcData: mockOhlcData,
          );

          // Request data from 400 days ago to now (starts before cutoff but ends within available range)
          final requestedStart = DateTime.now().subtract(
            const Duration(days: 400),
          );
          final endAt = DateTime.now();

          // Act
          final result = await repository.getCoinOhlc(
            TestData.bitcoinAsset,
            Stablecoin.usdt,
            GraphInterval.oneDay,
            startAt: requestedStart,
            endAt: endAt,
          );

          // Assert - should get available data from cutoff onwards
          expect(result.ohlc, isNotEmpty);

          VerificationHelpers.verifyFetchHistoricalOhlc(
            mockProvider,
            expectedCoinId: TestConstants.bitcoinCoinId,
            expectedQuote: Stablecoin.usdt,
            expectedCallCount: 5, // 400 days batched into ~90-day chunks
          );
        },
      );
    });

    group('supports', () {
      test('returns true for supported asset and quote currency', () async {
        // Arrange
        MockHelpers.setupProviderCoinListResponse(
          mockProvider,
          coins: [TestData.bitcoinCoin],
        );

        // Act
        final result = await repository.supports(
          TestData.bitcoinAsset,
          FiatCurrency.usd,
          PriceRequestType.currentPrice,
        );

        // Assert
        expect(result, isTrue);
      });

      test('returns true for supported stablecoin quote currency', () async {
        // Arrange
        MockHelpers.setupProviderCoinListResponse(
          mockProvider,
          coins: [TestData.bitcoinCoin],
        );

        // Act - Using USDT stablecoin which should be supported via its underlying fiat (USD)
        // even though the provider only lists USD, not USDT, in supportedQuoteCurrencies
        final result = await repository.supports(
          TestData.bitcoinAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
        );

        // Assert
        expect(result, isTrue);
      });

      test(
        'returns true for EUR-based stablecoin when EUR is supported',
        () async {
          // Arrange
          MockHelpers.setupProviderCoinListResponse(
            mockProvider,
            coins: [TestData.bitcoinCoin],
          );

          // Act - Using EURS stablecoin which should be supported via its underlying fiat (EUR)
          final result = await repository.supports(
            TestData.bitcoinAsset,
            Stablecoin.eurs,
            PriceRequestType.currentPrice,
          );

          // Assert
          expect(result, isTrue);
        },
      );

      test(
        'returns false for stablecoin with unsupported underlying fiat',
        () async {
          // Arrange - Mock provider that doesn't support JPY
          when(() => mockProvider.supportedQuoteCurrencies).thenReturn([
            FiatCurrency.usd,
            FiatCurrency.eur,
            // No JPY here
          ]);

          MockHelpers.setupProviderCoinListResponse(
            mockProvider,
            coins: [TestData.bitcoinCoin],
          );

          // Act - Using JPYT stablecoin which maps to JPY (not supported by provider)
          final result = await repository.supports(
            TestData.bitcoinAsset,
            Stablecoin.jpyt,
            PriceRequestType.currentPrice,
          );

          // Assert
          expect(result, isFalse);
        },
      );

      test('returns true for TRX via fallback CoinPaprika id', () async {
        when(
          () => mockProvider.supportedQuoteCurrencies,
        ).thenReturn([FiatCurrency.usd, FiatCurrency.eur]);

        MockHelpers.setupProviderCoinListResponse(
          mockProvider,
          coins: const [
            CoinPaprikaCoin(
              id: 'trx-tron',
              name: 'TRON',
              symbol: 'TRX',
              rank: 1,
              isNew: false,
              isActive: true,
              type: 'coin',
            ),
          ],
        );

        final trxAsset = AssetId(
          id: 'TRX',
          name: 'TRON',
          symbol: AssetSymbol(assetConfigId: 'TRX'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final result = await repository.supports(
          trxAsset,
          Stablecoin.usdt,
          PriceRequestType.priceHistory,
        );

        expect(result, isTrue);
      });

      test('returns false for unsupported quote currency', () async {
        // Arrange
        MockHelpers.setupProviderCoinListResponse(
          mockProvider,
          coins: [TestData.bitcoinCoin],
        );

        // Act - Using an unsupported quote currency
        final result = await repository.supports(
          TestData.bitcoinAsset,
          const QuoteCurrency.commodity(symbol: 'GOLD', displayName: 'Gold'),
          PriceRequestType.currentPrice,
        );

        // Assert
        expect(result, isFalse);
      });

      test('returns false for unsupported fiat currency', () async {
        // Arrange
        MockHelpers.setupProviderCoinListResponse(
          mockProvider,
          coins: [TestData.bitcoinCoin],
        );

        // Create an unsupported fiat currency
        const unsupportedFiat = QuoteCurrency.fiat(
          symbol: 'UNSUPPORTED',
          displayName: 'Unsupported Currency',
        );

        // Act - Using an unsupported fiat currency
        final result = await repository.supports(
          TestData.bitcoinAsset,
          unsupportedFiat,
          PriceRequestType.currentPrice,
        );

        // Assert
        expect(result, isFalse);
      });

      test('returns false when asset cannot be resolved', () async {
        // Act
        final result = await repository.supports(
          TestData.unsupportedAsset,
          FiatCurrency.usd,
          PriceRequestType.currentPrice,
        );

        // Assert
        expect(result, isFalse);
      });
    });

    group('stablecoin to fiat mapping', () {
      test('correctly maps USDT to USD for price requests', () async {
        // Arrange
        MockHelpers.setupProviderTickerResponse(mockProvider);

        // Act - Using USDT stablecoin
        final result = await repository.getCoinFiatPrice(TestData.bitcoinAsset);

        // Assert
        expect(result, equals(TestData.bitcoinPriceDecimal));

        // Verify that the provider was called with USDT stablecoin
        VerificationHelpers.verifyFetchCoinTicker(
          mockProvider,
          expectedCoinId: TestConstants.bitcoinCoinId,
          expectedQuotes: [Stablecoin.usdt],
        );
      });

      test('correctly maps EUR-pegged stablecoin for price requests', () async {
        // Arrange
        final mockTicker = TestFixtures.createMockTicker(
          quoteCurrency: TestConstants.eursQuote,
          price: 42000,
        );
        MockHelpers.setupProviderTickerResponse(
          mockProvider,
          ticker: mockTicker,
        );

        // Act - Using EURS stablecoin
        final result = await repository.getCoinFiatPrice(
          TestData.bitcoinAsset,
          fiatCurrency: Stablecoin.eurs,
        );

        // Assert
        expect(result, equals(Decimal.fromInt(42000)));

        // Verify that the provider was called with EURS stablecoin
        VerificationHelpers.verifyFetchCoinTicker(
          mockProvider,
          expectedCoinId: TestConstants.bitcoinCoinId,
          expectedQuotes: [Stablecoin.eurs],
        );
      });

      test(
        'uses correct coinPaprikaId for stablecoin in OHLC requests',
        () async {
          // Arrange
          final mockOhlcData = [TestFixtures.createMockOhlc()];
          MockHelpers.setupProviderOhlcResponse(
            mockProvider,
            ohlcData: mockOhlcData,
          );

          final now = DateTime.now();
          final startAt = now.subtract(const Duration(hours: 12));
          final endAt = now.subtract(const Duration(hours: 1));

          // Act - Using USDT stablecoin
          final result = await repository.getCoinOhlc(
            TestData.bitcoinAsset,
            Stablecoin.usdt,
            GraphInterval.oneHour,
            startAt: startAt,
            endAt: endAt,
          );

          // Assert
          expect(result.ohlc, hasLength(1));
          expect(
            result.ohlc.first.closeDecimal,
            equals(TestData.bitcoinPriceDecimal),
          );

          // Verify that the provider was called with USDT stablecoin directly
          VerificationHelpers.verifyFetchHistoricalOhlc(
            mockProvider,
            expectedCoinId: TestConstants.bitcoinCoinId,
            expectedQuote: Stablecoin.usdt,
          );
        },
      );

      test(
        'correctly handles 24hr price change with stablecoin currency',
        () async {
          // Arrange
          final mockTicker = TestFixtures.createMockTicker(
            quoteCurrency: TestConstants.usdcQuote,
            percentChange24h: 3.2,
          );
          MockHelpers.setupProviderTickerResponse(
            mockProvider,
            ticker: mockTicker,
          );

          // Act - Using USDC stablecoin
          final result = await repository.getCoin24hrPriceChange(
            TestData.bitcoinAsset,
            fiatCurrency: Stablecoin.usdc,
          );

          // Assert
          expect(result, equals(Decimal.parse('3.2')));

          // Verify that the provider was called with USDC stablecoin
          VerificationHelpers.verifyFetchCoinTicker(
            mockProvider,
            expectedCoinId: TestConstants.bitcoinCoinId,
            expectedQuotes: [Stablecoin.usdc],
          );
        },
      );
    });

    group('Batch Duration Validation Tests', () {
      test('ensures no batch exceeds 90 days for free plan', () async {
        // Arrange
        final assetId = AssetId(
          id: 'BTC',
          name: 'Bitcoin',
          symbol: AssetSymbol(
            assetConfigId: 'BTC',
            coinPaprikaId: 'btc-bitcoin',
          ),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        // Set up Free plan (90-day batch size for historical ticks)
        when(
          () => mockProvider.apiPlan,
        ).thenReturn(const CoinPaprikaApiPlan.free());

        final mockOhlcData = [
          Ohlc.coinpaprika(
            timeOpen: DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 30))
                .millisecondsSinceEpoch,
            timeClose: DateTime.now().toUtc().millisecondsSinceEpoch,
            open: Decimal.fromInt(50000),
            high: Decimal.fromInt(52000),
            low: Decimal.fromInt(48000),
            close: Decimal.fromInt(51000),
            volume: Decimal.fromInt(1000000),
            marketCap: Decimal.fromInt(900000000000),
          ),
        ];

        // Mock provider to track batch requests
        final capturedBatchRequests = <Map<String, dynamic>>[];
        when(
          () => mockProvider.fetchHistoricalOhlc(
            coinId: any(named: 'coinId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            quote: any(named: 'quote'),
            interval: any(named: 'interval'),
          ),
        ).thenAnswer((invocation) async {
          final startDate = invocation.namedArguments[#startDate] as DateTime;
          final endDate = invocation.namedArguments[#endDate] as DateTime;

          capturedBatchRequests.add({
            'startDate': startDate,
            'endDate': endDate,
            'duration': endDate.difference(startDate),
          });

          return mockOhlcData;
        });

        // Request data for exactly 200 days to force multiple batches
        // Each batch should be 90 days
        final now = DateTime.now().toUtc();
        final requestedStart = now.subtract(const Duration(days: 200));
        final requestedEnd = now;

        // Act
        await repository.getCoinOhlc(
          assetId,
          FiatCurrency.usd,
          GraphInterval.oneDay,
          startAt: requestedStart,
          endAt: requestedEnd,
        );

        // Assert
        expect(capturedBatchRequests, isNotEmpty);

        // Verify each batch is within the safe limit (90 days)
        const maxSafeDuration = Duration(days: 90);
        for (final request in capturedBatchRequests) {
          final duration = request['duration'] as Duration;
          expect(
            duration,
            lessThanOrEqualTo(maxSafeDuration),
            reason:
                'Batch duration ${duration.inDays} days '
                'exceeds safe limit of 90 days',
          );
        }
      });

      test('uses UTC time for all date calculations', () async {
        // Arrange
        final assetId = AssetId(
          id: 'BTC',
          name: 'Bitcoin',
          symbol: AssetSymbol(
            assetConfigId: 'BTC',
            coinPaprikaId: 'btc-bitcoin',
          ),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        when(
          () => mockProvider.apiPlan,
        ).thenReturn(const CoinPaprikaApiPlan.free());

        final mockOhlcData = [
          Ohlc.coinpaprika(
            timeOpen: DateTime.now().toUtc().millisecondsSinceEpoch,
            timeClose: DateTime.now().toUtc().millisecondsSinceEpoch,
            open: Decimal.fromInt(50000),
            high: Decimal.fromInt(52000),
            low: Decimal.fromInt(48000),
            close: Decimal.fromInt(51000),
            volume: Decimal.fromInt(1000000),
            marketCap: Decimal.fromInt(900000000000),
          ),
        ];

        DateTime? capturedEndDate;

        when(
          () => mockProvider.fetchHistoricalOhlc(
            coinId: any(named: 'coinId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            quote: any(named: 'quote'),
            interval: any(named: 'interval'),
          ),
        ).thenAnswer((invocation) async {
          capturedEndDate = invocation.namedArguments[#endDate] as DateTime?;
          return mockOhlcData;
        });

        // Act - don't provide endAt to test default behavior
        await repository.getCoinOhlc(
          assetId,
          FiatCurrency.usd,
          GraphInterval.oneDay,
        );

        // Assert
        expect(capturedEndDate, isNotNull);

        // Verify the captured endDate is in UTC (should have zero offset from UTC)
        if (capturedEndDate != null) {
          final utcNow = DateTime.now().toUtc();
          final timeDifference = capturedEndDate!.difference(utcNow).abs();

          // Should be very close to current UTC time (within 1 minute)
          expect(
            timeDifference,
            lessThan(const Duration(minutes: 1)),
            reason:
                'End date should be close to current UTC time. '
                'Captured: ${capturedEndDate!.toIso8601String()}, '
                'UTC Now: ${utcNow.toIso8601String()}',
          );
        }
      });

      test(
        'validates batch duration and throws error if exceeding safe limit',
        () async {
          // Arrange
          final assetId = AssetId(
            id: 'BTC',
            name: 'Bitcoin',
            symbol: AssetSymbol(
              assetConfigId: 'BTC',
              coinPaprikaId: 'btc-bitcoin',
            ),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          // Set up a custom plan that would create an invalid batch
          when(
            () => mockProvider.apiPlan,
          ).thenReturn(const CoinPaprikaApiPlan.free());

          // Mock the provider to return data
          when(
            () => mockProvider.fetchHistoricalOhlc(
              coinId: any(named: 'coinId'),
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
              quote: any(named: 'quote'),
              interval: any(named: 'interval'),
            ),
          ).thenAnswer(
            (_) async => [
              Ohlc.coinpaprika(
                timeOpen: DateTime.now().toUtc().millisecondsSinceEpoch,
                timeClose: DateTime.now().toUtc().millisecondsSinceEpoch,
                open: Decimal.fromInt(50000),
                high: Decimal.fromInt(52000),
                low: Decimal.fromInt(48000),
                close: Decimal.fromInt(51000),
                volume: Decimal.fromInt(1000000),
                marketCap: Decimal.fromInt(900000000000),
              ),
            ],
          );

          // Act & Assert
          // Create a scenario where batch calculation might exceed safe limit
          final now = DateTime.now().toUtc();
          final requestedStart = DateTime(
            now.year,
            now.month,
            now.day - 2,
          ); // Exactly 2 days ago
          final requestedEnd = DateTime(
            now.year,
            now.month,
            now.day,
          ); // Start of today

          // This should not throw an error as the repository should handle batching correctly
          expect(
            () => repository.getCoinOhlc(
              assetId,
              FiatCurrency.usd,
              GraphInterval.oneDay,
              startAt: requestedStart,
              endAt: requestedEnd,
            ),
            returnsNormally,
          );
        },
      );

      test(
        'handles starter plan with 5-year limit and 90-day batch size',
        () async {
          // Arrange
          final assetId = AssetId(
            id: 'BTC',
            name: 'Bitcoin',
            symbol: AssetSymbol(
              assetConfigId: 'BTC',
              coinPaprikaId: 'btc-bitcoin',
            ),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          // Set up Starter plan (5 years limit with 90-day batch size)
          when(
            () => mockProvider.apiPlan,
          ).thenReturn(const CoinPaprikaApiPlan.starter());

          final mockOhlcData = [
            Ohlc.coinpaprika(
              timeOpen: DateTime.now().toUtc().millisecondsSinceEpoch,
              timeClose: DateTime.now().toUtc().millisecondsSinceEpoch,
              open: Decimal.fromInt(50000),
              high: Decimal.fromInt(52000),
              low: Decimal.fromInt(48000),
              close: Decimal.fromInt(51000),
              volume: Decimal.fromInt(1000000),
              marketCap: Decimal.fromInt(900000000000),
            ),
          ];

          final capturedBatchRequests = <Duration>[];
          when(
            () => mockProvider.fetchHistoricalOhlc(
              coinId: any(named: 'coinId'),
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
              quote: any(named: 'quote'),
              interval: any(named: 'interval'),
            ),
          ).thenAnswer((invocation) async {
            final startDate = invocation.namedArguments[#startDate] as DateTime;
            final endDate = invocation.namedArguments[#endDate] as DateTime;
            capturedBatchRequests.add(endDate.difference(startDate));
            return mockOhlcData;
          });

          // Request data for exactly 200 days (should create multiple 90-day batches)
          final now = DateTime.now().toUtc();
          final requestedStart = now.subtract(const Duration(days: 200));
          final requestedEnd = now;

          // Act
          await repository.getCoinOhlc(
            assetId,
            FiatCurrency.usd,
            GraphInterval.oneDay,
            startAt: requestedStart,
            endAt: requestedEnd,
          );

          // Assert
          expect(capturedBatchRequests, isNotEmpty);

          // For starter plan with 90-day batch size, max batch should be 90 days
          const maxSafeDuration = Duration(days: 90);

          for (final duration in capturedBatchRequests) {
            expect(
              duration,
              lessThanOrEqualTo(maxSafeDuration),
              reason:
                  'Batch duration ${duration.inDays} days '
                  'exceeds safe limit of 90 days for starter plan',
            );
          }
        },
      );

      test('batch size prevents oversized requests', () async {
        // Arrange
        final assetId = AssetId(
          id: 'BTC',
          name: 'Bitcoin',
          symbol: AssetSymbol(
            assetConfigId: 'BTC',
            coinPaprikaId: 'btc-bitcoin',
          ),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        // Test with 90-day batch size for historical ticks
        when(
          () => mockProvider.apiPlan,
        ).thenReturn(const CoinPaprikaApiPlan.free());

        final mockOhlcData = [
          Ohlc.coinpaprika(
            timeOpen: DateTime.now().toUtc().millisecondsSinceEpoch,
            timeClose: DateTime.now().toUtc().millisecondsSinceEpoch,
            open: Decimal.fromInt(50000),
            high: Decimal.fromInt(52000),
            low: Decimal.fromInt(48000),
            close: Decimal.fromInt(51000),
            volume: Decimal.fromInt(1000000),
            marketCap: Decimal.fromInt(900000000000),
          ),
        ];

        Duration? capturedBatchDuration;
        when(
          () => mockProvider.fetchHistoricalOhlc(
            coinId: any(named: 'coinId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            quote: any(named: 'quote'),
            interval: any(named: 'interval'),
          ),
        ).thenAnswer((invocation) async {
          final startDate = invocation.namedArguments[#startDate] as DateTime;
          final endDate = invocation.namedArguments[#endDate] as DateTime;
          capturedBatchDuration = endDate.difference(startDate);
          return mockOhlcData;
        });

        // Request data for exactly 50 days - should fit in single batch
        final now = DateTime.now().toUtc();
        final requestedStart = now.subtract(const Duration(days: 50));
        final requestedEnd = now;

        // Act
        await repository.getCoinOhlc(
          assetId,
          FiatCurrency.usd,
          GraphInterval.oneDay,
          startAt: requestedStart,
          endAt: requestedEnd,
        );

        // Assert
        expect(capturedBatchDuration, isNotNull);

        // Batch should not exceed 90-day limit
        const expectedMaxDuration = Duration(days: 90);
        expect(
          capturedBatchDuration,
          lessThanOrEqualTo(expectedMaxDuration),
          reason:
              'Batch duration should not exceed 90-day limit. '
              'Expected max: 90 days, '
              'Actual: ${capturedBatchDuration!.inDays} days',
        );
      });
    });
  });
}
