import 'dart:js_interop';
import 'package:web/web.dart';

/// JavaScript async iterator result type
@JS()
@anonymous
extension type JSIteratorResult<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external bool get done;
  external T? get value;
}

/// JavaScript async iterator type
@JS()
@anonymous
extension type JSAsyncIterator<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external JSPromise<JSIteratorResult<T>> next();
}

/// Extensions for FileSystemDirectoryHandle to provide missing async iterator methods
/// that are available in the JavaScript File System API but not exposed in Flutter's web package.
@JS()
extension FileSystemDirectoryHandleExtension on FileSystemDirectoryHandle {
  /// Returns an async iterator for the values (handles) in this directory.
  /// Equivalent to calling `directoryHandle.values()` in JavaScript.
  external JSAsyncIterator<FileSystemHandle> values();

  /// Returns an async iterator for the keys (names) in this directory.
  /// Equivalent to calling `directoryHandle.keys()` in JavaScript.
  external JSAsyncIterator<JSString> keys();

  /// Returns an async iterator for the entries (name-handle pairs) in this directory.
  /// Equivalent to calling `directoryHandle.entries()` in JavaScript.
  external JSAsyncIterator<JSArray<JSAny?>> entries();
}

/// Helper extensions to convert JavaScript async iterators to Dart async iterables
extension JSAsyncIteratorExtension<T extends JSAny?> on JSAsyncIterator<T> {
  /// Converts a JavaScript async iterator to a Dart Stream
  Stream<T?> asStream() async* {
    while (true) {
      final result = await next().toDart;
      if (result.done) break;
      yield result.value;
    }
  }
}

/// Extension to provide async iteration capabilities for FileSystemDirectoryHandle values
extension FileSystemDirectoryHandleValuesIterable on FileSystemDirectoryHandle {
  /// Returns a Stream of FileSystemHandle objects for async iteration over directory contents
  Stream<FileSystemHandle> valuesStream() async* {
    await for (final handle in values().asStream()) {
      if (handle != null) {
        yield handle;
      }
    }
  }

  /// Returns a Stream of file/directory names for async iteration over directory contents
  Stream<String> keysStream() async* {
    await for (final key in keys().asStream()) {
      if (key != null) {
        yield key.toDart;
      }
    }
  }

  /// Returns a Stream of [name, handle] pairs for async iteration over directory contents
  Stream<(String, FileSystemHandle)> entriesStream() async* {
    await for (final entry in entries().asStream()) {
      if (entry == null || entry.length < 2) {
        continue;
      }

      final nameValue = entry[0];
      final handleValue = entry[1];
      if (!nameValue.isA<JSString>() || !handleValue.isA<FileSystemHandle>()) {
        continue;
      }

      yield (nameValue.dartify()! as String, handleValue as FileSystemHandle);
    }
  }
}
