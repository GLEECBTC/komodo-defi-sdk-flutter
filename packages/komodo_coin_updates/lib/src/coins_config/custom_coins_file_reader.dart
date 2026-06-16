import 'package:komodo_coin_updates/src/coins_config/custom_coins_file_source.dart';
// Platform-conditional file reader. The default (non-web) implementation uses
// dart:io; the web implementation throws because there is no filesystem path.
import 'package:komodo_coin_updates/src/coins_config/io/custom_coins_file_reader_io.dart'
    if (dart.library.js_interop) 'package:komodo_coin_updates/src/coins_config/io/custom_coins_file_reader_web.dart'
    as reader;

/// Resolves the textual content of a [CustomCoinsFileSource] in a
/// platform-agnostic way.
///
/// * If the source carries in-memory [CustomCoinsFileSource.content] (web, or
///   any pre-read file), that content is returned directly.
/// * Otherwise the file is read from [CustomCoinsFileSource.path] using the
///   native filesystem.
abstract final class CustomCoinsFileReader {
  /// Returns the content of [source], reading from disk only when necessary.
  static Future<String> read(CustomCoinsFileSource source) async {
    if (source.hasContent) return source.content!;
    if (source.hasPath) return reader.readCustomCoinsFileFromPath(source.path!);
    throw StateError(
      'CustomCoinsFileSource has neither in-memory content nor a file path.',
    );
  }
}
