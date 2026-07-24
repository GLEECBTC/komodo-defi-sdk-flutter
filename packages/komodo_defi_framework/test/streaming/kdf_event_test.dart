import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/streaming/events/kdf_event.dart';

void main() {
  group('KdfEvent.parseAll - BALANCE', () {
    test('BALANCE:TRX list payload yields one event per ticker, summed across '
        'addresses', () {
      // The real-world Tron payload: the type suffix is the platform (TRX)
      // but the entries carry token tickers (USDT-TRC20) across addresses.
      final events = KdfEvent.parseAll(<String, dynamic>{
        '_type': 'BALANCE:TRX',
        'message': [
          {
            'ticker': 'USDT-TRC20',
            'address': 'TDpG5sdBXmpCGfJJSr5RGnyHxmcJSYmrg7',
            'balance': {'spendable': '110', 'unspendable': '0'},
          },
          {
            'ticker': 'USDT-TRC20',
            'address': 'TPLDjoLfSrMFD1KjXjuT4u1Ge8Bi69rCSw',
            'balance': {'spendable': '0', 'unspendable': '0'},
          },
        ],
      });

      expect(events, hasLength(1));
      final event = events.single;
      expect(event, isA<BalanceEvent>());
      final balanceEvent = event as BalanceEvent;

      // Coin is taken from the entry ticker, NOT the BALANCE:TRX suffix.
      expect(balanceEvent.coin, 'USDT-TRC20');
      expect(balanceEvent.balance.spendable.toString(), '110');
      expect(balanceEvent.balance.unspendable.toString(), '0');
      expect(balanceEvent.balance.total.toString(), '110');
    });

    test('list payload with multiple tickers fans out to one event each', () {
      final events = KdfEvent.parseAll(<String, dynamic>{
        '_type': 'BALANCE:TRX',
        'message': [
          {
            'ticker': 'TRX',
            'address': 'TAddrA',
            'balance': {'spendable': '5', 'unspendable': '0'},
          },
          {
            'ticker': 'USDT-TRC20',
            'address': 'TAddrA',
            'balance': {'spendable': '110', 'unspendable': '0'},
          },
          {
            'ticker': 'USDT-TRC20',
            'address': 'TAddrB',
            'balance': {'spendable': '1', 'unspendable': '2'},
          },
        ],
      }).cast<BalanceEvent>();

      expect(events, hasLength(2));

      final trx = events.firstWhere((e) => e.coin == 'TRX');
      expect(trx.balance.spendable.toString(), '5');

      final usdt = events.firstWhere((e) => e.coin == 'USDT-TRC20');
      expect(usdt.balance.spendable.toString(), '111');
      expect(usdt.balance.unspendable.toString(), '2');
      expect(usdt.balance.total.toString(), '113');
    });

    test('single-object payload is parsed as one event', () {
      final events = KdfEvent.parseAll(<String, dynamic>{
        '_type': 'BALANCE:DOC',
        'message': {
          'coin': 'DOC',
          'balance': {'spendable': '1', 'unspendable': '2'},
        },
      });

      expect(events, hasLength(1));
      final balanceEvent = events.single as BalanceEvent;
      expect(balanceEvent.coin, 'DOC');
      expect(balanceEvent.balance.spendable.toString(), '1');
      expect(balanceEvent.balance.unspendable.toString(), '2');
    });

    test('entry without a ticker falls back to the type suffix', () {
      final events = KdfEvent.parseAll(<String, dynamic>{
        '_type': 'BALANCE:LTC',
        'message': [
          {
            'address': 'Laddr',
            'balance': {'spendable': '3', 'unspendable': '0'},
          },
        ],
      }).cast<BalanceEvent>();

      expect(events, hasLength(1));
      expect(events.single.coin, 'LTC');
      expect(events.single.balance.spendable.toString(), '3');
    });
  });

  group('KdfEvent.parseAll - GASLESS_TRACE', () {
    test('parses the exact success event shape', () {
      final event = KdfEvent.parseAll(<String, dynamic>{
        '_type': 'GASLESS_TRACE:USDT-TRC20',
        'message': {
          'coin': 'USDT-TRC20',
          'trace_id': 'trace-1',
          'state': 'on_chain',
          'tx_hash_on_chain': 'on-chain-hash',
          'block_height': 57175988,
          'confirmed_at': 1747909638,
          'final_fee': '2.000000',
          'failure_reason': null,
        },
      }).single;

      expect(event, isA<GaslessTraceEvent>());
      final trace = event as GaslessTraceEvent;
      expect(trace.coin, 'USDT-TRC20');
      expect(trace.traceId, 'trace-1');
      expect(trace.state, GaslessTraceEventState.onChain);
      expect(trace.txHashOnChain, 'on-chain-hash');
      expect(trace.blockHeight, 57175988);
      expect(trace.confirmedAt, 1747909638);
      expect(trace.finalFee, '2.000000');
    });

    test('parses the runtime ERROR prefix as a typed error', () {
      final event = KdfEvent.parseAll(<String, dynamic>{
        '_type': 'ERROR:GASLESS_TRACE:USDT-TRC20',
        'message': {
          'coin': 'USDT-TRC20',
          'trace_id': 'trace-2',
          'error': 'Request to GasFree provider timed out',
        },
      }).single;

      expect(event, isA<GaslessTraceErrorEvent>());
      final traceError = event as GaslessTraceErrorEvent;
      expect(traceError.coin, 'USDT-TRC20');
      expect(traceError.traceId, 'trace-2');
      expect(traceError.error, 'Request to GasFree provider timed out');
    });

    test('rejects unknown lifecycle states', () {
      expect(
        () => KdfEvent.parseAll(<String, dynamic>{
          '_type': 'GASLESS_TRACE:USDT-TRC20',
          'message': {
            'coin': 'USDT-TRC20',
            'trace_id': 'trace-3',
            'state': 'WAITING',
          },
        }),
        throwsFormatException,
      );
    });

    test('rejects a message coin that differs from the stream suffix', () {
      expect(
        () => KdfEvent.parseAll(<String, dynamic>{
          '_type': 'GASLESS_TRACE:USDT-TRC20',
          'message': {
            'coin': 'USDC-TRC20',
            'trace_id': 'trace-4',
            'state': 'submitted',
          },
        }),
        throwsFormatException,
      );
    });

    test('rejects mixed failure shapes', () {
      expect(
        () => KdfEvent.parseAll(<String, dynamic>{
          '_type': 'GASLESS_TRACE:USDT-TRC20',
          'message': {
            'coin': 'USDT-TRC20',
            'trace_id': 'trace-5',
            'state': 'failed',
          },
        }),
        throwsFormatException,
      );
      expect(
        () => KdfEvent.parseAll(<String, dynamic>{
          '_type': 'GASLESS_TRACE:USDT-TRC20',
          'message': {
            'coin': 'USDT-TRC20',
            'trace_id': 'trace-6',
            'state': 'confirmed',
            'failure_reason': 'must not be present',
          },
        }),
        throwsFormatException,
      );
    });
  });
}
