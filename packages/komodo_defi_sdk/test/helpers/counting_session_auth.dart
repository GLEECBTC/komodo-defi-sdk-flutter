import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';

import 'runtime_auth_fixture.dart';

/// Auth with `KdfAuthService`'s read costs, for counting identity RPCs.
///
/// Each `currentUser` read is one fresh identity check: in production a
/// `get_wallet_names` and a `get_public_key_hash` under the auth write lock.
/// [RuntimeAuthFixture] returns a live session without one, as the service
/// does.
class CountingSessionAuth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {
  CountingSessionAuth(this.user);

  KdfUser? user;
  final authChanges = StreamController<KdfUser?>.broadcast();

  /// `currentUser` reads so far; each one is an identity RPC pair.
  int identityReads = 0;

  @override
  Stream<KdfUser?> get authStateChanges => authChanges.stream;

  @override
  Future<KdfUser?> get currentUser async {
    identityReads++;
    return user;
  }
}

/// [CountingSessionAuth] whose session changes never reach the managers' auth
/// streams, as if their delivery were still pending.
///
/// The service revokes a session synchronously and announces it on a stream
/// that delivers later. In between, only the managers' synchronous session
/// check can reject work captured under the old session.
class HeldSessionStreamAuth extends CountingSessionAuth {
  HeldSessionStreamAuth(super.user);

  final heldSessionEvents = StreamController<AuthSessionContext?>.broadcast();

  @override
  Stream<AuthSessionContext?> watchSessionContext() => heldSessionEvents.stream;
}
