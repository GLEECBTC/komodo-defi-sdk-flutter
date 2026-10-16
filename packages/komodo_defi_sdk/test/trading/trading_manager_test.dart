import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _Kdf implements ApiClient {
  _Kdf(this.answer);

  FutureOr<JsonMap> Function(JsonMap request) answer;
  final List<JsonMap> requests = [];

  @override
  FutureOr<JsonMap> executeRpc(JsonMap request) {
    requests.add(request);
    return answer(request);
  }
}

JsonMap _depthAnswer(JsonMap request) => {
  'result': [
    for (final pair in request['pairs'] as List<dynamic>)
      {
        'pair': pair,
        'depth': {'asks': 0, 'bids': 2},
      },
  ],
};

void main() {
  late _Kdf kdf;
  late DateTime now;
  late TradingManager trading;

  setUp(() {
    kdf = _Kdf(_depthAnswer);
    now = DateTime(2026, 9, 29, 12);
    trading = TradingManager(
      client: kdf,
      eventStreamingManager: _MockEventStreamingManager(),
      now: () => now,
    );
  });

  final kmdAvn = OrderbookPair(base: 'KMD', rel: 'AVN');
  final kmdLtc = OrderbookPair(base: 'KMD', rel: 'LTC');

  group('orderbookDepth', () {
    test('sends one legacy request for every pair', () async {
      final response = await trading.orderbookDepth(pairs: [kmdAvn, kmdLtc]);

      expect(kdf.requests, hasLength(1));
      expect(kdf.requests.single['method'], 'orderbook_depth');
      expect(kdf.requests.single.containsKey('mmrpc'), isFalse);
      expect(response.depth.map((d) => (d.rel, d.bids)), [
        ('AVN', 2),
        ('LTC', 2),
      ]);
    });

    test('reuses an answer for the same pairs in any order', () async {
      await trading.orderbookDepth(pairs: [kmdAvn, kmdLtc]);
      now = now.add(const Duration(seconds: 19));
      await trading.orderbookDepth(pairs: [kmdLtc, kmdAvn]);

      expect(kdf.requests, hasLength(1));
    });

    test('asks again once the answer is 20 seconds old', () async {
      await trading.orderbookDepth(pairs: [kmdAvn]);
      now = now.add(const Duration(seconds: 20));
      await trading.orderbookDepth(pairs: [kmdAvn]);

      expect(kdf.requests, hasLength(2));
    });

    test('shares a request that is still in flight', () async {
      final answer = Completer<JsonMap>();
      kdf.answer = (_) => answer.future;

      final first = trading.orderbookDepth(pairs: [kmdAvn]);
      final second = trading.orderbookDepth(pairs: [kmdAvn]);
      answer.complete(
        _depthAnswer({
          'pairs': [
            ['KMD', 'AVN'],
          ],
        }),
      );

      expect((await first).depth.single.bids, 2);
      expect((await second).depth.single.bids, 2);
      expect(kdf.requests, hasLength(1));
    });

    test('does not keep an error', () async {
      kdf.answer = (_) => {'error': 'No response from any peer'};
      await expectLater(
        trading.orderbookDepth(pairs: [kmdAvn]),
        throwsA(isA<Exception>()),
      );

      kdf.answer = _depthAnswer;
      final response = await trading.orderbookDepth(pairs: [kmdAvn]);

      expect(response.depth.single.bids, 2);
      expect(kdf.requests, hasLength(2));
    });
  });

  test('min and max volumes reach KDF and read its answers', () async {
    kdf.answer = (request) => switch (request['method']) {
      'min_trading_vol' => {
        'result': {'coin': 'KMD', 'min_trading_vol': '0.0001'},
      },
      'max_taker_vol' => {
        'result': {'numer': '5', 'denom': '2'},
        'coin': 'KMD',
      },
      _ => throw StateError('unexpected ${request['method']}'),
    };

    final min = await trading.minTradingVolume(coin: 'KMD');
    final max = await trading.maxTakerVolume(coin: 'KMD', tradeWith: 'AVN');

    expect(min.amount, '0.0001');
    expect(max.amount, '2.5');
    for (final request in kdf.requests) {
      expect(request.containsKey('mmrpc'), isFalse);
      expect(request.containsKey('params'), isFalse);
    }
  });
}
