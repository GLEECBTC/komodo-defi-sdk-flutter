import 'dart:convert';

const String _defaultIndent = '  ';
const int _defaultMaxLineLength = 80;

/// Formats JSON using the same whitespace conventions as the IDE formatter:
/// two-space indentation with short primitive arrays kept on one line.
String formatJsonForIde(
  Object? json, {
  String indent = _defaultIndent,
  int maxLineLength = _defaultMaxLineLength,
}) {
  final formatter = _IdeJsonFormatter(
    indent: indent,
    maxLineLength: maxLineLength,
  );
  final buffer = StringBuffer();

  formatter.writeValue(buffer, json, depth: 0, currentLinePrefixLength: 0);
  buffer.writeln();

  return buffer.toString();
}

final class _IdeJsonFormatter {
  const _IdeJsonFormatter({required this.indent, required this.maxLineLength});

  final String indent;
  final int maxLineLength;

  void writeValue(
    StringBuffer buffer,
    Object? value, {
    required int depth,
    required int currentLinePrefixLength,
  }) {
    final inlineValue = _tryInlineValue(
      value,
      currentLinePrefixLength: currentLinePrefixLength,
    );

    if (inlineValue != null) {
      buffer.write(inlineValue);
      return;
    }

    if (value is Map<Object?, Object?>) {
      _writeObject(buffer, value, depth: depth);
      return;
    }

    if (value is List<Object?>) {
      _writeList(buffer, value, depth: depth);
      return;
    }

    buffer.write(jsonEncode(value));
  }

  String? _tryInlineValue(
    Object? value, {
    required int currentLinePrefixLength,
  }) {
    if (value is Map<Object?, Object?>) {
      return value.isEmpty ? '{}' : null;
    }

    if (value is! List<Object?>) {
      return jsonEncode(value);
    }

    if (value.isEmpty) {
      return '[]';
    }

    final encodedItems = <String>[];
    for (final item in value) {
      if (item is Map<Object?, Object?> || item is List<Object?>) {
        return null;
      }

      encodedItems.add(jsonEncode(item));
    }

    final inlineValue = '[${encodedItems.join(', ')}]';
    if (currentLinePrefixLength + inlineValue.length > maxLineLength) {
      return null;
    }

    return inlineValue;
  }

  void _writeObject(
    StringBuffer buffer,
    Map<Object?, Object?> value, {
    required int depth,
  }) {
    if (value.isEmpty) {
      buffer.write('{}');
      return;
    }

    buffer.writeln('{');
    final entries = value.entries.toList(growable: false);

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(
          key,
          'key',
          'JSON object keys must be strings',
        );
      }

      final entryIndent = _indentFor(depth + 1);
      final encodedKey = jsonEncode(key);

      buffer
        ..write(entryIndent)
        ..write(encodedKey)
        ..write(': ');

      writeValue(
        buffer,
        entry.value,
        depth: depth + 1,
        currentLinePrefixLength: entryIndent.length + encodedKey.length + 2,
      );

      if (i < entries.length - 1) {
        buffer.write(',');
      }
      buffer.writeln();
    }

    buffer
      ..write(_indentFor(depth))
      ..write('}');
  }

  void _writeList(
    StringBuffer buffer,
    List<Object?> value, {
    required int depth,
  }) {
    if (value.isEmpty) {
      buffer.write('[]');
      return;
    }

    buffer.writeln('[');

    for (var i = 0; i < value.length; i++) {
      final itemIndent = _indentFor(depth + 1);
      buffer.write(itemIndent);
      writeValue(
        buffer,
        value[i],
        depth: depth + 1,
        currentLinePrefixLength: itemIndent.length,
      );

      if (i < value.length - 1) {
        buffer.write(',');
      }
      buffer.writeln();
    }

    buffer
      ..write(_indentFor(depth))
      ..write(']');
  }

  String _indentFor(int depth) => List.filled(depth, indent).join();
}
