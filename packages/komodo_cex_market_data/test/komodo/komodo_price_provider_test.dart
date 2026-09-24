import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _lastUpdated = 1790251995;
const _kmdTicker = <String, dynamic>{
  'ticker': 'KMD',
  'last_price': '0.0039125313',
  'last_updated': '2026-09-24T12:13:15Z',
  'last_updated_timestamp': _lastUpdated,
  'volume24h': '10.3300000000',
  'price_provider': 'coinpaprika',
  'volume_provider': 'coingecko',
  'sparkline_7d': null,
  'sparkline_provider': 'coingecko',
  'change_24h': '-0.920000',
  'change_24h_provider': 'coinpaprika',
};

/// Serves KMD as defi_stats' get_v2_tickers does [ageSeconds] after its update.
http.Client _feedAt(int ageSeconds) => MockClient((request) async {
  final expireAt = int.parse(request.url.queryParameters['expire_at'] ?? '900');
  final now = _lastUpdated + ageSeconds;
  return http.Response(
    jsonEncode({if (_lastUpdated > now - expireAt) 'KMD': _kmdTicker}),
    200,
  );
});

void main() {
  final kmd = AssetId(
    id: 'KMD',
    name: 'KMD',
    symbol: AssetSymbol(assetConfigId: 'KMD'),
    chainId: AssetChainId(chainId: 0),
    derivationPath: null,
    subClass: CoinSubClass.utxo,
  );

  late KomodoPriceRepository repository;

  setUp(() {
    repository = KomodoPriceRepository(cexPriceProvider: KomodoPriceProvider());
  });

  Future<T> refreshAt<T>(int ageSeconds, Future<T> Function() body) {
    repository.clearCache();
    return http.runWithClient(body, () => _feedAt(ageSeconds));
  }

  Future<bool> supportsKmd() =>
      repository.supports(kmd, Stablecoin.usdt, PriceRequestType.currentPrice);

  group('KomodoPriceProvider feed window', () {
    test('keeps a ticker for up to 30 minutes after its last update', () async {
      final price = await refreshAt(
        300,
        () => repository.getCoinFiatPrice(kmd),
      );
      expect(price, Decimal.parse('0.0039125313'));

      // A 600-second window left KMD out of this response.
      await refreshAt(1790, () async {
        expect(await supportsKmd(), isTrue);
        expect(await repository.getCoinFiatPrice(kmd), price);
      });
    });

    test('drops a ticker more than 30 minutes after its last update', () async {
      expect(await refreshAt(300, supportsKmd), isTrue);

      await refreshAt(1810, () async {
        expect(await supportsKmd(), isFalse);
        await expectLater(repository.getCoinFiatPrice(kmd), throwsException);
      });
    });
  });
}
