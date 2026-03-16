// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';
import 'dart:js_interop' as js_interop;

import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:logging/logging.dart';

final Logger _jsInteropLogger = Logger('JsInteropUtils');

@js_interop.JS('Promise.resolve')
external js_interop.JSPromise<js_interop.JSAny?> _resolveJsPromise(
  js_interop.JSAny? value,
);

/// Parses a JS interop response into a JsonMap.
///
/// Accepts:
/// - JSAny/JSObject (will be dartified)
/// - Map (with non-string keys will be normalized)
/// - String (JSON encoded)
///
/// Throws a [FormatException] if the response cannot be parsed into a JSON map.
JsonMap parseJsInteropJson(js_interop.JSAny? jsResponse) {
  try {
    final dynamic value = jsResponse?.dartify();

    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return _deepConvertMap(decoded);
      }
      throw const FormatException('Expected JSON object string');
    }

    if (value is Map) {
      return _deepConvertMap(value);
    }

    throw FormatException('Unexpected JS response type: ${value.runtimeType}');
  } catch (e, s) {
    _jsInteropLogger.severe('Error parsing JS interop response', e, s);
    rethrow;
  }
}

/// Generic helper that parses a JS response and maps it to a Dart model.
T parseJsInteropCall<T>(
  js_interop.JSAny? jsResponse,
  T Function(JsonMap) fromJson,
) {
  final map = parseJsInteropJson(jsResponse);
  return fromJson(map);
}

// Recursively converts the provided map to JsonMap by stringifying keys and
// converting nested maps/lists to JSON-friendly structures.
JsonMap _deepConvertMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) {
    if (value is Map) return MapEntry(key.toString(), _deepConvertMap(value));
    if (value is List) {
      return MapEntry(key.toString(), _deepConvertList(value));
    }
    return MapEntry(key.toString(), value);
  });
}

List<dynamic> _deepConvertList(List<dynamic> list) {
  return list.map((value) {
    if (value is Map) return _deepConvertMap(value);
    if (value is List) return _deepConvertList(value);
    return value;
  }).toList();
}

/// Resolves a JS interop value that might be a Promise into a Dart value.
///
/// - If [jsValue] is a JSPromise, it awaits the promise, then dartifies it
/// - If [jsValue] is not a JSPromise, it is dartified directly
/// - Returns the dartified dynamic value
Future<dynamic> resolveJsAnyMaybePromise(js_interop.JSAny? jsValue) async {
  if (jsValue == null || jsValue.isUndefinedOrNull) {
    return null;
  }

  final resolved = await _resolveJsPromise(jsValue).toDart;
  return resolved?.dartify();
}

/// Generic helper to resolve a JS interop value (maybe a Promise) and map it.
///
/// After resolution and dartification, the provided [mapper] is used to convert
/// the dynamic result into type [T].
Future<T> parseJsInteropMaybePromise<T>(
  js_interop.JSAny? jsValue, [
  T Function(dynamic dartValue)? mapper,
]) async {
  final dartValue = await resolveJsAnyMaybePromise(jsValue);

  // If a mapper was provided, use it
  if (mapper != null) {
    return mapper(dartValue);
  }

  // Allow common primitive/collection types without a mapper
  if (T == dynamic || T == Object) {
    return dartValue as T;
  }
  if (T == int) {
    if (dartValue is int) return dartValue as T;
    if (dartValue is num) return dartValue.toInt() as T;
    if (dartValue is String) {
      final parsed = int.tryParse(dartValue);
      if (parsed != null) return parsed as T;
    }
  }
  if (T == double || T == num) {
    if (dartValue is num) {
      if (T == double) return dartValue.toDouble() as T;
      return dartValue as T; // T == num
    }
    if (dartValue is String) {
      final parsed = double.tryParse(dartValue);
      if (parsed != null) {
        if (T == num) {
          final num n = parsed;
          return n as T;
        } else {
          final double d = parsed;
          return d as T;
        }
      }
    }
  }
  if (T == String) {
    if (dartValue is String) return dartValue as T;
  }
  if (T == bool) {
    if (dartValue is bool) return dartValue as T;
  }
  if (T == Map || T == Map<String, dynamic>) {
    if (dartValue is Map) return dartValue as T;
  }
  if (T == List || T == List<dynamic>) {
    if (dartValue is List) return dartValue as T;
  }

  // Fallback: attempt a direct cast; this will surface a clear type error
  return dartValue as T;
}
