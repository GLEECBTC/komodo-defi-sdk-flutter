import 'dart:async';

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

/// Covers who may start an offer: only the session that priced it, so an
/// offer reviewed before a sign-out, a wallet switch or a sign-in to the same
/// wallet never reaches the engine.
void main() {
  late ScriptedKdf kdf;
  late CountingSessionAuth auth;
  late RoutedSwapManager manager;

  setUp(() {
    kdf = _engine();
    auth = CountingSessionAuth(_a);
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

  test('a Max offer priced before a wallet change never starts', () async {
    final max = await manager.quoteMax(from: usdc, to: usdt);
    final sell = await manager.maxSellAmount(
      from: usdc,
      to: usdt,
      balance: d('100'),
    );
    _signIn(auth, _b);

    await expectRefused(max);
    await expectRefused(sell.offer!);
  });

  test(
    'a copy of an offer starts only in the session that priced it',
    () async {
      final copy = (await quoted()).copyWith(quotedAt: DateTime.utc(2026, 11));

      await manager.start(copy);
      expect(kdf.calls('task::routed_swap::init'), 1);

      _signIn(auth, _b);
      await expectLater(
        manager.start(copy),
        throwsA(isA<AuthSessionChangedException>()),
      );
      expect(kdf.calls('task::routed_swap::init'), 1);
    },
  );

  test('an offer built by hand never starts', () async {
    await expectRefused(offerOf());
  });

  test('a re-priced offer from a failure seen before a wallet change never '
      'starts', () async {
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
    final fresh = (await manager.history()).entries.single.failure!.freshOffer!;
    _signIn(auth, _b);

    await expectRefused(fresh);
  });

  test('a quote answered after a wallet change gives no offer', () async {
    final answer = Completer<Map<String, dynamic>>();
    kdf.always('routed_swap::quote', (_) => answer.future);
    final quoting = quoted();
    await pumpEventQueue();
    _signIn(auth, _b);
    answer.complete(
      ok({
        'routes': [routeJson()],
      }),
    );

    await expectLater(quoting, throwsA(isA<AuthSessionChangedException>()));
    expect(kdf.calls('task::routed_swap::init'), 0);
  });
}
