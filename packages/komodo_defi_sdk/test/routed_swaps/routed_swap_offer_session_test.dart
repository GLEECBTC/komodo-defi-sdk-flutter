import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import '../helpers/counting_session_auth.dart';
import 'routed_swap_coverage_fakes.dart';

const _a = KdfUser(
  walletId: WalletId(
    name: 'a',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
  isBip39Seed: false,
);
const _b = KdfUser(
  walletId: WalletId(
    name: 'b',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    pubkeyHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  ),
  isBip39Seed: false,
);

/// An engine that prices every quote on the default route and starts
/// anything it is asked to.
ScriptedKdf _engine() => ScriptedKdf()
  ..always(
    'routed_swap::quote',
    (_) => ok({
      'routes': [routeJson()],
    }),
  )
  ..always('task::routed_swap::init', (_) => ok({'task_id': 1}))
  ..always(
    'task::routed_swap::status',
    (_) => ok(inProgress(uuidOf(1), 'Signing')),
  );

/// Ends [auth]'s session and starts another for [user], as signing out and
/// in again does.
void _signIn(CountingSessionAuth auth, KdfUser user) {
  auth.runtimeSessions.invalidate();
  auth.user = user;
  auth.runtimeSessions.observe(user);
}

/// Holds lease acquisition separately from the RPC, so a revoked caller can
/// be tested before anything has reached the engine. Real auth mutex behavior
/// is covered by the local-auth package's session-dispatch tests.
class _DispatchAuth extends CountingSessionAuth {
  _DispatchAuth(super.user);

  Completer<void>? leaseGate;
  bool leaseHeld = false;

  @override
  Future<T> runWithSession<T>(
    AuthSessionContext expected,
    Future<T> Function() dispatch,
  ) async {
    ensureSessionContextCurrent(expected);
    final gate = leaseGate;
    if (gate != null) await gate.future;
    ensureSessionContextCurrent(expected);
    leaseHeld = true;
    try {
      return await dispatch();
    } finally {
      leaseHeld = false;
    }
  }
}

/// Covers who may start an offer: only the session that priced it, so an
/// offer reviewed before a sign-out, a wallet switch or a sign-in to the same
/// wallet never reaches the engine.
void main() {
  late ScriptedKdf kdf;
  late _DispatchAuth auth;
  late RoutedSwapManager manager;

  setUp(() {
    kdf = _engine();
    auth = _DispatchAuth(_a);
    manager = managerFor(kdf, auth: auth);
  });

  tearDown(() async {
    await manager.dispose();
    await auth.runtimeSessions.dispose();
    await auth.authChanges.close();
  });

  Future<RoutedSwapOffer> quoted() =>
      manager.quote(from: usdc, to: usdt, amount: d('100'));

  Future<void> expectRefused(RoutedSwapOffer offer) async {
    await expectLater(
      manager.start(offer),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(kdf.calls('task::routed_swap::init'), 0);
  }

  test('an offer starts in the session that priced it', () async {
    final handle = await manager.start(await quoted());

    expect(handle.uuid, uuidOf(1));
    expect(kdf.calls('task::routed_swap::init'), 1);
  });

  for (final next in [_b, _a]) {
    test('an offer priced before signing in to '
        '${next == _a ? 'the same wallet again' : 'another wallet'} '
        'never starts', () async {
      final offer = await quoted();
      _signIn(auth, next);

      await expectRefused(offer);
    });
  }

  for (final next in [_b, _a]) {
    final transition = next == _a
        ? 'same-wallet reauthentication'
        : 'a wallet switch';

    test('a Max offer priced before $transition never starts', () async {
      final max = await manager.quoteMax(from: usdc, to: usdt);
      final sell = await manager.maxSellAmount(
        from: usdc,
        to: usdt,
        balance: d('100'),
      );
      _signIn(auth, next);

      await expectRefused(max);
      await expectRefused(sell.offer!);
    });

    test('a copied offer cannot start after $transition', () async {
      final copy = (await quoted()).copyWith(quotedAt: DateTime.utc(2026, 11));

      await manager.start(copy);
      expect(kdf.calls('task::routed_swap::init'), 1);

      _signIn(auth, next);
      await expectLater(
        manager.start(copy),
        throwsA(isA<AuthSessionChangedException>()),
      );
      expect(kdf.calls('task::routed_swap::init'), 1);
    });
  }

  test('an offer built by hand never starts', () async {
    await expectRefused(offerOf());
  });

  test(
    'another manager cannot execute an offer even in the same session',
    () async {
      final offer = await quoted();
      final other = managerFor(kdf, auth: auth);
      addTearDown(other.dispose);

      await expectLater(
        other.start(offer),
        throwsA(isA<AuthSessionChangedException>()),
      );
      expect(kdf.calls('task::routed_swap::init'), 0);
    },
  );

  test('a separately authenticated manager cannot execute an offer', () async {
    final offer = await quoted();
    final otherAuth = _DispatchAuth(_a);
    final other = managerFor(kdf, auth: otherAuth);
    addTearDown(other.dispose);
    addTearDown(otherAuth.authChanges.close);
    await otherAuth.captureSessionContext();

    await expectLater(
      other.start(offer),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(kdf.calls('task::routed_swap::init'), 0);
  });

  test(
    'an offer exposes no operation that rebinds it to a new session',
    () async {
      final offer = await quoted();
      _signIn(auth, _b);
      final replacement = await auth.captureSessionContext();

      // Exercise the former public rebinding escape hatch without making it a
      // compile-time dependency of the regression.
      expect(
        () => (offer as dynamic).boundTo(replacement),
        throwsNoSuchMethodError,
      );
      await expectRefused(offer);
    },
  );

  for (final next in [_b, _a]) {
    final transition = next == _a
        ? 'same-wallet reauthentication'
        : 'a wallet switch';

    test('keeping an accepted minimum cannot authorize $transition', () async {
      final offer = (await quoted()).keepingMinimum(d('98'))!;
      final copied = offer.copyWith(quotedAt: DateTime.utc(2026, 11));
      await manager.start(copied);
      expect(kdf.calls('task::routed_swap::init'), 1);

      _signIn(auth, next);
      await expectLater(
        manager.start(copied),
        throwsA(isA<AuthSessionChangedException>()),
      );
      expect(kdf.calls('task::routed_swap::init'), 1);
    });
  }

  test(
    'a pending lease cannot start after the originating session ends',
    () async {
      final offer = await quoted();
      final gate = auth.leaseGate = Completer<void>();
      final starting = manager.start(offer);
      final rejected = expectLater(
        starting,
        throwsA(isA<AuthSessionChangedException>()),
      );
      await pumpEventQueue();
      _signIn(auth, _a);
      gate.complete();

      await rejected;
      expect(kdf.calls('task::routed_swap::init'), 0);
    },
  );

  test('a caller can revoke its intent while waiting for the lease', () async {
    final offer = await quoted();
    final gate = auth.leaseGate = Completer<void>();
    var valid = true;
    final refusal = StateError('review was closed');
    final starting = manager.start(
      offer,
      beforeDispatch: () {
        if (!valid) throw refusal;
      },
    );
    final rejected = expectLater(starting, throwsA(same(refusal)));
    await pumpEventQueue();
    valid = false;
    gate.complete();

    await rejected;
    expect(kdf.calls('task::routed_swap::init'), 0);
    expect(auth.leaseHeld, isFalse);
  });

  test(
    'disposing the manager while waiting for the lease prevents dispatch',
    () async {
      final offer = await quoted();
      final gate = auth.leaseGate = Completer<void>();
      final starting = manager.start(offer);
      final rejected = expectLater(
        starting,
        throwsA(isA<AuthSessionChangedException>()),
      );
      await pumpEventQueue();
      await manager.dispose();
      gate.complete();

      await rejected;
      expect(kdf.calls('task::routed_swap::init'), 0);
    },
  );

  test(
    'session revocation inside the dispatch guard still sends nothing',
    () async {
      final offer = await quoted();
      await expectLater(
        manager.start(offer, beforeDispatch: () => _signIn(auth, _b)),
        throwsA(isA<AuthSessionChangedException>()),
      );
      expect(kdf.calls('task::routed_swap::init'), 0);
    },
  );

  test('only init runs under the lease, not UUID resolution', () async {
    kdf
      ..always('task::routed_swap::init', (_) {
        expect(auth.leaseHeld, isTrue);
        return ok({'task_id': 1});
      })
      ..always('task::routed_swap::status', (_) {
        expect(auth.leaseHeld, isFalse);
        return ok(inProgress(uuidOf(1), 'Signing'));
      });
    var guarded = 0;

    final handle = await manager.start(
      await quoted(),
      beforeDispatch: () {
        expect(auth.leaseHeld, isTrue);
        guarded++;
      },
    );

    expect(handle.uuid, uuidOf(1));
    expect(guarded, 1);
    expect(kdf.calls('task::routed_swap::init'), 1);
  });

  test('a typed init rejection stays a definite rejection', () async {
    kdf.always(
      'task::routed_swap::init',
      (_) => rpcError('InvalidParam', {'param': 'amount', 'reason': 'invalid'}),
    );

    await expectLater(
      manager.start(await quoted()),
      throwsA(isA<rpc.RoutedSwapInvalidParamException>()),
    );
    expect(auth.leaseHeld, isFalse);
    expect(kdf.calls('task::routed_swap::status'), 0);
  });

  test(
    'a lost init response remains unconfirmed without another dispatch',
    () async {
      kdf.always('task::routed_swap::init', dropped);

      await expectLater(
        manager.start(await quoted()),
        throwsA(isA<RoutedSwapStartUnconfirmedException>()),
      );
      expect(auth.leaseHeld, isFalse);
      expect(kdf.calls('task::routed_swap::init'), 1);
      expect(kdf.calls('task::routed_swap::status'), 0);
    },
  );

  for (final next in [_b, _a]) {
    final transition = next == _a
        ? 'same-wallet reauthentication'
        : 'a wallet switch';

    test('a re-priced recovery offer cannot start after $transition', () async {
      kdf.always(
        'routed_swap::history',
        (_) => historyAnswer([
          entryJson(
            failedWith(
              uuidOf(2),
              'QuoteWorsened',
              data: {'fresh_route': routeJson(toMin: '98')},
            ),
          ),
        ]),
      );
      final fresh =
          (await manager.history()).entries.single.failure!.freshOffer!;
      _signIn(auth, next);

      await expectRefused(fresh);
    });

    test('an exact quote answered after $transition gives no offer', () async {
      final answer = Completer<Map<String, dynamic>>();
      kdf.always('routed_swap::quote', (_) => answer.future);
      final quoting = quoted();
      final rejected = expectLater(
        quoting,
        throwsA(isA<AuthSessionChangedException>()),
      );
      await pumpEventQueue();
      _signIn(auth, next);
      answer.complete(
        ok({
          'routes': [routeJson()],
        }),
      );

      await rejected;
      expect(kdf.calls('task::routed_swap::init'), 0);
    });
  }

  for (final next in [_b, _a]) {
    test('a Max quote answered after '
        '${next == _a ? 'same-wallet reauthentication' : 'a wallet switch'} '
        'gives no executable offer', () async {
      final answer = Completer<Map<String, dynamic>>();
      kdf.always('routed_swap::quote', (_) => answer.future);
      final quoting = manager.quoteMax(from: usdc, to: usdt);
      final rejected = expectLater(
        quoting,
        throwsA(isA<AuthSessionChangedException>()),
      );
      await pumpEventQueue();
      _signIn(auth, next);
      answer.complete(
        ok({
          'routes': [routeJson()],
        }),
      );

      await rejected;
      expect(kdf.calls('task::routed_swap::init'), 0);
    });
  }
}
