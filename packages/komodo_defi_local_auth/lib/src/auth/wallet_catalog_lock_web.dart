import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Serializes catalog changes across same-origin tabs and workers.
Future<T> withWalletCatalogLock<T>(Future<T> Function() operation) =>
    _withNamedLock('gleec-wallet-catalog', operation);

/// The record lock is always acquired after catalog/auth locks. Its callback
/// must not enter another record transaction or an authentication operation.
Future<T> withWalletRecordLock<T>(Future<T> Function() operation) =>
    _withNamedLock('gleec-wallet-records', operation);

Future<T> _withNamedLock<T>(String name, Future<T> Function() operation) async {
  late T result;
  Object? failure;
  StackTrace? stackTrace;
  var completed = false;
  await web.window.navigator.locks
      .request(
        name,
        ((web.Lock? _) => Future<void>.sync(() async {
          try {
            result = await operation();
            completed = true;
          } catch (error, stack) {
            failure = error;
            stackTrace = stack;
          }
        }).toJS).toJS,
      )
      .toDart;
  if (failure != null) Error.throwWithStackTrace(failure!, stackTrace!);
  if (!completed) throw StateError('Wallet catalog lock did not complete');
  return result;
}
