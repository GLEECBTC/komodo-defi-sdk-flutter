import 'dart:async';

import 'package:komodo_defi_sdk/src/auth/session_user_reader.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import '../helpers/counting_session_auth.dart';

const _walletA = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

const _walletB = KdfUser(
  walletId: WalletId(
    name: 'wallet-b',
    pubkeyHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

/// Auth whose next `currentUser` reads can be held open or failed.
class _GatedAuth extends CountingSessionAuth {
  _GatedAuth(super.user);

  Completer<KdfUser?>? gate;

  @override
  Future<KdfUser?> get currentUser {
    identityReads++;
    return gate?.future ?? Future.value(user);
  }
}

Future<WalletOperationContext> _capture(CountingSessionAuth auth) async {
  final session = await auth.captureSessionContext();
  return WalletOperationContext(
    walletId: session.walletId,
    generation: 0,
    session: session,
  );
}

void main() {
  late _GatedAuth auth;

  setUp(() {
    auth = _GatedAuth(_walletA);
    addTearDown(auth.authChanges.close);
  });

  test(
    'concurrent first reads share one round trip; later reads none',
    () async {
      final context = await _capture(auth);
      final readsWithSession = auth.identityReads;
      final reader = SessionUserReader(auth);

      auth.gate = Completer();
      final first = reader.read(context);
      final second = reader.read(context);
      auth.gate!.complete(_walletA);

      expect(await first, _walletA);
      expect(await second, _walletA);
      expect(await reader.read(context), _walletA);
      expect(auth.identityReads - readsWithSession, 1);
    },
  );

  test('a new session reads the user again', () async {
    final reader = SessionUserReader(auth);
    expect(await reader.read(await _capture(auth)), _walletA);

    auth.runtimeSessions.invalidate();
    auth.user = _walletB;
    final contextB = await _capture(auth);
    final readsWithSession = auth.identityReads;

    expect(await reader.read(contextB), _walletB);
    expect(auth.identityReads - readsWithSession, 1);
  });

  test(
    'a read pending across a session change is not kept or joined',
    () async {
      final contextA = await _capture(auth);
      final reader = SessionUserReader(auth);
      final gateA = auth.gate = Completer();
      final staleRead = reader.read(contextA);

      // Wallet B signs in while wallet A's read is still in flight.
      auth.runtimeSessions.invalidate();
      auth
        ..user = _walletB
        ..gate = null;
      final contextB = await _capture(auth);
      final readsWithSessionB = auth.identityReads;
      final freshRead = reader.read(contextB);
      gateA.complete(_walletA);

      await expectLater(
        staleRead,
        throwsA(isA<WalletChangedDisconnectException>()),
      );
      expect(await freshRead, _walletB);
      expect(await reader.read(contextB), _walletB);
      expect(auth.identityReads - readsWithSessionB, 1);
    },
  );

  test('a wallet that does not continue the session is not kept', () async {
    final context = await _capture(auth);
    final reader = SessionUserReader(auth);

    auth.user = _walletB;
    await expectLater(
      reader.read(context),
      throwsA(isA<WalletChangedDisconnectException>()),
    );

    auth.user = _walletA;
    expect(await reader.read(context), _walletA);
  });

  test(
    'a failed read reaches every caller, whichever zone it waits in',
    () async {
      final context = await _capture(auth);
      final reader = SessionUserReader(auth);
      auth.gate = Completer();

      final outside = reader.read(context);
      final inside = Completer<Object?>();
      final uncaught = <Object>[];
      runZonedGuarded(() {
        reader
            .read(context)
            .then((_) => inside.complete(null), onError: inside.complete);
      }, (error, _) => uncaught.add(error));
      auth.gate!.completeError(StateError('KDF unreachable'));

      await expectLater(outside, throwsA(isA<StateError>()));
      expect(await inside.future, isA<StateError>());
      expect(uncaught, isEmpty);

      // The failure is not remembered.
      auth.gate = null;
      expect(await reader.read(context), _walletA);
    },
  );
}
