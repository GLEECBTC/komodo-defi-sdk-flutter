import 'dart:convert';

import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:meta/meta.dart';

extension BaseRequestApiClientExtension on ApiClient {
  Future<T> post<T extends BaseResponse, E extends Exception>(
    BaseRequest<T, E> request,
  ) async {
    final response = await executeRpc(request.toJson());

    if (GeneralErrorResponse.isErrorResponse(response) &&
        !request.shouldParseErrorAsResponse(response)) {
      // Endpoint-scoped errors are more precise than the global registry,
      // where common wire names such as CoinNotFound are intentionally
      // ambiguous.
      final customError = request.parseCustomErrorResponse(response);
      if (customError != null) {
        throw customError;
      }

      final typedException = _tryParseTypedException(
        response,
        rpcMethodHint: request.method,
      );
      if (typedException != null) {
        throw typedException;
      }

      throw GeneralErrorResponse.parse(response);
    }

    return request.parseResponse(jsonEncode(response));
  }

  /// Attempts to parse the error response into a typed [MmRpcException].
  MmRpcException? _tryParseTypedException(
    JsonMap response, {
    required String rpcMethodHint,
  }) {
    // Extract error details from the response structure
    final errorDetails =
        response.valueOrNull<JsonMap>('result', 'details') ??
        response.valueOrNull<JsonMap>('message') ??
        response;

    return KdfErrorRegistry.tryParse(
      errorDetails,
      rpcMethodHint: rpcMethodHint,
    );
  }
}

/// Base class for all API requests
///
/// Parameters:
/// - [T] - The response type
/// - [E] - The error response type
abstract class BaseRequest<T extends BaseResponse, E extends Exception> {
  BaseRequest({
    // required this.client,
    required this.method,
    this.rpcPass,
    this.mmrpc = '2.0',
    this.params,
  });

  /// RPC password used to authenticate the client. If null, the client's set
  /// password will be used. This is set using the `setRpcPass` method in the
  /// [ApiClient] class.
  final String? rpcPass;
  final String? mmrpc;
  final String method;
  final RpcRequestParams? params;

  /// Convert request to JSON as per the API specification:
  /// https://komodoplatform.com/en/docs/komodo-defi-framework/api/
  @mustCallSuper
  Map<String, dynamic> toJson() {
    final paramsJson = params?.toRpcParams().ensureJson();
    return {
      'method': method,
      if (mmrpc?.isNotEmpty ?? false) 'mmrpc': mmrpc,
      if (rpcPass?.isNotEmpty ?? false) 'rpc_pass': rpcPass,
    }.deepMerge(
      // When the legacy API is fully deprecated, remove this block. This is
      // to ensure that the request is compatible with both the legacy and
      // new API versions because the new API requires the parameters to be
      // nested under the 'params' key.
      mmrpc == RpcVersion.legacy || mmrpc == null
          ? paramsJson ?? {}
          : {'params': paramsJson},
    );
  }

  Future<T> send(ApiClient client) async {
    final response = await client.executeRpc(toJson());
    return parseResponse(jsonEncode(response));
  }

  /// Parse a response, handling both success and error envelopes.
  /// Subclasses should override [parse] method for success responses instead.
  ///
  /// Error handling order:
  /// 1. Allow subclasses to handle endpoint-specific error types via
  ///    [parseCustomErrorResponse]
  /// 2. Try to parse into a typed [MmRpcException] using [KdfErrorRegistry]
  /// 3. Fall back to [GeneralErrorResponse] via [parseGeneralErrorResponse]
  T parseResponse(String responseBody) {
    final json = jsonFromString(responseBody);

    // First check if this is an error response
    if (GeneralErrorResponse.isErrorResponse(json) &&
        !shouldParseErrorAsResponse(json)) {
      // Endpoint-scoped errors disambiguate common wire names before the
      // global registry gets a chance to parse them.
      final customError = parseCustomErrorResponse(json);
      if (customError != null) {
        throw customError;
      }

      final typedException = _tryParseTypedException(
        json,
        rpcMethodHint: method,
      );
      if (typedException != null) {
        throw typedException;
      }

      // Fall back to general error handling
      final generalError = parseGeneralErrorResponse(json);
      if (generalError != null) {
        throw generalError;
      }
    }

    return parse(json);
  }

  /// Attempts to parse the error response into a typed [MmRpcException].
  MmRpcException? _tryParseTypedException(
    JsonMap json, {
    required String rpcMethodHint,
  }) {
    // Extract error details from the response structure
    final errorDetails =
        json.valueOrNull<JsonMap>('result', 'details') ??
        json.valueOrNull<JsonMap>('message') ??
        json;

    return KdfErrorRegistry.tryParse(
      errorDetails,
      rpcMethodHint: rpcMethodHint,
    );
  }

  /// Override this method to provide custom error handling for specific error
  /// types. Return null when this request does not recognize the error type.
  E? parseCustomErrorResponse(JsonMap json) => null;

  /// Whether an error-shaped envelope is a typed endpoint response.
  ///
  /// Task status methods may return `result.status: "Error"` as their normal
  /// terminal response. Such endpoints can opt into parsing that envelope in
  /// [parse] instead of having the base layer throw it first.
  @protected
  bool shouldParseErrorAsResponse(JsonMap json) => false;

  /// Handles general error responses. This is a fallback for when
  /// [parseCustomErrorResponse] returns null.
  @protected
  Exception? parseGeneralErrorResponse(JsonMap json) {
    if (GeneralErrorResponse.isErrorResponse(json)) {
      return GeneralErrorResponse.parse(json);
    }
    return null;
  }

  /// Parse successful response from JSON. Override this method in subclasses
  /// to handle success responses.
  T parse(Map<String, dynamic> json);
}
