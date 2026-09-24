import 'dart:async';

final StreamController<void> _gaslessTransferChanges =
    StreamController<void>.broadcast(sync: true);

/// Process-wide notification that encrypted GasFree journal state changed.
Stream<void> get gaslessTransferChanges => _gaslessTransferChanges.stream;

/// Notifies every repository instance to reload its own wallet-scoped journal.
void notifyGaslessTransferChanged() => _gaslessTransferChanges.add(null);

/// Runs one journal read/modify/write unit on non-web platforms.
Future<T> withGaslessTransferLock<T>(Future<T> Function() operation) {
  return operation();
}
