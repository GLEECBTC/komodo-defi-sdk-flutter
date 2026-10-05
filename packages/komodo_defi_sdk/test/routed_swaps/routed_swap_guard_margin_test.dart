import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

/// Covers the guard an offer carries. `init` quotes again and refuses a fresh
/// minimum below the guard; a guard equal to the provider's minimum failed
/// six starts in seven on a Relay route (2026-10-05), so an offer guards, and
/// shows, a minimum slightly below the provider's.
void main() {
  ScriptedKdf quoting(String toMin, {String to = 'USDT-PLG20'}) => ScriptedKdf()
    ..always(
      'routed_swap::quote',
      (_) => ok({
        'routes': [routeJson(to: to, toMin: toMin)],
      }),
    );

  group('a quote', () {
    test(
      "guards 0.3% below the provider's minimum, to the decimals",
      () async {
        final offer = await managerFor(
          quoting('99.123457'),
        ).quote(from: usdc, to: usdt, amount: d('100'));

        // 99.123457 × 0.997 = 98.826086629, rounded down to 6 places.
        expect(offer.guaranteedReceive, d('98.826086'));
        expect(offer.route.toMinimum.amount, '99.123457');
      },
    );

    test("keeps the provider's minimum when there is no margin", () async {
      final offer = await managerFor(
        quoting('99.123457'),
        guardMargin: Decimal.zero,
      ).quote(from: usdc, to: usdt, amount: d('100'));

      expect(offer.guaranteedReceive, d('99.123457'));
    });

    test("without known decimals, keeps the minimum's own places", () async {
      final odd = coverageAsset('ODD-PLG20', chainId: 137, parent: matic);
      final offer = await managerFor(
        quoting('12.34', to: 'ODD-PLG20'),
        resolve: (ticker) => ticker == 'ODD-PLG20' ? odd : knownAssets[ticker],
      ).quote(from: usdc, to: odd, amount: d('100'));

      // 12.34 × 0.997 = 12.30298, rounded down to 2 places.
      expect(offer.guaranteedReceive, d('12.3'));
    });

    test('keeps a minimum too small to lose anything whole', () async {
      final offer = await managerFor(
        quoting('0.000001'),
      ).quote(from: usdc, to: usdt, amount: d('0.000002'));

      expect(offer.guaranteedReceive, d('0.000001'));
    });
  });

  test('start guards with exactly the number the offer shows', () {
    fakeAsync((async) {
      final kdf = quoting('99.123457')
        ..next('task::routed_swap::init', (_) => ok({'task_id': 1}))
        ..always(
          'task::routed_swap::status',
          (_) => ok(inProgress(uuidOf(1), 'FetchingQuote')),
        );
      final manager = managerFor(kdf);
      final offer = awaited(
        async,
        manager.quote(from: usdc, to: usdt, amount: d('100')),
      );

      awaited(async, manager.start(offer));

      expect(
        kdf.paramsFor('task::routed_swap::init').single['min_to_amount'],
        offer.guaranteedReceive.toString(),
      );
      expect(offer.guaranteedReceive, d('98.826086'));
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
