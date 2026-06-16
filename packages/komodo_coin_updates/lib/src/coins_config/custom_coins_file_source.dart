import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show JsonMap;

/// Describes a user-selected coins / coins-config file used to override the
/// bundled configuration.
///
/// The override can take one of two forms depending on the platform:
///
/// * **Native (desktop/mobile)** — the file is referenced by its absolute
///   filesystem [path]. The content is read lazily from disk when needed.
/// * **Web** — there is no real filesystem path, so the file [content] is
///   captured in memory at selection time (and optionally its [fileName] for
///   display purposes) and persisted directly.
///
/// Instances are JSON-serializable so they can be persisted by
/// [CustomCoinsConfig] and survive an app restart.
class CustomCoinsFileSource {
  const CustomCoinsFileSource._({this.path, this.content, this.fileName});

  /// Creates a source that references a file by its absolute [path].
  ///
  /// Intended for native platforms where a real filesystem path is available.
  const CustomCoinsFileSource.path(String path)
    : this._(path: path, fileName: path);

  /// Creates a source that captures the file [content] in memory.
  ///
  /// Intended for web, where a real filesystem path cannot be obtained. The
  /// optional [fileName] is kept only for display.
  const CustomCoinsFileSource.content({
    required String content,
    String? fileName,
  }) : this._(content: content, fileName: fileName);

  /// Absolute filesystem path to the file (native only). `null` on web.
  final String? path;

  /// In-memory file content (web, or any pre-read source). `null` when the
  /// content should be read lazily from [path].
  final String? content;

  /// Optional display name for the file.
  final String? fileName;

  /// Whether this source references a filesystem [path].
  bool get hasPath => path != null && path!.isNotEmpty;

  /// Whether this source carries in-memory [content].
  bool get hasContent => content != null;

  /// A short human-readable label suitable for display in settings UIs.
  String get displayLabel => path ?? fileName ?? 'custom file';

  /// Serializes this source to a JSON map for persistence.
  JsonMap toJson() => <String, dynamic>{
    if (path != null) 'path': path,
    if (content != null) 'content': content,
    if (fileName != null) 'fileName': fileName,
  };

  /// Reconstructs a source from a persisted JSON map.
  ///
  /// Returns `null` when [json] is `null` or describes neither a path nor
  /// content.
  static CustomCoinsFileSource? fromJson(JsonMap? json) {
    if (json == null) return null;
    final path = json['path'] as String?;
    final content = json['content'] as String?;
    final fileName = json['fileName'] as String?;
    if (path != null && path.isNotEmpty) {
      return CustomCoinsFileSource.path(path);
    }
    if (content != null) {
      return CustomCoinsFileSource.content(
        content: content,
        fileName: fileName,
      );
    }
    return null;
  }

  @override
  String toString() =>
      'CustomCoinsFileSource(${hasPath ? 'path: $path' : 'content: ${content?.length ?? 0} chars, fileName: $fileName'})';
}
