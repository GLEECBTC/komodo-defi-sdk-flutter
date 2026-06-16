import 'dart:io';

/// Reads the contents of a coins / coins-config file from a filesystem [path].
///
/// Native (dart:io) implementation. See `custom_coins_file_reader.dart` for the
/// platform-conditional entry point.
Future<String> readCustomCoinsFileFromPath(String path) {
  return File(path).readAsString();
}
