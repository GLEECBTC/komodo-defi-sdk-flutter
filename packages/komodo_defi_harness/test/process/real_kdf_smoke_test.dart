@Tags(['process'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';

/// The real-KDF tier. Informational, never gating.
///
/// **Every process test in this repo must live in this one file**, or be run
/// with `-j 1`. KDF's RPC port is fixed at 7783 - `generateWithDefaults`
/// defaults it and the auth path never overrides it - so two test files running
/// concurrently would each spawn a 120 MB binary and race for the same port.
/// There is no ephemeral-port allocator to build here; it would never be used.
///
/// Skips cleanly, with a reason, whenever [KdfProcessRequirements] is not
/// satisfied: no `KDF_HARNESS`, no `KDF_TEST_SEED`, or no binary. Gating on the
/// env var rather than on binary-existence is deliberate - the SDK's own
/// `flutter-tests.yml` runs the build transformer, so an existence check would
/// not skip there and a real KDF would spawn in a workflow with no timeout for
/// it.
///
/// The seed is read from the environment only, wrapped in `Secret`, and
/// redacted out of the captured log stream. The workspace holds a real wallet
/// database: never upload it as a CI artifact.
void main() {
  late KdfProcessRequirements requirements;

  setUpAll(() async {
    requirements = await KdfProcessRequirements.check();
    if (!requirements.isSatisfied) {
      // ignore: avoid_print
      print('SKIP: ${requirements.skipReason}');
    }
  });

  group('real KDF process', () {
    for (final walletType in harnessWalletTypes) {
      test('boots, signs in and reads a balance (${walletType.name})', () async {
        final harness = await KdfHarness.process(walletType: walletType);
        if (harness == null) {
          markTestSkipped(requirements.skipReason);
          return;
        }
        addTearDown(harness.dispose);

        expect(harness.isProcessTier, isTrue);
        expect(
          harness.metrics['kdf_boot_and_signin_ms'],
          isNotNull,
          reason: 'binary boot plus sign-in must be its own phase, not folded '
              'into auth_signin_ms - the two tiers are otherwise not '
              'comparable',
        );

        final asset = harness.sdk.assets.available.values.firstWhere(
          (a) => a.id.id == 'KMD',
        );
        await harness.measureFirstBalance(
          asset.id,
          // Real electrum servers, real chain state. Generous on purpose: this
          // tier measures reality, it does not gate on it.
          timeout: const Duration(minutes: 3),
        );

        // ignore: avoid_print
        print('PROCESS TIER (${walletType.name}): ${harness.metrics}');
        // The per-method breakdown is what makes the HD/iguana gap
        // attributable rather than merely visible: it shows the scan and
        // account-balance polling that only HD pays for.
        final counts = harness.processOperations!.invocationCounts.entries
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        // ignore: avoid_print
        print(
          'PROCESS TIER RPCs (${walletType.name}): '
          '${counts.map((e) => '${e.key}=${e.value}').join(' ')}',
        );

        expect(
          harness.metrics['first_paint_ms'],
          isNotNull,
          reason: 'no balance of any kind reached the stream',
        );
        expect(
          harness.metrics['first_post_activation_balance_ms'],
          isNotNull,
          reason: 'the asset never produced a balance after activation',
        );
      }, timeout: const Timeout(Duration(minutes: 6)));
    }

    test('records RPC volume against a real KDF too', () async {
      final harness = await KdfHarness.process(
        walletType: KdfWalletType.iguana,
      );
      if (harness == null) {
        markTestSkipped(requirements.skipReason);
        return;
      }
      addTearDown(harness.dispose);

      // The counter is the whole point of running this tier at all: the replay
      // number is the SDK's own amplification with a zero-latency backend,
      // and this is the same count against a KDF that actually takes time to
      // answer. A divergence between them is a KDF-side effect.
      // ignore: avoid_print
      print(
        'PROCESS TIER identity RPCs: '
        '${harness.metrics.counters['identity_rpcs_per_signin']} of '
        '${harness.metrics.counters['rpcs_per_signin']} total',
      );
      expect(harness.metrics.counters['rpcs_per_signin'], greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 6)));

    test('leaves nothing holding the port', () async {
      final harness = await KdfHarness.process(
        walletType: KdfWalletType.iguana,
      );
      if (harness == null) {
        markTestSkipped(requirements.skipReason);
        return;
      }
      await harness.dispose();

      // A leaked 120 MB KDF on a fixed port breaks every subsequent run on the
      // machine, so teardown is a tested property rather than an assumption.
      // The kill is by pid and unconditional; this checks it landed.
      var free = false;
      for (var attempt = 0; attempt < 20 && !free; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        free = !await isPortOccupied();
      }
      expect(
        free,
        isTrue,
        reason: 'port $kdfRpcPort is still held after dispose',
      );
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}
