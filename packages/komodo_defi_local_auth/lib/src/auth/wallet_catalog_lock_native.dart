import 'package:mutex/mutex.dart';

final _catalogMutex = Mutex();

/// Serializes local SDK instances sharing the native wallet catalog.
Future<T> withWalletCatalogLock<T>(Future<T> Function() operation) =>
    _catalogMutex.protect(operation);

final _recordMutex = Mutex();

/// Last lock in the order catalog -> auth -> record. Callbacks must not enter
/// authentication/catalog operations or another record transaction.
Future<T> withWalletRecordLock<T>(Future<T> Function() operation) =>
    _recordMutex.protect(operation);
