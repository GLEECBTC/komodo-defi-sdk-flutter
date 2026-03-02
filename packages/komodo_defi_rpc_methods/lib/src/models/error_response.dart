import 'package:komodo_defi_rpc_methods/src/models/models.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Error response class
class GeneralErrorResponse extends BaseResponse implements Exception {
  GeneralErrorResponse({
    required super.mmrpc,
    required this.error,
    required this.errorPath,
    required this.errorTrace,
    required this.errorType,
    required this.errorData,
    required this.object,
  });

  @override
  factory GeneralErrorResponse.parse(Map<String, dynamic> json) {
    final error =
        json.valueOrNull<JsonMap>('result', 'details') ??
        json.valueOrNull<JsonMap>('message');
    return GeneralErrorResponse(
      mmrpc: json.valueOrNull<String>('mmrpc') ?? '',
      error:
          error?.valueOrNull<String>('message') ??
          error?.valueOrNull<String>('error'),
      errorPath: error?.valueOrNull<String>('error_path'),
      errorTrace: error?.valueOrNull<String>('error_trace'),
      errorType: error?.valueOrNull<String>('error_type'),
      errorData: error?.valueOrNull<dynamic>('error_data'),
      object: json,
    );
  }

  final String? error;
  final String? errorPath;
  final String? errorTrace;
  final String? errorType;
  final JsonMap? object;
  final dynamic errorData;

  static bool isErrorResponse(Map<String, dynamic> json) {
    final isError =
        json.hasNestedKey('result', 'details', 'error') ||
        json.hasNestedKey('error') ||
        json.valueOrNull<String>('result', 'status') == 'Error' ||
        json.valueOrNull<int>('code') == -1;

    return isError;
  }

  /// Attempts to convert this error response to a typed [MmRpcException].
  ///
  /// Returns `null` if the error type is not recognized or if this error
  /// response does not contain sufficient type information.
  ///
  /// Example:
  /// ```dart
  /// final typedException = errorResponse.toTypedException();
  /// if (typedException != null) {
  ///   // Handle specific exception type
  ///   switch (typedException) {
  ///     case AccountRpcErrorNameTooLongException():
  ///       print('Name too long!');
  ///     // ... other cases
  ///   }
  /// }
  /// ```
  MmRpcException? toTypedException() {
    // Build a JSON map suitable for KdfErrorRegistry parsing
    final errorJson = <String, dynamic>{
      'error_type': errorType,
      'error_data': errorData,
      'error': error,
      'error_path': errorPath,
      'error_trace': errorTrace,
    };
    return KdfErrorRegistry.tryParse(errorJson);
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'mmrpc': mmrpc,
      'error': error,
      'error_path': errorPath,
      'error_type': errorType,
      'error_data': errorData,
      'error_trace': errorTrace,
      'object': object,
    };
  }

  @override
  String toString() {
    return 'GeneralErrorResponse: ${toJson().toJsonString()}';
  }
}
