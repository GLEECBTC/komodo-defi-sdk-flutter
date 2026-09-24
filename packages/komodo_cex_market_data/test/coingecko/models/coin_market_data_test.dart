import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/coingecko/models/coin_market_data.dart';
import 'package:test/test.dart';

void main() {
  group('CoinMarketData.fromJson', () {
    // An entry as the live `/coins/markets?vs_currency=usd` endpoint sends it,
    // with distinct, non-zero values so a missing or swapped key shows up.
    const liveMarket = <String, dynamic>{
      'id': 'bitcoin',
      'symbol': 'btc',
      'name': 'Bitcoin',
      'current_price': 83840,
      'market_cap': 1683198278696,
      'market_cap_rank': 1,
      'fully_diluted_valuation': 1760640000000,
      'total_volume': 40590996306,
      'high_24h': 84843,
      'low_24h': 82941,
      'price_change_24h': -802.79,
      'price_change_percentage_24h': -0.94844,
      'market_cap_change_24h': -17137477837.8,
      'market_cap_change_percentage_24h': -1.00789,
      'circulating_supply': 20088728.0,
      'total_supply': 20088743.0,
      'max_supply': 21000000.0,
      'ath': 126080,
      'ath_change_percentage': -33.50233,
      'ath_date': '2025-10-06T10:57:42.000Z',
      'atl': 67.81,
      'atl_change_percentage': 123541.68846,
      'atl_date': '2013-07-05T16:00:00.000Z',
      'roi': null,
      'last_updated': '2026-09-24T15:11:20.000Z',
    };

    test('reads the 24h fields CoinGecko names with a digit suffix', () {
      final data = CoinMarketData.fromJson(liveMarket);

      expect(data.high24h, equals(Decimal.parse('84843')));
      expect(data.low24h, equals(Decimal.parse('82941')));
      expect(data.priceChange24h, equals(Decimal.parse('-802.79')));
      expect(data.priceChangePercentage24h, equals(Decimal.parse('-0.94844')));
      expect(data.marketCapChange24h, equals(Decimal.parse('-17137477837.8')));
      expect(
        data.marketCapChangePercentage24h,
        equals(Decimal.parse('-1.00789')),
      );
    });
  });
}
