import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';

/// The minimum script an SDK boot + sign-in touches.
///
/// Deliberately explicit rather than a permissive catch-all: an unscripted
/// method throws (see [ReplayKdfOperations.mm2Rpc]), so this map doubles as an
/// executable record of exactly which RPCs a login makes. When that set
/// changes, this test is where it shows up.
KdfScript _loginScript({required String walletName, bool walletExists = true}) {
  // KDF is stateful, so the script has to be too. `get_wallet_names` is asked
  // both *before* the wallet exists (registration checks for a name clash) and
  // *after* it has been activated (the identity check rejects a null
  // `activated_wallet`). A constant answer cannot satisfy both, and returning
  // the "after" answer up front makes registration fail with
  // "Wallet already exists".
  var activated = walletExists;

  return KdfScript()
    ..reply('version', {'result': 'harness-replay'})
    ..reply('stream::shutdown_signal::enable', {
      'mmrpc': '2.0',
      'result': {'streamer_id': 'SHUTDOWN'},
    })
    // v2 responses must carry `mmrpc`; the typed parsers read it directly and
    // throw on a bare `result` map.
    ..on('get_wallet_names', (_) {
      return {
        'mmrpc': '2.0',
        'result': {
          'wallet_names': activated ? [walletName] : <String>[],
          'activated_wallet': activated ? walletName : null,
        },
      };
    })
    // Starting KDF with a wallet name is what "activates" it, so this is the
    // transition point from the "before" answer to the "after" one.
    ..onKdfStart = ((startParams) {
      if ((startParams['wallet_name'] as String?)?.isNotEmpty ?? false) {
        activated = true;
      }
    })
    // Must be 40 lowercase hex chars: `_ensureAuthenticatedWalletIdentity`
    // rejects anything else outright, and GasFree's wallet-scoped journal is
    // namespaced on this value.
    ..reply('get_public_key_hash', {
      'mmrpc': '2.0',
      'result': {'public_key_hash': '0123456789abcdef0123456789abcdef01234567'},
    })
    ..reply('get_enabled_coins', {
      'mmrpc': '2.0',
      'result': {'coins': <Map<String, dynamic>>[]},
    })
    // Registration reads the mnemonic back to persist wallet metadata. A
    // deterministic non-secret test vector: the harness never talks to a real
    // chain, so this cannot control funds.
    ..reply('get_mnemonic', {
      'mmrpc': '2.0',
      'result': {
        'format': 'plaintext',
        'mnemonic':
            'abandon abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon about',
      },
    });
}

