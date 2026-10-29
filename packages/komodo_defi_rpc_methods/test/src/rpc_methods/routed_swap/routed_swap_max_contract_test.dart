import 'dart:convert';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

Map<String, dynamic> wire(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  test(
    'exact and Max quote requests have mutually exclusive amount fields',
    () {
      final exact = wire(
        RoutedSwapQuoteRequest(
          rpcPass: 'test',
          from: 'ETH',
          to: 'USDC',
          amount: '1.25',
        ).toJson(),
      );
      expect(exact['params'], {'from': 'ETH', 'to': 'USDC', 'amount': '1.25'});
      final max = wire(
        RoutedSwapQuoteRequest.max(
          rpcPass: 'test',
          from: 'ETH',
          to: 'USDC',
          order: RoutedSwapOrder.fastest,
          slippage: 0.005,
          provider: 'lifi',
        ).toJson(),
      );
      expect(max['params'], {
        'from': 'ETH',
        'to': 'USDC',
        'max': true,
        'order': 'fastest',
        'slippage': 0.005,
        'provider': 'lifi',
      });
      expect(max['method'], 'routed_swap::quote');
    },
  );

  test('execution always sends a concrete amount and the accepted minimum', () {
    final init = wire(
      RoutedSwapInitRequest(
        rpcPass: 'test',
        from: 'ETH',
        to: 'USDC',
        amount: '0.997',
        minToAmount: '2987.123456',
      ).toJson(),
    );
    expect(init['params'], {
      'from': 'ETH',
      'to': 'USDC',
      'amount': '0.997',
      'min_to_amount': '2987.123456',
    });
    expect(init['method'], 'task::routed_swap::init');
  });

  for (final locked in [null, '0', '1.25']) {
    test('quote and task insufficient balances preserve locked=$locked', () {
      final data = <String, dynamic>{
        'coin': 'ETH',
        'available': '0.01',
        'required': '0.02',
        if (locked != null) 'locked_by_swaps': locked,
      };
      final envelope = wire({
        'mmrpc': '2.0',
        'error_type': 'InsufficientBalance',
        'error': 'short',
        'error_data': data,
      });
      final quote =
          RoutedSwapRpcException.tryParse(envelope)!
              as RoutedSwapInsufficientBalanceException;
      expect(quote.coin, 'ETH');
      expect(quote.available, '0.01');
      expect(quote.required, '0.02');
      expect(quote.lockedBySwaps, locked);
      expect(quote.errorData, data);
      final task =
          RoutedSwapTaskError.parse('InsufficientBalance', wire(data))
              as RoutedSwapInsufficientBalanceError;
      expect(task.lockedBySwaps, locked);
      expect(wire(task.toJson()), data);
      expect(
        RoutedSwapTaskError.parse(task.errorType, wire(task.toJson())),
        task,
      );
    });
  }
}
