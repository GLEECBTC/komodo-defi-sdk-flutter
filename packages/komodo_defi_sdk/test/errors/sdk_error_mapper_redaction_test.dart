import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:test/test.dart';

void main() {
  test('generic SDK errors do not expose raw provider bodies', () {
    final error = GeneralErrorResponse.parse({
      'mmrpc': '2.0',
      'error_type': 'UnknownProviderFailure',
      'error_data': {
        'api_secret': 'provider-secret',
        'signed_authorization': 'signed-payload',
      },
      'object': {'upstream_body': 'private-provider-body'},
    });

    final sdkError = const SdkErrorMapper().map(error);

    expect(sdkError.fallbackMessage, 'Something went wrong. Please try again.');
    expect(sdkError.toString(), isNot(contains('provider-secret')));
    expect(sdkError.toString(), isNot(contains('signed-payload')));
    expect(sdkError.toString(), isNot(contains('private-provider-body')));
  });
}
