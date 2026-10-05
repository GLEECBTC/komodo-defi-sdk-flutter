import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Reads the signed-in [KdfUser] once per SDK session.
///
/// `auth.currentUser` re-verifies the wallet against KDF on every call: a
/// `get_wallet_names` and a `get_public_key_hash` round trip under the auth
/// write lock. What managers need from the user - HD mode, private-key policy,
/// whether this session created the wallet, the `isImported` flag - cannot
/// change within a session, so reading it on every poll only multiplied those
/// round trips.
///
/// Like the session token, the result scopes work. It never authorises secret
/// access or a wallet write.
final class SessionUserReader {
  /// Creates a reader over [_auth]'s `currentUser`.
  SessionUserReader(this._auth);

  final KomodoDefiLocalAuth _auth;
  AuthSessionContext? _session;
  KdfUser? _user;
  Future<_UserReadOutcome>? _pending;

  /// The signed-in user for [context]'s session.
  ///
  /// Throws [WalletChangedDisconnectException] when the session has ended or
  /// the signed-in wallet does not continue [context]'s identity. A name-only
  /// read of the same wallet, while `get_public_key_hash` is unavailable,
  /// still continues it; see [walletIdentityContinuesSession].
  Future<KdfUser> read(WalletOperationContext context) async {
    final session = context.session;
    if (_session != session) {
      _session = session;
      _user = null;
      _pending = null;
    }
    final cached = _user;
    if (cached != null) return cached;

    // Concurrent first reads share one round trip. The shared future carries
    // failures as values: callers can sit in different error zones (`retry()`
    // runs each attempt in its own), and Dart drops an error that crosses one.
    final pending = _pending ??= _auth.currentUser.then(
      _UserReadOutcome.success,
      onError: _UserReadOutcome.failure,
    );
    final outcome = await pending;
    if (identical(_pending, pending)) _pending = null;

    final user = outcome.unwrap();
    if (user == null ||
        !_auth.isSessionContextCurrent(session) ||
        !walletIdentityContinuesSession(context.walletId, user.walletId)) {
      throw const WalletChangedDisconnectException(
        'Wallet changed while reading the signed-in user',
      );
    }
    if (_session == session) _user = user;
    return user;
  }
}

class _UserReadOutcome {
  const _UserReadOutcome._(this._user, this._error, this._stackTrace);

  factory _UserReadOutcome.success(KdfUser? user) =>
      _UserReadOutcome._(user, null, null);

  factory _UserReadOutcome.failure(Object error, StackTrace stackTrace) =>
      _UserReadOutcome._(null, error, stackTrace);

  final KdfUser? _user;
  final Object? _error;
  final StackTrace? _stackTrace;

  /// Returns the user, or rethrows the original error in the caller's zone.
  KdfUser? unwrap() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stackTrace!);
    return _user;
  }
}
