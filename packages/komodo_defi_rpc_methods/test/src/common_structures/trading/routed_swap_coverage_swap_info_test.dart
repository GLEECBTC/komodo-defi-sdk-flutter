import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

Map<String, dynamic> _envelope(String? swapType, Map<String, dynamic> data) => {
  'swap_type': ?swapType,
  'swap_data': data,
};

Map<String, dynamic> _data({
  List<Object?> events = const [],
  bool? finished,
  int? finishedAt,
}) => {
  'uuid': 'c3d4',
  'my_coin': 'DOC',
  'other_coin': 'MARTY',
  'events': events,
  'is_finished': ?finished,
  'finished_at': ?finishedAt,
};

void main() {
  group('event log', () {
    test('reads every event shape KDF has used, skipping the rest', () {
      final info = SwapInfo.fromJson(
        _envelope(
          'TakerV2',
          _data(
            events: [
              {
                'timestamp': 1,
                'event': {'type': 'Started'},
              },
              {'event_type': 'Negotiated', 'event_data': <String, dynamic>{}},
              {'type': 'TakerFundingSent'},
              {'event': 'not an object', 'type': 'MakerPaymentReceived'},
              {
                'event': {'type': 7},
              },
              {'event_type': null},
              'not an event',
              null,
            ],
          ),
        ),
      );

      expect(info.eventTypes, [
        'Started',
        'Negotiated',
        'TakerFundingSent',
        'MakerPaymentReceived',
      ]);
    });

    test('an absent log has no events and is not complete', () {
      final info = SwapInfo.fromJson(
        _envelope('MakerV2', {'uuid': 'c3d4', 'events': null}),
      );
      expect(info.eventTypes, isEmpty);
      expect(info.isComplete, isFalse);
      expect(info.successEvents, isEmpty);
      expect(info.errorEvents, isEmpty);
    });

    test('every v2 abort or refund event fails the swap', () {
      for (final event in [
        'Aborted',
        'TakerFundingRefundRequired',
        'TakerPaymentRefundRequired',
        'MakerPaymentRefundRequired',
        'TakerFundingRefunded',
        'TakerPaymentRefunded',
        'MakerPaymentRefunded',
      ]) {
        final info = SwapInfo.fromJson(
          _envelope(
            'TakerV2',
            _data(
              finished: true,
              events: [
                {'event_type': event},
              ],
            ),
          ),
        );
        expect(info.hasFailed, isTrue, reason: event);
        expect(info.isSuccessful, isFalse, reason: event);
      }
    });

    test('completion comes from a finish time, the flag or the log', () {
      bool complete(Map<String, dynamic> data) =>
          SwapInfo.fromJson(_envelope('TakerV2', data)).isComplete;
      expect(complete(_data(finishedAt: 1700000100)), isTrue);
      expect(complete(_data(finished: true)), isTrue);
      expect(
        complete(
          _data(
            finished: false,
            events: [
              {'type': 'Finished'},
            ],
          ),
        ),
        isTrue,
      );
      expect(complete(_data(finished: false)), isFalse);
    });
  });

  group('role and amounts', () {
    test('a type inside the swap wins over the envelope', () {
      final info = SwapInfo.fromJson(
        _envelope('TakerV1', {..._data(), 'type': 'Maker'}),
      );
      expect(info.type, 'Maker');
      expect(info.makerCoin, 'DOC');
      expect(info.takerCoin, 'MARTY');
    });

    test('an unrecognised or missing swap type is kept as given', () {
      final later = SwapInfo.fromJson(_envelope('TakerV3', _data()));
      expect(later.type, 'TakerV3');
      expect(later.makerCoin, 'DOC');

      final untyped = SwapInfo.fromJson(_envelope(null, _data()));
      expect(untyped.type, isEmpty);
    });

    test('missing coins and volumes read as empty text', () {
      final info = SwapInfo.fromJson(
        _envelope('TakerV2', {
          'uuid': 'c3d4',
          'maker_volume': {'fraction': <String, dynamic>{}},
        }),
      );
      expect(info.takerCoin, isEmpty);
      expect(info.makerCoin, isEmpty);
      expect(info.takerAmount, isEmpty);
      expect(info.makerAmount, isEmpty);
      expect(info.myOrderUuid, isEmpty);
    });
  });

  test('toJson writes the log and the finished flag back', () {
    final info = SwapInfo.fromJson(
      _envelope(
        'MakerV2',
        _data(
          finished: false,
          events: [
            {'event_type': 'Started'},
          ],
        ),
      ),
    );
    final json = info.toJson();
    expect(json['events'], [
      {
        'event': {'type': 'Started'},
      },
    ]);
    expect(json['is_finished'], isFalse);

    final again = SwapInfo.fromJson(json);
    expect(again.eventTypes, ['Started']);
    expect(again.isFinishedFlag, isFalse);
    expect(again.type, 'Maker');

    final quiet = SwapInfo.fromJson(_envelope('MakerV2', {'uuid': 'c3d4'}));
    expect(quiet.toJson().containsKey('events'), isFalse);
    expect(quiet.toJson().containsKey('is_finished'), isFalse);
  });
}
