import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

/// The accepted provider minimum reaches execution without an extra margin.
void main() {
  ScriptedKdf quoting(String toMin, {String to = 'USDT-PLG20'}) => ScriptedKdf()
    ..always(
      'routed_swap::quote',
      (_) => ok({
        'routes': [routeJson(to: to, toMin: toMin)],
      }),
    );

  group('a quote', () {
    test("keeps the provider's minimum exactly", () async {
      final offer = await managerFor(
        quoting('99.123457'),
      ).quote(from: usdc, to: usdt, amount: d('100'));

      expect(offer.guaranteedReceive, d('99.123457'));
      expect(offer.route.toMinimum.amount, '99.123457');
    });

    test("keeps the provider's minimum when there is no margin", () async {
      final offer = await managerFor(
        quoting('99.123457'),
      ).quote(from: usdc, to: usdt, amount: d('100'));

      expect(offer.guaranteedReceive, d('99.123457'));
    });

    test("without known decimals, keeps the minimum's own places", () async {
      final odd = coverageAsset('ODD-PLG20', chainId: 137, parent: matic);
      final offer = await managerFor(
        quoting('12.34', to: 'ODD-PLG20'),
        resolve: (ticker) => ticker == 'ODD-PLG20' ? odd : knownAssets[ticker],
      ).quote(from: usdc, to: odd, amount: d('100'));

      expect(offer.guaranteedReceive, d('12.34'));
    });

    test('keeps a minimum too small to lose anything whole', () async {
      final offer = await managerFor(
        quoting('0.000001'),
      ).quote(from: usdc, to: usdt, amount: d('0.000002'));

      expect(offer.guaranteedReceive, d('0.000001'));
    });
  });

  group('keeping a minimum already shown', () {
    Future<RoutedSwapOffer> offer() => managerFor(
      quoting('99.123457'),
    ).quote(from: usdc, to: usdt, amount: d('100'));

    test('keeps one the route still clears, and only that', () async {
      final fresh = await offer();

      final kept = fresh.keepingMinimum(d('99'))!;

      expect(kept.guaranteedReceive, d('99.123457'));
      expect(kept.route, same(fresh.route));
      expect(kept.expectedReceive, fresh.expectedReceive);
      expect(kept.quotedAt, fresh.quotedAt);
    });

    test("keeps one equal to the provider's minimum", () async {
      final kept = (await offer()).keepingMinimum(d('99.123457'))!;

      expect(kept.guaranteedReceive, d('99.123457'));
    });

    test('refuses one the route no longer clears', () async {
      expect((await offer()).keepingMinimum(d('99.123458')), isNull);
    });

    test("never loosens the offer's own guard", () async {
      final fresh = await offer();

      expect(fresh.keepingMinimum(d('98.5')), same(fresh));
      expect(fresh.keepingMinimum(d('99.123457')), same(fresh));
    });

    test('start guards with the minimum kept', () {
      fakeAsync((async) {
        final kdf = quoting('99.123457')
          ..next('task::routed_swap::init', (_) => ok({'task_id': 1}))
          ..always(
            'task::routed_swap::status',
            (_) => ok(inProgress(uuidOf(1), 'FetchingQuote')),
          );
        final manager = managerFor(kdf);
        final fresh = awaited(
          async,
          manager.quote(from: usdc, to: usdt, amount: d('100')),
        );

        awaited(async, manager.start(fresh.keepingMinimum(d('99'))!));

        expect(
          kdf.paramsFor('task::routed_swap::init').single['min_to_amount'],
          '99.123457',
        );
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
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
      expect(offer.guaranteedReceive, d('99.123457'));
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
