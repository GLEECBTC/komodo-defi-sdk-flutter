import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

void main() {
  group('Gasless account-status provenance', () {
    final baseResult = <String, dynamic>{
      'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      'on_chain_balance': '7',
      'availability': 'provider_unreachable',
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
            ..remove('availability'),
        }),
        throwsArgumentError,
      );
    });

    test('marks boolean availability as compatibility-only', () {
      final explicit = GaslessAccountStatusResponse.parse({
        'mmrpc': '2.0',
        'result': baseResult,
      });
      final legacy = GaslessAccountStatusResponse.parse({
        'mmrpc': '2.0',
        'result': {...baseResult, 'provider_available': false}
          ..remove('availability'),
      });

      expect(explicit.hasExplicitAvailability, isTrue);
      expect(legacy.hasExplicitAvailability, isFalse);
      expect(
        legacy.availability,
        GaslessAccountAvailability.providerUnreachable,
      );
      expect(legacy.toJson()['result'], isNot(contains('availability')));
    });

    test('preserves pure legacy reason parsing', () {
      final legacy = GaslessAccountStatusResponse.parse({
        'mmrpc': '2.0',
        'result': {
          ...baseResult,
          'provider_available': false,
          'reason_code': 'token_unsupported',
        }..remove('availability'),
      });

      expect(legacy.hasExplicitAvailability, isFalse);
      expect(legacy.availability, GaslessAccountAvailability.tokenUnsupported);
      expect(legacy.reasonCode, 'token_unsupported');
    });

    for (final legacyValue in <Object?>[true, false, null]) {
      test('rejects mixed availability fields ($legacyValue)', () {
        expect(
          () => GaslessAccountStatusResponse.parse({
            'mmrpc': '2.0',
            'result': {...baseResult, 'provider_available': legacyValue},
          }),
          throwsFormatException,
        );
      });
    }

    for (final legacyReason in <Object?>[
      'provider_temporarily_unavailable',
      null,
    ]) {
      test('rejects mixed reason fields ($legacyReason)', () {
        expect(
          () => GaslessAccountStatusResponse.parse({
            'mmrpc': '2.0',
            'result': {...baseResult, 'reason_code': legacyReason},
          }),
          throwsFormatException,
        );
      });
    }

    test('rejects unknown availability states', () {
      expect(
        () => GaslessAccountStatusResponse.parse({
          'mmrpc': '2.0',
          'result': {...baseResult, 'availability': 'new_provider_state'},
        }),
        throwsFormatException,
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
