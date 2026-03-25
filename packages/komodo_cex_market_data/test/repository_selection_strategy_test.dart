import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/_core_index.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

// Test provider implementations similar to repository_priority_manager_test.dart
class TestBinanceProvider implements IBinanceProvider {
  @override
  Future<Binance24hrTicker> fetch24hrTicker(
    String symbol, {
    String? baseUrl,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<BinanceExchangeInfoResponse> fetchExchangeInfo({
    String? baseUrl,
  }) async {
    return BinanceExchangeInfoResponse(
      symbols: [],
      rateLimits: [],
      serverTime: 0,
      timezone: '',
    );
  }

  @override
  Future<BinanceExchangeInfoResponseReduced> fetchExchangeInfoReduced({
    String? baseUrl,
  }) async {
    return BinanceExchangeInfoResponseReduced(
      timezone: 'UTC',
      serverTime: DateTime.now().millisecondsSinceEpoch,
      symbols: [
        SymbolReduced(
          symbol: 'BTCUSD',
          status: 'TRADING',
          baseAsset: 'BTC',
          baseAssetPrecision: 8,
          quoteAsset: 'USD',
          quotePrecision: 8,
          quoteAssetPrecision: 8,
          isSpotTradingAllowed: true,
        ),
      ],
    );
  }

  @override
  Future<CoinOhlc> fetchKlines(
    String symbol,
    String interval, {
    int? startUnixTimestampMilliseconds,
    int? endUnixTimestampMilliseconds,
    int? limit,
    String? baseUrl,
  }) async {
    throw UnimplementedError();
  }
}

// Mock repository that always supports requests
class MockSupportingRepository implements CexRepository {
  MockSupportingRepository(this.name, {this.shouldSupport = true});
  final String name;
  final bool shouldSupport;

  @override
  Future<bool> supports(
    AssetId assetId,
    QuoteCurrency fiatCurrency,
    PriceRequestType requestType,
  ) async {
    return shouldSupport;
  }

  // Other methods not needed for this test
  @override
  Future<List<CexCoin>> getCoinList() async => [];

  @override
  Future<CoinOhlc> getCoinOhlc(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    GraphInterval interval, {
    DateTime? startAt,
    DateTime? endAt,
    int? limit,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoinFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Map<DateTime, Decimal>> getCoinFiatPrices(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoin24hrPriceChange(
    AssetId assetId, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  String resolveTradingSymbol(AssetId assetId) => '';

  @override
  bool canHandleAsset(AssetId assetId) => true;

  @override
  void dispose() {
    // No resources to dispose in mock
  }

  @override
  String toString() => 'MockRepository($name)';
}

// Mock repository that throws errors during support checks
class MockFailingRepository implements CexRepository {
  @override
  Future<bool> supports(
    AssetId assetId,
    QuoteCurrency fiatCurrency,
    PriceRequestType requestType,
  ) async {
    throw Exception('Mock error during support check');
  }

  // Other methods not needed for this test
  @override
  Future<List<CexCoin>> getCoinList() async => [];

  @override
  Future<CoinOhlc> getCoinOhlc(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    GraphInterval interval, {
    DateTime? startAt,
    DateTime? endAt,
    int? limit,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoinFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Map<DateTime, Decimal>> getCoinFiatPrices(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoin24hrPriceChange(
    AssetId assetId, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  String resolveTradingSymbol(AssetId assetId) => '';

  @override
  bool canHandleAsset(AssetId assetId) => true;

  @override
  void dispose() {
    // No resources to dispose in mock
  }

  @override
  String toString() => 'MockFailingRepository';
}

class MockSlowSupportingRepository extends MockSupportingRepository {
  MockSlowSupportingRepository(super.name, {required this.delay});

  final Duration delay;

  @override
  Future<bool> supports(
    AssetId assetId,
    QuoteCurrency fiatCurrency,
    PriceRequestType requestType,
  ) async {
    await Future<void>.delayed(delay);
    return super.supports(assetId, fiatCurrency, requestType);
  }
}

void main() {
  group('RepositorySelectionStrategy', () {
    late RepositorySelectionStrategy strategy;
    late BinanceRepository binance;

    setUp(() {
      strategy = DefaultRepositorySelectionStrategy();
      binance = BinanceRepository(
        binanceProvider: TestBinanceProvider(),
        enableMemoization: false,
      );
    });

    group('selectRepository', () {
      test('selects repository based on priority', () async {
        final supportingRepo = MockSupportingRepository('supporting');
        final nonSupportingRepo = MockSupportingRepository(
          'non-supporting',
          shouldSupport: false,
        );

        final asset = AssetId(
          id: 'BTC',
          name: 'BTC',
          symbol: AssetSymbol(assetConfigId: 'BTC'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );
        const fiat = FiatCurrency.usd;

        final repo = await strategy.selectRepository(
          assetId: asset,
          fiatCurrency: fiat,
          requestType: PriceRequestType.currentPrice,
          availableRepositories: [nonSupportingRepo, supportingRepo],
        );

        expect(repo, equals(supportingRepo));
      });

      test(
        'returns null if no repositories support the asset/fiat combination',
        () async {
          final nonSupportingRepo1 = MockSupportingRepository(
            'repo1',
            shouldSupport: false,
          );
          final nonSupportingRepo2 = MockSupportingRepository(
            'repo2',
            shouldSupport: false,
          );

          final asset = AssetId(
            id: 'UNSUPPORTED',
            name: 'Unsupported',
            symbol: AssetSymbol(assetConfigId: 'UNSUPPORTED'),
            chainId: AssetChainId(chainId: 0),
            derivationPath: null,
            subClass: CoinSubClass.utxo,
          );

          final repo = await strategy.selectRepository(
            assetId: asset,
            fiatCurrency: FiatCurrency.usd,
            requestType: PriceRequestType.currentPrice,
            availableRepositories: [nonSupportingRepo1, nonSupportingRepo2],
          );

          expect(repo, isNull);
        },
      );

      test('handles repository support check failures gracefully', () async {
        final errorRepo = MockFailingRepository();
        final supportingRepo = MockSupportingRepository('supporting');

        final asset = AssetId(
          id: 'BTC',
          name: 'BTC',
          symbol: AssetSymbol(assetConfigId: 'BTC'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final repo = await strategy.selectRepository(
          assetId: asset,
          fiatCurrency: FiatCurrency.usd,
          requestType: PriceRequestType.currentPrice,
          availableRepositories: [errorRepo, supportingRepo],
        );

        expect(repo, equals(supportingRepo));
      });

      test('allows slower support checks within timeout budget', () async {
        final slowRepo = MockSlowSupportingRepository(
          'slow-supporting',
          delay: const Duration(seconds: 3),
        );

        final asset = AssetId(
          id: 'TRX',
          name: 'TRON',
          symbol: AssetSymbol(assetConfigId: 'TRX'),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        final repo = await strategy.selectRepository(
          assetId: asset,
          fiatCurrency: Stablecoin.usdt,
          requestType: PriceRequestType.priceHistory,
          availableRepositories: [slowRepo],
        );

        expect(repo, equals(slowRepo));
      });
    });

    group('mapped quote currency support', () {
      test('should demonstrate quote currency mapping behavior', () async {
        // Test USDT stablecoin mapping behavior
        expect(
          Stablecoin.usdt.coinGeckoId,
          equals('usd'),
          reason: 'USDT should map to USD for CoinGecko',
        );

        expect(
          Stablecoin.usdt.coinPaprikaId,
          equals('usdt'),
          reason: 'USDT should use usdt identifier for CoinPaprika',
        );

        // Test EUR-pegged stablecoin
        expect(
          Stablecoin.eurs.coinGeckoId,
          equals('eur'),
          reason: 'EURS should map to EUR for CoinGecko',
        );

        expect(
          Stablecoin.eurs.coinPaprikaId,
          equals('eurs'),
          reason: 'EURS should use eurs identifier for CoinPaprika',
        );
      });

      test('should work with mock repositories that handle mapping', () async {
        // Create mock repositories that demonstrate the mapping behavior
        final geckoLikeRepo = MockGeckoStyleRepository();
        final paprikaLikeRepo = MockPaprikaStyleRepository();

        final btcAsset = AssetId(
          id: 'BTC',
          name: 'Bitcoin',
          symbol: AssetSymbol(
            assetConfigId: 'BTC',
            coinGeckoId: 'bitcoin',
            coinPaprikaId: 'btc-bitcoin',
          ),
          chainId: AssetChainId(chainId: 0),
          derivationPath: null,
          subClass: CoinSubClass.utxo,
        );

        // Both should support USDT but via different mapping strategies
        final geckoSupportsUSDT = await geckoLikeRepo.supports(
          btcAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
        );
        expect(geckoSupportsUSDT, isTrue);

        final paprikaSupportsUSDT = await paprikaLikeRepo.supports(
          btcAsset,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
        );
        expect(paprikaSupportsUSDT, isTrue);

        // Repository selection should work for mapped currencies
        final selectedRepo = await strategy.selectRepository(
          assetId: btcAsset,
          fiatCurrency: Stablecoin.usdt,
          requestType: PriceRequestType.currentPrice,
          availableRepositories: [geckoLikeRepo, paprikaLikeRepo],
        );

        expect(selectedRepo, isNotNull);
      });
    });

    group('ensureCacheInitialized', () {
      test('should complete without error (no-op implementation)', () async {
        await expectLater(
          strategy.ensureCacheInitialized([binance]),
          completes,
        );
      });
    });
  });
}

// Mock repository that simulates CoinGecko-style mapping (USDT -> USD)
class MockGeckoStyleRepository implements CexRepository {
  @override
  Future<bool> supports(
    AssetId assetId,
    QuoteCurrency fiatCurrency,
    PriceRequestType requestType,
  ) async {
    // Simulate CoinGecko behavior: uses coinGeckoId for quote mapping
    final mappedQuote = fiatCurrency.coinGeckoId;

    // Support common assets and mapped quote currencies
    final supportedAssets = {'BTC', 'ETH'};
    final supportedQuotes = {'usd', 'eur', 'gbp'};

    final assetSupported = supportedAssets.contains(
      assetId.symbol.configSymbol.toUpperCase(),
    );
    final quoteSupported = supportedQuotes.contains(mappedQuote);

    return assetSupported && quoteSupported;
  }

  // Implement required methods
  @override
  Future<List<CexCoin>> getCoinList() async => [];

  @override
  Future<CoinOhlc> getCoinOhlc(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    GraphInterval interval, {
    DateTime? startAt,
    DateTime? endAt,
    int? limit,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoinFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Map<DateTime, Decimal>> getCoinFiatPrices(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoin24hrPriceChange(
    AssetId assetId, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  String resolveTradingSymbol(AssetId assetId) =>
      assetId.symbol.configSymbol.toLowerCase();

  @override
  bool canHandleAsset(AssetId assetId) => true;

  @override
  void dispose() {
    // No resources to dispose in mock
  }

  @override
  String toString() => 'MockGeckoStyleRepository';
}

// Mock repository that simulates CoinPaprika-style mapping (USDT -> usdt)
class MockPaprikaStyleRepository implements CexRepository {
  @override
  Future<bool> supports(
    AssetId assetId,
    QuoteCurrency fiatCurrency,
    PriceRequestType requestType,
  ) async {
    // Simulate CoinPaprika behavior: uses coinPaprikaId for quote mapping
    final mappedQuote = fiatCurrency.coinPaprikaId;

    // Support common assets and direct quote currencies
    final supportedAssets = {'BTC', 'ETH'};
    final supportedQuotes = {'usd', 'eur', 'usdt', 'usdc'};

    final assetSupported = supportedAssets.contains(
      assetId.symbol.configSymbol.toUpperCase(),
    );
    final quoteSupported = supportedQuotes.contains(mappedQuote);

    return assetSupported && quoteSupported;
  }

  // Implement required methods
  @override
  Future<List<CexCoin>> getCoinList() async => [];

  @override
  Future<CoinOhlc> getCoinOhlc(
    AssetId assetId,
    QuoteCurrency quoteCurrency,
    GraphInterval interval, {
    DateTime? startAt,
    DateTime? endAt,
    int? limit,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoinFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Map<DateTime, Decimal>> getCoinFiatPrices(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  Future<Decimal> getCoin24hrPriceChange(
    AssetId assetId, {
    QuoteCurrency fiatCurrency = Stablecoin.usdt,
  }) async => throw UnimplementedError();

  @override
  String resolveTradingSymbol(AssetId assetId) =>
      assetId.symbol.configSymbol.toLowerCase();

  @override
  bool canHandleAsset(AssetId assetId) => true;

  @override
  void dispose() {
    // No resources to dispose in mock
  }

  @override
  String toString() => 'MockPaprikaStyleRepository';
}
