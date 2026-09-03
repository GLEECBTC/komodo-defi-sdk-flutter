import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

GaslessAccountStatusResponse _status(Map<String, dynamic> result) =>
    GaslessAccountStatusResponse.parse({'mmrpc': '2.0', 'result': result});

Map<String, dynamic> _providerStatus({
  required String availability,
  Object? maxWithdrawable = '9.5',
}) => {
  'gasfree_address': 'TCustody',
  'service_provider': 'TProvider',
  'availability': availability,
  'active': false,
  'on_chain_balance': '12.5',
  'frozen_balance': '1',
  'spendable_balance': '11.5',
  'transfer_fee': '2',
  'activation_fee': '1',
  'max_withdrawable': maxWithdrawable,
};

Map<String, dynamic> _directError(String type, [Object? data = 'USDT']) => {
  'mmrpc': '2.0',
  'error': 'GasFree endpoint error',
  'error_type': type,
  'error_data': data,
};

void main() {
  group('GasFree account status contract', () {
    test('parses available with authoritative provider and fee data', () {
      final status = _status(_providerStatus(availability: 'available'));

      expect(status.availability, GaslessAccountAvailability.available);
      expect(status.serviceProvider, 'TProvider');
      expect(status.active, isFalse);
      expect(status.onChainBalance, Decimal.parse('12.5'));
      expect(status.frozenBalance, Decimal.one);
      expect(status.spendableBalance, Decimal.parse('11.5'));
      expect(status.transferFee, Decimal.parse('2'));
      expect(status.activationFee, Decimal.one);
      expect(status.maxWithdrawable, Decimal.parse('9.5'));
    });

    test('parses pending_transfer while retaining provider and fee data', () {
      final status = _status(
        _providerStatus(
          availability: 'pending_transfer',
          maxWithdrawable: null,
        ),
      );

      expect(status.availability, GaslessAccountAvailability.pendingTransfer);
      expect(status.serviceProvider, 'TProvider');
      expect(status.onChainBalance, Decimal.parse('12.5'));
      expect(status.frozenBalance, Decimal.one);
      expect(status.spendableBalance, Decimal.parse('11.5'));
      expect(status.transferFee, Decimal.parse('2'));
      expect(status.activationFee, Decimal.one);
      expect(status.maxWithdrawable, isNull);
    });

    test('parses token_unsupported with provider identity only', () {
      final status = _status({
        'gasfree_address': 'TCustody',
        'service_provider': 'TProvider',
        'availability': 'token_unsupported',
        'active': null,
        'on_chain_balance': '7',
        'frozen_balance': null,
        'spendable_balance': null,
        'transfer_fee': null,
        'activation_fee': null,
        'max_withdrawable': null,
      });

      expect(status.availability, GaslessAccountAvailability.tokenUnsupported);
      expect(status.serviceProvider, 'TProvider');
      expect(status.onChainBalance, Decimal.parse('7'));
      expect(status.active, isNull);
      expect(status.transferFee, isNull);
      expect(status.spendableBalance, isNull);
      expect(status.frozenBalance, isNull);
    });

    test('parses provider_unreachable with a fresh custody total only', () {
      final status = _status({
        'gasfree_address': 'TCustody',
        'service_provider': null,
        'availability': 'provider_unreachable',
        'active': null,
        'on_chain_balance': '7',
        'frozen_balance': null,
        'spendable_balance': null,
        'transfer_fee': null,
        'activation_fee': null,
        'max_withdrawable': null,
      });

      expect(
        status.availability,
        GaslessAccountAvailability.providerUnreachable,
      );
      expect(status.serviceProvider, isNull);
      expect(status.onChainBalance, Decimal.parse('7'));
      expect(status.spendableBalance, isNull);
      expect(status.frozenBalance, isNull);
    });

    for (final invalid in <Map<String, dynamic>>[
      _providerStatus(availability: 'available', maxWithdrawable: null),
      _providerStatus(availability: 'pending_transfer'),
      {
        'gasfree_address': 'TCustody',
        'service_provider': 'TProvider',
        'availability': 'token_unsupported',
        'active': false,
        'on_chain_balance': '7',
        'frozen_balance': null,
        'spendable_balance': null,
        'transfer_fee': null,
        'activation_fee': null,
        'max_withdrawable': null,
      },
      {
        'gasfree_address': 'TCustody',
        'service_provider': 'TProvider',
        'availability': 'provider_unreachable',
        'active': null,
        'on_chain_balance': '7',
        'frozen_balance': null,
        'spendable_balance': null,
        'transfer_fee': null,
        'activation_fee': null,
        'max_withdrawable': null,
      },
    ]) {
      test('rejects invalid mixed shape ${invalid['availability']}', () {
        expect(() => _status(invalid), throwsFormatException);
      });
    }

    test('rejects an activation fee for an already active account', () {
      expect(
        () => _status({
          ..._providerStatus(availability: 'available'),
          'active': true,
        }),
        throwsFormatException,
      );
    });

    test('requires the documented availability enum', () {
      final missing = _providerStatus(availability: 'available')
        ..remove('availability');

      expect(() => _status(missing), throwsFormatException);
      expect(
        () => _status({
          ..._providerStatus(availability: 'available'),
          'availability': 'new_provider_state',
        }),
        throwsFormatException,
      );
    });

    test('rejects removed compatibility fields', () {
      expect(
        () => _status({
          ..._providerStatus(availability: 'available'),
          'provider_available': true,
        }),
        throwsFormatException,
      );
      expect(
        () => _status({
          ..._providerStatus(availability: 'available'),
          'reason_code': 'available',
        }),
        throwsFormatException,
      );
    });
  });

  group('endpoint-scoped GasFree errors', () {
    final accountRequest = GaslessAccountStatusRequest(
      rpcPass: 'rpc-pass',
      coin: 'USDT-TRC20',
    );
    final traceRequest = GaslessTraceStatusRequest(
      rpcPass: 'rpc-pass',
      coin: 'USDT-TRC20',
      traceId: 'trace-1',
    );
    final streamRequest = StreamGaslessTraceEnableRequest(
      rpcPass: 'rpc-pass',
      coin: 'USDT-TRC20',
    );

    for (final type in GaslessAccountStatusErrorType.values) {
      test('maps account-status ${type.wireValue}', () {
        final data = switch (type) {
          GaslessAccountStatusErrorType.providerIdentityMismatch => {
            'configured': 'TConfigured',
            'offered': ['TProvider'],
          },
          GaslessAccountStatusErrorType.gasfreeAddressMismatch => {
            'expected': 'TExpected',
            'provider_reported': 'TActual',
          },
          GaslessAccountStatusErrorType.tokenDecimalMismatch => {
            'token_address': 'TToken',
            'expected': 6,
            'provider_reported': 18,
          },
          _ => 'USDT-TRC20',
        };

        expect(
          () => accountRequest.parseResponse(
            jsonEncode(_directError(type.wireValue, data)),
          ),
          throwsA(
            isA<GaslessAccountStatusException>().having(
              (error) => error.type,
              'type',
              type,
            ),
          ),
        );
      });
    }

    for (final type in GaslessTraceStatusErrorType.values) {
      test('maps trace-status ${type.wireValue}', () {
        expect(
          () => traceRequest.parseResponse(
            jsonEncode(_directError(type.wireValue)),
          ),
          throwsA(
            isA<GaslessTraceStatusException>().having(
              (error) => error.type,
              'type',
              type,
            ),
          ),
        );
      });
    }

    for (final type in GaslessTraceStreamingRequestErrorType.values) {
      test('maps trace-stream ${type.wireValue}', () {
        expect(
          () => streamRequest.parseResponse(
            jsonEncode(_directError(type.wireValue)),
          ),
          throwsA(
            isA<GaslessTraceStreamingRequestException>().having(
              (error) => error.type,
              'type',
              type,
            ),
          ),
        );
      });
    }

    for (final entry in <String, Map<String, dynamic>>{
      'result.details': {
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': _directError('GaslessNotConfigured'),
        },
      },
      'message': {
        'mmrpc': '2.0',
        'message': _directError('GaslessNotConfigured'),
      },
    }.entries) {
      test('rejects undocumented ${entry.key} endpoint error wrappers', () {
        expect(accountRequest.parseCustomErrorResponse(entry.value), isNull);
        expect(traceRequest.parseCustomErrorResponse(entry.value), isNull);
        expect(streamRequest.parseCustomErrorResponse(entry.value), isNull);
      });
    }

    test('rejects direct endpoint errors with only message metadata', () {
      final messageOnly = {
        'mmrpc': '2.0',
        'message': 'Undocumented GasFree endpoint error',
        'error_type': 'GaslessNotConfigured',
        'error_data': 'USDT-TRC20',
      };

      expect(accountRequest.parseCustomErrorResponse(messageOnly), isNull);
      expect(traceRequest.parseCustomErrorResponse(messageOnly), isNull);
      expect(streamRequest.parseCustomErrorResponse(messageOnly), isNull);
    });
  });

  test('GeneralErrorResponse stringification does not expose error data', () {
    final error = GeneralErrorResponse.parse({
      'error': 'GasFree relay submission failed',
      'error_type': 'UnknownSubmissionError',
      'error_data': {'api_secret': 'provider-secret'},
    });

    expect(
      error.toString(),
      'GeneralErrorResponse(errorType: UnknownSubmissionError)',
    );
    expect(error.toString(), isNot(contains('provider-secret')));
  });
}
