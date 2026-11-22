import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:komodo_defi_framework/src/native/backup_exclusion.dart';
import 'package:logging/logging.dart';

final _log = Logger('BackupExclusion');

/// Only iOS excludes anything. Standard iCloud Backup is encrypted with keys
/// Apple holds. On macOS the same flag opts out of Time Machine, whose backups
/// the user holds, so excluding there would only remove their own restore.
/// Android has no per-file flag: apps opt out in their manifest.
BackupExclusion platformBackupExclusion() =>
    Platform.isIOS ? CoreFoundationBackupExclusion().exclude : keepInBackups;

/// Sets `kCFURLIsExcludedFromBackupKey`, the CoreFoundation form of
/// `URLResourceValues.isExcludedFromBackup`. On a directory it also covers
/// files created inside it later.
final class CoreFoundationBackupExclusion {
  CoreFoundationBackupExclusion({DynamicLibrary? library})
    : _library = library ?? DynamicLibrary.process();

  final DynamicLibrary _library;
  _CoreFoundation? _bindings;

  _CoreFoundation get _cf => _bindings ??= _CoreFoundation(_library);

  /// A [BackupExclusion]: logs a failure instead of throwing it.
  void exclude(String directoryPath) {
    try {
      _withDirectoryUrl(directoryPath, (url, arena) {
        final error = arena<Pointer<Void>>();
        final set = _cf.setResourceProperty(
          url,
          _cf.excludedFromBackupKey,
          _cf.booleanTrue,
          error,
        );
        if (set == 0) throw _cf.takeError(error.value);
      });
    } on Object catch (error) {
      _log.warning('Device backups still include $directoryPath: $error');
    }
  }

  /// Whether the file system reports [directoryPath] as excluded.
  ///
  /// Throws a [BackupExclusionException] when the flag cannot be read.
  bool isExcluded(String directoryPath) =>
      _withDirectoryUrl(directoryPath, (url, arena) {
        final value = arena<Pointer<Void>>();
        final error = arena<Pointer<Void>>();
        final read = _cf.copyResourceProperty(
          url,
          _cf.excludedFromBackupKey,
          value,
          error,
        );
        if (read == 0) throw _cf.takeError(error.value);
        if (value.value == nullptr) return false;
        try {
          return _cf.booleanGetValue(value.value) != 0;
        } finally {
          _cf.release(value.value);
        }
      });

  T _withDirectoryUrl<T>(
    String directoryPath,
    T Function(Pointer<Void> url, Arena arena) body,
  ) {
    if (directoryPath.isEmpty) {
      throw ArgumentError.value(directoryPath, 'directoryPath', 'is empty');
    }
    return using((arena) {
      final bytes = utf8.encode(directoryPath);
      final buffer = arena<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      // A new URL each call: CFURL caches resource values per object, so a
      // reused one could report a stale flag.
      final url = _cf.createUrl(nullptr, buffer, bytes.length, 1);
      if (url == nullptr) {
        throw BackupExclusionException('no URL for $directoryPath');
      }
      try {
        return body(url, arena);
      } finally {
        _cf.release(url);
      }
    });
  }
}

/// A CoreFoundation call that failed, with its `CFError` domain and code.
final class BackupExclusionException implements Exception {
  const BackupExclusionException(this.message);

  final String message;

  @override
  String toString() => 'BackupExclusionException: $message';
}

typedef _Ref = Pointer<Void>;

const _kCFStringEncodingUTF8 = 0x08000100;

final class _CoreFoundation {
  _CoreFoundation(DynamicLibrary library)
    : createUrl = library
          .lookupFunction<
            _Ref Function(_Ref, Pointer<Uint8>, Long, Uint8),
            _Ref Function(_Ref, Pointer<Uint8>, int, int)
          >('CFURLCreateFromFileSystemRepresentation'),
      setResourceProperty = library
          .lookupFunction<
            Uint8 Function(_Ref, _Ref, _Ref, Pointer<_Ref>),
            int Function(_Ref, _Ref, _Ref, Pointer<_Ref>)
          >('CFURLSetResourcePropertyForKey'),
      copyResourceProperty = library
          .lookupFunction<
            Uint8 Function(_Ref, _Ref, Pointer<_Ref>, Pointer<_Ref>),
            int Function(_Ref, _Ref, Pointer<_Ref>, Pointer<_Ref>)
          >('CFURLCopyResourcePropertyForKey'),
      booleanGetValue = library
          .lookupFunction<Uint8 Function(_Ref), int Function(_Ref)>(
            'CFBooleanGetValue',
          ),
      errorGetCode = library
          .lookupFunction<Long Function(_Ref), int Function(_Ref)>(
            'CFErrorGetCode',
          ),
      errorGetDomain = library
          .lookupFunction<_Ref Function(_Ref), _Ref Function(_Ref)>(
            'CFErrorGetDomain',
          ),
      stringGetCString = library
          .lookupFunction<
            Uint8 Function(_Ref, Pointer<Utf8>, Long, Uint32),
            int Function(_Ref, Pointer<Utf8>, int, int)
          >('CFStringGetCString'),
      release = library
          .lookupFunction<Void Function(_Ref), void Function(_Ref)>(
            'CFRelease',
          ),
      excludedFromBackupKey = library
          .lookup<_Ref>('kCFURLIsExcludedFromBackupKey')
          .value,
      booleanTrue = library.lookup<_Ref>('kCFBooleanTrue').value;

  final _Ref Function(_Ref, Pointer<Uint8>, int, int) createUrl;
  final int Function(_Ref, _Ref, _Ref, Pointer<_Ref>) setResourceProperty;
  final int Function(_Ref, _Ref, Pointer<_Ref>, Pointer<_Ref>)
  copyResourceProperty;
  final int Function(_Ref) booleanGetValue;
  final int Function(_Ref) errorGetCode;
  final _Ref Function(_Ref) errorGetDomain;
  final int Function(_Ref, Pointer<Utf8>, int, int) stringGetCString;
  final void Function(_Ref) release;
  final _Ref excludedFromBackupKey;
  final _Ref booleanTrue;

  /// Describes and releases an error a Create/Copy-rule call handed back.
  BackupExclusionException takeError(_Ref error) {
    if (error == nullptr) {
      return const BackupExclusionException('no CFError returned');
    }
    try {
      return BackupExclusionException(
        '${_domainOf(error)} error ${errorGetCode(error)}',
      );
    } finally {
      release(error);
    }
  }

  String _domainOf(_Ref error) {
    final domain = errorGetDomain(error);
    if (domain == nullptr) return 'unknown domain';
    return using((arena) {
      const capacity = 256;
      final buffer = arena<Uint8>(capacity).cast<Utf8>();
      final copied = stringGetCString(
        domain,
        buffer,
        capacity,
        _kCFStringEncodingUTF8,
      );
      return copied == 0 ? 'unknown domain' : buffer.toDartString();
    });
  }
}
