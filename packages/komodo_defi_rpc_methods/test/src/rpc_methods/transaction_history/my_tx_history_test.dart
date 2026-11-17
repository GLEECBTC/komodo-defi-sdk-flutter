import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _solanaFee = {
  'type': 'Solana',
  'fee_amount': '0.000005',
  'rent_amount': '0.00203928',
  'total_amount': '0.00204428',
};

Map<String, dynamic> _row(String hash, {Object? fee = _solanaFee}) => {
  'coin': 'TESTSOL',
  'tx_hash': hash,
  'internal_id': hash,
  'block_height': 42,
  'timestamp': 1730000000,
  'confirmations': 1,
  'from': ['SenderBase58'],
  'to': ['RecipientBase58'],
  'my_balance_change': '-1',
  'spent_by_me': '1',
  'received_by_me': '0',
  if (fee != null) 'fee_details': fee,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
  'mmrpc': '2.0',
  'result': {
    'current_block': 100,
    'limit': 10,
    'skipped': 0,
    'sync_status': {'state': 'Finished'},
    'total': rows.length,
    'total_pages': 1,
    'transactions': rows,
  },
};

void main() {
  group('my_tx_history page with a nonconforming Solana fee', () {
    for (final (label, fee) in <(String, Map<String, dynamic>)>[
      ('no rent breakdown', {..._solanaFee}..remove('rent_amount')),
      (
        'a total that is not fee plus rent',
        {..._solanaFee, 'total_amount': '1'},
      ),
      ('a numeric amount', {..._solanaFee, 'fee_amount': 0.000005}),
      ('a negative amount', {..._solanaFee, 'rent_amount': '-1'}),
      ('an unparsable amount', {..._solanaFee, 'fee_amount': 'five'}),
    ]) {
      test('loads the row with $label without its fee', () {
        // The strict contract still applies wherever a fee is parsed alone.
        expect(() => FeeInfo.fromJson(fee), throwsFormatException);

        final page = MyTxHistoryResponse.parse(
          _page([_row('First'), _row('Odd', fee: fee), _row('Last')]),
        );

        expect(page.transactions.map((tx) => tx.txHash), [
          'First',
          'Odd',
          'Last',
        ]);
        expect(page.transactions[1].feeDetails, isNull);
        expect(page.transactions[1].myBalanceChange, '-1');
        for (final tx in [page.transactions.first, page.transactions.last]) {
          expect(
            (tx.feeDetails! as SolanaFeeInfo).totalAmount,
            Decimal.parse('0.00204428'),
          );
        }
      });
    }

    test('still fails on a row that is malformed outside its fee', () {
      // `coin` is read after the fee, so this also covers the second parse.
      final broken = _row('Odd', fee: {..._solanaFee, 'total_amount': '1'})
        ..remove('coin');
      expect(
        () => MyTxHistoryResponse.parse(_page([_row('First'), broken])),
        throwsA(isNot(isA<FormatException>())),
      );
    });

    test('does not relax fee parsing for other protocols', () {
      final utxo = _row('Utxo', fee: {'type': 'Utxo', 'amount': 'five'});
      expect(
        () => MyTxHistoryResponse.parse(_page([_row('First'), utxo])),
        throwsFormatException,
      );
    });
  });
}
