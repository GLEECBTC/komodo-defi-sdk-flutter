import 'dart:convert';

import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _record({
  String? traceId = 'trace-123',
  String? journalId,
  String? legacyRequestId,
  String state = 'submittedPending',
}) => {
  if (traceId != null) 'trace_id': traceId,
  if (journalId != null) 'journal_id': journalId,
  if (legacyRequestId != null) 'request_id': legacyRequestId,
  'asset_id': 'USDT-TRC20',
  'network': 'TRX',
  'source_address': 'TSource',
  'custody_address': 'TCustody',
  'destination_address': 'TDestination',
  'requested_amount': '5',
  'signed_max_fee': '2',
  'authorization_deadline': 1999999999,
  'balance_changes': {
    'my_balance_change': '-7',
    'received_by_me': '0',
    'spent_by_me': '7',
    'total_amount': '5',
  },
  'fee': <String, dynamic>{
    'type': 'TronGasless',
    'coin': 'USDT-TRC20',
    'fee_method': 'gasless',
    'provider_name': 'gasfree',
    'gasfree_address': 'TCustody',
    'transfer_fee': '2',
    'total_token_fee': '2',
    'signed_max_fee': '2',
    'trace_id': null,
  },
  'accepted_at': '2026-07-10T12:00:00Z',
  'updated_at': '2026-07-10T12:01:00Z',
  'state': state,
};

void main() {
  test('migrates legacy request_id to the local journal id', () {
    final legacy = _record(legacyRequestId: 'legacy-local-id');
    (legacy['fee']! as Map<String, dynamic>).addAll({
      'final_fee': '1.5',
      'provider_address': 'TProvider',
      'request_id': 'legacy-local-id',
      'authorization_fingerprint': 'legacy-fingerprint',
      'trace_id': 'legacy-fee-trace',
    });
    final transfer = PendingGaslessTransfer.fromJson(legacy);

    expect(transfer.journalId, 'legacy-local-id');
    expect(transfer.traceId, 'trace-123');
    expect(transfer.state, GaslessTransferState.submittedPending);
    expect(transfer.toJson(), isNot(contains('request_id')));
    expect(transfer.toJson(), containsPair('journal_id', 'legacy-local-id'));
    expect(transfer.fee.toJson(), isNot(contains('final_fee')));
    expect(transfer.fee.toJson(), isNot(contains('provider_address')));
    expect(transfer.fee.toJson(), containsPair('trace_id', null));
  });

  test('recovers an accepted legacy trace without a local id', () {
    final transfer = PendingGaslessTransfer.fromJson(_record());

    expect(transfer.journalId, 'legacy:trace-123');
    expect(transfer.traceId, 'trace-123');
  });

  test('recovers a trace-bearing legacy fee without its nested cap', () {
    final legacy = _record();
    (legacy['fee']! as Map<String, dynamic>).remove('signed_max_fee');

    final transfer = PendingGaslessTransfer.fromJson(legacy);
    final fee = transfer.fee as FeeInfoTronGasless;

    expect(transfer.traceId, 'trace-123');
    expect(fee.signedMaxFee.toString(), '2');
    expect(transfer.toJson()['fee'], containsPair('signed_max_fee', '2'));
  });

  test('trace-less legacy reservations remain outcome-unknown', () {
    final transfer = PendingGaslessTransfer.fromJson(
      _record(
        traceId: null,
        legacyRequestId: 'legacy-local-id',
        state: 'preparing',
      ),
    );

    expect(transfer.traceId, isNull);
    expect(transfer.state, GaslessTransferState.submittedUnknown);
  });

  test('rejects a record with neither a trace nor local journal identity', () {
    expect(
      () => PendingGaslessTransfer.fromJson(_record(traceId: null)),
      throwsFormatException,
    );
  });

  test('persistence never includes signed authorization material', () {
    final persisted = PendingGaslessTransfer.fromJson(
      _record(journalId: 'journal-123'),
    ).toJson();
    final encoded = jsonEncode(persisted);

    expect(persisted, isNot(contains('signed_authorization')));
    expect(persisted, isNot(contains('signature')));
    expect(persisted, isNot(contains('fingerprint')));
    expect(encoded, isNot(contains('"signed_authorization"')));
    expect(encoded, isNot(contains('"sig"')));
    expect(encoded, isNot(contains('"nonce"')));
    expect(encoded, isNot(contains('"service_provider"')));
    expect(encoded, isNot(contains('"verifying_contract"')));
  });
}
