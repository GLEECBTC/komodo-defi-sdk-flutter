import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('BaseRequest response parsing', () {
    test('ApiClient.post delegates custom errors to the request parser', () {
      const client = _ApiClientStub({
        'mmrpc': '2.0',
        'error': {'reason': 'request-specific'},
      });

      expect(
        () => client.post(_CustomErrorRequest()),
        throwsA(isA<_RequestSpecificException>()),
      );
    });

    test('opted-in task status parses Error as a response variant', () async {
      const client = _ApiClientStub({
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': {
            'error_type': 'UnknownFutureTaskError',
            'error_data': {'safe': true},
          },
        },
      });

      final response = await client.post(_TaskStatusRequest());

      expect(response.status, 'Error');
      expect(response.details['error_type'], 'UnknownFutureTaskError');
    });

    test('task status opt-in does not hide top-level RPC errors', () {
      const client = _ApiClientStub({
        'mmrpc': '2.0',
        'code': -1,
        'error': {'message': 'transport-level failure'},
        'result': {'status': 'Error'},
      });

      expect(
        () => client.post(_TaskStatusRequest()),
        throwsA(isA<GeneralErrorResponse>()),
      );
    });
  });
}

class _ApiClientStub implements ApiClient {
  const _ApiClientStub(this.response);

  final JsonMap response;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async => response;
}

class _CustomErrorRequest
    extends BaseRequest<_TestResponse, _RequestSpecificException> {
  _CustomErrorRequest()
    : super(method: 'test::custom_error', mmrpc: RpcVersion.v2_0);

  @override
  _TestResponse parse(JsonMap json) => _TestResponse.parse(json);

  @override
  _RequestSpecificException? parseCustomErrorResponse(JsonMap json) =>
      const _RequestSpecificException();
}

class _TaskStatusRequest
    extends BaseRequest<_TestResponse, GeneralErrorResponse> {
  _TaskStatusRequest()
    : super(method: 'task::test::status', mmrpc: RpcVersion.v2_0);

  @override
  bool get parseTaskErrorStatusAsResponse => true;

  @override
  _TestResponse parse(JsonMap json) => _TestResponse.parse(json);
}

class _TestResponse extends BaseResponse {
  _TestResponse({
    required super.mmrpc,
    required this.status,
    required this.details,
  });

  factory _TestResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    return _TestResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      status: result.value<String>('status'),
      details: result.value<JsonMap>('details'),
    );
  }

  final String status;
  final JsonMap details;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {'status': status, 'details': details},
  };
}

class _RequestSpecificException implements Exception {
  const _RequestSpecificException();
}
