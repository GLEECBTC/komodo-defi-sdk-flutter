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
}
