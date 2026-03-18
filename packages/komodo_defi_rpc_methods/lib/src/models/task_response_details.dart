import 'dart:convert';

import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Generic response details wrapper for task status responses
class ResponseDetails<T, E extends Exception, D extends Object> {
  ResponseDetails({required this.data, required this.error, this.description})
    : assert(
        [data, error, description].where((e) => e != null).length == 1,
        'Of the three fields, exactly one must be non-null',
      );

  final T? data;
  final E? error;

  // Usually only non-null for in-progress tasks
  /// Additional status information for in-progress tasks
  final D? description;

  void get throwIfError {
    if (error != null) {
      throw error!;
    }
  }

  T? get dataOrNull => data;

  Map<String, dynamic> toJson() {
    return {
      if (data != null) 'data': jsonEncode(data),
      if (error != null) 'error': error.toString(),
      if (description != null)
        'description': description is String
            ? description
            : jsonEncode(description),
    };
  }
}

/// Parses task error details into a typed [Exception].
Exception parseTaskErrorDetails(dynamic detailsJson) {
  if (detailsJson is Map) {
    try {
      final detailsMap = convertToJsonMap(detailsJson);
      final typedError = KdfErrorRegistry.tryParse(detailsMap);
      if (typedError != null) {
        return typedError;
      }
      return GeneralErrorResponse.parse(detailsMap);
    } catch (_) {
      // Fall back to string-based exception extraction below.
    }
  }

  final message = detailsJson?.toString().trim();
  if (message == null || message.isEmpty) {
    return Exception('Unknown error');
  }
  return Exception(message);
}

/// Extracts a human-readable message from [Exception].
String? exceptionMessage(Exception? error) {
  if (error == null) {
    return null;
  }

  if (error is MmRpcException) {
    return error.displayMessage;
  }

  if (error is GeneralErrorResponse) {
    return error.error;
  }

  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return null;
  }
  const exceptionPrefix = 'Exception: ';
  if (raw.startsWith(exceptionPrefix)) {
    final message = raw.substring(exceptionPrefix.length).trim();
    return message.isEmpty ? null : message;
  }
  return raw;
}
