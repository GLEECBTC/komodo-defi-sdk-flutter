/// Test fixtures for creating mock data used across CoinPaprika tests
library;

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart'
    show CoinPaprikaQuote;
import 'package:komodo_cex_market_data/src/_core_index.dart'
    show CoinPaprikaMarket;
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_ticker.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_ticker_quote.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';

import 'test_constants.dart';

/// Factory for creating test fixtures
class TestFixtures {
  TestFixtures._();

  /// Creates a mock HTTP response for coin list endpoint
  static http.Response createCoinListResponse({
    int statusCode = 200,
    List<Map<String, dynamic>>? coins,
  }) {
    final coinsData =
        coins ??
        [
          {
            'id': TestConstants.bitcoinCoinId,
            'name': TestConstants.bitcoinName,
            'symbol': TestConstants.bitcoinSymbol,
            'rank': 1,
            'is_new': false,
            'is_active': true,
            'type': 'coin',
          },
          {
            'id': TestConstants.ethereumCoinId,
            'name': TestConstants.ethereumName,
            'symbol': TestConstants.ethereumSymbol,
            'rank': 2,
            'is_new': false,
            'is_active': true,
            'type': 'coin',
          },
        ];

    return http.Response(jsonEncode(coinsData), statusCode);
  }

  /// Creates a mock HTTP response for historical OHLC endpoint
  static http.Response createHistoricalOhlcResponse({
    int statusCode = 200,
    List<Map<String, dynamic>>? ticks,
    String? timestamp,
    double? price,
    double? volume24h,
    double? marketCap,
  }) {
    final ticksData =
        ticks ??
        [
          {
            'timestamp': timestamp ?? TestConstants.currentTimestamp,
            'price': price ?? TestConstants.bitcoinPrice,
            'volume_24h': volume24h ?? TestConstants.highVolume,
            'market_cap': marketCap ?? TestConstants.bitcoinMarketCap,
          },
        ];

    return http.Response(jsonEncode(ticksData), statusCode);
  }

  /// Creates a mock HTTP response for ticker endpoint
  static http.Response createTickerResponse({
    int statusCode = 200,
    String? coinId,
    String? name,
    String? symbol,
    Map<String, Map<String, dynamic>>? quotes,
  }) {
    final tickerData = {
      'id': coinId ?? TestConstants.bitcoinCoinId,
      'name': name ?? TestConstants.bitcoinName,
      'symbol': symbol ?? TestConstants.bitcoinSymbol,
      'rank': 1,
      'circulating_supply': TestConstants.bitcoinCirculatingSupply,
      'total_supply': TestConstants.bitcoinTotalSupply,
      'max_supply': TestConstants.bitcoinMaxSupply,
      'beta_value': 0.0,
      'first_data_at': TestConstants.pastTimestamp,
      'last_updated': TestConstants.currentTimestamp,
      'quotes':
          quotes ??
          {
            TestConstants.usdtQuote: {
              'price': TestConstants.bitcoinPrice,
              'volume_24h': TestConstants.highVolume,
              'volume_24h_change_24h': 0.0,
              'market_cap': TestConstants.bitcoinMarketCap,
              'market_cap_change_24h': 0.0,
              'percent_change_15m': 0.0,
              'percent_change_30m': 0.0,
              'percent_change_1h': 0.0,
              'percent_change_6h': 0.0,
              'percent_change_12h': 0.0,
              'percent_change_24h': TestConstants.positiveChange,
              'percent_change_7d': 0.0,
              'percent_change_30d': 0.0,
              'percent_change_1y': 0.0,
            },
          },
    };

    return http.Response(jsonEncode(tickerData), statusCode);
  }

