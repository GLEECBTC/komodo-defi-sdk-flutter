import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// An SDK-issued token for one uninterrupted runtime wallet session.
///
/// This token scopes asynchronous work; it is not fresh identity proof and
/// cannot authorize secret access or a wallet write by itself.
@immutable
final class AuthSessionContext {
  const AuthSessionContext._(this.walletId, this.epoch, this._owner);

  final WalletId walletId;
  final int epoch;
  final Object _owner;

  @override
  bool operator ==(Object other) =>
      other is AuthSessionContext &&
      identical(_owner, other._owner) &&
      epoch == other.epoch;

  @override
  int get hashCode => Object.hash(_owner, epoch);

  @override
  String toString() => 'AuthSessionContext(redacted)';
}

/// The original runtime session ended, including same-wallet reauthentication.
class AuthSessionChangedException extends WalletChangedDisconnectException {
  const AuthSessionChangedException() : super('Wallet session changed');
}

/// The session still exists, but a fresh identity proof is unavailable.
class AuthIdentityUnavailableException
    extends WalletChangedDisconnectException {
  const AuthIdentityUnavailableException()
    : super('Wallet identity is temporarily unavailable; retry the operation');
}

/// Internal runtime-session ownership, independent of strict auth revisions.
final class AuthSessionTracker {
  final Object _owner = Object();
  final _changes = StreamController<AuthSessionContext?>.broadcast();
  AuthSessionContext? _current;
  String? _entryId;
  int _epoch = 0;
  bool _disposed = false;

  AuthSessionContext? get current => _current;
  int get epoch => _epoch;
  Stream<AuthSessionContext?> get changes => _changes.stream;

  bool isCurrent(AuthSessionContext context) =>
      !_disposed &&
      identical(context._owner, _owner) &&
      _current?.epoch == context.epoch;

  void invalidate() {
    _epoch++;
    _current = null;
    _entryId = null;
    if (!_changes.isClosed) _changes.add(null);
  }

  void observe(KdfUser? user) {
    if (_disposed) return;
    if (user == null) {
      if (_current != null) invalidate();
      return;
    }
    final previous = _current;
    final rawEntryId = user.metadata['_wallet_entry_id'];
    final entryId = rawEntryId is String && rawEntryId.isNotEmpty
        ? rawEntryId
        : null;
    if (previous != null &&
        (!_continues(previous.walletId, user.walletId) ||
            (_entryId != null && entryId != null && _entryId != entryId))) {
      invalidate();
    }
    _entryId = entryId ?? _entryId;
    final current = _current;
    final identity = current != null && _hash(user.walletId) == null
        ? current.walletId
        : user.walletId;
    if (current?.walletId == identity) return;
    _current = AuthSessionContext._(identity, _epoch, _owner);
    _changes.add(_current);
  }

  Future<void> dispose() async {
    invalidate();
    _disposed = true;
    await _changes.close();
  }

  static String? _hash(WalletId wallet) {
    final hash = wallet.pubkeyHash?.trim().toLowerCase();
    return hash == null || hash.isEmpty ? null : hash;
  }

  static bool _continues(WalletId previous, WalletId current) {
    if (previous.name != current.name ||
        previous.authOptions.derivationMethod !=
            current.authOptions.derivationMethod ||
        previous.authOptions.privKeyPolicy !=
            current.authOptions.privKeyPolicy) {
      return false;
    }
    final previousHash = _hash(previous);
    final currentHash = _hash(current);
    if (previousHash != null && currentHash != null) {
      return previousHash == currentHash;
    }
    return previous.name == current.name;
  }
}
