import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_ticker_quote.dart';
import 'package:test/test.dart';

void main() {
  group('CoinPaprikaTickerQuote.fromJson', () {
    // Keys as the live `/v1/tickers/{id}?quotes=USD` endpoint sends them, with
    // distinct, non-zero values so a missing or swapped key shows up.
    const liveQuote = <String, dynamic>{
      'price': 0.00394,
      'volume_24h': 16121.08,
      'volume_24h_change_24h': -2.93,
      'market_cap': 555602,
      'market_cap_change_24h': -0.46,
      'percent_change_15m': -0.03,
      'percent_change_30m': 0.75,
      'percent_change_1h': 0.73,
      'percent_change_6h': -0.55,
      'percent_change_12h': -0.51,
      'percent_change_24h': -0.47,
      'percent_change_7d': 0.02,
      'percent_change_30d': 4.1,
      'percent_change_1y': -12.5,
      'ath_price': 15.4149,
      'ath_date': '2017-12-21T08:04:00Z',
      'percent_from_price_ath': -99.97,
    };

    test('reads the fields CoinPaprika names with a digit suffix', () {
      final quote = CoinPaprikaTickerQuote.fromJson(liveQuote);

      expect(quote.volume24h, equals(16121.08));
      expect(quote.volume24hChange24h, equals(-2.93));
      expect(quote.marketCapChange24h, equals(-0.46));
      expect(quote.percentChange15m, equals(-0.03));
      expect(quote.percentChange30m, equals(0.75));
      expect(quote.percentChange1h, equals(0.73));
      expect(quote.percentChange6h, equals(-0.55));
      expect(quote.percentChange12h, equals(-0.51));
      expect(quote.percentChange24h, equals(-0.47));
      expect(quote.percentChange7d, equals(0.02));
      expect(quote.percentChange30d, equals(4.1));
      expect(quote.percentChange1y, equals(-12.5));
    });

    test('reads the remaining fields', () {
      final quote = CoinPaprikaTickerQuote.fromJson(liveQuote);

      expect(quote.price, equals(0.00394));
      expect(quote.marketCap, equals(555602));
      expect(quote.athPrice, equals(15.4149));
      expect(quote.athDate, equals(DateTime.utc(2017, 12, 21, 8, 4)));
      expect(quote.percentFromPriceAth, equals(-99.97));
    });
  });
}
