import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
// Test-only issuer for real owner-scoped runtime tokens.
// ignore: implementation_imports
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A stable wallet for transport/contract fixtures that do not exercise auth.
class RoutedTestAuth extends Fake implements KomodoDefiLocalAuth {
  RoutedTestAuth() {
    _sessions.observe(
      const KdfUser(
        walletId: WalletId(
          name: 'routed-fixture',
          pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        ),
        isBip39Seed: false,
      ),
    );
    addTearDown(_sessions.dispose);
  }

  final _sessions = AuthSessionTracker();

  @override
  Future<AuthSessionContext> captureSessionContext() async =>
      _sessions.current!;

  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      _sessions.isCurrent(context);

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!_sessions.isCurrent(context)) {
      throw const AuthSessionChangedException();
    }
  }

  @override
  Stream<AuthSessionContext?> watchSessionContext() => _sessions.changes;
}
