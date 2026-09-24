import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/src/_core_index.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

// The mocked-provider tests build CoinMarketData directly, so they never parse
// the keys the API sends.
void main() {
  test(
    'CoinGeckoRepository.getCoin24hrPriceChange reads the change the API sends',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'id': 'bitcoin',
              'symbol': 'btc',
              'name': 'Bitcoin',
              'price_change_percentage_24h': -0.94844,
            },
          ]),
          200,
        ),
      );
      final repository = CoinGeckoRepository(
        coinGeckoProvider: CoinGeckoCexProvider(),
        enableMemoization: false,
      );
      final bitcoin = AssetId(
        id: 'BTC',
        name: 'Bitcoin',
        symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
        chainId: AssetChainId(chainId: 0),
        derivationPath: null,
        subClass: CoinSubClass.utxo,
      );

      final change = await http.runWithClient(
        () => repository.getCoin24hrPriceChange(bitcoin),
        () => client,
      );

      expect(change, equals(Decimal.parse('-0.94844')));
    },
  );
}
