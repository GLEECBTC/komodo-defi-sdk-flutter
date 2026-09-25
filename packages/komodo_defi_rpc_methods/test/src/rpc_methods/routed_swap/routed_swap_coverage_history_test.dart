import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

const String _uuid = '00000000-0000-4000-8000-000000000001';

JsonMap _tracking(String uuid) => {
  'status': 'InProgress',
  'details': {'uuid': uuid, 'provider': 'lifi', 'state': 'TrackingBridge'},
};

JsonMap _entry({
  String uuid = _uuid,
  JsonMap? swap,
  int? finishedAt,
  List<Object?> approvals = const ['0xapprove'],
}) => {
  'created_at': 20,
  'updated_at': 24,
  'finished_at': ?finishedAt,
  'requested': {'from': 'USDT-ETH', 'to': 'USDC-POLYGON', 'amount': '1'},
  'min_to_amount_accepted': '1.9',
  'approval_tx_hashes': approvals,
  'gas_spent': [
    {'tx_hash': '0xapprove', 'coin': 'ETH', 'amount': '0.002'},
    {'coin': 'ETH', 'amount': '0.001'},
    'not a gas row',
  ],
  'total_gas_spent': [
    {'coin': 'ETH', 'amount': '0.003'},
    42,
  ],
  'swap': swap ?? _tracking(uuid),
};

