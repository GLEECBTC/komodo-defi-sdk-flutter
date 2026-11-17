import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _coinId = 'grs-groestlcoin';

final _asset = AssetId(
  id: _coinId,
  name: _coinId,
  symbol: AssetSymbol(assetConfigId: 'GRS', coinPaprikaId: _coinId),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

void main() {
  group('CoinPaprikaRepository coin list', () {
    late List<Uri> requests;
    late int statusCode;
    Completer<void>? gate;
    late DateTime now;
    late CoinPaprikaRepository repository;

    setUp(() {
      requests = [];
      statusCode = 200;
      gate = null;
      now = DateTime.utc(2026, 11, 17, 12);
      final client = MockClient((request) async {
        requests.add(request.url);
        await gate?.future;
        if (statusCode != 200)
          return http.Response('{"error":"down"}', statusCode);
        return http.Response(
          jsonEncode([
            {
              'id': _coinId,
              'name': 'Groestlcoin',
              'symbol': 'GRS',
              'rank': 2400,
              'is_new': false,
              'is_active': true,
              'type': 'coin',
            },
          ]),
          200,
        );
      });
      repository = CoinPaprikaRepository(
        coinPaprikaProvider: CoinPaprikaProvider(httpClient: client),
        clock: () => now,
      );
    });

    Future<bool> supportsHistory() => repository.supports(
      _asset,
      FiatCurrency.usd,
      PriceRequestType.priceHistory,
    );

    test('fetches again after a failure once the cooldown ends', () async {
      // Started offline.
      statusCode = 503;
      expect(await supportsHistory(), isFalse);

      statusCode = 200;
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(await supportsHistory(), isFalse);
      expect(requests, hasLength(1));

      now = now.add(const Duration(seconds: 1));
      expect(await supportsHistory(), isTrue);
      expect(await supportsHistory(), isTrue);
      expect(requests.map((uri) => uri.path), ['/v1/coins', '/v1/coins']);
    });

    test('a failed fetch reaches callers in other error zones', () async {
      statusCode = 503;
      gate = Completer<void>();

      // RepositoryFallbackMixin runs each lookup inside `retry`, which gives
      // each attempt its own error zone.
      final lookups = [
        for (var i = 0; i < 4; i++)
          retry(repository.getCoinList, maxAttempts: 1),
      ];
      gate!.complete();

      final outcomes = await Future.wait([
        for (final lookup in lookups)
          lookup.then<Object>((value) => value, onError: (Object e) => e),
      ]).timeout(const Duration(seconds: 5));

      expect(outcomes, everyElement(isException));
      expect(requests, hasLength(1));
    });
  });
}