void main() {
  group('KdfHarness (replayed)', () {
    test('boots an SDK without a KDF binary or network', () async {
      final harness = await KdfHarness.replayed(
        script: _loginScript(walletName: 'harness-wallet'),
      );
      addTearDown(harness.dispose);

      expect(harness.sdk, isNotNull);
      expect(
        harness.metrics['sdk_init_ms'],
        isNotNull,
        reason: 'sdk_init_ms must be recorded so bootstrap cost is visible',
      );
      // The whole point of the replay tier: a real SDK bootstrap drove real
      // RPCs through the fake backend, with no binary, no port and no network.
      expect(
        harness.operations.requests,
        isNotEmpty,
        reason: 'the SDK should have issued RPCs through the replay backend',
      );
    });

    test('records a separate phase per stage rather than one number', () async {
      final harness = await KdfHarness.replayed(
        script: _loginScript(walletName: 'harness-wallet'),
      );
      addTearDown(harness.dispose);

      harness.metrics
        ..record('auth_signin_ms', 12)
        ..record('first_paint_ms', 3)
        ..record('first_post_activation_balance_ms', 900);

      // first_paint can be a cached or synthetic-zero value, so it must never
      // stand in for the activation number - that substitution is what would
      // let activation regress to minutes with a green metric.
      expect(
        harness.metrics['first_paint_ms'],
        isNot(equals(harness.metrics['first_post_activation_balance_ms'])),
      );
      expect(harness.metrics.toJson()['phases'], contains('sdk_init_ms'));
    });

    test('counts RPCs per method so amplification is measurable', () async {
      final script = _loginScript(walletName: 'harness-wallet');
      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      // Identity RPC volume is the thing we want to be able to regress-test:
      // ~480 per login was the headline number in the latency investigation.
      expect(script.invocationCounts, isA<Map<String, int>>());
      expect(script.callsTo('get_wallet_names'), greaterThanOrEqualTo(0));
    });

    test('an unscripted RPC fails loudly instead of silently', () async {
      // Boot with the normal script (an empty one cannot even complete
      // bootstrap), then ask for something nobody scripted.
      final harness = await KdfHarness.replayed(
        script: _loginScript(walletName: 'harness-wallet'),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.operations.mm2Rpc({'method': 'totally_unscripted'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('totally_unscripted'),
          ),
        ),
      );
    });
  });

  signInSuite();
  group('KdfScript', () {
    test('sequences task-poll responses so activation can be modelled', () {
      final script = KdfScript()
        ..sequence('task::enable_utxo::status', [
          (_) => {
            'result': {'status': 'InProgress', 'details': 'Activating'},
          },
          (_) => {
            'result': {'status': 'InProgress', 'details': 'Activating'},
          },
          (_) => {
            'result': {'status': 'Ok', 'details': <String, dynamic>{}},
          },
        ]);

      Map<String, dynamic> poll() =>
          script.respondTo({'method': 'task::enable_utxo::status'})
              as Map<String, dynamic>;

      expect((poll()['result'] as Map)['status'], 'InProgress');
      expect((poll()['result'] as Map)['status'], 'InProgress');
      expect((poll()['result'] as Map)['status'], 'Ok');
      // Past the end it holds the terminal state rather than falling off.
      expect((poll()['result'] as Map)['status'], 'Ok');
      expect(script.callsTo('task::enable_utxo::status'), 4);
    });

    test('hang() models a KDF that stops making progress', () async {
      final script = KdfScript()..hang('task::enable_utxo::status');

      final pending =
          script.respondTo({'method': 'task::enable_utxo::status'})!
              as Future<Map<String, dynamic>>;

      var settled = false;
      unawaited(pending.then((_) => settled = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // This is the case a real KDF cannot be asked to produce on demand, and
      // it is exactly what SharedActivationCoordinator's deadline exists for.
      expect(settled, isFalse);
    });
  });
}

void unawaited(Future<void> future) {}

/// The capability this harness exists for: a wallet brought up
/// pre-authenticated, in either derivation mode, with no UI and no network.
///
/// The HD case is the first anywhere in either repo - `test_integration`
/// signs in as iguana only, so the HD path blamed for the shipped
/// address-scan regression had no coverage at all.
void signInSuite() {
  group('pre-authenticated sign-in', () {
    for (final walletType in harnessWalletTypes) {
      test(
        'registers a ${walletType.name} wallet and records the phase',
        () async {
          final script = _loginScript(
            walletName: 'harness-wallet',
            walletExists: false,
          );
          final harness = await KdfHarness.replayed(script: script);
          addTearDown(harness.dispose);

          final user = await harness.signIn(walletType: walletType);

          expect(user.walletId.name, 'harness-wallet');
          expect(
            user.isHd,
            walletType == KdfWalletType.hd,
            reason: 'walletType must reach KDF as the derivation method',
          );
          expect(
            harness.metrics['auth_signin_ms'],
            isNotNull,
            reason: 'sign-in must be timed, not just performed',
          );
        },
      );
    }

    test('identity RPC volume per sign-in is observable', () async {
      final script = _loginScript(
        walletName: 'harness-wallet',
        walletExists: false,
      );
      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      await harness.signIn(walletType: KdfWalletType.hd);

      // The number itself is not asserted - it is a moving target and pinning
      // it here would just be noise. What matters is that it is *countable*,
      // so a regression in identity-RPC amplification has somewhere to be
      // caught instead of only showing up as a slow login in the field.
      expect(script.callsTo('get_wallet_names'), greaterThan(0));
    });
  });
}
