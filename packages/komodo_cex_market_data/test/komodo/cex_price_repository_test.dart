import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/src/komodo/prices/komodo_price_provider.dart';
import 'package:komodo_cex_market_data/src/komodo/prices/komodo_price_repository.dart';
import 'package:test/test.dart';

void main() {
  late KomodoPriceRepository cexPriceRepository;
  setUp(() {
    cexPriceRepository = KomodoPriceRepository(
      cexPriceProvider: KomodoPriceProvider(),
    );
  });

  group('getCoinList', () {
    test('returns the coins present in the ticker response', () async {
      // The live feed can omit stale tickers. Test the provider/repository
      // contract without depending on a particular coin's current listing.
      final result = await http.runWithClient(
        cexPriceRepository.getCoinList,
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'KMD': {'ticker': 'KMD', 'last_price': '0.01'},
              'BTC': {'ticker': 'BTC', 'last_price': '50000'},
            }),
            200,
          ),
        ),
      );

      expect(result.map((coin) => coin.id), unorderedEquals(['KMD', 'BTC']));
      for (final coin in result) {
        expect(coin.symbol, coin.id);
        expect(coin.name, coin.id);
        expect(coin.source, 'komodo');
        expect(coin.currencies, {'USD', 'USDT'});
      }
    });

    test(
      'returns an empty list when the feed has no current tickers',
      () async {
        final result = await http.runWithClient(
          cexPriceRepository.getCoinList,
          () => MockClient((_) async => http.Response('{}', 200)),
        );

        expect(result, isEmpty);
      },
    );
  });
}
