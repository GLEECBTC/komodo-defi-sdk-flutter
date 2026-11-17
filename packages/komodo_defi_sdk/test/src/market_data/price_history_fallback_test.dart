import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_sdk/src/market_data/market_data_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _HistoryRepository extends Mock implements CexRepository {}

class _CurrentPriceRepository extends Mock implements CexRepository {}

final _btc = AssetId(
  id: 'BTC',
  name: 'BTC',
  symbol: AssetSymbol(assetConfigId: 'BTC'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

final _today = DateTime.utc(2026, 11, 17);

DateTime _daysAgo(int days) => _today.subtract(Duration(days: days));

void main() {
  setUpAll(() {
    registerFallbackValue(_btc);
    registerFallbackValue(Stablecoin.usdt);
    registerFallbackValue(PriceRequestType.priceHistory);
    registerFallbackValue(<DateTime>[]);
  });

  late _HistoryRepository history;
  late _CurrentPriceRepository current;
  late DateTime now;
  late CexMarketDataManager manager;

  /// What [history] answers; an [Exception] is thrown.
  late Object Function(List<DateTime> dates) historyAnswer;

  /// What [current] answers; an [Exception] is thrown.
  late Object currentAnswer;

  void supportOnly(CexRepository repo, PriceRequestType type) {
    when(() => repo.supports(any(), any(), any())).thenAnswer(
      (invocation) async => invocation.positionalArguments[2] == type,
    );
  }

  setUp(() async {
    now = _today.add(const Duration(hours: 9));
    history = _HistoryRepository();
    current = _CurrentPriceRepository();
    historyAnswer = (dates) => {for (final date in dates) date: Decimal.one};
    currentAnswer = Decimal.fromInt(5);

    supportOnly(history, PriceRequestType.priceHistory);
    supportOnly(current, PriceRequestType.currentPrice);
    for (final repo in <CexRepository>[history, current]) {
      when(repo.getCoinList).thenAnswer((_) async => []);
    }
    when(
      () => history.getCoinFiatPrices(
        any(),
        any(),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer((invocation) async {
      final answer = historyAnswer(
        invocation.positionalArguments[1] as List<DateTime>,
      );
      if (answer is Exception) throw answer;
      return answer as Map<DateTime, Decimal>;
    });
    when(
      () => current.getCoinFiatPrice(
        any(),
        priceDate: any(named: 'priceDate'),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer((_) async {
      final answer = currentAnswer;
      if (answer is Exception) throw answer;
      return answer as Decimal;
    });

    manager = CexMarketDataManager(
      priceRepositories: [history, current],
      clock: () => now,
    );
    await manager.init();
  });

  tearDown(() => manager.dispose());

  /// History requests made since the previous call, oldest first.
  List<List<DateTime>> historyRequests() => verify(
    () => history.getCoinFiatPrices(
      any(),
      captureAny(),
      fiatCurrency: any(named: 'fiatCurrency'),
    ),
  ).captured.cast<List<DateTime>>();

  void verifyNoHistoryRequest() => verifyNever(
    () => history.getCoinFiatPrices(
      any(),
      any(),
      fiatCurrency: any(named: 'fiatCurrency'),
    ),
  );

  group('when the fetch for the remaining days fails', () {
    test("keeps the days already cached and today's price", () async {
      await manager.fiatPriceHistory(_btc, [_daysAgo(2)]);
      historyAnswer = (_) => Exception('Connection reset');

      final prices = await manager.fiatPriceHistory(_btc, [
        _daysAgo(3),
        _daysAgo(2),
        _today,
      ]);

      expect(prices, {_daysAgo(2): Decimal.one, _today: Decimal.fromInt(5)});
    });

    test('asks for the failed days again on the next lookup', () async {
      await manager.fiatPriceHistory(_btc, [_daysAgo(2)]);
      historyAnswer = (_) => Exception('Connection reset');
      await manager.fiatPriceHistory(_btc, [_daysAgo(3), _daysAgo(2)]);
      manager.clearRepositoryHealthData();
      historyRequests();

      historyAnswer = (dates) => {for (final date in dates) date: Decimal.ten};
      final prices = await manager.fiatPriceHistory(_btc, [
        _daysAgo(3),
        _daysAgo(2),
      ]);

      expect(prices, {_daysAgo(3): Decimal.ten, _daysAgo(2): Decimal.one});
      expect(historyRequests(), [
        [_daysAgo(3)],
      ]);
    });

    test(
      "returns today's price for an asset no repository has history for",
      () async {
        supportOnly(history, PriceRequestType.priceChange);

        final prices = await manager.fiatPriceHistory(_btc, [
          _daysAgo(30),
          _daysAgo(1),
          _today,
        ]);

        expect(prices, {_today: Decimal.fromInt(5)});
        verifyNoHistoryRequest();
      },
    );

    test('rethrows when no price is known at all', () async {
      historyAnswer = (_) => Exception('Connection reset');
      currentAnswer = Exception('Connection reset');

      await expectLater(
        manager.fiatPriceHistory(_btc, [_daysAgo(1), _today]),
        throwsException,
      );
    });

    test('rethrows when no repository supports the asset', () async {
      supportOnly(history, PriceRequestType.priceChange);
      supportOnly(current, PriceRequestType.priceChange);

      await expectLater(
        manager.fiatPriceHistory(_btc, [_daysAgo(1)]),
        throwsStateError,
      );
    });
  });

  group('a day in progress without a current price', () {
    setUp(() {
      supportOnly(current, PriceRequestType.priceChange);
      historyAnswer = (dates) => {
        for (final date in dates)
          if (date != _today) date: Decimal.one,
      };
    });

    test('is asked of history again only after five minutes', () async {
      final dates = [_daysAgo(1), _today];

      expect(await manager.fiatPriceHistory(_btc, dates), {
        _daysAgo(1): Decimal.one,
      });
      expect(historyRequests(), [dates]);

      now = now.add(const Duration(minutes: 4, seconds: 59));
      await manager.fiatPriceHistory(_btc, dates);
      verifyNoHistoryRequest();

      now = now.add(const Duration(seconds: 1));
      await manager.fiatPriceHistory(_btc, dates);
      expect(historyRequests(), [
        [_today],
      ]);
    });

    test('is asked again at once after a failed fetch', () async {
      historyAnswer = (_) => Exception('Connection reset');
      await expectLater(
        manager.fiatPriceHistory(_btc, [_today]),
        throwsException,
      );
      manager.clearRepositoryHealthData();
      historyRequests();

      historyAnswer = (dates) => {for (final date in dates) date: Decimal.ten};
      expect(await manager.fiatPriceHistory(_btc, [_today]), {
        _today: Decimal.ten,
      });
    });

    test('uses a current price as soon as one is available', () async {
      await manager.fiatPriceHistory(_btc, [_today]);
      historyRequests();

      supportOnly(current, PriceRequestType.currentPrice);
      expect(await manager.fiatPriceHistory(_btc, [_today]), {
        _today: Decimal.fromInt(5),
      });
      verifyNoHistoryRequest();
    });
  });

  group('a date given in local time', () {
    DateTime utcDay(DateTime date) {
      final utc = date.toUtc();
      return DateTime.utc(utc.year, utc.month, utc.day);
    }

    test('is filed under the UTC day it falls on', () async {
      // Half an hour from either end of a local day: wherever the device's
      // clock is not on UTC, one of them falls on a neighbouring UTC day.
      final early = DateTime(2026, 11, 10, 0, 30);
      final late = DateTime(2026, 11, 10, 23, 30);
      final days = {utcDay(early), utcDay(late)}.toList()..sort();

      final prices = await manager.fiatPriceHistory(_btc, [early, late]);

      expect(prices.keys, days);
      expect(historyRequests(), [days]);
    });

    test('is today whenever it is today in UTC', () async {
      for (final hour in [0, 23]) {
        now = _today.add(Duration(hours: hour, minutes: 30));

        final prices = await manager.fiatPriceHistory(_btc, [now.toLocal()]);

        expect(prices, {_today: Decimal.fromInt(5)});
      }
      verifyNoHistoryRequest();
    });
  });

  group('a repository benched for another kind of request', () {
    test('does not stop unpriced past days from being remembered', () async {
      // The current-price repository is rate limited; it never had history.
      currentAnswer = Exception('429 Too Many Requests');
      expect(await manager.maybeFiatPrice(_btc), isNull);
      historyAnswer = (_) => {_daysAgo(3): Decimal.one};
      final dates = [_daysAgo(400), _daysAgo(3)];

      await manager.fiatPriceHistory(_btc, dates);
      final prices = await manager.fiatPriceHistory(_btc, dates);

      expect(prices, {_daysAgo(3): Decimal.one});
      expect(historyRequests(), [dates]);
    });

    test(
      'still leaves gaps open while a history repository is benched',
      () async {
        // The repository that might have priced the gap is rate limited.
        supportOnly(current, PriceRequestType.priceHistory);
        when(
          () => current.getCoinFiatPrices(
            any(),
            any(),
            fiatCurrency: any(named: 'fiatCurrency'),
          ),
        ).thenThrow(Exception('429 Too Many Requests'));
        historyAnswer = (_) => {_daysAgo(3): Decimal.one};
        final dates = [_daysAgo(400), _daysAgo(3)];

        await manager.fiatPriceHistory(_btc, dates);
        await manager.fiatPriceHistory(_btc, dates);

        expect(historyRequests(), [
          dates,
          [_daysAgo(400)],
        ]);
      },
    );
  });
}
