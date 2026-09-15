import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import '../helpers/runtime_auth_fixture.dart';

KdfUser _user(String name, {List<String> selected = const ['KMD']}) => KdfUser(
  walletId: WalletId.fromName(
    name,
    const AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: true,
  metadata: {'activated_coins': selected},
);

void main() {
  test('loading saved selection performs no metadata write', () async {
    final auth = _Auth(_user('A'));
    final selection = WalletAssetSelection(auth);
    addTearDown(selection.dispose);
    expect(await selection.load(), {'KMD'});
    expect(await selection.load(), {'KMD'});
    expect(auth.writes, isEmpty);
  });

  test('concurrent changes preserve additions and removals', () async {
    final auth = _Auth(_user('A'));
    final selection = WalletAssetSelection(auth);
    addTearDown(selection.dispose);
    await selection.load();
    await Future.wait([
      selection.add(['ETH']),
      selection.add(['BTC']),
      selection.remove(['KMD']),
    ]);
    expect(selection.current, {'ETH', 'BTC'});
    expect(
      auth.writes.last['activated_coins'],
      unorderedEquals(['ETH', 'BTC']),
    );
  });

  test('unavailable identity retains intent and retries persistence', () async {
    final auth = _Auth(_user('A'))..identityAvailable = false;
    final selection = WalletAssetSelection(
      auth,
      persistenceRetryDelay: const Duration(milliseconds: 5),
    );
    addTearDown(selection.dispose);
    await selection.add(['ETH']);
    expect(selection.current, {'KMD', 'ETH'});
    expect(auth.writes, isEmpty);
    auth.identityAvailable = true;
    await auth.written.future.timeout(const Duration(seconds: 1));
    expect(
      auth.writes.single['activated_coins'],
      unorderedEquals(['KMD', 'ETH']),
    );
  });

  test(
    'late old-wallet load cannot overwrite a replacement selection',
    () async {
      final original = _user('A');
      final replacement = _user('B', selected: ['BTC']);
      final auth = _Auth(original);
      final selection = WalletAssetSelection(auth);
      addTearDown(selection.dispose);
      final pending = Completer<KdfUser?>();
      var reads = 0;
      auth.read = () => ++reads == 2 ? pending.future : Future.value(auth.user);
      final oldLoad = selection.load();
      final rejected = expectLater(
        oldLoad,
        throwsA(isA<AuthSessionChangedException>()),
      );
      await Future<void>.delayed(Duration.zero);
      auth.runtimeSessions.invalidate();
      auth.user = replacement;
      auth.runtimeSessions.observe(replacement);
      expect(await selection.load(), {'BTC'});
      pending.complete(original);
      await rejected;
      expect(selection.current, {'BTC'});
    },
  );

  test(
    'captured session prevents a same-wallet reauthentication write',
    () async {
      final auth = _Auth(_user('A'));
      final selection = WalletAssetSelection(auth);
      addTearDown(selection.dispose);
      final originalSession = await auth.captureSessionContext();
      auth.runtimeSessions.invalidate();
      auth.runtimeSessions.observe(auth.user);
      await expectLater(
        selection.add(['ETH'], expectedSession: originalSession),
        throwsA(isA<AuthSessionChangedException>()),
      );
      expect(auth.writes, isEmpty);
    },
  );

  test('a pending load does not publish after disposal', () async {
    final auth = _Auth(_user('A'));
    final selection = WalletAssetSelection(auth);
    final pending = Completer<KdfUser?>();
    var reads = 0;
    auth.read = () => ++reads == 2 ? pending.future : Future.value(auth.user);
    final rejected = expectLater(selection.load(), throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    await selection.dispose();
    pending.complete(auth.user);
    await rejected;
    expect(selection.current, isEmpty);
  });
}

class _Auth with RuntimeAuthFixture implements KomodoDefiLocalAuth {
  _Auth(this.user);
  KdfUser user;
  bool identityAvailable = true;
  Future<KdfUser?> Function()? read;
  final writes = <Map<String, dynamic>>[];
  final written = Completer<void>();
  @override
  Future<KdfUser?> get currentUser => read?.call() ?? Future.value(user);
  @override
  Stream<KdfUser?> get authStateChanges => const Stream.empty();
  @override
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext session,
    Map<String, dynamic> updates,
  ) async {
    ensureSessionContextCurrent(session);
    if (!identityAvailable) throw const AuthIdentityUnavailableException();
    user = user.copyWith(metadata: {...user.metadata, ...updates});
    writes.add(Map.of(updates));
    if (!written.isCompleted) written.complete();
    return user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
