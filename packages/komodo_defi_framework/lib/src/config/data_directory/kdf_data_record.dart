// Read at start-up on the UI isolate; synchronous I/O would freeze it.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_tree.dart';
import 'package:logging/logging.dart';

final _log = Logger('KdfDataRecord');

/// What a move of KDF's data copied, kept beside the new data directory.
///
/// It sits outside that directory because KDF lists every `*.json` file at
/// the top of its data directory as a wallet.
class KdfDataRecord {
  const KdfDataRecord({
    required this.source,
    required this.copiedAt,
    required this.files,
    this.verifiedAt,
    this.cleanedAt,
  });

  static const fileName = 'kdf-migration.json';
  static const _version = 1;

  /// The directory the data was copied from: the old one, put aside.
  final String source;

  final DateTime copiedAt;

  /// When KDF first came up on the new directory with a wallet open.
  final DateTime? verifiedAt;

  /// When the copy left behind was cleaned up.
  final DateTime? cleanedAt;

  /// Each copied file, by `/`-separated path relative to [source].
  final Map<String, KdfDataDigest> files;

  /// The record at [file], or null if there is none or it can't be read.
  /// Without a record, nothing is ever deleted.
  static Future<KdfDataRecord?> read(File file) async {
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map;
      if (json['version'] != _version) return null;
      return KdfDataRecord(
        source: json['source'] as String,
        copiedAt: DateTime.parse(json['copied_at'] as String),
        verifiedAt: _time(json['verified_at']),
        cleanedAt: _time(json['cleaned_at']),
        files: {
          for (final MapEntry(:key, :value) in (json['files'] as Map).entries)
            key as String: (
              size: (value as Map)['size'] as int,
              sha256: value['sha256'] as String,
            ),
        },
      );
    } on Object catch (error) {
      _log.warning('Ignoring unreadable ${file.path}: $error');
      return null;
    }
  }

  KdfDataRecord copyWith({DateTime? verifiedAt, DateTime? cleanedAt}) =>
      KdfDataRecord(
        source: source,
        copiedAt: copiedAt,
        files: files,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        cleanedAt: cleanedAt ?? this.cleanedAt,
      );

  /// Replaces [file] with one rename, so a crash leaves either version whole.
  Future<void> write(File file) async {
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(_toJson()), flush: true);
    await pending.rename(file.path);
  }

  Map<String, Object?> _toJson() => {
    'version': _version,
    'source': source,
    'copied_at': copiedAt.toUtc().toIso8601String(),
    'verified_at': verifiedAt?.toUtc().toIso8601String(),
    'cleaned_at': cleanedAt?.toUtc().toIso8601String(),
    'files': {
      for (final MapEntry(:key, :value) in files.entries)
        key: {'size': value.size, 'sha256': value.sha256},
    },
  };
}

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
