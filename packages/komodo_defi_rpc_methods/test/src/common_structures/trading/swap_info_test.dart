import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

// Shapes follow KDF's serde output: `SwapRpcData` is tagged
// `{swap_type, swap_data}`, a legacy `TakerSavedSwap` has no `type` field and
// logs `{timestamp, event: {type, data}}`, and a v2 `MySwapForRpc` logs
// `{event_type, event_data}`.

/// KDF's static `TAKER_ERROR_EVENTS` (abridged): present on every legacy
/// taker swap, whether or not anything went wrong.
const _takerErrorEvents = [
  'StartFailed',
  'NegotiateFailed',
  'TakerFeeSendFailed',
  'MakerPaymentWaitConfirmFailed',
  'TakerPaymentWaitConfirmFailed',
  'TakerPaymentRefunded',
];

Map<String, dynamic> _legacyTaker(List<String> events) => {
  'uuid': 'a1b2',
  'my_order_uuid': 'o1',
  'events': [
    for (final (i, type) in events.indexed)
      {
        'timestamp': 1700000000000 + i,
        'event': {'type': type, 'data': <String, dynamic>{}},
      },
  ],
  'maker_amount': '3000',
  'maker_coin': 'USDC-ERC20',
  'maker_coin_usd_price': null,
  'taker_amount': '1',
  'taker_coin': 'ETH',
  'taker_coin_usd_price': null,
  'gui': 'gleec-wallet',
  'mm_version': '2.6.0',
  'success_events': ['Started', 'Negotiated', 'Finished'],
  'error_events': _takerErrorEvents,
};

/// An `MmNumberMultiRepr` of a whole number (its `rational` form omitted).
Map<String, dynamic> _volume(String whole) => {
  'decimal': whole,
  'fraction': {'numer': whole, 'denom': '1'},
};

Map<String, dynamic> _v2(
  String swapType, {
  required bool finished,
  required List<String> events,
}) => {
  'swap_type': swapType,
  'swap_data': {
    'my_coin': 'DOC',
    'other_coin': 'MARTY',
    'uuid': 'c3d4',
    'started_at': 1700000000,
    'is_finished': finished,
    'events': [
      for (final type in events)
        {'event_type': type, 'event_data': <String, dynamic>{}},
    ],
    'maker_volume': _volume('2'),
    'taker_volume': _volume('1'),
    'swap_version': 2,
  },
};

void main() {
  group('legacy swaps inside the v2 envelope', () {
    test('take their role from swap_type', () {
      final info = SwapInfo.fromJson({
        'swap_type': 'TakerV1',
        'swap_data': _legacyTaker(['Started', 'Negotiated']),
      });

      expect(info.type, 'Taker');
      expect(info.uuid, 'a1b2');
      expect(info.takerCoin, 'ETH');
      expect(info.makerAmount, '3000');
    });

    test('a clean finish succeeds despite the static error list', () {
      final info = SwapInfo.fromJson({
        'swap_type': 'TakerV1',
        'swap_data': _legacyTaker(['Started', 'Negotiated', 'Finished']),
      });

      expect(info.errorEvents, isNotEmpty);
      expect(info.isComplete, isTrue);
      expect(info.hasFailed, isFalse);
      expect(info.isSuccessful, isTrue);
    });

    test('an error event that happened fails the swap', () {
      final info = SwapInfo.fromJson({
        'swap_type': 'TakerV1',
        'swap_data': _legacyTaker([
          'Started',
          'Negotiated',
          'TakerPaymentWaitConfirmFailed',
          'TakerPaymentRefunded',
          'Finished',
        ]),
      });

      expect(info.isComplete, isTrue);
      expect(info.hasFailed, isTrue);
      expect(info.isSuccessful, isFalse);
    });

    test('a swap still running is neither complete nor failed', () {
      final info = SwapInfo.fromJson({
        'swap_type': 'TakerV1',
        'swap_data': _legacyTaker(['Started', 'Negotiated']),
      });

      expect(info.isComplete, isFalse);
      expect(info.hasFailed, isFalse);
      expect(info.isSuccessful, isFalse);
    });

    test('tolerates the optional order uuid and amounts being null', () {
      final info = SwapInfo.fromJson({
        'swap_type': 'MakerV1',
        'swap_data': {
          ..._legacyTaker(['Started']),
          'my_order_uuid': null,
          'maker_amount': null,
          'taker_amount': null,
        },
      });

      expect(info.type, 'Maker');
      expect(info.myOrderUuid, isEmpty);
      expect(info.makerAmount, isEmpty);
    });
  });

  group('v2-protocol swaps', () {
    test('map my_coin and other_coin by role, and volumes to amounts', () {
      final taker = SwapInfo.fromJson(
        _v2('TakerV2', finished: false, events: ['Initialized']),
      );
      final maker = SwapInfo.fromJson(
        _v2('MakerV2', finished: false, events: ['Initialized']),
      );

      expect(taker.type, 'Taker');
      expect(taker.takerCoin, 'DOC');
      expect(taker.makerCoin, 'MARTY');
      expect(taker.takerAmount, '1');
      expect(taker.makerAmount, '2');
      expect(taker.startedAt, 1700000000);
      expect(maker.makerCoin, 'DOC');
      expect(maker.takerCoin, 'MARTY');
      expect(taker.isComplete, isFalse);
    });

    test('completion is judged by is_finished and the events', () {
      final completed = SwapInfo.fromJson(
        _v2('TakerV2', finished: true, events: ['Initialized', 'Completed']),
      );
      final aborted = SwapInfo.fromJson(
        _v2('MakerV2', finished: true, events: ['Initialized', 'Aborted']),
      );
      final refunded = SwapInfo.fromJson(
        _v2(
          'TakerV2',
          finished: true,
          events: ['Initialized', 'TakerFundingSent', 'TakerFundingRefunded'],
        ),
      );

      expect(completed.isSuccessful, isTrue);
      expect(aborted.hasFailed, isTrue);
      expect(aborted.isSuccessful, isFalse);
      expect(refunded.hasFailed, isTrue);
    });
  });

  test('a bare legacy swap with its own type still parses and round-trips', () {
    final bare = {
      ..._legacyTaker(['Started', 'Finished']),
      'type': 'Taker',
    };

    final info = SwapInfo.fromJson(bare);
    final again = SwapInfo.fromJson(info.toJson());

    expect(info.type, 'Taker');
    expect(again.eventTypes, ['Started', 'Finished']);
    expect(again.isSuccessful, isTrue);
  });

  test('status, recent and active responses all read the envelope', () {
    final envelope = {
      'swap_type': 'TakerV1',
      'swap_data': _legacyTaker(['Started', 'Finished']),
    };

    final status = SwapStatusResponse.parse({
      'mmrpc': '2.0',
      'result': envelope,
    });
    final recent = RecentSwapsResponse.parse({
      'mmrpc': '2.0',
      'result': {
        'swaps': [envelope],
      },
    });
    final active = ActiveSwapsResponse.parse({
      'mmrpc': '2.0',
      'result': {
        'uuids': ['a1b2'],
        'statuses': {'a1b2': envelope},
      },
    });

    expect(status.swapInfo.type, 'Taker');
    expect(recent.swaps.single.isSuccessful, isTrue);
    expect(active.statuses!['a1b2']!.swapType, 'TakerV1');
    expect(active.statuses!['a1b2']!.swapData.type, 'Taker');
  });
}
