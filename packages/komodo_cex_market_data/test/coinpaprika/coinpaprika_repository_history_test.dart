import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fixtures/mock_helpers.dart';
import 'fixtures/test_constants.dart';
import 'fixtures/test_fixtures.dart';

const _planCutoffBody =
    '{"error":"Getting daily historical data before 2025-11-06 '
    '08:44:51.330733739 +0000 UTC is not allowed in this plan. Check plans '
    'on coinpaprika.com/api"}';

DateTime _utcDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// The free plan as observed on 2026-11-06: a date-only `start` is read as
/// 00:00 UTC and refused before now - 365 days, and today's daily tick is
/// never served.
MockClient _freePlanApi(List<Uri> requests) => MockClient((request) async {
  requests.add(request.url);
  final query = request.url.queryParameters;
  final now = DateTime.now().toUtc();
  final start = DateTime.parse('${query['start']}T00:00:00Z');
  if (start.isBefore(now.subtract(const Duration(days: 365)))) {
    return http.Response(_planCutoffBody, 402);
  }
  final end = DateTime.parse('${query['end']}T00:00:00Z');
  final today = _utcDay(now);
  final ticks = [
    for (
      var day = start;
      !day.isAfter(end) && day.isBefore(today);
      day = day.add(const Duration(days: 1))
    )
      {'timestamp': day.toIso8601String(), 'price': 0.00003},
  ];
  return http.Response(jsonEncode(ticks), 200);
});

MarketDataApiException _rateLimited() => MarketDataApiException(
  ApiErrorParser.parseCoinPaprikaError(402, null),
  service: 'CoinPaprika',
);

void main() {
  setUpAll(MockHelpers.registerFallbackValues);

  group('CoinPaprikaRepository history batches', () {
    late MockCoinPaprikaProvider provider;
    late CoinPaprikaRepository repository;

    setUp(() {
      provider = MockCoinPaprikaProvider();
      MockHelpers.setupMockProvider(provider);
      repository = CoinPaprikaRepository(
        coinPaprikaProvider: provider,
        enableMemoization: false,
      );
    });

    When<Future<List<Ohlc>>> whenFetch() => when(
      () => provider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    );

    List<DateTime> requestedStarts() => verify(
      () => provider.fetchHistoricalOhlc(
        coinId: any(named: 'coinId'),
        startDate: captureAny(named: 'startDate'),
        endDate: any(named: 'endDate'),
        quote: any(named: 'quote'),
        interval: any(named: 'interval'),
      ),
    ).captured.cast<DateTime>();

    // Starts before the plan's cutoff, so the first batch is clamped.
    Future<CoinOhlc> fetchSinceLastYear() => repository.getCoinOhlc(
      TestData.bitcoinAsset,
      Stablecoin.usdt,
      GraphInterval.oneDay,
      startAt: DateTime.now().subtract(const Duration(days: 400)),
      endAt: DateTime.now(),
    );

    test(
      'starts the first batch at the earliest date the plan accepts',
      () async {
        await fetchSinceLastYear();

        final starts = requestedStarts();
        expect(starts, hasLength(5));
        expect(
          starts.first,
          const CoinPaprikaApiPlan.free().getEarliestStartDate(),
        );
        expect(starts.first, _utcDay(starts.first));
      },
    );

    test('rethrows when every batch fails', () async {
      whenFetch().thenThrow(Exception('CoinPaprika server error'));

      await expectLater(fetchSinceLastYear(), throwsA(isA<Exception>()));
      expect(requestedStarts(), hasLength(5));
    });

    test('stops at a rate limit and rethrows it', () async {
      whenFetch().thenThrow(_rateLimited());

      await expectLater(
        fetchSinceLastYear(),
        throwsA(
          isA<MarketDataApiException>().having(
            (e) => e.isRateLimited,
            'isRateLimited',
            isTrue,
          ),
        ),
      );
      expect(requestedStarts(), hasLength(1));
    });

    test('keeps the batches that succeed when one fails', () async {
      var call = 0;
      whenFetch().thenAnswer((_) async {
        if (call++ == 0) throw Exception('CoinPaprika server error');
        return [TestFixtures.createMockOhlc()];
      });

      final result = await fetchSinceLastYear();

      expect(result.ohlc, hasLength(4));
    });
  });

  test('prices a year of history without a request the plan refuses', () async {
    final requests = <Uri>[];
    final repository = CoinPaprikaRepository(
      coinPaprikaProvider: CoinPaprikaProvider(
        httpClient: _freePlanApi(requests),
      ),
      enableMemoization: false,
    );
    final today = _utcDay(DateTime.now().toUtc());
    final earliest = const CoinPaprikaApiPlan.free().getEarliestStartDate()!;
    final dates = [
      for (
        var day = earliest;
        day.isBefore(today);
        day = day.add(const Duration(days: 1))
      )
        day,
    ];

    final prices = await repository.getCoinFiatPrices(
      TestData.bitcoinAsset,
      dates,
    );

    expect(
      requests.first.queryParameters['start'],
      earliest.toIso8601String().substring(0, 10),
    );
    expect(prices.keys, containsAll(dates));
  });
}
