import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A UTXO/SmartChain asset, so activation goes through the task-based
/// `task::enable_utxo::init` -> `::status` protocol rather than a single-shot
/// RPC. That polling loop is where activation latency actually lives.
const _utxoTicker = 'KMD';

/// A platform asset activated through the batch `enable_eth_with_tokens` RPC.
const _ethTicker = 'ETH';

Asset _assetFor(KdfHarness harness, String ticker) {
  return harness.sdk.assets.available.values.firstWhere(
    (asset) => asset.id.id == ticker,
    orElse: () => throw StateError('$ticker missing from the coins config'),
  );
}

void main() {
  group('activation through a real SDK', () {
    for (final walletType in harnessWalletTypes) {
      test('records first paint and post-activation balance separately '
          '(${walletType.name})', () async {
        final fixture = KdfWalletFixture()
          ..enableUtxo(_utxoTicker, inProgressPolls: 3)
          ..balance(_utxoTicker, spendable: '12.5');

        final harness = await KdfHarness.replayed(script: fixture.build());
        addTearDown(harness.dispose);

        await harness.signIn(walletType: walletType);
        final asset = _assetFor(harness, _utxoTicker);
        await harness.measureFirstBalance(asset.id);

        final firstPaint = harness.metrics['first_paint_ms'];
        final activation = harness.metrics['activation_ms'];
        final postActivation =
            harness.metrics['first_post_activation_balance_ms'];

        expect(
          firstPaint,
          isNotNull,
          reason: 'the pre-activation paint must be measured',
        );
        expect(
          activation,
          isNotNull,
          reason: 'the asset never reached the active state',
        );
        expect(
          postActivation,
          isNotNull,
          reason:
              'no balance landed after activation - measureFirstBalance '
              'timed out, which is the failure the split exists to expose',
        );

        // The point of the split. A pre-activation paint that equalled the
        // post-activation number would mean one of them is not measuring
        // what its name says, and the cheap one is the one a gate would
        // accidentally end up watching.
        expect(
          postActivation,
          greaterThan(firstPaint!),
          reason:
              'first_paint_ms must precede the fetched balance; if these '
              'converge, first_paint_ms has stopped being a cache/synthetic '
              'paint and the activation gate has quietly lost its teeth',
        );
        expect(
          postActivation,
          greaterThanOrEqualTo(activation!),
          reason: 'a post-activation balance cannot predate activation',
        );
      });
    }

    test('polls task::enable_utxo::status until it reports Ok', () async {
      final fixture = KdfWalletFixture()
        ..enableUtxo(_utxoTicker, inProgressPolls: 3)
        ..balance(_utxoTicker, spendable: '1');
      final script = fixture.build();

      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      await harness.signIn(walletType: KdfWalletType.iguana);
      await harness.measureFirstBalance(_assetFor(harness, _utxoTicker).id);

      expect(script.callsTo('task::enable_utxo::init'), 1);
      // 3 InProgress + the terminal Ok. A fixture that answered Ok on the
      // first poll would report a plausible-looking activation time that
      // contained no polling at all.
      expect(
        script.callsTo('task::enable_utxo::status'),
        greaterThanOrEqualTo(4),
      );
      expect(
        script.callLog.indexOf('task::enable_utxo::init'),
        lessThan(script.callLog.indexOf('task::enable_utxo::status')),
      );
    });

    test('activates a platform asset through enable_eth_with_tokens', () async {
      final fixture = KdfWalletFixture()
        ..enableEthWithTokens(_ethTicker, spendable: '2')
        ..balance(_ethTicker, spendable: '2');
      final script = fixture.build();

      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      await harness.signIn(walletType: KdfWalletType.iguana);
      final asset = _assetFor(harness, _ethTicker);
      await harness.measureFirstBalance(asset.id);

      expect(
        script.callsTo('enable_eth_with_tokens'),
        1,
        reason: 'the platform batch RPC should be issued exactly once',
      );
      expect(
        harness.metrics['first_post_activation_balance_ms'],
        isNotNull,
        reason: 'a batch-activated platform asset must still reach a balance',
      );
    });

    test('an HD sign-in scans for addresses before reading balances', () async {
      final fixture = KdfWalletFixture()
        ..enableUtxo(_utxoTicker)
        ..balance(_utxoTicker, spendable: '3');
      final script = fixture.build();

      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      await harness.signIn(walletType: KdfWalletType.hd);
      await harness.measureFirstBalance(_assetFor(harness, _utxoTicker).id);

      // The HD branch had no coverage anywhere in either repo before this
      // harness, and the address scan is the cost that only HD pays - the
      // difference a cold-vs-warm web measurement is meant to expose.
      expect(
        script.callsTo('task::scan_for_new_addresses::init'),
        greaterThan(0),
        reason: 'HD pubkey resolution must scan for new addresses',
      );
      expect(
        script.callsTo('task::account_balance::init'),
        greaterThan(0),
        reason:
            'HD balances resolve through task::account_balance, not '
            'my_balance',
      );
      expect(
        script.callsTo('my_balance'),
        0,
        reason: 'an HD wallet must not fall back to the single-address path',
      );
    });

    test('an iguana sign-in reads balances through my_balance', () async {
      final fixture = KdfWalletFixture()
        ..enableUtxo(_utxoTicker)
        ..balance(_utxoTicker, spendable: '3');
      final script = fixture.build();

      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      await harness.signIn(walletType: KdfWalletType.iguana);
      await harness.measureFirstBalance(_assetFor(harness, _utxoTicker).id);

      expect(script.callsTo('my_balance'), greaterThan(0));
      expect(
        script.callsTo('task::scan_for_new_addresses::init'),
        0,
        reason: 'iguana has a single address; scanning would be pure overhead',
      );
    });
  });

  group('RPC volume', () {
    test('identity RPCs per sign-in are recorded, not asserted', () async {
      final fixture = KdfWalletFixture()
        ..enableUtxo(_utxoTicker)
        ..balance(_utxoTicker);
      final script = fixture.build();

      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      await harness.signIn(walletType: KdfWalletType.hd);

      final identityRpcs = harness.metrics.counters['identity_rpcs_per_signin'];
      expect(
        identityRpcs,
        isNotNull,
        reason: 'sign-in must record identity RPC volume as a metric',
      );
      // Deliberately a sanity bound rather than an exact value: ~480 per login
      // was the field number, and the useful signal is the trend, not a
      // constant that turns every call-site change into a red build.
      expect(identityRpcs, greaterThan(0));
      expect(
        identityRpcs,
        lessThan(480),
        reason:
            'a replay-tier login with one asset should be nowhere near the '
            'production amplification figure; if it is, the amplification is '
            'in the SDK rather than in the app fan-out',
      );

      expect(harness.metrics.counters['rpcs_per_signin'], greaterThan(0));
      expect(harness.metrics.toJson(), contains('counters'));
    });

    test('every method a login touches is countable', () async {
      final fixture = KdfWalletFixture()
        ..enableUtxo(_utxoTicker)
        ..balance(_utxoTicker);
      final script = fixture.build();

      final harness = await KdfHarness.replayed(script: script);
      addTearDown(harness.dispose);

      await harness.signIn(walletType: KdfWalletType.iguana);
      await harness.measureFirstBalance(_assetFor(harness, _utxoTicker).id);

      // The script is an executable record of the login RPC set: an
      // unscripted method throws, so this map cannot silently drift.
      expect(
        script.invocationCounts.keys,
        containsAll(<String>[
          'get_wallet_names',
          'get_public_key_hash',
          'get_enabled_coins',
          'task::enable_utxo::init',
          'task::enable_utxo::status',
          'my_balance',
        ]),
      );
    });
  });
}
