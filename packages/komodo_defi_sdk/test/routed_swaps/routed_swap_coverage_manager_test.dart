import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

void main() {
  group('quote', () {
    test('an answer without a route is a protocol violation', () async {
      final kdf = ScriptedKdf()
        ..always('routed_swap::quote', (_) => ok({'routes': <Object>[]}));

      await expectLater(
        managerFor(kdf).quote(from: usdc, to: usdt, amount: d('100')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('USDC-ERC20 -> USDT-PLG20'),
          ),
        ),
      );
    });

    test('without engine totals, gas is summed per coin', () async {
      final kdf = ScriptedKdf()
        ..always(
          'routed_swap::quote',
          (_) => ok({
            'routes': [
              routeJson(
                totalGasCosts: const [],
                gasCosts: const [
                  {'coin': 'ETH', 'amount': '0.01', 'amount_usd': '20'},
                  {'coin': 'MATIC', 'amount': '0.002', 'amount_usd': '4'},
                  {'coin': 'ETH', 'amount': '0.003', 'amount_usd': '6'},
                ],
                approval: approvalJson(
                  gasCosts: const [
                    {'coin': 'MATIC', 'amount': '0.001'},
                    {'coin': 'MATIC', 'amount': '0.0005', 'amount_usd': '1'},
                  ],
                ),
              ),
            ],
          }),
        );

      final offer = await managerFor(
        kdf,
      ).quote(from: usdc, to: usdt, amount: d('100'));

      // One row without USD voids the coin's USD total for good.
      expect(offer.networkFees, [
        RoutedSwapNetworkFee(
          ticker: 'ETH',
          assetId: eth,
          amount: d('0.013'),
          usdValue: d('26'),
        ),
        RoutedSwapNetworkFee(
          ticker: 'MATIC',
          assetId: matic,
          amount: d('0.0035'),
        ),
      ]);
      expect(offer.costs.map((c) => (c.kind, c.label)), [
        (RoutedSwapCostKind.gas, 'Network fee'),
        (RoutedSwapCostKind.gas, 'Network fee'),
        (RoutedSwapCostKind.gas, 'Network fee'),
        (RoutedSwapCostKind.approvalGas, 'Approval network fee'),
        (RoutedSwapCostKind.approvalGas, 'Approval network fee'),
      ]);
    });

    test(
      'fees in coins the wallet cannot resolve stay apart and named',
      () async {
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::quote',
            (_) => ok({
              'routes': [
                routeJson(
                  feeCosts: const [
                    {
                      'name': 'Relayer fee',
                      'coin': 'FEE-ONE',
                      'amount': '0.25',
                      'included': false,
                    },
                    {
                      'name': 'Bridge fee',
                      'coin': 'FEE-TWO',
                      'amount': '0.1',
                      'included': false,
                    },
                  ],
                ),
              ],
            }),
          );

        final offer = await managerFor(
          kdf,
        ).quote(from: usdc, to: usdt, amount: d('100'));

        expect(offer.additionalFeesByToken, hasLength(2));
        expect(offer.costs.first.tokenLabel, 'FEE-ONE');
      },
    );
  });

  group('maxSellAmount', () {
    test(
      'a native coin without chain decimals keeps the exact reserve',
      () async {
        final bare = coverageAsset('BARE', chainId: 56);
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::quote',
            (_) => ok({
              'routes': [
                routeJson(
                  from: 'BARE',
                  fromAmount: '1',
                  gasCosts: const [
                    {'coin': 'BARE', 'amount': '0.00123'},
                    {'coin': 'ETH', 'amount': '0.5'},
                  ],
                ),
              ],
            }),
          );

        final max = await managerFor(
          kdf,
        ).maxSellAmount(from: bare, to: usdt, balance: d('1'));

        expect(max.reservedForFees, d('0.00369'));
        expect(max.amount, d('0.99631'));
        expect(max.feeAsset, bare);
      },
    );

    test('nothing to sell holds nothing back and names the gas coin', () async {
      final kdf = ScriptedKdf();
      final manager = managerFor(kdf);

      final token = await manager.maxSellAmount(
        from: usdc,
        to: usdt,
        balance: Decimal.zero,
      );
      expect(
        token,
        RoutedSwapMaxSell(
          amount: Decimal.zero,
          reservedForFees: Decimal.zero,
          feeAsset: eth,
        ),
      );
      final native = await manager.maxSellAmount(
        from: eth,
        to: usdt,
        balance: d('-1'),
      );
      expect(native.feeAsset, eth);
      expect(native.amount, Decimal.zero);
      expect(kdf.requests, isEmpty);
    });

    test('a failing probe quote throws its typed error', () async {
      final kdf = ScriptedKdf()
        ..always(
          'routed_swap::quote',
          (_) => rpcError('NoRouteFound', {
            'reasons': ['amount too low'],
          }),
        );
      await expectLater(
        managerFor(kdf).maxSellAmount(from: eth, to: usdt, balance: d('0.01')),
        throwsA(isA<RoutedSwapNoRouteException>()),
      );
    });
  });

  group('start', () {
    test(
      'without first reads, a start missing from history is unconfirmed',
      () async {
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::quote',
            (_) => ok({
              'routes': [routeJson()],
            }),
          )
          ..always('task::routed_swap::init', (_) => ok({'task_id': 7}))
          ..always('routed_swap::history', (_) => historyAnswer(const []));
        final manager = managerFor(kdf, firstReadAttempts: 0);
        final offer = await manager.quote(
          from: usdc,
          to: usdt,
          amount: d('100'),
        );

        await expectLater(
          manager.start(offer),
          throwsA(
            isA<RoutedSwapStartUnconfirmedException>()
                .having((e) => e.taskId, 'taskId', 7)
                .having(
                  (e) => '${e.cause}',
                  'cause',
                  contains('No status for task 7'),
                ),
          ),
        );
        expect(kdf.calls('task::routed_swap::status'), 0);
        final lookup = kdf.paramsFor('routed_swap::history').single;
        expect(lookup['my_coin'], 'USDC-ERC20');
        expect(lookup['other_coin'], 'USDT-PLG20');
        expect(lookup['limit'], 10);
        expect(lookup['from_timestamp'], isA<int>());
      },
    );

    test('a second start of one offer never adopts the first swap', () {
      fakeAsync((async) {
        final first = uuidOf(1);
        final second = uuidOf(2);
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::quote',
            (_) => ok({
              'routes': [routeJson()],
            }),
          )
          ..next('task::routed_swap::init', (_) => ok({'task_id': 1}))
          ..next('task::routed_swap::init', (_) => ok({'task_id': 2}))
          ..always(
            'task::routed_swap::status',
            (params) => params['task_id'] == 2
                ? dropped(params)
                : ok(inProgress(first, 'FetchingQuote')),
          )
          // Both records match the offer; within one second the engine
          // sorts by uuid, so the swap already followed comes first.
          ..always(
            'routed_swap::history',
            (_) => historyAnswer([
              entryJson(inProgress(first, 'FetchingQuote')),
              entryJson(inProgress(second, 'FetchingQuote')),
            ]),
          );
        final manager = managerFor(kdf);
        final offer = awaited(
          async,
          manager.quote(from: usdc, to: usdt, amount: d('100')),
        );

        final a = awaited(async, manager.start(offer));
        final b = awaited(
          async,
          manager.start(offer),
          elapse: const Duration(seconds: 2),
        );

        expect(a.uuid, first);
        expect(b.uuid, second);
        expect(b.latest.createdAt, isNotNull);
        expect(b.latest.acceptedOffer, offer);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });
  });

  group('watch', () {
    test('two screens watching one swap at once share one follow', () {
      fakeAsync((async) {
        final uuid = uuidOf(3);
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::history',
            (_) => historyAnswer([
              entryJson(
                inProgress(
                  uuid,
                  'TrackingBridge',
                  route: routeJson(),
                  stage: 'bridging',
                ),
              ),
            ]),
          );
        final manager = managerFor(kdf);

        final handles = awaited(
          async,
          Future.wait([manager.watch(uuid), manager.watch(uuid)]),
        );

        expect(handles[0].result, same(handles[1].result));
        expect(handles[0].latest, same(handles[1].latest));
        // Two lookups, then one immediate read from the single follower.
        expect(kdf.calls('routed_swap::history'), 3);
        async.elapse(const Duration(seconds: 5));
        expect(kdf.calls('routed_swap::history'), 4);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });
  });

  group('history', () {
    test('a page read while a swap is followed uses what was seen live', () {
      fakeAsync((async) {
        final uuid = uuidOf(4);
        final timedOut = failedWith(
          uuid,
          'SigningRejected',
          data: {'reason': 'timeout'},
          route: routeJson(),
        );
        final kdf = ScriptedKdf()
          ..always('task::routed_swap::status', (_) => ok(timedOut))
          ..always(
            'routed_swap::history',
            (_) => historyAnswer([entryJson(timedOut, finishedAt: 1754784020)]),
          );
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'Signing', route: routeJson()),
        );
        final offer = handle.latest.acceptedOffer;
        async.elapse(const Duration(seconds: 3));
        expect(handle.latest.isTerminal, isTrue);

        final mine = awaited(async, manager.history()).entries.single;
        expect(mine.acceptedOffer, offer);
        expect(mine.failure!.fundsMovement, RoutedSwapFundsMovement.none);
        expect(mine.failure!.retryPolicy, RoutedSwapRetryPolicy.retry);

        // Without the live observation a timeout may have broadcast.
        final cold = awaited(async, managerFor(kdf).history()).entries.single;
        expect(cold.acceptedOffer, isNull);
        expect(cold.failure!.fundsMovement, RoutedSwapFundsMovement.uncertain);
        expect(cold.failure!.retryPolicy, RoutedSwapRetryPolicy.wait);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });

    test('inFlight reads at most twenty pages', () async {
      final kdf = ScriptedKdf()
        ..always('routed_swap::history', (params) {
          final page = params['page_number'] as int;
          return historyAnswer(
            [entryJson(inProgress(uuidOf(page), 'TrackingBridge'))],
            total: 99,
            page: page,
            totalPages: 99,
          );
        });

      final running = await managerFor(kdf).inFlight(pageSize: 1);

      expect(running, hasLength(20));
      expect(kdf.calls('routed_swap::history'), 20);
      expect(kdf.paramsFor('routed_swap::history').last, {
        'status_filter': 'in_flight',
        'limit': 1,
        'page_number': 20,
      });
    });
  });
}