void main() {
  group('routed_swap::history request', () {
    test('omits every unset filter so the engine defaults apply', () {
      final json = RoutedSwapHistoryRequest(rpcPass: '').toJson();
      expect(json['method'], 'routed_swap::history');
      expect(json['params'], isEmpty);
    });

    test('sends every filter it is given', () {
      final json = RoutedSwapHistoryRequest(
        rpcPass: '',
        uuid: _uuid,
        filter: RoutedSwapHistoryFilter.inFlight,
        myCoin: 'USDT-ETH',
        otherCoin: 'USDC-POLYGON',
        fromTimestamp: 10,
        toTimestamp: 20,
        limit: 5,
        pageNumber: 2,
      ).toJson();
      expect(json['params'], {
        'uuid': _uuid,
        'status_filter': 'in_flight',
        'my_coin': 'USDT-ETH',
        'other_coin': 'USDC-POLYGON',
        'from_timestamp': 10,
        'to_timestamp': 20,
        'limit': 5,
        'page_number': 2,
      });
      expect(RoutedSwapHistoryFilter.values.map((f) => f.wire), [
        'all',
        'in_flight',
        'terminal',
      ]);
    });
  });

  group('routed_swap::history response', () {
    test('drops an entry it cannot read rather than the whole page', () {
      final response = RoutedSwapHistoryResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'entries': [
            _entry(),
            'not an entry',
            {'swap': _tracking('no-request')},
            _entry(uuid: 'second'),
          ],
          'total': 9,
          'limit': 4,
          'page_number': 2,
          'total_pages': 3,
        },
      });

      expect(response.entries.map((e) => e.uuid), [_uuid, 'second']);
      expect(response.total, 9);
      expect(response.limit, 4);
      expect(response.pageNumber, 2);
      expect(response.totalPages, 3);
      expect(response.hasMore, isTrue);
    });

    test('without paging it describes the entries it holds', () {
      final response = RoutedSwapHistoryResponse.parse({
        'result': {
          'entries': [_entry()],
        },
      });
      expect(response.mmrpc, '2.0');
      expect(response.total, 1);
      expect(response.limit, 1);
      expect(response.pageNumber, 1);
      expect(response.totalPages, 1);
      expect(response.hasMore, isFalse);

      final empty = RoutedSwapHistoryResponse.parse({
        'result': <String, dynamic>{},
      });
      expect(empty.entries, isEmpty);
      expect(empty.total, 0);
    });

    test('toJson summarises the page with an entry count', () {
      final response = RoutedSwapHistoryResponse.parse({
        'mmrpc': '2.0',
        'result': {
          'entries': [_entry(), _entry(uuid: 'second')],
          'total': 9,
          'limit': 4,
          'page_number': 2,
          'total_pages': 3,
        },
      });
      expect(response.toJson(), {
        'mmrpc': '2.0',
        'result': {
          'entries': 2,
          'total': 9,
          'limit': 4,
          'page_number': 2,
          'total_pages': 3,
        },
      });
    });
  });

  group('a history entry', () {
    test('reads the durable envelope around the status', () {
      final entry = RoutedSwapHistoryEntry.fromJson(
        _entry(approvals: ['0xreset', 7, '0xapprove']),
      );

      expect(entry.createdAt, 20);
      expect(entry.updatedAt, 24);
      expect(entry.finishedAt, isNull);
      expect(entry.requested.from, 'USDT-ETH');
      expect(entry.requested.to, 'USDC-POLYGON');
      expect(entry.requested.amount, '1');
      expect(entry.minToAmountAccepted, '1.9');
      expect(entry.approvalTxHashes, ['0xreset', '0xapprove']);
      expect(entry.gasSpent.map((g) => [g.txHash, g.coin, g.amount]), [
        ['0xapprove', 'ETH', '0.002'],
        ['', 'ETH', '0.001'],
      ]);
      expect(entry.totalGasSpent.single.coin, 'ETH');
      expect(entry.totalGasSpent.single.amount, '0.003');
      expect(entry.uuid, _uuid);
      expect(entry.provider, 'lifi');
      expect(entry.isInFlight, isTrue);
    });

    test('missing optional fields read as empty or zero', () {
      final entry = RoutedSwapHistoryEntry.fromJson({
        'requested': const {'from': 'ETH', 'to': 'USDC-POLYGON', 'amount': '1'},
        'swap': _tracking(_uuid),
      });
      expect(entry.createdAt, 0);
      expect(entry.updatedAt, 0);
      expect(entry.finishedAt, isNull);
      expect(entry.minToAmountAccepted, '0');
      expect(entry.approvalTxHashes, isEmpty);
      expect(entry.gasSpent, isEmpty);
      expect(entry.totalGasSpent, isEmpty);
    });

    test('an entry without its swap or request is unreadable', () {
      expect(
        () => RoutedSwapHistoryEntry.fromJson({..._entry()}..remove('swap')),
        throwsArgumentError,
      );
      expect(
        () =>
            RoutedSwapHistoryEntry.fromJson({..._entry()}..remove('requested')),
        throwsArgumentError,
      );
    });

    test('a terminal entry is not in flight', () {
      final entry = RoutedSwapHistoryEntry.fromJson(
        _entry(
          finishedAt: 30,
          swap: {
            'status': 'Error',
            'details': {
              'uuid': _uuid,
              'provider': 'other',
              'error_type': 'AbortedOnRestart',
            },
          },
        ),
      );
      expect(entry.isInFlight, isFalse);
      expect(entry.finishedAt, 30);
      expect(entry.provider, 'other');
    });

    test('equal records are equal; any changed field is not', () {
      RoutedSwapHistoryEntry parse(JsonMap json) =>
          RoutedSwapHistoryEntry.fromJson(json);
      final entry = parse(_entry());
      expect(entry, parse(_entry()));
      expect(entry.hashCode, parse(_entry()).hashCode);
      expect(entry, isNot(parse(_entry(finishedAt: 30))));
      expect(entry, isNot(parse(_entry(approvals: const []))));
      expect(entry, isNot(parse({..._entry(), 'updated_at': 25})));
      expect(
        entry,
        isNot(parse({..._entry(), 'min_to_amount_accepted': '1.8'})),
      );
    });

    test('its parts compare by value', () {
      const requested = RoutedSwapRequested(from: 'A', to: 'B', amount: '1');
      expect(
        requested,
        RoutedSwapRequested.fromJson(const {
          'from': 'A',
          'to': 'B',
          'amount': '1',
        }),
      );
      expect(
        requested.hashCode,
        const RoutedSwapRequested(from: 'A', to: 'B', amount: '1').hashCode,
      );
      expect(
        requested,
        isNot(const RoutedSwapRequested(from: 'A', to: 'B', amount: '2')),
      );

      const spent = RoutedSwapGasSpent(txHash: '0x1', coin: 'ETH', amount: '1');
      expect(
        spent.hashCode,
        const RoutedSwapGasSpent(
          txHash: '0x1',
          coin: 'ETH',
          amount: '1',
        ).hashCode,
      );
      expect(
        spent,
        isNot(
          const RoutedSwapGasSpent(txHash: '0x2', coin: 'ETH', amount: '1'),
        ),
      );

      const total = RoutedSwapGasTotal(coin: 'ETH', amount: '1');
      expect(total, const RoutedSwapGasTotal(coin: 'ETH', amount: '1'));
      expect(
        total.hashCode,
        const RoutedSwapGasTotal(coin: 'ETH', amount: '1').hashCode,
      );
      expect(
        total,
        isNot(const RoutedSwapGasTotal(coin: 'MATIC', amount: '1')),
      );
    });
  });
}
