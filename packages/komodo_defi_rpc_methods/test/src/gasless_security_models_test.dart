import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

void main() {
  group('Gasless account-status provenance', () {
    final baseResult = <String, dynamic>{
      'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      'on_chain_balance': '7',
      'provider_available': false,
    };

    test('requires the on-chain custody balance', () {
      expect(
        () => GaslessAccountStatusResponse.parse({
          'mmrpc': '2.0',
          'result': Map<String, dynamic>.from(baseResult)
            ..remove('on_chain_balance'),
        }),
        throwsArgumentError,
      );
    });

    test('requires provider availability provenance', () {
      expect(
        () => GaslessAccountStatusResponse.parse({
          'mmrpc': '2.0',
          'result': Map<String, dynamic>.from(baseResult)
            ..remove('provider_available'),
        }),
        throwsArgumentError,
      );
    });
  });

  test('GeneralErrorResponse stringification is redacted', () {
    final error = GeneralErrorResponse.parse({
      'error': 'GasFree relay submission failed',
      'error_type': 'GaslessRelaySubmission',
      'error_data': {
        'code': 'authorization_expired',
        'api_secret': 'provider-secret',
      },
    });

    expect(
      error.toString(),
      'GeneralErrorResponse(errorType: GaslessRelaySubmission)',
    );
    expect(error.toString(), isNot(contains('authorization_expired')));
    expect(error.toString(), isNot(contains('provider-secret')));
  });
}
