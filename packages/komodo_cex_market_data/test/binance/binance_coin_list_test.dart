import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'binance_test_helpers.dart';

const _global = 'https://api.binance.com/api/v3';
const _us = 'https://api.binance.us/api/v3';

/// Answers `exchangeInfo` per endpoint with exchange info or an error.
class _FakeBinance implements IBinanceProvider {
  final exchangeInfoRequests = <String?>[];
  final answers = <String, Object>{};
  Completer<void>? gate;

  @override
  Future<BinanceExchangeInfoResponseReduced> fetchExchangeInfoReduced({
    String? baseUrl,
  }) async {
    exchangeInfoRequests.add(baseUrl);
    await gate?.future;
    final answer = answers[baseUrl];
    if (answer is BinanceExchangeInfoResponseReduced) return answer;
    throw answer ?? Exception('Connection failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _btc = AssetId(
  id: 'BTC',
  name: 'Bitcoin',
  symbol: AssetSymbol(assetConfigId: 'BTC'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

BinanceExchangeInfoResponseReduced _noSymbols() =>
    BinanceExchangeInfoResponseReduced(
      timezone: '',
      serverTime: 0,
      symbols: [],
    );

void main() {
  group('BinanceRepository coin list', () {
    late _FakeBinance binance;
    late DateTime now;
    late BinanceRepository repository;

    setUp(() {
      binance = _FakeBinance();
      now = DateTime.utc(2026, 11, 17, 12);
      repository = BinanceRepository(
        binanceProvider: binance,
        clock: () => now,
      );
    });

    Future<bool> supportsBtc() => repository.supports(
      _btc,
      Stablecoin.usdt,
      PriceRequestType.currentPrice,
    );

    test('fetches again after a failure once the cooldown ends', () async {
      // Started offline: neither endpoint answers.
      await expectLater(repository.getCoinList(), throwsException);
      expect(binance.exchangeInfoRequests, [_global, _us]);

      binance.answers[_global] = buildComprehensiveExchangeInfo();
      now = now.add(const Duration(minutes: 4, seconds: 59));
      await expectLater(repository.getCoinList(), throwsStateError);
      expect(binance.exchangeInfoRequests, hasLength(2));

      now = now.add(const Duration(seconds: 1));
      expect(await supportsBtc(), isTrue);
      expect(await supportsBtc(), isTrue);
      expect(binance.exchangeInfoRequests, [_global, _us, _global]);
    });

    test('an endpoint without symbols does not answer the coin list', () async {
      binance.answers[_global] = _noSymbols();
      binance.answers[_us] = buildComprehensiveExchangeInfo();

      expect(await supportsBtc(), isTrue);
      expect(binance.exchangeInfoRequests, [_global, _us]);
    });

    test('fails when no endpoint lists a symbol, then tries again', () async {
      binance.answers[_global] = _noSymbols();
      binance.answers[_us] = _noSymbols();

      await expectLater(repository.getCoinList(), throwsException);

      binance.answers[_us] = buildComprehensiveExchangeInfo();
      now = now.add(const Duration(minutes: 5));
      expect(await supportsBtc(), isTrue);
    });

    test('a failed fetch reaches callers in other error zones', () async {
      binance.gate = Completer<void>();

      // RepositoryFallbackMixin runs each lookup inside `retry`, which gives
      // each attempt its own error zone.
      final lookups = [
        for (var i = 0; i < 4; i++)
          retry(repository.getCoinList, maxAttempts: 1),
      ];
      binance.gate!.complete();

      final outcomes = await Future.wait([
        for (final lookup in lookups)
          lookup.then<Object>((value) => value, onError: (Object e) => e),
      ]).timeout(const Duration(seconds: 5));

      expect(outcomes, everyElement(isException));
      expect(binance.exchangeInfoRequests, [_global, _us]);
    });
  });

  test(
    'a geo-blocked endpoint (HTTP 451) falls back to the next one',
    () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.host == 'api.binance.com') {
          return http.Response('{"code":0,"msg":"Service unavailable"}', 451);
        }
        return http.Response(
          jsonEncode({
            'timezone': 'UTC',
            'serverTime': 1640995200000,
            'symbols': [
              {
                'symbol': 'BTCUSDT',
                'status': 'TRADING',
                'baseAsset': 'BTC',
                'baseAssetPrecision': 8,
                'quoteAsset': 'USDT',
                'quotePrecision': 8,
                'quoteAssetPrecision': 8,
                'isSpotTradingAllowed': true,
              },
            ],
          }),
          200,
        );
      });
      final repository = BinanceRepository(
        binanceProvider: const BinanceProvider(),
      );

      final supported = await http.runWithClient(
        () => repository.supports(
          _btc,
          Stablecoin.usdt,
          PriceRequestType.currentPrice,
        ),
        () => client,
      );

      expect(supported, isTrue);
      expect(hosts, ['api.binance.com', 'api.binance.us']);
    },
  );
}
