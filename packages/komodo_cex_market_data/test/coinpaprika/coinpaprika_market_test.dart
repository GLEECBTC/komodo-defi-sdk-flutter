import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_market.dart';
import 'package:test/test.dart';

void main() {
  // A market as the live `/v1/coins/{id}/markets?quotes=USD` endpoint sends
  // it, with distinct, non-zero values so a missing or swapped key shows up.
  Map<String, dynamic> liveMarket() => {
    'exchange_id': 'freiexchange',
    'exchange_name': 'FreiExchange',
    'pair': 'KMD/BTC',
    'base_currency_id': 'kmd-komodo',
    'base_currency_name': 'komodo',
    'quote_currency_id': 'btc-bitcoin',
    'quote_currency_name': 'bitcoin',
    'market_url': 'https://freiexchange.com/market/KMD/BTC',
    'category': 'Spot',
    'fee_type': 'Percentage',
    'outlier': false,
    'adjusted_volume_24h_share': 0.1069,
    'quotes': {
      'USD': {'price': 0.00754, 'volume_24h': 17.174},
    },
    'trust_score': 'high',
    'last_updated': '2026-09-24T15:11:02Z',
  };

  group('CoinPaprikaMarket.fromJson', () {
    test('reads a live market', () {
      final market = CoinPaprikaMarket.fromJson(liveMarket());

      expect(market.adjustedVolume24hShare, equals(0.1069));
      expect(
        market.marketUrl,
        equals('https://freiexchange.com/market/KMD/BTC'),
      );
      expect(market.quotes['USD']!.price, equals(Decimal.parse('0.00754')));
      expect(market.quotes['USD']!.volume24h, equals(Decimal.parse('17.174')));
    });

    test('reads a market without a URL', () {
      final market = CoinPaprikaMarket.fromJson(
        liveMarket()..['market_url'] = null,
      );

      expect(market.marketUrl, isNull);
    });
  });

  group('CoinPaprikaQuote.fromJson', () {
    test('reads the numeric price and volume the API sends', () {
      final quote = CoinPaprikaQuote.fromJson(const {
        'price': 0.00754,
        'volume_24h': 17.174,
      });

      expect(quote.price, equals(Decimal.parse('0.00754')));
      expect(quote.volume24h, equals(Decimal.parse('17.174')));
    });
  });
}
