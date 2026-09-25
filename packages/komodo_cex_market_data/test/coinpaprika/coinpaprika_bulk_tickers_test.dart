import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/src/_core_index.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Coins in the bulk tickers, with their USD prices.
const _topCoins = {
  'btc-bitcoin': 50000.0,
  'eth-ethereum': 3000.0,
  'kmd-komodo': 0.0039,
  'flr-flare-network': 0.021,
  'xdc-xdc-network': 0.035,
};

/// Active on CoinPaprika but ranked below 2,000, so the free plan's bulk
/// tickers leave it out.
const _tailCoinId = 'grs-groestlcoin';

void main() {
  late _FakeCoinPaprika api;
  late DateTime now;
  late CoinPaprikaRepository repository;

  setUp(() {
    api = _FakeCoinPaprika();
    now = DateTime.utc(2026, 9, 24, 12);
    repository = CoinPaprikaRepository(
      coinPaprikaProvider: CoinPaprikaProvider(httpClient: api.client),
      clock: () => now,
    );
  });

  Future<Decimal> price(String coinId) => repository.getCoinFiatPrice(
    _asset(coinId),
    fiatCurrency: FiatCurrency.usd,
  );

  Future<bool> supports(String coinId, PriceRequestType requestType) =>
      repository.supports(_asset(coinId), FiatCurrency.usd, requestType);

  group('CoinPaprikaRepository bulk tickers', () {
    test('prices and 24h changes for many coins cost one request', () async {
      for (final MapEntry(key: id, value: usd) in _topCoins.entries) {
        expect(await price(id), equals(_decimal(usd)));
        await repository.getCoin24hrPriceChange(
          _asset(id),
          fiatCurrency: FiatCurrency.usd,
        );
      }

      expect(api.requests, hasLength(1));
      expect(api.requests.single.path, equals('/v1/tickers'));
      expect(api.requests.single.queryParameters, equals({'quotes': 'USD'}));
    });

    test('lookups through the fallback mixin share one request', () async {
      final manager = _FallbackManager([repository]);

      final prices = await Future.wait([
        for (final id in _topCoins.keys)
          manager.tryRepositoriesInOrder(
            _asset(id),
            FiatCurrency.usd,
            PriceRequestType.currentPrice,
            (repo) => repo.getCoinFiatPrice(
              _asset(id),
              fiatCurrency: FiatCurrency.usd,
            ),
            'fiatPrice',
          ),
      ]);

      expect(
        prices,
        equals([for (final usd in _topCoins.values) _decimal(usd)]),
      );
      expect(api.requests, hasLength(1));
    });

    test('reuses the tickers for five minutes, then refetches', () async {
      await price('btc-bitcoin');
      now = now.add(const Duration(minutes: 4, seconds: 59));
      await price('eth-ethereum');
      expect(api.requests, hasLength(1));

      now = now.add(const Duration(seconds: 1));
      await price('eth-ethereum');
      expect(api.requests, hasLength(2));
    });

    test(
      'treats coins outside the tickers as unsupported for current data',
      () async {
        expect(
          await supports('kmd-komodo', PriceRequestType.currentPrice),
          isTrue,
        );
        expect(
          await supports(_tailCoinId, PriceRequestType.currentPrice),
          isFalse,
        );
        expect(
          await supports(_tailCoinId, PriceRequestType.priceChange),
          isFalse,
        );
        expect(
          await supports(_tailCoinId, PriceRequestType.priceHistory),
          isTrue,
        );

        expect(
          api.requests.map((uri) => uri.path),
          unorderedEquals(['/v1/tickers', '/v1/coins']),
        );
      },
    );

    test('support checks refresh hour-old tickers without waiting', () async {
      expect(
        await supports('kmd-komodo', PriceRequestType.currentPrice),
        isTrue,
      );
      now = now.add(const Duration(minutes: 59, seconds: 59));
      expect(
        await supports('kmd-komodo', PriceRequestType.priceChange),
        isTrue,
      );
      await pumpEventQueue();
      expect(api.requests, hasLength(1));

      api.gate = Completer<void>();
      now = now.add(const Duration(seconds: 1));
      expect(
        await supports(
          'kmd-komodo',
          PriceRequestType.currentPrice,
        ).timeout(const Duration(seconds: 5)),
        isTrue,
      );
      await pumpEventQueue();
      expect(api.requests, hasLength(2));
      api.gate!.complete();
    });

    test('support checks return false quietly during the cooldown', () async {
      final warnings = <LogRecord>[];
      final subscription = Logger.root.onRecord
          .where((r) => r.loggerName == 'CoinPaprikaRepository')
          .where((r) => r.level >= Level.WARNING)
          .listen(warnings.add);
      addTearDown(subscription.cancel);
      api.statusCode = 429;

      for (var i = 0; i < 20; i++) {
        expect(
          await supports('kmd-komodo', PriceRequestType.currentPrice),
          isFalse,
        );
      }
      expect(api.requests, hasLength(1));
      expect(warnings, hasLength(1));

      api.statusCode = 200;
      now = now.add(const Duration(minutes: 5));
      await supports('kmd-komodo', PriceRequestType.currentPrice);
      await pumpEventQueue();
      expect(
        await supports('kmd-komodo', PriceRequestType.currentPrice),
        isTrue,
      );
      expect(api.requests, hasLength(2));
    });

    test('treats an empty ticker list as a failed fetch', () async {
      api.tickers.clear();

      expect(
        await supports('kmd-komodo', PriceRequestType.currentPrice),
        isFalse,
      );
      await expectLater(price('kmd-komodo'), throwsStateError);
      expect(api.requests, hasLength(1));
    });

    test('refetches when the clock moves backwards', () async {
      await price('btc-bitcoin');
      now = now.subtract(const Duration(days: 1));
      await price('btc-bitcoin');
      expect(api.requests, hasLength(2));
    });

    test('requests a stablecoin quote as its fiat', () async {
      expect(
        await repository.supports(
          _asset('kmd-komodo'),
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
        ),
        isTrue,
      );
      expect(api.requests.single.queryParameters, equals({'quotes': 'USD'}));
    });

    test('does not retry a failed fetch until the cooldown ends', () async {
      api.statusCode = 429;
      await expectLater(price('btc-bitcoin'), throwsException);

      now = now.add(const Duration(minutes: 4, seconds: 59));
      await expectLater(price('eth-ethereum'), throwsException);
      expect(
        await supports('eth-ethereum', PriceRequestType.currentPrice),
        isFalse,
      );
      expect(api.requests, hasLength(1));

      api.statusCode = 200;
      now = now.add(const Duration(seconds: 1));
      expect(await price('eth-ethereum'), equals(_decimal(3000)));
      expect(api.requests, hasLength(2));
    });

    test('a failed fetch reaches callers in other error zones', () async {
      api
        ..statusCode = 500
        ..gate = Completer<void>();

      // RepositoryFallbackMixin runs each lookup inside `retry`, which gives
      // each attempt its own error zone.
      final lookups = [
        for (final id in _topCoins.keys) retry(() => price(id), maxAttempts: 1),
      ];
      api.gate!.complete();

      final outcomes = await Future.wait([
        for (final lookup in lookups)
          lookup.then<Object>((value) => value, onError: (Object e) => e),
      ]).timeout(const Duration(seconds: 5));

      expect(outcomes, everyElement(isException));
      expect(api.requests, hasLength(1));
    });

    test('drops only a ticker that fails to parse', () async {
      api.tickers.firstWhere((t) => t['id'] == 'eth-ethereum')['quotes'] = null;

      expect(await price('btc-bitcoin'), equals(_decimal(50000)));
      await expectLater(price('eth-ethereum'), throwsException);
      expect(
        await supports('eth-ethereum', PriceRequestType.currentPrice),
        isFalse,
      );
      expect(api.requests, hasLength(1));
    });
  });
}

