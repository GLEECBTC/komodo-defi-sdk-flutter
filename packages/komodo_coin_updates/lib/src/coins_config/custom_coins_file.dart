import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show JsonMap;

/// A user-selected coins / coins-config file captured as an in-memory snapshot.
///
/// The override is content-based on every platform: when a file is selected its
/// [content] is read once and stored (together with the original [fileName] for
/// display), rather than keeping a filesystem path. This keeps behaviour
/// identical on native and web — web has no persistable filesystem path — and
/// makes the override immune to the source file later being moved, renamed,
/// deleted, or edited out from under the app.
///
/// Instances are JSON-serializable so they can be persisted by
/// [CustomCoinsStore] and survive an app restart.
class CustomCoinsFile {
  /// Creates a snapshot from the file's [content] and optional [fileName].
  const CustomCoinsFile({required this.content, this.fileName});

  /// The captured textual content of the file.
  final String content;

  /// The original file name, kept only for display in settings UIs.
  final String? fileName;

  /// A short human-readable label suitable for display.
  String get displayLabel => fileName ?? 'custom file';

  /// Serializes this snapshot to a JSON map for persistence.
  JsonMap toJson() => <String, dynamic>{
    'content': content,
    if (fileName != null) 'fileName': fileName,
  };

  /// Reconstructs a snapshot from a persisted JSON map.
  ///
  /// Returns `null` when [json] is `null` or carries no content.
  static CustomCoinsFile? fromJson(JsonMap? json) {
    if (json == null) return null;
    final content = json['content'] as String?;
    if (content == null) return null;
    return CustomCoinsFile(
      content: content,
      fileName: json['fileName'] as String?,
    );
  }

  @override
  String toString() =>
      'CustomCoinsFile(${content.length} chars, fileName: $fileName)';
}
