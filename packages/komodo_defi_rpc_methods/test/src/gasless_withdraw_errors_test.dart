import 'dart:convert';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

/// `WithdrawError::Gasless` and `GaslessWithdrawError` are both adjacently
/// tagged in KDF, so every GasFree failure is nested under an outer `Gasless`
/// envelope.
Map<String, dynamic> _nestedGaslessError({
  required GaslessWithdrawErrorType type,
  Object? errorData,
}) => {
  'error': 'GasFree withdrawal failed: ${type.wireValue}',
  'error_path': 'eth_withdraw.withdraw',
  'error_trace': 'eth_withdraw:348',
  'error_type': 'Gasless',
  'error_data': {'error_type': type.wireValue, 'error_data': errorData},
};

Object? _fixtureData(GaslessWithdrawErrorType type) => switch (type) {
  GaslessWithdrawErrorType.insufficientGasFreeBalance => {
    'coin': 'USDT-TRC20',
    'available': '0',
    'required': '8',
  },
  GaslessWithdrawErrorType.insufficientGasFreeBalanceForActivation => {
    'coin': 'USDT-TRC20',
    'available': '2',
    'required': '8',
    'activation_fee': '1.5',
  },
  _ => null,
};

void main() {
  final request = WithdrawStatusRequest(rpcPass: 'rpc-pass', taskId: 42);

  group('GasFree withdrawal errors', () {
    for (final type in GaslessWithdrawErrorType.values) {
      test('parses exact nested ${type.wireValue}', () {
        final wire = _nestedGaslessError(
          type: type,
          errorData: _fixtureData(type),
        );

        expect(
          () => request.parseResponse(jsonEncode(wire)),
          throwsA(
            isA<GaslessWithdrawException>()
                .having((error) => error.type, 'type', type)
                .having(
                  (error) => error.message,
                  'message',
                  contains(type.wireValue),
                )
                .having((error) => error.path, 'path', 'eth_withdraw.withdraw')
                .having((error) => error.trace, 'trace', 'eth_withdraw:348'),
          ),
        );
      });
    }

    test(
      'preserves structured custody shortfall data without inventing fields',
      () {
        final error = GaslessWithdrawException.tryParse(
          _nestedGaslessError(
            type: GaslessWithdrawErrorType
                .insufficientGasFreeBalanceForActivation,
            errorData: _fixtureData(
              GaslessWithdrawErrorType.insufficientGasFreeBalanceForActivation,
            ),
          ),
        );

        expect(error, isNotNull);
        expect(error!.errorData, {
          'coin': 'USDT-TRC20',
          'available': '2',
          'required': '8',
          'activation_fee': '1.5',
        });
        expect(error.toJson(), {
          'error_type': 'Gasless',
          'error_data': {
            'error_type': 'InsufficientGasFreeBalanceForActivation',
            'error_data': {
              'coin': 'USDT-TRC20',
              'available': '2',
              'required': '8',
              'activation_fee': '1.5',
            },
          },
          'error':
              'GasFree withdrawal failed: '
              'InsufficientGasFreeBalanceForActivation',
          'error_path': 'eth_withdraw.withdraw',
          'error_trace': 'eth_withdraw:348',
        });
        expect(error.toJson(), isNot(contains('gasfree_address')));
      },
    );

    test('parses task-status details after KDF JSON-stringifies the error', () {
      final wire = {
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': jsonEncode(
            _nestedGaslessError(type: GaslessWithdrawErrorType.pendingTransfer),
          ),
        },
      };

      final response = request.parseResponse(jsonEncode(wire));

      expect(response.status, 'Error');
      expect(
        response.details,
        isA<GaslessWithdrawException>().having(
          (error) => error.type,
          'type',
          GaslessWithdrawErrorType.pendingTransfer,
        ),
      );
    });

    test('exposes a registry-parsed task error as typed details', () {
      final wire = {
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': jsonEncode({
            'error': 'Invalid GasFree fee options',
            'error_type': 'InvalidFee',
            'error_data': {
              'reason': 'deadline_seconds must be greater than zero',
              'details': null,
            },
          }),
        },
      };

      final response = request.parseResponse(jsonEncode(wire));

      expect(response.status, 'Error');
      expect(
        response.details,
        isA<WithdrawErrorInvalidFeeException>().having(
          (error) => error.reason,
          'reason',
          'deadline_seconds must be greater than zero',
        ),
      );
    });

    test('preserves a plain-string task error without inferring a type', () {
      final wire = {
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': 'Provider returned an undocumented failure',
        },
      };

      final response = request.parseResponse(jsonEncode(wire));

      expect(response.status, 'Error');
      expect(response.details, 'Provider returned an undocumented failure');
    });

    test('rejects the removed flat compatibility shape', () {
      expect(
        GaslessWithdrawException.tryParse({
          'error': 'GasFree withdrawal failed',
          'error_type': 'PendingTransfer',
          'error_data': null,
        }),
        isNull,
      );
    });

    for (final entry in <String, Map<String, dynamic>>{
      'result.details': {
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': _nestedGaslessError(
            type: GaslessWithdrawErrorType.pendingTransfer,
          ),
        },
      },
      'message': {
        'mmrpc': '2.0',
        'message': _nestedGaslessError(
          type: GaslessWithdrawErrorType.pendingTransfer,
        ),
      },
    }.entries) {
      test('rejects undocumented ${entry.key} withdraw error wrapper', () {
        expect(request.parseCustomErrorResponse(entry.value), isNull);
      });
    }

    test('rejects a direct withdraw error with only message metadata', () {
      final directMessageOnly =
          _nestedGaslessError(type: GaslessWithdrawErrorType.pendingTransfer)
            ..remove('error')
            ..['message'] = 'Undocumented GasFree withdrawal error';

      expect(request.parseCustomErrorResponse(directMessageOnly), isNull);
    });

    test('does not claim standard withdrawal errors', () {
      expect(
        request.parseCustomErrorResponse({
          'error': 'Coin is not active',
          'error_type': 'CoinIsNotActivated',
          'error_data': {'coin': 'USDT-TRC20'},
        }),
        isNull,
      );
    });

    test(
      'does not invent a lifecycle state from an unknown provider string',
      () {
        expect(
          GaslessWithdrawException.tryParse({
            'error': 'upstream returned an unexpected text failure',
            'error_type': 'Gasless',
            'error_data': {
              'error_type': 'UnknownProviderState',
              'error_data': null,
            },
          }),
          isNull,
        );
      },
    );
  });
}
