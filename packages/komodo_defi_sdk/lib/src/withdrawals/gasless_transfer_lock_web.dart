import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _lockName = 'gleec-gasfree-transfer-journal';
const _changeChannelName = 'gleec-gasfree-transfer-journal-changes';

final StreamController<void> _gaslessTransferChanges =
    StreamController<void>.broadcast(sync: true);
web.BroadcastChannel? _changeChannel;
var _changeChannelInitialized = false;

/// Cross-instance and cross-tab notification that journal state changed.
Stream<void> get gaslessTransferChanges {
  _ensureChangeChannel();
  return _gaslessTransferChanges.stream;
}

/// Notifies local repository instances and other same-origin browser contexts.
///
/// The BroadcastChannel message intentionally carries no wallet, trace, or
/// transfer identity. Each watcher reloads only its own scoped storage key.
void notifyGaslessTransferChanged() {
  _gaslessTransferChanges.add(null);
  _ensureChangeChannel();
  try {
    _changeChannel?.postMessage(null);
  } on Object {
    // Journal writes remain durable and serialized. A blocked notification
    // channel only delays another tab's presentation until its next refresh.
  }
}

void _ensureChangeChannel() {
  if (_changeChannelInitialized) return;
  _changeChannelInitialized = true;
  try {
    final channel = web.BroadcastChannel(_changeChannelName)
      ..onmessage = ((web.MessageEvent _) {
        _gaslessTransferChanges.add(null);
      }).toJS;
    _changeChannel = channel;
  } on Object {
    // BroadcastChannel is optional presentation synchronization. Web Locks
    // still enforce the journal's cross-tab read/modify/write invariant.
  }
}

/// Serializes journal read/modify/write units across tabs and workers.
///
/// If Web Locks are unavailable or fail, the operation fails closed rather
/// than falling back to an unsafe cross-tab read/write race.
Future<T> withGaslessTransferLock<T>(Future<T> Function() operation) async {
  late T operationResult;
  Object? operationError;
  StackTrace? operationStackTrace;
  var operationCompleted = false;
  final lockPromise = web.window.navigator.locks.request(
    _lockName,
    ((web.Lock? _) {
      return Future<T>.sync(operation)
          .then<JSAny?>(
            (value) {
              operationResult = value;
              operationCompleted = true;
              return null;
            },
            onError: (Object error, StackTrace stackTrace) {
              operationError = error;
              operationStackTrace = stackTrace;
              return null;
            },
          )
          .toJS;
    }).toJS,
  );
  await lockPromise.toDart;

  final error = operationError;
  if (error != null) {
    Error.throwWithStackTrace(error, operationStackTrace!);
  }
  if (!operationCompleted) {
    throw StateError('GasFree journal lock completed without a result');
  }
  return operationResult;
}
