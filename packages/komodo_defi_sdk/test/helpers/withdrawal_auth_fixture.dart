import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'runtime_auth_fixture.dart';

/// Keeps withdrawal scenarios' mutable identity inputs behind real sessions.
class WithdrawalAuthFixture
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {
  WithdrawalAuthFixture({
    Future<WalletId?> Function()? walletResolver,
    Stream<KdfUser?>? userChanges,
  }) : _walletResolver = walletResolver,
       _userChanges = (userChanges ?? const Stream<KdfUser?>.empty())
           .asBroadcastStream();

  final Future<WalletId?> Function()? _walletResolver;
  final Stream<KdfUser?> _userChanges;

  @override
  Future<KdfUser?> get currentUser async {
    final wallet = await _walletResolver?.call();
    return wallet == null
        ? null
        : KdfUser(walletId: wallet, isBip39Seed: false);
  }

  @override
  Stream<KdfUser?> get authStateChanges => _userChanges;

  @override
  Stream<KdfUser?> watchCurrentUser() => _userChanges;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
