import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _tickers = ['KMD', 'BTC', 'LTC', 'DOGE'];

class _FakeFeed implements IKomodoPriceProvider {
  int requests = 0;
  Completer<void>? gate;
  Object? failure;
  Map<String, AssetMarketInformation> prices = {
    for (final ticker in _tickers)
      ticker: AssetMarketInformation(ticker: ticker, lastPrice: Decimal.one),
  };

  @override
  Future<Map<String, AssetMarketInformation>> getKomodoPrices() async {
    requests++;
    await gate?.future;
    final error = failure;
    if (error != null) throw error;
    return prices;
  }
}

class _FallbackManager with RepositoryFallbackMixin {
  _FallbackManager(this.priceRepositories);

  @override
  final List<CexRepository> priceRepositories;

  @override
  final RepositorySelectionStrategy selectionStrategy =
      DefaultRepositorySelectionStrategy();
}

AssetId _asset(String ticker) => AssetId(
  id: ticker,
  name: ticker,
  symbol: AssetSymbol(assetConfigId: ticker),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

Future<List<Object>> _outcomes(List<Future<Decimal>> lookups) => Future.wait([
  for (final lookup in lookups)
    lookup.then<Object>((value) => value, onError: (Object e) => e),
]).timeout(const Duration(seconds: 5));

void main() {
  group('KomodoPriceRepository feed failures', () {
    late _FakeFeed feed;
    late DateTime now;
    late KomodoPriceRepository repository;

    setUp(() {
      feed = _FakeFeed();
      now = DateTime.utc(2026, 11, 17, 12);
      repository = KomodoPriceRepository(
        cexPriceProvider: feed,
        clock: () => now,
      );
    });

    test('a failed fetch reaches callers in other error zones', () async {
      feed
        ..failure = Exception('HTTP 503')
        ..gate = Completer<void>();

      // RepositoryFallbackMixin runs each lookup inside `retry`, which gives
      // each attempt its own error zone.
      final lookups = [
        for (final ticker in _tickers)
          retry(
            () => repository.getCoinFiatPrice(_asset(ticker)),
            maxAttempts: 1,
          ),
      ];
      feed.gate!.complete();

      expect(await _outcomes(lookups), everyElement(isException));
      expect(feed.requests, 1);
    });

    test('a refresh that fails does not hang concurrent lookups', () async {
      final manager = _FallbackManager([repository]);
      Future<Decimal> price(String ticker) => manager.tryRepositoriesInOrder(
        _asset(ticker),
        Stablecoin.usdt,
        PriceRequestType.currentPrice,
        (repo) => repo.getCoinFiatPrice(_asset(ticker)),
        'fiatPrice',
        maxTotalAttempts: 1,
      );
      expect(await price('KMD'), Decimal.one);

      // The prices expired while the app was asleep, and it wakes offline.
      now = now.add(const Duration(minutes: 5));
      feed
        ..failure = Exception('Failed host lookup')
        ..gate = Completer<void>();
      final lookups = [for (final ticker in _tickers) price(ticker)];
      await pumpEventQueue();
      feed.gate!.complete();

      expect(await _outcomes(lookups), everyElement(isException));
      expect(feed.requests, 2);

      feed.failure = null;
      expect(await repository.getCoinFiatPrice(_asset('BTC')), Decimal.one);
      expect(feed.requests, 3);
    });

    test('a ticker with a zero price is unknown, not worth nothing', () async {
      feed.prices = {
        'KMD': AssetMarketInformation(ticker: 'KMD', lastPrice: Decimal.one),
        'DEAD': AssetMarketInformation(ticker: 'DEAD', lastPrice: Decimal.zero),
        'NEG': AssetMarketInformation(
          ticker: 'NEG',
          lastPrice: Decimal.parse('-1'),
          change24h: Decimal.one,
        ),
      };

      expect(await repository.getCoinFiatPrice(_asset('KMD')), Decimal.one);
      for (final ticker in ['DEAD', 'NEG']) {
        expect(
          await repository.supports(
            _asset(ticker),
            Stablecoin.usdt,
            PriceRequestType.currentPrice,
          ),
          isFalse,
        );
        await expectLater(
          repository.getCoinFiatPrice(_asset(ticker)),
          throwsException,
        );
        await expectLater(
          repository.getCoin24hrPriceChange(_asset(ticker)),
          throwsException,
        );
      }
      expect((await repository.getCoinList()).map((coin) => coin.id), ['KMD']);
    });
  });

  group('KomodoPriceProvider', () {
    test('skips only the entries that fail to parse', () async {
      final feed = jsonEncode({
        'KMD': {'ticker': 'KMD', 'last_price': '0.0039'},
        'NULLPRICE': {'ticker': 'NULLPRICE', 'last_price': null},
        'WORDS': {'ticker': 'WORDS', 'last_price': 'n/a'},
        'NOTAMAP': 'delisted',
        'BTC': {'ticker': 'BTC', 'last_price': '50000'},
      });

      final prices = await http.runWithClient(
        KomodoPriceProvider().getKomodoPrices,
        () => MockClient((_) async => http.Response(feed, 200)),
      );

      expect(prices.keys, unorderedEquals(['KMD', 'BTC']));
      expect(prices['BTC']!.lastPrice, Decimal.fromInt(50000));
    });

    test('fails a request the feed never answers', () async {
      final provider = KomodoPriceProvider(
        requestTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        http
            .runWithClient(
              provider.getKomodoPrices,
              () => MockClient((_) => Completer<http.Response>().future),
            )
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.duration,
            'duration',
            const Duration(milliseconds: 50),
          ),
        ),
      );
    });
  });
}