class _FakeCoinPaprika {
  final requests = <Uri>[];
  final tickers = [
    for (final MapEntry(key: id, value: usd) in _topCoins.entries)
      _tickerJson(id, usd),
  ];
  int statusCode = 200;
  Completer<void>? gate;

  late final client = MockClient((request) async {
    requests.add(request.url);
    await gate?.future;
    if (statusCode != 200) {
      return http.Response('{"error":"Too many requests"}', statusCode);
    }

    final path = request.url.path;
    if (path == '/v1/tickers') return http.Response(jsonEncode(tickers), 200);
    if (path == '/v1/coins') {
      final ids = [..._topCoins.keys, _tailCoinId];
      return http.Response(
        jsonEncode([for (final id in ids) _coinJson(id)]),
        200,
      );
    }
    // The per-coin endpoint serves every active coin, including the tail.
    final id = path.substring('/v1/tickers/'.length);
    return http.Response(
      jsonEncode(_tickerJson(id, _topCoins[id] ?? 0.028)),
      200,
    );
  });
}

class _FallbackManager with RepositoryFallbackMixin {
  _FallbackManager(this.priceRepositories);

  @override
  final List<CexRepository> priceRepositories;

  @override
  final RepositorySelectionStrategy selectionStrategy =
      DefaultRepositorySelectionStrategy();
}

AssetId _asset(String coinPaprikaId) => AssetId(
  id: coinPaprikaId,
  name: coinPaprikaId,
  symbol: AssetSymbol(
    assetConfigId: coinPaprikaId.split('-').first.toUpperCase(),
    coinPaprikaId: coinPaprikaId,
  ),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

Decimal _decimal(double value) => Decimal.parse(value.toString());

Map<String, dynamic> _coinJson(String id) => {
  'id': id,
  'name': id,
  'symbol': id.split('-').first.toUpperCase(),
  'rank': 1,
  'is_new': false,
  'is_active': true,
  'type': 'coin',
};

/// A `/v1/tickers` entry shaped like the live response on 2026-09-24.
Map<String, dynamic> _tickerJson(String id, double usd) => {
  'id': id,
  'name': id,
  'symbol': id.split('-').first.toUpperCase(),
  'rank': 1709,
  'total_supply': 140992325,
  'max_supply': 0,
  'beta_value': 0.434462,
  'first_data_at': '2017-02-05T00:00:00Z',
  'last_updated': '2026-09-24T20:46:18Z',
  'quotes': {
    'USD': {
      'price': usd,
      'volume_24h': 16246.77,
      'volume_24h_change_24h': 0.46,
      'market_cap': 554902,
      'market_cap_change_24h': 0.72,
      'percent_change_15m': 0.26,
      'percent_change_30m': 0.26,
      'percent_change_1h': 0.78,
      'percent_change_6h': 0.03,
      'percent_change_12h': 0.59,
      'percent_change_24h': 0.72,
      'percent_change_7d': -0.98,
      'percent_change_30d': 0,
      'percent_change_1y': 0,
      'ath_price': 15.4149,
      'ath_date': '2017-12-21T08:04:00Z',
      'percent_from_price_ath': -99.97,
    },
  },
};
