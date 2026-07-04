import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

/// The canonical wire shape from the KDF fork: `WithdrawError` and
/// `GaslessWithdrawError` are BOTH adjacently tagged (`error_type` /
/// `error_data`), so gasless withdraw errors arrive nested under an outer
/// `error_type: 'Gasless'` envelope. `gasfree_address` is NOT sent by current
/// KDF builds.
Map<String, dynamic> _nestedGaslessError({
  required String innerType,
  required Map<String, dynamic> innerData,
  required String message,
}) => {
  'error': message,
  'error_path': 'eth_withdraw.withdraw',
  'error_trace': 'eth_withdraw:348]',
  'error_type': 'Gasless',
  'error_data': {'error_type': innerType, 'error_data': innerData},
};

void main() {
  group('GasFree custody shortfall error parsing', () {
    test(
      'parses nested InsufficientGasFreeBalance without gasfree_address',
      () {
        final result = KdfErrorRegistry.tryParse(
          _nestedGaslessError(
            innerType: 'InsufficientGasFreeBalance',
            innerData: {
              'coin': 'USDT-TRC20',
              'available': '0',
              'required': '8',
            },
            message:
                'Not enough USDT-TRC20 in your GasFree deposit address: '
                'available 0, required 8. Deposit USDT-TRC20 into your GasFree '
                'address.',
          ),
          rpcMethodHint: 'task::withdraw::status',
        );

        expect(
          result,
          isA<GaslessWithdrawErrorInsufficientGasFreeBalanceException>(),
        );
        final typed =
            result! as GaslessWithdrawErrorInsufficientGasFreeBalanceException;
        expect(typed.coin, 'USDT-TRC20');
        expect(typed.available.value, '0');
        expect(typed.required.value, '8');
        expect(typed.gasfreeAddress, isEmpty);
        expect(typed.message, contains('GasFree deposit address'));
      },
    );

    test('parses nested InsufficientGasFreeBalanceForActivation without '
        'gasfree_address', () {
      final result = KdfErrorRegistry.tryParse(
        _nestedGaslessError(
          innerType: 'InsufficientGasFreeBalanceForActivation',
          innerData: {
            'coin': 'USDT-TRC20',
            'available': '2',
            'required': '8',
            'activation_fee': '1.5',
          },
          message:
              'Not enough USDT-TRC20 in your GasFree deposit address: '
              'available 2, required 8 (incl. one-time activation fee 1.5). '
              'Deposit USDT-TRC20 into your GasFree address.',
        ),
        rpcMethodHint: 'task::withdraw::status',
      );

      expect(
        result,
        isA<
          GaslessWithdrawErrorInsufficientGasFreeBalanceForActivationException
        >(),
      );
      final typed =
          result!
              as GaslessWithdrawErrorInsufficientGasFreeBalanceForActivationException;
      expect(typed.coin, 'USDT-TRC20');
      expect(typed.available.value, '2');
      expect(typed.required.value, '8');
      expect(typed.activationFee.value, '1.5');
      expect(typed.gasfreeAddress, isEmpty);
    });

    test(
      'parses a flat (unnested) shape with gasfree_address, forward-compat',
      () {
        final result = KdfErrorRegistry.tryParse({
          'error': 'Not enough USDT-TRC20 in your GasFree deposit address',
          'error_type': 'InsufficientGasFreeBalance',
          'error_data': {
            'coin': 'USDT-TRC20',
            'gasfree_address': 'TPRN9HuCCTUuEsw5DsPBM8CQGRq77Aey5g',
            'available': '0',
            'required': '8',
          },
        });

        expect(
          result,
          isA<GaslessWithdrawErrorInsufficientGasFreeBalanceException>(),
        );
        final typed =
            result! as GaslessWithdrawErrorInsufficientGasFreeBalanceException;
        expect(typed.gasfreeAddress, 'TPRN9HuCCTUuEsw5DsPBM8CQGRq77Aey5g');
      },
    );

    test(
      'non-shortfall Gasless variants degrade to null (no typed parser)',
      () {
        final result = KdfErrorRegistry.tryParse(
          _nestedGaslessError(
            innerType: 'PendingTransfer',
            innerData: const {},
            message:
                'A gasless transfer is already pending; wait for settlement '
                'and retry',
          ),
        );
        expect(result, isNull);
      },
    );
  });
}