  /// Creates a mock HTTP response for markets endpoint
  static http.Response createMarketsResponse({
    int statusCode = 200,
    List<Map<String, dynamic>>? markets,
  }) {
    final marketsData =
        markets ??
        [
          {
            'exchange_id': 'binance',
            'exchange_name': 'Binance',
            'pair': 'BTC/USDT',
            'base_currency_id': TestConstants.bitcoinCoinId,
            'base_currency_name': TestConstants.bitcoinName,
            'quote_currency_id': 'usdt-tether',
            'quote_currency_name': 'Tether',
            'market_url': 'https://binance.com/trade/BTC_USDT',
            'category': 'Spot',
            'fee_type': 'Percentage',
            'outlier': false,
            'adjusted_volume_24h_share': 12.5,
            'last_updated': TestConstants.currentTimestamp,
            'quotes': {
              TestConstants.usdQuote: {
                'price': TestConstants.bitcoinPrice,
                'volume_24h': TestConstants.highVolume,
              },
            },
            'trust_score': 'high',
          },
        ];

    return http.Response(jsonEncode(marketsData), statusCode);
  }

  /// Creates a mock error HTTP response
  static http.Response createErrorResponse({
    int statusCode = 500,
    String? errorMessage,
  }) {
    return http.Response(errorMessage ?? 'Server Error', statusCode);
  }

  /// Creates a mock CoinPaprikaTicker with customizable parameters
  static CoinPaprikaTicker createMockTicker({
    String? id,
    String? name,
    String? symbol,
    int? rank,
    String quoteCurrency = TestConstants.usdtQuote,
    double price = TestConstants.bitcoinPrice,
    double percentChange24h = TestConstants.positiveChange,
    double volume24h = TestConstants.highVolume,
    double marketCap = TestConstants.bitcoinMarketCap,
  }) {
    return CoinPaprikaTicker(
      id: id ?? TestConstants.bitcoinCoinId,
      name: name ?? TestConstants.bitcoinName,
      symbol: symbol ?? TestConstants.bitcoinSymbol,
      rank: rank ?? 1,
      circulatingSupply: TestConstants.bitcoinCirculatingSupply,
      totalSupply: TestConstants.bitcoinTotalSupply,
      maxSupply: TestConstants.bitcoinMaxSupply,
      firstDataAt: TestData.pastDate,
      lastUpdated: TestData.testDate,
      quotes: {
        quoteCurrency: CoinPaprikaTickerQuote(
          price: price,
          volume24h: volume24h,
          marketCap: marketCap,
          percentChange24h: percentChange24h,
        ),
      },
    );
  }

  /// Creates a mock OHLC data point
  static Ohlc createMockOhlc({
    DateTime? timeOpen,
    DateTime? timeClose,
    Decimal? open,
    Decimal? high,
    Decimal? low,
    Decimal? close,
    Decimal? volume,
    Decimal? marketCap,
  }) {
    final now = DateTime.now();
    return Ohlc.coinpaprika(
      timeOpen:
          timeOpen?.millisecondsSinceEpoch ??
          now.subtract(const Duration(hours: 12)).millisecondsSinceEpoch,
      timeClose:
          timeClose?.millisecondsSinceEpoch ??
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      open: open ?? TestData.bitcoinPriceDecimal,
      high: high ?? Decimal.fromInt(52000),
      low: low ?? Decimal.fromInt(44000),
      close: close ?? TestData.bitcoinPriceDecimal,
      volume: volume ?? TestData.highVolumeDecimal,
      marketCap: marketCap ?? TestData.bitcoinMarketCapDecimal,
    );
  }

  /// Creates a list of mock OHLC data points
  static List<Ohlc> createMockOhlcList({
    int count = 1,
    DateTime? baseTime,
    Duration? interval,
  }) {
    final base = baseTime ?? DateTime.now().subtract(const Duration(days: 1));
    final step = interval ?? const Duration(hours: 1);

    return List.generate(count, (index) {
      final timeOpen = base.add(step * index);
      final timeClose = timeOpen.add(step);

      return createMockOhlc(
        timeOpen: timeOpen,
        timeClose: timeClose,
        open: Decimal.fromInt(50000 + index * 100),
        high: Decimal.fromInt(52000 + index * 100),
        low: Decimal.fromInt(48000 + index * 100),
        close: Decimal.fromInt(51000 + index * 100),
      );
    });
  }

