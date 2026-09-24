import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

/// Custom JSON converter for [Decimal] type with null-safe handling.
///
/// This converter handles various input formats including strings, numbers,
/// integers, and doubles, converting them to [Decimal] for high-precision
/// arithmetic operations. Returns null for invalid or null inputs.
class DecimalConverter implements JsonConverter<Decimal?, dynamic> {
  const DecimalConverter();

  /// Converts JSON value to [Decimal].
  ///
  /// Supports conversion from:
  /// - String: parsed directly as [Decimal]
  /// - num, int, double: converted to string then parsed as [Decimal]
  /// - Other types: converted to string then parsed
  ///
  /// Returns null for null inputs, empty strings, or parsing failures.
  @override
  Decimal? fromJson(dynamic json) {
    if (json == null) return null;

    try {
      // Handle different input types
      if (json is String) {
        if (json.isEmpty) return null;
        return Decimal.parse(json);
      } else if (json is num) {
        return Decimal.parse(json.toString());
      } else if (json is int) {
        return Decimal.parse(json.toString());
      } else if (json is double) {
        return Decimal.parse(json.toString());
      }

      // Try to convert any other type to string first
      final stringValue = json.toString();
      if (stringValue.isEmpty || stringValue == 'null') return null;
      return Decimal.parse(stringValue);
    } catch (e) {
      return null;
    }
  }

  /// Converts [Decimal] to JSON string representation.
  ///
  /// Returns null if the input [decimal] is null.
  @override
  String? toJson(Decimal? decimal) {
    return decimal?.toString();
  }
}

/// [DecimalConverter] for non-nullable [Decimal] fields.
///
/// json_serializable does not apply a nullable converter to a non-nullable
/// field: `@DecimalConverter()` on a `Decimal` field is silently ignored, and
/// the generated code calls `Decimal.fromJson(json as String)`, which throws on
/// a JSON number.
class NonNullableDecimalConverter implements JsonConverter<Decimal, dynamic> {
  const NonNullableDecimalConverter();

  /// Converts a JSON string or number to [Decimal].
  ///
  /// Throws a [FormatException] if [json] is null or cannot be parsed.
  @override
  Decimal fromJson(dynamic json) {
    final decimal = const DecimalConverter().fromJson(json);
    if (decimal == null) {
      throw FormatException('Cannot convert "$json" to Decimal');
    }
    return decimal;
  }

  /// Converts [Decimal] to its JSON string representation.
  @override
  String toJson(Decimal decimal) => decimal.toString();
}

/// Custom JSON converter for Unix timestamps in seconds to UTC [DateTime].
///
/// This converter handles Unix epoch timestamps (seconds since 1970-01-01 UTC)
/// and converts them to UTC [DateTime] objects. All converted dates are
/// explicitly set to UTC timezone to ensure consistency across different
/// system timezones.
class TimestampConverter implements JsonConverter<DateTime?, int?> {
  const TimestampConverter();

  /// Converts Unix timestamp in seconds to UTC [DateTime].
  ///
  /// Takes a Unix epoch timestamp (seconds since 1970-01-01 UTC) and
  /// returns a [DateTime] object explicitly set to UTC timezone.
  ///
  /// Returns null if the input timestamp is null.
  @override
  DateTime? fromJson(int? json) {
    if (json == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(json * 1000, isUtc: true);
  }

  /// Converts [DateTime] to Unix timestamp in seconds.
  ///
  /// Takes a [DateTime] object and returns the Unix epoch timestamp
  /// in seconds since 1970-01-01 UTC. The input [DateTime] timezone
  /// is automatically handled by the conversion.
  ///
  /// Returns null if the input [dateTime] is null.
  @override
  int? toJson(DateTime? dateTime) {
    if (dateTime == null) return null;
    return dateTime.millisecondsSinceEpoch ~/ 1000;
  }
}
