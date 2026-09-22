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

final Set<(String, String)> _submissionLeases = {};
final Map<String, int> _walletReaders = {};
final Set<String> _walletWriters = {};

/// Stable wallet lifecycle lock name, shared by submissions and deletion.
String gaslessWalletLockName(String walletNamespace) =>
    'gleec-gasfree-wallet-lifecycle:$walletNamespace';

/// Submissions share a wallet lease; deletion requires exclusive ownership.
Future<GaslessSubmissionLease?> tryAcquireGaslessWalletLease(
  String walletNamespace, {
  bool exclusive = false,
}) async {
  if (_walletWriters.contains(walletNamespace) ||
      (exclusive && (_walletReaders[walletNamespace] ?? 0) > 0)) {
    return null;
  }
  if (exclusive) {
    _walletWriters.add(walletNamespace);
  } else {
    _walletReaders.update(walletNamespace, (n) => n + 1, ifAbsent: () => 1);
  }
  return GaslessSubmissionLease._(() async {
    if (exclusive) {
      _walletWriters.remove(walletNamespace);
    } else {
      final remaining = (_walletReaders[walletNamespace] ?? 1) - 1;
      if (remaining == 0) {
        _walletReaders.remove(walletNamespace);
      } else {
        _walletReaders[walletNamespace] = remaining;
      }
    }
  });
}

/// Exclusive ownership of a live submission or an explicit discard attempt.
final class GaslessSubmissionLease {
  GaslessSubmissionLease._(this._release);

  final Future<void> Function() _release;
  Future<void>? _released;

  /// Releases ownership once. Repeated releases await the same completion.
  Future<void> release() => _released ??= _release();
}

/// Stable, opaque lock name shared by same-origin browser contexts.
String gaslessSubmissionLockName(String walletNamespace, String journalId) =>
    'gleec-gasfree-submission:$walletNamespace:$journalId';

/// Tries to protect one submission without waiting behind another owner.
///
/// Native managers share this registry within their isolate. Browser builds
/// use the corresponding Web Lock across tabs and workers.
Future<GaslessSubmissionLease?> tryAcquireGaslessSubmissionLease(
  String walletNamespace,
  String journalId,
) async {
  final identity = (walletNamespace, journalId);
  if (!_submissionLeases.add(identity)) return null;
  return GaslessSubmissionLease._(() async {
    _submissionLeases.remove(identity);
  });
}
