import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

/// Issues real owner-scoped contexts for hand-written auth fixtures.
mixin RuntimeAuthFixture implements KomodoDefiLocalAuth {
  final runtimeSessions = AuthSessionTracker();
  StreamSubscription<KdfUser?>? _source;

  @override
  Future<AuthSessionContext> captureSessionContext() async {
    final epoch = runtimeSessions.epoch;
    final previous = runtimeSessions.current;
    final user = await currentUser;
    final accepted = runtimeSessions.current;
    if (epoch != runtimeSessions.epoch ||
        (accepted != null &&
            !identical(previous, accepted) &&
            user?.walletId != accepted.walletId)) {
      throw const AuthSessionChangedException();
    }
    runtimeSessions.observe(user);
    return runtimeSessions.current ?? (throw AuthException.notSignedIn());
  }

  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      runtimeSessions.isCurrent(context);

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!isSessionContextCurrent(context)) {
      throw const AuthSessionChangedException();
    }
  }

  @override
  Stream<AuthSessionContext?> watchSessionContext() {
    if (_source == null) {
      _source = authStateChanges.listen(runtimeSessions.observe);
      addTearDown(_disposeRuntimeAuthFixture);
    }
    return runtimeSessions.changes;
  }

  Future<void> _disposeRuntimeAuthFixture() async {
    await _source?.cancel();
    _source = null;
    await runtimeSessions.dispose();
  }
}
