import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_sdk/src/market_data/market_data_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockRepository extends Mock implements CexRepository {}

class _FallbackRepository extends Mock implements CexRepository {}

final _btc = AssetId(
  id: 'BTC',
  name: 'BTC',
  symbol: AssetSymbol(assetConfigId: 'BTC'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

final _today = DateTime.utc(2026, 11, 6);

DateTime _daysAgo(int days) => _today.subtract(Duration(days: days));

void main() {
  setUpAll(() {
    registerFallbackValue(_btc);
    registerFallbackValue(Stablecoin.usdt);
    registerFallbackValue(PriceRequestType.priceHistory);
    registerFallbackValue(<DateTime>[]);
  });

  late _MockRepository repo;
  late DateTime now;
  late CexMarketDataManager manager;

  setUp(() async {
    now = _today.add(const Duration(hours: 9));
    repo = _MockRepository();
    when(repo.getCoinList).thenAnswer((_) async => []);
    when(
      () => repo.supports(any(), any(), any()),
    ).thenAnswer((_) async => true);
    when(
      () => repo.getCoinFiatPrices(
        any(),
        any(),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer(
      (invocation) async => {
        for (final date in invocation.positionalArguments[1] as List<DateTime>)
          date: Decimal.one,
      },
    );
    manager = CexMarketDataManager(
      priceRepositories: [repo],
      selectionStrategy: DefaultRepositorySelectionStrategy(),
      cacheClearInterval: const Duration(milliseconds: 20),
      clock: () => now,
    );
    await manager.init();
  });

  tearDown(() => manager.dispose());

  /// History requests made since the previous call, oldest first.
  List<List<DateTime>> historyRequests() => verify(
    () => repo.getCoinFiatPrices(
      any(),
      captureAny(),
      fiatCurrency: any(named: 'fiatCurrency'),
    ),
  ).captured.cast<List<DateTime>>();

  void verifyNoHistoryRequest() => verifyNever(
    () => repo.getCoinFiatPrices(
      any(),
      any(),
      fiatCurrency: any(named: 'fiatCurrency'),
    ),
  );

  test('keeps past-day prices after the live cache rotates', () async {
    final dates = [_daysAgo(3), _daysAgo(2)];

    await manager.fiatPriceHistory(_btc, dates);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final prices = await manager.fiatPriceHistory(_btc, dates);

    expect(prices.keys, dates);
    expect(historyRequests(), [dates]);
  });

  test('asks again for an unpriced past day only after an hour', () async {
    when(
      () => repo.getCoinFiatPrices(
        any(),
        any(),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer((_) async => {_daysAgo(3): Decimal.one});
    final dates = [_daysAgo(400), _daysAgo(3)];

    await manager.fiatPriceHistory(_btc, dates);
    final prices = await manager.fiatPriceHistory(_btc, dates);
    expect(prices.keys, [_daysAgo(3)]);
    expect(historyRequests(), [dates]);

    now = now.add(const Duration(minutes: 59));
    await manager.fiatPriceHistory(_btc, dates);
    verifyNoHistoryRequest();

    now = now.add(const Duration(minutes: 2));
    await manager.fiatPriceHistory(_btc, dates);
    expect(historyRequests(), [
      [_daysAgo(400)],
    ]);
  });

  test('prices today with the current price, not from history', () async {
    when(
      () => repo.getCoinFiatPrice(
        any(),
        priceDate: any(named: 'priceDate'),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer((_) async => Decimal.fromInt(5));

    final prices = await manager.fiatPriceHistory(_btc, [_daysAgo(1), _today]);

    expect(prices, {_daysAgo(1): Decimal.one, _today: Decimal.fromInt(5)});
    expect(historyRequests(), [
      [_daysAgo(1)],
    ]);
  });

  test('asks history for today when no current price is known', () async {
    when(() => repo.supports(any(), any(), any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments[2] == PriceRequestType.priceHistory,
    );

    final prices = await manager.fiatPriceHistory(_btc, [_daysAgo(1), _today]);

    expect(prices.keys, [_daysAgo(1), _today]);
    expect(historyRequests(), [
      [_daysAgo(1), _today],
    ]);
  });

  test('returns prices sorted by date', () async {
    final prices = await manager.fiatPriceHistory(_btc, [
      _daysAgo(1),
      _daysAgo(3),
      _daysAgo(2),
    ]);

    expect(prices.keys, [_daysAgo(3), _daysAgo(2), _daysAgo(1)]);
  });

  test(
    'fills partial history from the next provider before caching gaps',
    () async {
      final fallback = _FallbackRepository();
      when(
        () => fallback.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => repo.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async => {_daysAgo(1): Decimal.one});
      when(
        () => fallback.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async => {_daysAgo(2): Decimal.fromInt(2)});
      await manager.dispose();
      manager = CexMarketDataManager(
        priceRepositories: [repo, fallback],
        clock: () => now,
      );
      await manager.init();

      final prices = await manager.fiatPriceHistory(_btc, [
        _daysAgo(2),
        _daysAgo(1),
      ]);

      expect(prices, {
        _daysAgo(2): Decimal.fromInt(2),
        _daysAgo(1): Decimal.one,
      });
      verify(() => fallback.getCoinFiatPrices(_btc, [_daysAgo(2)])).called(1);
      await manager.fiatPriceHistory(_btc, [_daysAgo(2), _daysAgo(1)]);
      expect(historyRequests(), [
        [_daysAgo(2), _daysAgo(1)],
      ]);
      verifyNever(
        () => fallback.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      );
    },
  );

  test(
    'future dates are unavailable rather than assigned the current price',
    () async {
      when(
        () => repo.getCoinFiatPrice(
          any(),
          priceDate: any(named: 'priceDate'),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async => Decimal.fromInt(5));

      expect(
        await manager.fiatPriceHistory(_btc, [
          _today.add(const Duration(days: 1)),
        ]),
        isEmpty,
      );
      verifyNoHistoryRequest();
      verifyNever(
        () => repo.getCoinFiatPrice(
          any(),
          priceDate: any(named: 'priceDate'),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      );
    },
  );

  test(
    'a request crossing midnight does not permanently cache an unfinished day',
    () async {
      final started = Completer<void>();
      final response = Completer<Decimal>();
      var calls = 0;
      when(
        () => repo.getCoinFiatPrice(
          any(),
          priceDate: any(named: 'priceDate'),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async {
        if (calls++ == 0) {
          started.complete();
          return response.future;
        }
        return Decimal.fromInt(2);
      });
      now = _today.add(const Duration(hours: 23, minutes: 59));
      final pending = manager.fiatPrice(_btc, priceDate: _today);
      await started.future;
      now = _today.add(const Duration(days: 1));
      response.complete(Decimal.one);
      expect(await pending, Decimal.one);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        await manager.fiatPrice(_btc, priceDate: _today),
        Decimal.fromInt(2),
      );
      expect(calls, 2);
    },
  );

  test('a provider outage does not negative-cache missing dates', () async {
    final fallback = _FallbackRepository();
    var recovering = false;
    when(
      () => fallback.supports(any(), any(), any()),
    ).thenAnswer((_) async => true);
    when(
      () => repo.getCoinFiatPrices(
        any(),
        any(),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer((_) async => {_daysAgo(1): Decimal.one});
    when(
      () => fallback.getCoinFiatPrices(
        any(),
        any(),
        fiatCurrency: any(named: 'fiatCurrency'),
      ),
    ).thenAnswer((_) async {
      if (!recovering) throw Exception('temporary provider outage');
      return {_daysAgo(2): Decimal.fromInt(2)};
    });
    await manager.dispose();
    manager = CexMarketDataManager(
      priceRepositories: [repo, fallback],
      clock: () => now,
    );
    await manager.init();

    expect(await manager.fiatPriceHistory(_btc, [_daysAgo(2), _daysAgo(1)]), {
      _daysAgo(1): Decimal.one,
    });
    recovering = true;
    expect(await manager.fiatPriceHistory(_btc, [_daysAgo(2), _daysAgo(1)]), {
      _daysAgo(2): Decimal.fromInt(2),
      _daysAgo(1): Decimal.one,
    });
  });

  test(
    'a skipped rate-limited provider does not make gaps definitive',
    () async {
      final fallback = _FallbackRepository();
      when(() => repo.supports(any(), any(), any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments[2] == PriceRequestType.priceHistory,
      );
      when(
        () => fallback.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => repo.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => fallback.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer((_) async => {_daysAgo(1): Decimal.one});
      when(
        () => fallback.getCoinFiatPrice(
          any(),
          priceDate: any(named: 'priceDate'),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenThrow(Exception('429 rate limit'));
      await manager.dispose();
      manager = CexMarketDataManager(
        priceRepositories: [repo, fallback],
        clock: () => now,
      );
      await manager.init();
      expect(await manager.maybeFiatPrice(_btc), isNull);
      expect(await manager.fiatPriceHistory(_btc, [_daysAgo(1)]), isEmpty);

      manager.clearRepositoryHealthData();
      expect(await manager.fiatPriceHistory(_btc, [_daysAgo(1)]), {
        _daysAgo(1): Decimal.one,
      });
    },
  );

  test('tries all history providers before declaring a date absent', () async {
    final repositories = List.generate(4, (_) => _MockRepository());
    for (final repository in repositories) {
      when(
        () => repository.supports(any(), any(), any()),
      ).thenAnswer((_) async => true);
      when(
        () => repository.getCoinFiatPrices(
          any(),
          any(),
          fiatCurrency: any(named: 'fiatCurrency'),
        ),
      ).thenAnswer(
        (_) async =>
            repository == repositories.last ? {_daysAgo(1): Decimal.one} : {},
      );
    }
    await manager.dispose();
    manager = CexMarketDataManager(
      priceRepositories: repositories,
      clock: () => now,
    );
    await manager.init();

    expect(await manager.fiatPriceHistory(_btc, [_daysAgo(1)]), {
      _daysAgo(1): Decimal.one,
    });
  });

  test('evicts the oldest past-day price beyond 25,000', () async {
    final dates = [for (var days = 25001; days >= 1; days--) _daysAgo(days)];

    await manager.fiatPriceHistory(_btc, dates);
    expect(historyRequests(), hasLength(1));

    await manager.fiatPriceHistory(_btc, [dates.last]);
    verifyNoHistoryRequest();

    await manager.fiatPriceHistory(_btc, [dates.first]);
    expect(historyRequests(), [
      [dates.first],
    ]);
  });
}
