import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The deadline the app depends on, exercised through a real SDK.
///
/// There are unit tests for [SharedActivationCoordinator] at
/// `komodo_defi_sdk/test/activation/shared_activation_coordinator_timeout_test.dart`.
/// This is the integration-level equivalent: the same guarantee, but reached
/// through `KomodoDefiSdk`, a real `ActivationManager`, a real protocol
/// strategy and a KDF that accepted the task and then stopped answering. That
/// last part is why the replay tier exists at all - a real KDF cannot be asked
/// to wedge on demand, and this is the failure mode that cost users minutes.
///
/// The shipped bug: with no deadline, the coordinator's completer stayed
/// pending forever, and because `activateAsset` hands the *same* completer to
/// every later caller, the app's retry re-joined the wedged attempt instead of
/// starting a new one. Four retries x 90s produced the 363.5s per-asset waits
/// seen in the field. So the assertion that matters is not just "it fails" -
/// it is "the next attempt is genuinely new".
const _ticker = 'KMD';

/// Short enough for a per-PR gate, long enough that the init RPC and the first
/// status poll have both been issued before it fires.
const _deadline = Duration(seconds: 2);

Asset _assetFor(KdfHarness harness) => harness.sdk.assets.available.values
    .firstWhere((asset) => asset.id.id == _ticker);

Future<KdfHarness> _wedgedHarness() async {
  final fixture = KdfWalletFixture()
    ..enableUtxo(_ticker)
    ..balance(_ticker)
    // A KDF that accepted `::init` and then stopped making progress. The
    // strategy polls in `while (!isComplete)` and emits a progress event per
    // iteration, so a stalled activation looks *healthy* to any inter-event
    // timeout - only a total deadline catches it.
    ..hang('task::enable_utxo::status');

  final harness = await KdfHarness.replayed(script: fixture.build());
  await harness.signIn(walletType: KdfWalletType.iguana);
  return harness;
}

void main() {
  group('activation deadline (integration)', () {
    test('a wedged activation does not hold the slot forever', () async {
      final harness = await _wedgedHarness();
      addTearDown(harness.dispose);
      final asset = _assetFor(harness);
      final script = harness.script;

      // Deliberately not awaited. The deadline completes the coordinator's
      // completer and releases the pending slot, but the strategy's poll loop
      // is still suspended inside the hung RPC, so the `await for` that drives
      // this call cannot resume. Awaiting here would hang the test on a
      // behaviour the fix does not claim to change - what it claims, and what
      // the app relies on, is that the *slot* is released so the next attempt
      // is fresh.
      final firstAttempt = harness.sdk.ensureAssetActivated(
        asset,
        timeout: _deadline,
      );
      unawaited(firstAttempt.catchError((Object _) => false));

      await Future<void>.delayed(_deadline + const Duration(milliseconds: 750));

      expect(
        script.callsTo('task::enable_utxo::init'),
        1,
        reason: 'the first attempt should have started exactly one activation',
      );
      expect(
        script.callsTo('task::enable_utxo::status'),
        greaterThan(0),
        reason:
            'the deadline must be measured against a task that was '
            'actually polled, not one that never got started',
      );
    });

    test(
      'a later attempt starts fresh instead of joining the dead one',
      () async {
        final harness = await _wedgedHarness();
        addTearDown(harness.dispose);
        final asset = _assetFor(harness);
        final script = harness.script;

        unawaited(
          harness.sdk
              .ensureAssetActivated(asset, timeout: _deadline)
              .catchError((Object _) => false),
        );
        await Future<void>.delayed(
          _deadline + const Duration(milliseconds: 750),
        );
        expect(script.callsTo('task::enable_utxo::init'), 1);

        unawaited(
          harness.sdk
              .ensureAssetActivated(asset, timeout: _deadline)
              .catchError((Object _) => false),
        );
        await Future<void>.delayed(const Duration(milliseconds: 750));

        // This is the regression. Before the deadline landed, the second call
        // found the wedged completer still registered in `_pendingActivations`
        // and returned its future - no second `::init`, no progress, ever.
        expect(
          script.callsTo('task::enable_utxo::init'),
          2,
          reason:
              'the retry must issue a NEW activation. One init here means it '
              're-joined the dead completer, which is exactly the 4 x 90s = '
              '363.5s per-asset stall this deadline exists to prevent',
        );
      },
    );

    test('concurrent callers still share one in-flight attempt', () async {
      final harness = await _wedgedHarness();
      addTearDown(harness.dispose);
      final asset = _assetFor(harness);
      final script = harness.script;

      for (var i = 0; i < 3; i++) {
        unawaited(
          harness.sdk
              .ensureAssetActivated(asset, timeout: _deadline)
              .catchError((Object _) => false),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // The deduplication the coordinator exists for. Releasing the slot on a
      // deadline must not degrade into "every caller starts its own
      // activation", which would multiply RPC load on exactly the saturated
      // KDF that caused the stall.
      expect(
        script.callsTo('task::enable_utxo::init'),
        1,
        reason: 'callers arriving while an attempt is live must join it',
      );
    });

    test('a healthy activation is unaffected by the deadline', () async {
      final fixture = KdfWalletFixture()
        ..enableUtxo(_ticker, inProgressPolls: 2)
        ..balance(_ticker, spendable: '1');
      final harness = await KdfHarness.replayed(script: fixture.build());
      addTearDown(harness.dispose);
      await harness.signIn(walletType: KdfWalletType.iguana);

      final activated = await harness.sdk.ensureAssetActivated(
        _assetFor(harness),
        timeout: _deadline,
      );

      expect(
        activated,
        isTrue,
        reason: 'the deadline must bound a stall, not cap normal activation',
      );
    });
  });
}
