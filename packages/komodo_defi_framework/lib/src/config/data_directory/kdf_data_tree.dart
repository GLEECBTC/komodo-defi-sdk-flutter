// Walked at start-up on the UI isolate; synchronous I/O would freeze it.
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Whether a walked entry is a file or a directory.
enum KdfDataEntryKind { file, directory }

/// An entry found under a walked directory. `relativePath` uses `/` on every
/// platform, so a record written on Windows matches paths read back anywhere.
typedef KdfDataEntry = ({
  String path,
  String relativePath,
  KdfDataEntryKind kind,
});

/// The size and SHA-256 of a file's contents.
typedef KdfDataDigest = ({int size, String sha256});

/// Thrown for a symbolic link or junction inside KDF's data.
///
/// Someone set it up on purpose, and following it could copy or delete data
/// outside the directory, so the move leaves such a directory alone.
class KdfDataLinkException implements Exception {
  KdfDataLinkException(this.path);

  final String path;

  @override
  String toString() => 'KdfDataLinkException: $path is a link';
}

/// Every file and directory under [root], each parent before its children.
Future<List<KdfDataEntry>> walkKdfData(Directory root) async {
  final entries = <KdfDataEntry>[];
  await for (final entity in root.list(followLinks: false)) {
    entries.addAll(await walkKdfDataEntity(entity, root: root));
  }
  return entries;
}

/// [entity] and, for a directory, everything under it, relative to [root].
Future<List<KdfDataEntry>> walkKdfDataEntity(
  FileSystemEntity entity, {
  required Directory root,
}) async {
  final kind = await _kindOf(entity);
  final entries = <KdfDataEntry>[
    (
      path: entity.path,
      relativePath: p.posix.joinAll(
        p.split(p.relative(entity.path, from: root.path)),
      ),
      kind: kind,
    ),
  ];
  if (kind == KdfDataEntryKind.directory) {
    await for (final child in Directory(entity.path).list(followLinks: false)) {
      entries.addAll(await walkKdfDataEntity(child, root: root));
    }
  }
  return entries;
}

// Unfollowed, Windows lists every reparse point as a link, including
// OneDrive's placeholders, which are ordinary files and folders to read. Only
// symbolic links and junctions have a target.
Future<KdfDataEntryKind> _kindOf(FileSystemEntity entity) async {
  if (entity is File) return KdfDataEntryKind.file;
  if (entity is Directory) return KdfDataEntryKind.directory;
  if (await isKdfDataLink(entity.path)) throw KdfDataLinkException(entity.path);
  return switch (await FileSystemEntity.type(entity.path)) {
    FileSystemEntityType.file => KdfDataEntryKind.file,
    FileSystemEntityType.directory => KdfDataEntryKind.directory,
    _ => throw FileSystemException('Not a file or directory', entity.path),
  };
}

/// Whether [path] is a symbolic link or junction, rather than another kind of
/// reparse point such as a cloud-file placeholder.
///
/// Reading such a placeholder's target fails with ERROR_NOT_A_REPARSE_POINT.
/// Any other failure counts as a link, so a link that can't be read is never
/// followed.
Future<bool> isKdfDataLink(String path) async {
  if (!await FileSystemEntity.isLink(path)) return false;
  try {
    await Link(path).target();
    return true;
  } on FileSystemException catch (error) {
    return error.osError?.errorCode != _errorNotAReparsePoint;
  }
}

const _errorNotAReparsePoint = 4390;

/// Reads [file] in full. On Windows that downloads an online-only file, and
/// fails while OneDrive is offline or not running.
Future<KdfDataDigest> digestKdfDataFile(File file) async {
  var size = 0;
  final digest = await sha256
      .bind(
        file.openRead().map((chunk) {
          size += chunk.length;
          return chunk;
        }),
      )
      .first;
  return (size: size, sha256: digest.toString());
}

/// Copies [source] to [destination] and flushes the copy to disk.
Future<void> copyKdfDataFile(File source, File destination) async {
  final sink = destination.openWrite();
  try {
    await sink.addStream(source.openRead());
  } finally {
    await sink.close();
  }
  final handle = await destination.open(mode: FileMode.append);
  try {
    await handle.flush();
  } finally {
    await handle.close();
  }
}

/// The path of [relativePath] under [root], in the platform's own form.
String kdfDataPath(String root, String relativePath) =>
    p.joinAll([root, ...p.posix.split(relativePath)]);