  /// Creates a mock CoinPaprikaMarket
  static CoinPaprikaMarket createMockMarket({
    String? exchangeId,
    String? exchangeName,
    String? pair,
    String? baseId,
    String? baseName,
    String? quoteId,
    String? quoteName,
    Map<String, CoinPaprikaQuote>? quotes,
  }) {
    return CoinPaprikaMarket(
      exchangeId: exchangeId ?? 'binance',
      exchangeName: exchangeName ?? 'Binance',
      pair: pair ?? 'BTC/USDT',
      baseCurrencyId: baseId ?? TestConstants.bitcoinCoinId,
      baseCurrencyName: baseName ?? TestConstants.bitcoinName,
      quoteCurrencyId: quoteId ?? 'usdt-tether',
      quoteCurrencyName: quoteName ?? 'Tether',
      marketUrl: 'https://binance.com/trade/BTC_USDT',
      category: 'Spot',
      feeType: 'Percentage',
      outlier: false,
      adjustedVolume24hShare: 12.5,
      lastUpdated: TestData.testDate.toIso8601String(),
      quotes: quotes ?? <String, CoinPaprikaQuote>{},
    );
  }

  /// Creates a ticker with empty quotes for testing error scenarios
  static CoinPaprikaTicker createEmptyQuotesTicker({
    String? id,
    String? name,
    String? symbol,
  }) {
    return CoinPaprikaTicker(
      id: id ?? TestConstants.bitcoinCoinId,
      name: name ?? TestConstants.bitcoinName,
      symbol: symbol ?? TestConstants.bitcoinSymbol,
      rank: 1,
      circulatingSupply: TestConstants.bitcoinCirculatingSupply,
      totalSupply: TestConstants.bitcoinTotalSupply,
      maxSupply: TestConstants.bitcoinMaxSupply,
      firstDataAt: TestData.pastDate,
      lastUpdated: TestData.testDate,
      quotes: {}, // Empty quotes to trigger exception
    );
  }

  /// Creates multiple quote currencies data for testing
  static Map<String, Map<String, dynamic>> createMultipleQuotes({
    List<String>? currencies,
    List<double>? prices,
  }) {
    final defaultCurrencies =
        currencies ??
        [
          TestConstants.usdQuote,
          TestConstants.usdtQuote,
          TestConstants.eurQuote,
        ];
    final defaultPrices =
        prices ??
        [TestConstants.bitcoinPrice, TestConstants.bitcoinPrice + 10, 42000.0];

    final quotes = <String, Map<String, dynamic>>{};

    for (int i = 0; i < defaultCurrencies.length; i++) {
      quotes[defaultCurrencies[i]] = {
        'price': defaultPrices[i],
        'volume_24h': TestConstants.highVolume,
        'volume_24h_change_24h': 0.0,
        'market_cap': TestConstants.bitcoinMarketCap,
        'market_cap_change_24h': 0.0,
        'percent_change_15m': 0.0,
        'percent_change_30m': 0.0,
        'percent_change_1h': 0.0,
        'percent_change_6h': 0.0,
        'percent_change_12h': 0.0,
        'percent_change_24h': TestConstants.positiveChange,
        'percent_change_7d': 0.0,
        'percent_change_30d': 0.0,
        'percent_change_1y': 0.0,
      };
    }

    return quotes;
  }

  /// Creates batch OHLC data for testing pagination/batching scenarios
  static List<Ohlc> createBatchOhlcData({
    int batchCount = 2,
    int itemsPerBatch = 10,
    DateTime? startDate,
  }) {
    final start =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final allData = <Ohlc>[];

    for (int batch = 0; batch < batchCount; batch++) {
      for (int item = 0; item < itemsPerBatch; item++) {
        final index = batch * itemsPerBatch + item;
        final timeOpen = start.add(Duration(hours: index));
        final timeClose = timeOpen.add(const Duration(hours: 1));

        allData.add(
          createMockOhlc(
            timeOpen: timeOpen,
            timeClose: timeClose,
            open: Decimal.fromInt(45000 + index * 10),
            high: Decimal.fromInt(52000 + index * 10),
            low: Decimal.fromInt(44000 + index * 10),
            close: Decimal.fromInt(50000 + index * 10),
          ),
        );
      }
    }

    return allData;
  }
}
