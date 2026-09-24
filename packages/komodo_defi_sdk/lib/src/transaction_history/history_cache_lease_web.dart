import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// One browser context owns the Hive index and cache key at a time.
///
/// Another tab uses bounded memory instead of racing key generation, eviction,
/// or a stale in-memory Hive index. Web Locks release automatically on tab
/// exit.
class HistoryCacheLease {
  HistoryCacheLease._(this._release, this._finished);

  final Completer<void> _release;
  final Future<void> _finished;

  /// Acquires ownership before loading a key or opening the cache.
  static Future<HistoryCacheLease> acquire(String cacheName) async {
    final acquired = Completer<bool>();
    final release = Completer<void>();
    final finished = web.window.navigator.locks
        .request(
          'komodo-history-cache:$cacheName',
          web.LockOptions(ifAvailable: true),
          ((web.Lock? lock) {
            acquired.complete(lock != null);
            return (lock == null ? Future<void>.value() : release.future)
                .then<JSAny?>((_) => null)
                .toJS;
          }).toJS,
        )
        .toDart
        .then<void>((_) {});
    unawaited(
      finished.catchError((Object error, StackTrace stack) {
        if (!acquired.isCompleted) acquired.completeError(error, stack);
      }),
    );
    if (!await acquired.future) {
      await finished;
      throw StateError('Transaction history cache is in use by another tab');
    }
    return HistoryCacheLease._(release, finished);
  }

  /// Releases ownership; repeating release is harmless.
  Future<void> release() async {
    if (!_release.isCompleted) _release.complete();
    await _finished;
  }
}
