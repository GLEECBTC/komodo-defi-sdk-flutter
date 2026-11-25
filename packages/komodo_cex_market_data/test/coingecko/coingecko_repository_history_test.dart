import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _day = Duration(days: 1);

DateTime _utcDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// A price that identifies the day it belongs to.
Decimal _closeOn(DateTime day) =>
    Decimal.fromInt(day.millisecondsSinceEpoch ~/ _day.inMilliseconds);

/// Serves `/ohlc?days=N` as CoinGecko does: the window always ends now,
/// whatever range the caller has in mind.
class _FakeCoinGecko implements ICoinGeckoProvider {
  final ohlcDays = <int>[];
  int coinListRequests = 0;
  Completer<void>? coinListGate;

  @override
  Future<CoinOhlc> fetchCoinOhlc(
    String id,
    String vsCurrency,
    int days, {
    int? precision,
  }) async {
    ohlcDays.add(days);
    final now = DateTime.now().toUtc();
    final windowStart = now.subtract(_day * days);
    return CoinOhlc(
      ohlc: [
        for (
          var day = _utcDay(windowStart);
          !day.isAfter(now);
          day = day.add(_day)
        )
          if (!day.isBefore(windowStart))
            Ohlc.coingecko(
              timestamp: day.millisecondsSinceEpoch,
              open: _closeOn(day),
              high: _closeOn(day),
              low: _closeOn(day),
              close: _closeOn(day),
            ),
      ],
    );
  }

  @override
  Future<List<CexCoin>> fetchCoinList({bool includePlatforms = false}) async {
    coinListRequests++;
    await coinListGate?.future;
    throw Exception('CoinGecko is unreachable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _btc = AssetId(
  id: 'BTC',
  name: 'Bitcoin',
  symbol: AssetSymbol(assetConfigId: 'BTC', coinGeckoId: 'bitcoin'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

void main() {
  late _FakeCoinGecko api;
  late CoinGeckoRepository repository;
  late DateTime today;

  setUp(() {
    api = _FakeCoinGecko();
    repository = CoinGeckoRepository(coinGeckoProvider: api);
    today = _utcDay(DateTime.now().toUtc());
  });

  DateTime daysAgo(int days) => today.subtract(_day * days);

  List<DateTime> range(int oldest, int newest) => [
    for (var age = oldest; age >= newest; age--) daysAgo(age),
  ];

  Map<DateTime, Decimal> closesOn(List<DateTime> days) => {
    for (final day in days) day: _closeOn(day),
  };

  group('CoinGeckoRepository.getCoinFiatPrices', () {
    test('a past range costs one request that reaches back to it', () async {
      final wanted = range(40, 30);

      final prices = await repository.getCoinFiatPrices(_btc, wanted);

      expect(api.ohlcDays, hasLength(1));
      expect(api.ohlcDays.single, inInclusiveRange(41, 365));
      expect(prices, closesOn(wanted));
    });

    test('a range ending today costs one request', () async {
      final wanted = range(7, 0);

      final prices = await repository.getCoinFiatPrices(_btc, wanted);

      expect(api.ohlcDays, hasLength(1));
      expect(prices, closesOn(wanted));
    });

    test('a range older than the plan serves costs no request', () async {
      final prices = await repository.getCoinFiatPrices(_btc, range(400, 380));

      expect(prices, isEmpty);
      expect(api.ohlcDays, isEmpty);
    });

    test('asks only for the days the plan serves', () async {
      final prices = await repository.getCoinFiatPrices(_btc, [
        daysAgo(400),
        daysAgo(10),
        today.add(_day),
      ]);

      expect(api.ohlcDays, hasLength(1));
      expect(prices, closesOn([daysAgo(10)]));
    });

    test('asks for a window length the API documents', () async {
      for (final age in [0, 1, 6, 7, 20, 45, 100, 200, 364]) {
        await repository.getCoinFiatPrices(_btc, [daysAgo(age)]);
      }

      expect(api.ohlcDays, everyElement(isIn([1, 7, 14, 30, 90, 180, 365])));
      expect(api.ohlcDays, hasLength(9));
    });

    test('keys a time of day by its UTC day', () async {
      final prices = await repository.getCoinFiatPrices(_btc, [
        daysAgo(3).add(const Duration(hours: 15)),
      ]);

      expect(prices, closesOn([daysAgo(3)]));
    });
  });

  test(
    'a failed coin list fetch reaches callers in other error zones',
    () async {
      api.coinListGate = Completer<void>();

      // RepositoryFallbackMixin runs each lookup inside `retry`, which gives
      // each attempt its own error zone.
      final lookups = [
        for (var i = 0; i < 4; i++)
          retry(repository.getCoinList, maxAttempts: 1),
      ];
      api.coinListGate!.complete();

      final outcomes = await Future.wait([
        for (final lookup in lookups)
          lookup.then<Object>((value) => value, onError: (Object e) => e),
      ]).timeout(const Duration(seconds: 5));

      expect(outcomes, everyElement(isException));
      expect(api.coinListRequests, 1);
    },
  );
}
