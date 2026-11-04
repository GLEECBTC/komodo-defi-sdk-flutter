import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:rational/rational.dart';
import 'package:test/test.dart';

// KDF serves these three methods only on its legacy dispatcher, which it tries
// only when `mmrpc` is absent. The payloads below are the shapes it sends at
// 4872ef2 (rpc/lp_commands/legacy.rs, lp_swap/taker_swap.rs,
// lp_ordermatch/orderbook_depth.rs).
void main() {
  void expectLegacyWire(Map<String, dynamic> json) {
    expect(json.containsKey('mmrpc'), isFalse);
    expect(json.containsKey('params'), isFalse);
  }

  group('min_trading_vol', () {
    final request = MinTradingVolumeRequest(rpcPass: 'pass', coin: 'KMD');

    test('is sent to the legacy dispatcher', () {
      final json = request.toJson();
      expectLegacyWire(json);
      expect(json['method'], 'min_trading_vol');
      expect(json['coin'], 'KMD');
    });

    test('reads the legacy result', () {
      final response = request.parseResponseJson({
        'result': {
          'coin': 'KMD',
          'min_trading_vol': '0.0001',
          'min_trading_vol_fraction': {'numer': '1', 'denom': '10000'},
          'min_trading_vol_rat': [
            [
              1,
              [1],
            ],
            [
              1,
              [10000],
            ],
          ],
        },
      });

      expect(response.mmrpc, isNull);
      expect(response.amount, '0.0001');
      expect(response.amountFraction?.denom, '10000');
      expect(response.amountRat, Rational(BigInt.one, BigInt.from(10000)));
      expect(
        MinTradingVolumeResponse.parse(response.toJson()).amount,
        '0.0001',
      );
    });

    test('throws on an error answer', () {
      expect(
        () => request.parseResponseJson({'error': 'No such coin: KMD'}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('max_taker_vol', () {
    final request = MaxTakerVolumeRequest(
      rpcPass: 'pass',
      coin: 'KMD',
      tradeWith: 'BTC',
    );

    test('is sent to the legacy dispatcher', () {
      final json = request.toJson();
      expectLegacyWire(json);
      expect(json['method'], 'max_taker_vol');
      expect(json['coin'], 'KMD');
      expect(json['trade_with'], 'BTC');
      expect(
        MaxTakerVolumeRequest(rpcPass: 'pass', coin: 'KMD').toJson(),
        isNot(contains('trade_with')),
      );
    });

    test('reads the legacy fraction as a decimal amount', () {
      final response = request.parseResponseJson({
        'result': {'numer': '2499', 'denom': '100'},
        'coin': 'KMD',
      });

      expect(response.mmrpc, isNull);
      expect(response.amount, '24.99');
      expect(response.amountFraction?.numer, '2499');
      expect(response.amountRat, Rational(BigInt.from(2499), BigInt.from(100)));
      expect(MaxTakerVolumeResponse.parse(response.toJson()).amount, '24.99');
    });

    test('truncates a repeating fraction rather than rounding it up', () {
      final response = request.parseResponseJson({
        'result': {'numer': '2', 'denom': '3'},
        'coin': 'KMD',
      });

      expect(response.amount, '0.666666666666666666');
    });

    test('serialises a response built from an amount alone', () {
      final json = MaxTakerVolumeResponse(mmrpc: null, amount: '1.5').toJson();

      expect(MaxTakerVolumeResponse.parse(json).amount, '1.5');
    });

    test('throws on an error answer', () {
      expect(
        () => request.parseResponseJson({'error': 'No such coin: KMD'}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('orderbook_depth', () {
    final request = OrderbookDepthRequest(
      rpcPass: 'pass',
      pairs: [
        OrderbookPair(base: 'KMD', rel: 'AVN'),
        OrderbookPair(base: 'KMD', rel: 'BTC-segwit'),
      ],
    );

    test('is sent to the legacy dispatcher with the pairs as tuples', () {
      final json = request.toJson();
      expectLegacyWire(json);
      expect(json['method'], 'orderbook_depth');
      expect(json['pairs'], [
        ['KMD', 'AVN'],
        ['KMD', 'BTC-segwit'],
      ]);
    });

    test('reads every pair, including the alias KDF answers under', () {
      final response = request.parseResponseJson({
        'result': [
          {
            'pair': ['KMD', 'AVN'],
            'depth': {'asks': 0, 'bids': 0},
          },
          {
            'pair': ['KMD', 'BTC-segwit'],
            'depth': {'asks': 3, 'bids': 5},
          },
          {
            'pair': ['KMD', 'BTC'],
            'depth': {'asks': 3, 'bids': 5},
          },
        ],
      });

      expect(response.mmrpc, isNull);
      expect(
        response.depth.map((d) => (d.base, d.rel, d.asks, d.bids)).toList(),
        [
          ('KMD', 'AVN', 0, 0),
          ('KMD', 'BTC-segwit', 3, 5),
          ('KMD', 'BTC', 3, 5),
        ],
      );
      expect(OrderbookDepthResponse.parse(response.toJson()).depth.length, 3);
    });

    test('throws on an error answer', () {
      expect(
        () => request.parseResponseJson({
          'error': 'Pairs [("KMD", "TRX")] have wallet only coins',
        }),
        throwsA(isA<Exception>()),
      );
    });
  });
}
