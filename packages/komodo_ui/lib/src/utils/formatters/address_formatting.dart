import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Returns a truncated address suitable for display.
String formatCompactAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}...'
      '${address.substring(address.length - 6)}';
}

/// Returns a shorter truncated address for compact controls.
String formatShortAddress(String address) {
  if (address.length <= 8) return address;
  return '${address.substring(0, 4)}...'
      '${address.substring(address.length - 4)}';
}

/// Returns the full address grouped in chunks of 4 characters.
String formatGroupedAddress(String address) {
  final chunks = <String>[];
  for (var i = 0; i < address.length; i += 4) {
    final end = i + 4;
    chunks.add(
      end > address.length ? address.substring(i) : address.substring(i, end),
    );
  }
  return chunks.join(' ');
}

/// Extension methods for formatting PubkeyInfo addresses
extension PubkeyInfoFormatting on PubkeyInfo {
  /// Returns a truncated version of the address suitable for display
  /// Shows the first 6 and last 6 characters with ... in between
  String get formatted => formatCompactAddress(address);

  /// Returns a short version of the address suitable for very compact displays
  /// Shows just the first 4 and last 4 characters
  String get formattedShort => formatShortAddress(address);

  /// Returns the full address with proper spacing for monospace fonts
  /// Groups the address in chunks of 4 characters for better readability
  String get formattedFull => formatGroupedAddress(address);
}
