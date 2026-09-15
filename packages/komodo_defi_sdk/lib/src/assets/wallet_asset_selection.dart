import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// Wallet intent is independent of which assets KDF currently has enabled.
/// Reading the existing selection never rewrites it. Temporary activations
/// never call [add] or [remove], preserving every other consumer's intent.
class WalletAssetSelection {
  /// Tracks one authenticated session and retries unavailable persistence.
  WalletAssetSelection(
    this._auth, {
    this.persistenceRetryDelay = const Duration(seconds: 5),
  }) {
    _sessionSubscription = _auth.watchSessionContext().listen((session) {
      if (session == null ||
          (_session != null && !_auth.isSessionContextCurrent(_session!))) {
        _reset();
      } else if (_dirty) {
        unawaited(_persist().catchError((Object _) {}));
      }
    });
  }

  final KomodoDefiLocalAuth _auth;

  /// Delay before retrying a write without discarding runtime intent.
  final Duration persistenceRetryDelay;
  final _log = Logger('WalletAssetSelection');
  late final StreamSubscription<AuthSessionContext?> _sessionSubscription;
  final _changes = StreamController<Set<String>>.broadcast();
  AuthSessionContext? _session;
  Set<String> _selected = const {};
  Future<Set<String>>? _loading;
  AuthSessionContext? _loadingSession;
  Future<void>? _writing;
  Timer? _retry;
  bool _dirty = false;
  bool _disposed = false;
  int _revision = 0;

  /// Selected config IDs for the current session, empty before [load].
  Set<String> get current =>
      _session != null && _auth.isSessionContextCurrent(_session!)
      ? _selected
      : const {};

  /// Runtime selection changes, including the first load and session reset.
  Stream<Set<String>> get changes => _changes.stream;

  /// Reads persisted selection once per runtime session, without rewriting it.
  Future<Set<String>> load() async {
    if (_disposed) throw StateError('Wallet asset selection is disposed');
    final context = await _auth.captureSessionContext();
    if (_session != null && _auth.isSessionContextCurrent(_session!)) {
      return _selected;
    }
    if (_loading != null &&
        _loadingSession != null &&
        _auth.isSessionContextCurrent(_loadingSession!)) {
      return _loading!;
    }
    _loadingSession = context;
    late final Future<Set<String>> pending;
    pending = _load(context).whenComplete(() {
      if (identical(_loading, pending)) {
        _loading = null;
        _loadingSession = null;
      }
    });
    return _loading = pending;
  }

  Future<Set<String>> _load(AuthSessionContext context) async {
    final user = await _auth.currentUser;
    if (_disposed) throw StateError('Wallet asset selection is disposed');
    _auth.ensureSessionContextCurrent(context);
    if (user == null) throw AuthException.notSignedIn();
    _session = context;
    _selected = Set.unmodifiable(
      user.metadata.valueOrNull<List<String>>('activated_coins') ?? const [],
    );
    if (!_disposed) _changes.add(_selected);
    return _selected;
  }

  /// Adds wallet intent and persists it when fresh identity proof is available.
  /// Use [expectedSession] for requests crossing an asynchronous boundary.
  Future<void> add(
    Iterable<String> ids, {
    WalletId? expectedWalletId,
    AuthSessionContext? expectedSession,
  }) => _update(
    ids,
    adding: true,
    expectedWalletId: expectedWalletId,
    expectedSession: expectedSession,
  );

  /// Removes wallet intent without disabling unrelated runtime consumers.
  Future<void> remove(
    Iterable<String> ids, {
    WalletId? expectedWalletId,
    AuthSessionContext? expectedSession,
  }) => _update(
    ids,
    adding: false,
    expectedWalletId: expectedWalletId,
    expectedSession: expectedSession,
  );

  Future<void> _update(
    Iterable<String> ids, {
    required bool adding,
    WalletId? expectedWalletId,
    AuthSessionContext? expectedSession,
  }) async {
    if (expectedSession != null) {
      _auth.ensureSessionContextCurrent(expectedSession);
    }
    await load();
    if (expectedSession != null) {
      _auth.ensureSessionContextCurrent(expectedSession);
    }
    _auth.ensureSessionContextCurrent(_session!);
    if (expectedWalletId != null &&
        !walletIdentityContinuesSession(expectedWalletId, _session!.walletId)) {
      throw const AuthSessionChangedException();
    }
    final next = {..._selected};
    adding ? next.addAll(ids) : next.removeAll(ids);
    if (next.length == _selected.length && next.containsAll(_selected)) return;
    _selected = Set.unmodifiable(next);
    _dirty = true;
    _revision++;
    _changes.add(_selected);
    await _persist();
  }

  Future<void> _persist() async {
    if (_writing != null) return _writing;
    late final Future<void> pending;
    pending = _write().whenComplete(() {
      if (identical(_writing, pending)) _writing = null;
    });
    return _writing = pending;
  }

  Future<void> _write() async {
    final context = _session;
    if (!_dirty || context == null || _disposed) return;
    try {
      while (_dirty && !_disposed) {
        _auth.ensureSessionContextCurrent(context);
        final revision = _revision;
        await _auth.updateMetadataForSession(context, {
          'activated_coins': _selected.toList(),
        });
        _auth.ensureSessionContextCurrent(context);
        if (revision == _revision) _dirty = false;
      }
      _retry?.cancel();
      _retry = null;
    } on AuthSessionChangedException {
      // A previous wallet's delayed write must not reset the incoming wallet.
      if (identical(_session, context)) _reset();
      rethrow;
    } on Object {
      if (_disposed || !identical(_session, context) || !_dirty) return;
      // Keep runtime intent usable while verified persistence is unavailable.
      // Retrying is session scoped and cancelled on logout/disposal.
      _log.warning('Wallet asset selection persistence is unavailable');
      _retry ??= Timer(persistenceRetryDelay, () {
        _retry = null;
        unawaited(_persist().catchError((Object _) {}));
      });
    }
  }

  void _reset() {
    _retry?.cancel();
    _retry = null;
    _session = null;
    _loading = null;
    _loadingSession = null;
    _writing = null;
    _selected = const {};
    _dirty = false;
    _revision++;
    if (!_disposed) _changes.add(_selected);
  }

  /// Cancels session listeners and pending persistence retries.
  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _sessionSubscription.cancel();
    await _changes.close();
  }
}
