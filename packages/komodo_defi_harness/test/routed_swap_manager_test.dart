@Timeout(Duration(seconds: 30))
library;

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Drives [RoutedSwapManager] against the scripted KDF.
///
/// The manager absorbs the parts of the contract that are easy to get wrong:
/// resolving the durable uuid before handing out a handle, never destroying a
/// terminal result before reading it, treating the event stream as a hint,
/// recovering a vanished task from history, and saying honestly whether the
/// user's funds moved. None of that is visible from the type signatures, so
/// each is asserted here.
void main() {
  final matic = _asset('MATIC', chainId: 137, decimals: 18);
  final usdt = _asset('USDT-PLG20', chainId: 137, parent: matic, decimals: 6);
  final eth = _asset('ETH', chainId: 1, decimals: 18);
  final usdc = _asset('USDC-ERC20', chainId: 1, parent: eth, decimals: 6);
  final low = _asset('LOW', chainId: 137, decimals: 4);
  final assets = {
    for (final a in [matic, usdt, eth, usdc, low]) a.id: a,
  };

  RoutedSwapQuote route({
    String from = 'USDT-PLG20',
    String to = 'USDC-ERC20',
    RoutedSwapQuoteApproval? approval,
    bool crossChain = true,
    List<RoutedSwapQuoteGas> gasCosts = const [
      RoutedSwapQuoteGas(coin: 'MATIC', amount: '0.012', amountUsd: '0.01'),
    ],
  }) => RoutedSwapQuote(
    from: from,
    to: to,
    toAmount: '100.21',
    toAmountMin: '99.71',
    crossChain: crossChain,
    approval: approval,
    gasCosts: gasCosts,
  );

  const approval = RoutedSwapQuoteApproval.noAllowance(
    gasCoin: 'MATIC',
    gasAmount: '0.0009',
  );

  RoutedSwapManager managerFor(
    _Client client, {
    RoutedSwapTaskNudges? nudges,
    Duration pollInterval = const Duration(milliseconds: 5),
  }) {
    final manager = RoutedSwapManager(
      client: client,
      resolveAsset: (ticker) => assets[ticker],
      taskNudges: nudges,
      pollInterval: pollInterval,
      historyPollInterval: const Duration(milliseconds: 5),
      maxBackoff: const Duration(milliseconds: 20),
      firstReadRetryDelay: const Duration(milliseconds: 1),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  Future<RoutedSwapOffer> offerFrom(RoutedSwapManager manager) =>
      manager.quote(from: usdt, to: usdc, amount: Decimal.parse('100.5'));

  /// Starts [run] against the scripted route and returns the handle.
  Future<(RoutedSwapHandle, RoutedSwapFixture, _Client)> started(
    RoutedSwapRun run, {
    RoutedSwapQuote? quoted,
    Duration pollInterval = const Duration(milliseconds: 5),
    RoutedSwapTaskNudges? nudges,
  }) async {
    final fixture = RoutedSwapFixture()
      ..quote(quoted ?? route())
      ..run(run);
    final client = _Client(fixture.build());
    final manager = managerFor(
      client,
      pollInterval: pollInterval,
      nudges: nudges,
    );
    final handle = await manager.start(await offerFrom(manager));
    return (handle, fixture, client);
  }

  Future<RoutedSwapProgress> until(
    RoutedSwapHandle handle,
    bool Function(RoutedSwapProgress) test,
  ) => handle.progress.firstWhere(test).timeout(_timeout);

  group('eligibleAssets', () {
    test('lists only supported coins the wallet can resolve', () async {
      final fixture = RoutedSwapFixture()
        ..supportedCoin('USDT-PLG20', chainId: 137)
        ..supportedCoin('USDC-ERC20', chainId: 1)
        ..supportedCoin('FEE-INACTIVE', chainId: 137);
      final manager = managerFor(_Client(fixture.build()));

      expect(await manager.eligibleAssets(), {usdt, usdc});
    });
  });

  group('quote', () {
    late RoutedSwapOffer offer;
    late _Client client;

    setUp(() async {
      final fixture = RoutedSwapFixture()
        ..quote(
          RoutedSwapQuote(
            from: 'USDT-PLG20',
            to: 'USDC-ERC20',
            toAmount: '100.21',
            toAmountMin: '99.71',
            toolLogoUrl: 'https://li.fi/stargate.png',
            approval: approval,
            steps: const [
              RoutedSwapQuoteStep.swap(tool: '1inch', chainId: 137),
              RoutedSwapQuoteStep.cross(
                tool: 'stargateV2',
                fromChainId: 137,
                toChainId: 1,
              ),
            ],
            feeCosts: [
              RoutedSwapQuoteFee(
                name: 'LIFI Fixed Fee',
                coin: 'USDT-PLG20',
                amount: '0.05',
                amountUsd: '0.05',
                included: true,
              ),
              RoutedSwapQuoteFee(
                name: 'Bridge fee',
                symbol: 'axlUSDC',
                amount: '0.02',
                included: false,
              ),
              RoutedSwapQuoteFee(
                name: 'Protocol fee',
                coin: 'USDT-PLG20',
                amount: '0.1',
                included: false,
              ),
            ],
            gasCosts: const [
              RoutedSwapQuoteGas(
                coin: 'MATIC',
                amount: '0.012',
                amountUsd: '0.01',
              ),
              RoutedSwapQuoteGas(
                coin: 'ETH',
                amount: '0.001',
                amountUsd: '2.5',
              ),
            ],
          ),
        );
      client = _Client(fixture.build());
      offer = await managerFor(client).quote(
        from: usdt,
        to: usdc,
        amount: Decimal.parse('100.5'),
        slippage: 0.01,
        order: RoutedSwapOrder.fastest,
      );
    });

    test('separates the guaranteed receive from the expected one', () {
      expect(offer.from, usdt);
      expect(offer.to, usdc);
      expect(offer.sellAmount, Decimal.parse('100.5'));
      expect(offer.expectedReceive, Decimal.parse('100.21'));
      expect(offer.guaranteedReceive, Decimal.parse('99.71'));
      expect(offer.slippageAllowance, Decimal.parse('0.5'));
      expect(offer.kind, RoutedSwapRouteKind.crossChain);
      expect(offer.isCrossChain, isTrue);
    });

    test('carries order, slippage, tool, legs and addresses', () {
      expect(offer.order, RoutedSwapOrder.fastest);
      expect(offer.slippage, 0.01);
      expect(offer.provider, 'lifi');
      expect(offer.toolKey, 'stargateV2');
      expect(offer.toolLogoUrl, 'https://li.fi/stargate.png');
      expect(offer.estimatedDuration, const Duration(seconds: 95));
      expect(offer.fromAddress, RoutedSwapQuote.defaultAddress);
      expect(offer.toAddress, offer.fromAddress);
      expect(offer.legs.map((l) => l.type), [
        RoutedSwapStepType.swap,
        RoutedSwapStepType.cross,
      ]);
      expect(offer.legs.first.chainId, 137);
      expect(
        [offer.legs.last.fromChainId, offer.legs.last.toChainId],
        [137, 1],
      );
      final params = client.paramsFor('routed_swap::quote').single;
      expect(params['order'], 'fastest');
      expect(params['slippage'], 0.01);
    });

    test('describes the approval', () {
      expect(offer.requiresApproval, isTrue);
      expect(offer.approval!.txCount, 1);
      expect(offer.approval!.resetsFirst, isFalse);
      expect(offer.approval!.spender, RoutedSwapQuoteApproval.lifiDiamond);
    });

    test('reconciles fees, execution gas and approval gas', () {
      expect(offer.costs.map((c) => c.kind), [
        RoutedSwapCostKind.providerFee,
        RoutedSwapCostKind.providerFee,
        RoutedSwapCostKind.providerFee,
        RoutedSwapCostKind.gas,
        RoutedSwapCostKind.gas,
        RoutedSwapCostKind.approvalGas,
      ]);
      final symbolFee = offer.costs[1];
      expect(symbolFee.assetId, isNull);
      expect(symbolFee.symbol, 'axlUSDC');
      expect(symbolFee.tokenLabel, 'axlUSDC');
      expect(offer.costs.first.isDeductedFromReceive, isTrue);
      expect(offer.costs.last.usdValue, isNull);
      // Included fees are already inside the receive amount; a provider
      // symbol never merges with a wallet asset.
      expect(offer.additionalFeesByToken, {
        'USDT-PLG20': Decimal.parse('0.1'),
        'symbol:axlUSDC': Decimal.parse('0.02'),
      });
    });

    test('network fees omit USD for the coin paying approval gas', () {
      final byTicker = {for (final f in offer.networkFees) f.ticker: f};
      expect(byTicker.keys, ['MATIC', 'ETH']);
      expect(byTicker['MATIC']!.amount, Decimal.parse('0.0129'));
      expect(byTicker['MATIC']!.usdValue, isNull);
      expect(byTicker['MATIC']!.assetId, matic);
      expect(byTicker['ETH']!.usdValue, Decimal.parse('2.5'));
    });

    test('typed quote errors propagate', () async {
      final fixture = RoutedSwapFixture()
        ..quoteFails(
          'USDT-PLG20',
          'USDC-ERC20',
          RoutedSwapQuoteError.noRouteFound(
            reasons: const ['Amount too low (across)'],
            providerRequestId: 'req-1',
          ),
          times: 1,
        )
        ..quoteFails(
          'USDT-PLG20',
          'USDC-ERC20',
          RoutedSwapQuoteError.rateLimited(),
        );
      final manager = managerFor(_Client(fixture.build()));

      await expectLater(
        offerFrom(manager),
        throwsA(
          isA<RoutedSwapNoRouteException>()
              .having((e) => e.reasons, 'reasons', ['Amount too low (across)'])
              .having((e) => e.providerRequestId, 'providerRequestId', 'req-1'),
        ),
      );
      await expectLater(
        offerFrom(manager),
        throwsA(
          isA<RoutedSwapRateLimitedException>().having(
            (e) => e.isTransient,
            'isTransient',
            isTrue,
          ),
        ),
      );
    });
  });

  group('maxSellAmount', () {
    test('a token sells its whole balance; gas is the parent coin', () async {
      final client = _Client(RoutedSwapFixture().build());
      final max = await managerFor(
        client,
      ).maxSellAmount(from: usdt, to: usdc, balance: Decimal.parse('250'));
      expect(max.amount, Decimal.parse('250'));
      expect(max.reservedForFees, Decimal.zero);
      expect(max.feeAsset, matic);
      expect(client.requestsFor('routed_swap::quote'), isEmpty);
    });

    test('a native sell holds back 1.25x its network fee', () async {
      final fixture = RoutedSwapFixture()
        ..quote(
          route(
            from: 'LOW',
            gasCosts: const [
              RoutedSwapQuoteGas(coin: 'LOW', amount: '0.0013'),
              RoutedSwapQuoteGas(coin: 'ETH', amount: '0.001'),
            ],
          ),
        );
      final client = _Client(fixture.build());
      final max = await managerFor(
        client,
      ).maxSellAmount(from: low, to: usdc, balance: Decimal.one);
      // 0.0013 * 1.25 = 0.001625, ceiled to 4 decimals; the rest floored.
      expect(max.reservedForFees, Decimal.parse('0.0017'));
      expect(max.amount, Decimal.parse('0.9983'));
      expect(max.feeAsset, low);
      expect(client.paramsFor('routed_swap::quote').single['amount'], '1');
    });

    test('an empty balance, or one below the fee, sells nothing', () async {
      final fixture = RoutedSwapFixture()
        ..quote(
          route(
            from: 'LOW',
            gasCosts: const [RoutedSwapQuoteGas(coin: 'LOW', amount: '0.0013')],
          ),
        );
      final manager = managerFor(_Client(fixture.build()));
      final empty = await manager.maxSellAmount(
        from: low,
        to: usdc,
        balance: Decimal.zero,
      );
      expect(empty.amount, Decimal.zero);
      final dust = await manager.maxSellAmount(
        from: low,
        to: usdc,
        balance: Decimal.parse('0.001'),
      );
      expect(dust.amount, Decimal.zero);
    });
  });

  group('start', () {
    test('resolves the uuid and sends the offer the user saw', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun(autoAdvance: false));
      final client = _Client(fixture.build());
      final manager = managerFor(client);
      final offer = await manager.quote(
        from: usdt,
        to: usdc,
        amount: Decimal.parse('100.5'),
        slippage: 0.01,
        order: RoutedSwapOrder.fastest,
      );

      final handle = await manager.start(offer);

      expect(handle.uuid, fixture.uuidOf(1));
      expect(handle.latest.acceptedOffer, offer);
      expect(handle.latest.phase, RoutedSwapPhase.preparing);
      expect(handle.latest.canCancel, isTrue);
      expect(client.paramsFor('task::routed_swap::init').single, {
        'from': 'USDT-PLG20',
        'to': 'USDC-ERC20',
        'amount': '100.5',
        // The guaranteed receive: the expected one would fail nearly every
        // swap QuoteWorsened.
        'min_to_amount': '99.71',
        'slippage': 0.01,
        'order': 'fastest',
        'provider': 'lifi',
      });
    });

    test('retries a failed first status read', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun(autoAdvance: false));
      final client = _Client(fixture.build())
        ..failNext('task::routed_swap::status');
      final manager = managerFor(client);

      final handle = await manager.start(await offerFrom(manager));

      expect(handle.uuid, fixture.uuidOf(1));
      expect(client.requestsFor('task::routed_swap::status').length, 2);
    });

    test('falls back to the durable record when reads keep failing', () async {
      final fixture = RoutedSwapFixture(clock: RoutedSwapFixture.wallClock)
        ..quote(route())
        ..run(RoutedSwapRun());
      final client = _Client(fixture.build())
        ..failNext('task::routed_swap::status', times: 3);
      final manager = managerFor(client);

      final handle = await manager.start(await offerFrom(manager));

      expect(handle.uuid, fixture.uuidOf(1));
      expect(handle.latest.createdAt, isNotNull);
      // The task id is still followed once reads recover.
      final result = await handle.result.timeout(_timeout);
      expect(result.isSuccess, isTrue);
    });

    test('an unrecoverable start is unconfirmed, never retried', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun());
      final client = _Client(fixture.build())
        ..failNext('task::routed_swap::status', times: 3)
        ..failNext('routed_swap::history');
      final manager = managerFor(client);

      await expectLater(
        manager.start(await offerFrom(manager)),
        throwsA(
          isA<RoutedSwapStartUnconfirmedException>().having(
            (e) => e.taskId,
            'taskId',
            1,
          ),
        ),
      );
      // The engine did start it.
      expect(fixture.historyEntries, hasLength(1));
    });

    test('a lost init request is unconfirmed without a task id', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun());
      final client = _Client(fixture.build())
        ..failNext('task::routed_swap::init');
      final manager = managerFor(client);

      await expectLater(
        manager.start(await offerFrom(manager)),
        throwsA(
          isA<RoutedSwapStartUnconfirmedException>().having(
            (e) => e.taskId,
            'taskId',
            isNull,
          ),
        ),
      );
    });

    test('a pre-task rejection rethrows the typed error', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..initFails(RoutedSwapQuoteError.coinNotActive('USDC-ERC20'));
      final manager = managerFor(_Client(fixture.build()));

      await expectLater(
        manager.start(await offerFrom(manager)),
        throwsA(
          isA<RoutedSwapCoinNotActiveException>().having(
            (e) => e.coin,
            'coin',
            'USDC-ERC20',
          ),
        ),
      );
      expect(fixture.historyEntries, isEmpty);
    });

    test(
      'a first read that is already terminal is enriched and forgotten',
      () async {
        final (handle, fixture, client) = await started(
          RoutedSwapRun(advanceOnInit: 100),
        );
        final result = await handle.result.timeout(_timeout);
        await _settle();

        expect(result.isSuccess, isTrue);
        expect(result.createdAt, isNotNull, reason: 'not enriched');
        expect(
          fixture.hasTask(1),
          isFalse,
          reason: 'the terminal result was never released',
        );
      },
    );
  });

  group('progress', () {
    test('listeners share one follow; a late one gets the latest', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      final early = <RoutedSwapProgress>[];
      final done = Completer<void>();
      handle.progress.listen(early.add, onDone: done.complete);

      await until(handle, (p) => p.phase == RoutedSwapPhase.bridging);
      final seen = handle.latest;
      final late = await handle.progress.first.timeout(_timeout);
      expect(late, same(seen));

      await done.future.timeout(_timeout);
      expect(early.first.phase, RoutedSwapPhase.preparing);
      expect(early.last.isTerminal, isTrue);
      expect(early.last, await handle.result);
      expect(
        early.map((p) => p.phase).toSet(),
        containsAll([
          RoutedSwapPhase.preparing,
          RoutedSwapPhase.signing,
          RoutedSwapPhase.sending,
          RoutedSwapPhase.confirming,
          RoutedSwapPhase.bridging,
          RoutedSwapPhase.finished,
        ]),
      );
    });

    test('the stream ends at the terminal snapshot', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      final all = await handle.progress.toList().timeout(_timeout);
      expect(all.last.isTerminal, isTrue);
      expect(all.where((p) => p.isTerminal), hasLength(1));
      expect(await handle.result, all.last);
      // A listener after the end still gets the final snapshot.
      expect(await handle.progress.toList(), [all.last]);
    });

    test('polling carries on with nobody listening', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      final result = await handle.result.timeout(_timeout);
      expect(result.phase, RoutedSwapPhase.finished);
    });

    test('unchanged FetchingQuote polls do not re-emit', () async {
      final (handle, _, client) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      final seen = <RoutedSwapProgress>[];
      final sub = handle.progress.listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        client.requestsFor('task::routed_swap::status').length,
        greaterThan(5),
      );
      expect(seen, [handle.latest]);
    });

    test('unchanged polls with an executed route do not re-emit', () async {
      final (handle, _, _) = await started(RoutedSwapRun(pollsPerState: 3));
      final all = await handle.progress.toList().timeout(_timeout);
      final keys = [for (final p in all) _key(p)];
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i], isNot(keys[i - 1]), reason: 'emission $i repeats');
      }
    });

    test('a nudge refreshes before the poll interval', () async {
      final nudges = StreamController<void>.broadcast();
      addTearDown(nudges.close);
      final (handle, _, _) = await started(
        RoutedSwapRun(),
        pollInterval: const Duration(minutes: 1),
        nudges: (_) => nudges.stream,
      );
      expect(handle.latest.rawState, 'FetchingQuote');

      nudges.add(null);
      final next = await until(handle, (p) => p.rawState != 'FetchingQuote');
      expect(next.rawState, 'CheckingAllowance');
    });

    test('a broken event stream does not stop the swap', () async {
      final (handle, _, _) = await started(
        RoutedSwapRun(),
        nudges: (_) => Stream<void>.error(StateError('sse down')),
      );
      expect((await handle.result.timeout(_timeout)).isSuccess, isTrue);
    });
  });

  group('reconciliation', () {
    test('a vanished task is followed through history', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.advance(1, steps: 5);
      await until(handle, (p) => p.phase == RoutedSwapPhase.bridging);

      fixture.restartKdf();
      final recovered = await until(handle, (p) => p.createdAt != null);
      expect(recovered.isTerminal, isFalse);
      expect(recovered.canCancel, isFalse);
      expect(recovered.phase, RoutedSwapPhase.bridging);

      fixture.finishPersisted(handle.uuid);
      final result = await handle.result.timeout(_timeout);
      expect(result.isSuccess, isTrue);
      expect(result.finishedAt, isNotNull);
    });

    test('failing reads back off, flag a delay, then clear it', () async {
      final (handle, fixture, client) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      final seen = <RoutedSwapProgress>[];
      final sub = handle.progress.listen(seen.add);
      addTearDown(sub.cancel);
      fixture.statusFailsInternally(times: 4);

      await until(handle, (p) => p.delayedSince != null);
      final reads = client.requestsFor('task::routed_swap::status').length;
      await until(handle, (p) => p.delayedSince == null);

      expect(reads, greaterThanOrEqualTo(4));
      expect(seen.where((p) => p.delayedSince != null), hasLength(1));
      expect(handle.latest.phase, RoutedSwapPhase.preparing);
      expect(handle.latest.isTerminal, isFalse);
    });

    test('a terminal read is enriched from history, then forgotten', () async {
      final (handle, fixture, client) = await started(
        RoutedSwapRun(approvalGas: '0.001', sourceGas: '0.002'),
        quoted: route(
          approval: const RoutedSwapQuoteApproval.zeroReset(
            gasCoin: 'MATIC',
            gasAmount: '0.0018',
          ),
        ),
      );
      final result = await handle.result.timeout(_timeout);
      await _settle();

      expect(result.createdAt, isNotNull);
      expect(result.updatedAt, isNotNull);
      expect(result.finishedAt, isNotNull);
      expect(result.approvalTxHashes, hasLength(2));
      expect(result.approvalTxHash, result.approvalTxHashes.last);
      expect(result.gasSpent.map((g) => g.amount), [
        Decimal.parse('0.001'),
        Decimal.parse('0.001'),
        Decimal.parse('0.002'),
      ]);
      expect(result.gasSpent.first.assetId, matic);
      expect(result.totalGasSpent.single.amount, Decimal.parse('0.004'));
      expect(result.requested!.from, usdt);
      expect(result.requested!.amount, Decimal.parse('100.5'));
      expect(result.minToAmountAccepted, Decimal.parse('99.71'));

      expect(client.paramsFor('task::routed_swap::status').last, {
        'task_id': 1,
        'forget_if_finished': true,
      });
      expect(fixture.hasTask(1), isFalse);
    });

    test(
      'a task id reused after a restart never adopts another swap',
      () async {
        final fixture = RoutedSwapFixture()
          ..quote(route())
          ..run(RoutedSwapRun(autoAdvance: false))
          ..run(RoutedSwapRun(autoAdvance: false));
        final script = fixture.build();
        final manager = managerFor(
          _Client(script),
          pollInterval: const Duration(milliseconds: 30),
        );
        final first = await manager.start(await offerFrom(manager));
        fixture.advance(1, steps: 5);
        await until(first, (p) => p.phase == RoutedSwapPhase.bridging);

        fixture.restartKdf();
        // Another client starts a swap: the engine hands out id 1 again.
        await script.respondTo({
          'method': 'task::routed_swap::init',
          'params': {
            'from': 'USDT-PLG20',
            'to': 'USDC-ERC20',
            'amount': '1',
            'min_to_amount': '0.9',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(first.latest.uuid, first.uuid);
        expect(first.latest.phase, RoutedSwapPhase.bridging);
      },
    );
  });

  group('cancel', () {
    test('accepted before broadcast: cancelled, funds untouched', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      await handle.cancel();

      final latest = handle.latest;
      expect(latest.phase, RoutedSwapPhase.failed);
      expect(latest.failure!.kind, RoutedSwapFailureKind.cancelled);
      expect(latest.failure!.errorType, 'TaskCancelled');
      expect(latest.failure!.fundsMovement, RoutedSwapFundsMovement.none);
      expect(latest.failure!.retryPolicy, RoutedSwapRetryPolicy.retry);
      expect(await handle.result.timeout(_timeout), latest);
      expect(fixture.hasTask(1), isFalse);
    });

    test('accepted after an approval: only fees were spent', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        quoted: route(approval: approval),
      );
      fixture.advance(1, steps: 3);
      await until(handle, (p) => p.approvalTxHashes.isNotEmpty);

      await handle.cancel();

      final failure = handle.latest.failure!;
      expect(failure.kind, RoutedSwapFailureKind.cancelled);
      expect(failure.fundsMovement, RoutedSwapFundsMovement.feesOnly);
      expect(handle.latest.approvalTxHashes, hasLength(1));
    });

    test('refused by KDF once broadcast began', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        pollInterval: const Duration(minutes: 1),
      );
      fixture.advance(1, steps: 3);
      expect(handle.latest.canCancel, isTrue, reason: 'not yet re-read');

      await expectLater(
        handle.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.alreadyBroadcast,
          ),
        ),
      );
    });

    test('refused by KDF once the task finished', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        pollInterval: const Duration(minutes: 1),
      );
      fixture.advance(1, steps: 100);

      await expectLater(
        handle.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.alreadyFinished,
          ),
        ),
      );
    });

    test('refused locally once the snapshot is past broadcast', () async {
      final (handle, fixture, client) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.advance(1, steps: 3);
      await until(handle, (p) => p.phase == RoutedSwapPhase.sending);

      await expectLater(
        handle.cancel(),
        throwsA(isA<RoutedSwapNotCancellableException>()),
      );
      expect(client.requestsFor('task::routed_swap::cancel'), isEmpty);
    });

    test('a finished swap refuses as alreadyFinished', () async {
      final (handle, _, _) = await started(RoutedSwapRun());
      await handle.result.timeout(_timeout);
      await expectLater(
        handle.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.alreadyFinished,
          ),
        ),
      );
    });

    test('NoSuchTask after an earlier cancel counts as done', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun(autoAdvance: false));
      final script = fixture.build();
      final manager = managerFor(
        _Client(script),
        pollInterval: const Duration(minutes: 1),
      );
      final handle = await manager.start(await offerFrom(manager));
      // Another client, or an earlier attempt whose answer was lost.
      await script.respondTo({
        'method': 'task::routed_swap::cancel',
        'params': {'task_id': 1},
      });

      await handle.cancel();
      expect(handle.latest.failure!.kind, RoutedSwapFailureKind.cancelled);
    });

    test('a history-only handle has nothing to cancel', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.advance(1, steps: 5);
      await until(handle, (p) => p.phase == RoutedSwapPhase.bridging);
      fixture.restartKdf();

      // A fresh app session finds the swap by its uuid.
      final watched = await managerFor(
        _Client(fixture.build()),
      ).watch(handle.uuid);
      expect(watched.latest.canCancel, isFalse);
      await expectLater(
        watched.cancel(),
        throwsA(
          isA<RoutedSwapNotCancellableException>().having(
            (e) => e.refusal,
            'refusal',
            RoutedSwapCancelRefusal.notAddressable,
          ),
        ),
      );
    });

    test('an unanswered cancel is unconfirmed', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
        pollInterval: const Duration(minutes: 1),
      );
      fixture.cancelFailsInternally();
      await expectLater(
        handle.cancel(),
        throwsA(isA<RoutedSwapCancelUnconfirmedException>()),
      );
    });
  });

  group('watch', () {
    test('returns the live session for a swap already followed', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun(autoAdvance: false));
      final manager = managerFor(_Client(fixture.build()));
      final handle = await manager.start(await offerFrom(manager));

      final watched = await manager.watch(handle.uuid);
      expect(watched.uuid, handle.uuid);
      expect(watched.latest, same(handle.latest));

      fixture.advance(1, steps: 100);
      expect(
        await watched.result.timeout(_timeout),
        same(await handle.result.timeout(_timeout)),
      );
    });

    test('replays a finished swap, then ends', () async {
      final (handle, fixture, _) = await started(RoutedSwapRun());
      await handle.result.timeout(_timeout);

      final watched = await managerFor(
        _Client(fixture.build()),
      ).watch(handle.uuid);
      final all = await watched.progress.toList().timeout(_timeout);
      expect(all, hasLength(1));
      expect(all.single.isSuccess, isTrue);
      expect(all.single.acceptedOffer, isNull);
      expect(all.single.executedOffer!.from, usdt);
    });

    test('follows an in-flight swap after a restart to its end', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.advance(1, steps: 5);
      await until(handle, (p) => p.phase == RoutedSwapPhase.bridging);
      fixture.restartKdf();

      final watched = await managerFor(
        _Client(fixture.build()),
      ).watch(handle.uuid);
      expect(watched.latest.phase, RoutedSwapPhase.bridging);
      expect(watched.latest.canCancel, isFalse);

      fixture.finishPersisted(handle.uuid);
      final result = await watched.result.timeout(_timeout);
      expect(result.receipt!.outcome, RoutedSwapOutcome.completed);
    });

    test('throws NotFound for an unknown swap', () async {
      final manager = managerFor(_Client(RoutedSwapFixture().build()));
      await expectLater(
        manager.watch('00000000-0000-4000-8000-00000000abcd'),
        throwsA(isA<RoutedSwapNotFoundException>()),
      );
    });

    test('a malformed uuid is the engine rejecting the request', () async {
      final manager = managerFor(_Client(RoutedSwapFixture().build()));
      await expectLater(
        manager.watch('nope'),
        throwsA(
          isA<RoutedSwapRpcException>().having(
            (e) => e.errorType,
            'errorType',
            'InvalidRequest',
          ),
        ),
      );
    });
  });

  group('history', () {
    Future<(RoutedSwapManager, _Client)> withSwaps({
      int inFlight = 0,
      int finished = 0,
    }) async {
      final fixture = RoutedSwapFixture()..quote(route());
      final script = fixture.build();
      Future<int> init() async {
        final response = await script.respondTo({
          'method': 'task::routed_swap::init',
          'params': {
            'from': 'USDT-PLG20',
            'to': 'USDC-ERC20',
            'amount': '100.5',
            'min_to_amount': '99.71',
          },
        });
        return (response!['result'] as Map<String, dynamic>)['task_id'] as int;
      }

      for (var i = 0; i < finished; i++) {
        fixture.run(RoutedSwapRun());
        final taskId = await init();
        fixture.advance(taskId, steps: 100);
      }
      for (var i = 0; i < inFlight; i++) {
        fixture.run(RoutedSwapRun());
        await init();
      }
      final client = _Client(script);
      return (managerFor(client), client);
    }

    test('pages newest first', () async {
      final (manager, _) = await withSwaps(inFlight: 5);
      final first = await manager.history(limit: 2);
      expect(first.entries, hasLength(2));
      expect(first.total, 5);
      expect(first.totalPages, 3);
      expect(first.hasMore, isTrue);
      expect(first.entries.first.uuid, _uuid(5));
      expect(first.entries.first.canCancel, isFalse);

      final last = await manager.history(limit: 2, pageNumber: 3);
      expect(last.entries.single.uuid, _uuid(1));
      expect(last.hasMore, isFalse);
    });

    test('inFlight gathers every page', () async {
      final (manager, client) = await withSwaps(inFlight: 3, finished: 2);
      final running = await manager.inFlight(pageSize: 2);
      expect(running.map((p) => p.uuid), [_uuid(5), _uuid(4), _uuid(3)]);
      expect(running.every((p) => !p.isTerminal), isTrue);
      expect(client.requestsFor('routed_swap::history'), hasLength(2));
    });

    test('forwards its filters', () async {
      final (manager, client) = await withSwaps();
      await manager.history(
        filter: RoutedSwapHistoryFilter.terminal,
        from: usdt,
        to: usdc,
        createdAfter: DateTime.utc(2025),
        createdBefore: DateTime.utc(2026),
      );
      expect(client.paramsFor('routed_swap::history').single, {
        'status_filter': 'terminal',
        'my_coin': 'USDT-PLG20',
        'other_coin': 'USDC-ERC20',
        'from_timestamp': 1735689600,
        'to_timestamp': 1767225600,
        'limit': 20,
        'page_number': 1,
      });
    });
  });

  group('failure mapping', () {
    const signingTimeout = [
      RoutedSwapTick.fetchingQuote,
      RoutedSwapTick.checkingAllowance,
      RoutedSwapTick.signing,
    ];

    Future<RoutedSwapProgress> failedWith(
      RoutedSwapRunError error, {
      List<RoutedSwapTick>? ladder,
    }) async {
      final (handle, _, _) = await started(
        RoutedSwapRun(error: error, ladder: ladder),
      );
      final result = await handle.result.timeout(_timeout);
      expect(result.phase, RoutedSwapPhase.failed);
      expect(result.failure!.errorType, error.errorType);
      return result;
    }

    test('QuoteWorsened offers the re-priced route', () async {
      final failure = (await failedWith(
        RoutedSwapRunError.quoteWorsened(
          freshRoute: RoutedSwapQuote(
            from: 'USDT-PLG20',
            to: 'USDC-ERC20',
            toAmount: '98.8',
            toAmountMin: '98.31',
          ),
        ),
      )).failure!;
      expect(failure.kind, RoutedSwapFailureKind.priceMoved);
      expect(failure.message, 'Fresh route is below the accepted minimum');
      expect(failure.fundsMovement, RoutedSwapFundsMovement.none);
      expect(failure.retryPolicy, RoutedSwapRetryPolicy.requote);
      expect(failure.isRetryable, isTrue);
      expect(failure.freshOffer!.guaranteedReceive, Decimal.parse('98.31'));
      expect(failure.freshOffer!.from, usdt);
      expect(failure.freshOffer!.to, usdc);
    });

    test('InsufficientBalance reports the shortfall', () async {
      final failure = (await failedWith(
        RoutedSwapRunError.insufficientBalance(
          coin: 'MATIC',
          available: '0.001',
          requiredAmount: '0.0129',
        ),
      )).failure!;
      expect(failure.kind, RoutedSwapFailureKind.insufficientBalance);
      expect(failure.fundsMovement, RoutedSwapFundsMovement.none);
      expect(failure.retryPolicy, RoutedSwapRetryPolicy.fixAndRetry);
      expect(failure.shortfall!.ticker, 'MATIC');
      expect(failure.shortfall!.assetId, matic);
      expect(failure.shortfall!.available, Decimal.parse('0.001'));
      expect(failure.shortfall!.required, Decimal.parse('0.0129'));
      expect(
        failure.message,
        'Insufficient MATIC balance: available 0.001, required 0.0129',
      );
    });

    test('ApprovalFailed: nothing broadcast, or approval fees', () async {
      final unsent = (await failedWith(
        RoutedSwapRunError.approvalFailed('approval_broadcast_failed'),
      )).failure!;
      expect(unsent.kind, RoutedSwapFailureKind.approvalFailed);
      expect(unsent.fundsMovement, RoutedSwapFundsMovement.none);
      expect(unsent.retryPolicy, RoutedSwapRetryPolicy.retry);
      expect(
        unsent.approvalFailureReason,
        RoutedSwapApprovalFailureReason.approvalBroadcastFailed,
      );

      final mined = await failedWith(
        RoutedSwapRunError.approvalFailed('approval_transaction_failed'),
      );
      expect(mined.failure!.fundsMovement, RoutedSwapFundsMovement.feesOnly);
      expect(mined.approvalTxHashes, hasLength(1));
    });

    test(
      'SwapTxFailed: reverted costs fees; unconfirmed is uncertain',
      () async {
        final reverted = (await failedWith(
          RoutedSwapRunError.swapTxFailed('source_transaction_reverted'),
        )).failure!;
        expect(reverted.kind, RoutedSwapFailureKind.swapTransactionFailed);
        expect(reverted.fundsMovement, RoutedSwapFundsMovement.feesOnly);
        expect(reverted.retryPolicy, RoutedSwapRetryPolicy.requote);
        expect(reverted.sourceTxHash, startsWith('0x'));
        expect(
          reverted.txFailureReason,
          RoutedSwapTxFailureReason.sourceTransactionReverted,
        );

        final unconfirmed = (await failedWith(
          RoutedSwapRunError.swapTxFailed('source_transaction_not_confirmed'),
        )).failure!;
        expect(unconfirmed.fundsMovement, RoutedSwapFundsMovement.uncertain);
        expect(unconfirmed.retryPolicy, RoutedSwapRetryPolicy.wait);
      },
    );

    test('SigningRejected: a timeout after the handoff is uncertain', () async {
      final declined = (await failedWith(
        RoutedSwapRunError.signingRejected('user_rejected'),
      )).failure!;
      expect(declined.kind, RoutedSwapFailureKind.signingRejected);
      expect(declined.fundsMovement, RoutedSwapFundsMovement.none);
      expect(declined.retryPolicy, RoutedSwapRetryPolicy.retry);
      expect(
        declined.signingRejectionReason,
        RoutedSwapSigningRejectionReason.userRejected,
      );

      final beforeHandoff = (await failedWith(
        RoutedSwapRunError.signingRejected('timeout'),
        ladder: signingTimeout,
      )).failure!;
      expect(beforeHandoff.fundsMovement, RoutedSwapFundsMovement.none);

      final afterHandoff = (await failedWith(
        RoutedSwapRunError.signingRejected('timeout'),
        ladder: [
          ...signingTimeout,
          const RoutedSwapTick.broadcasting(withSourceTxHash: false),
        ],
      )).failure!;
      expect(afterHandoff.fundsMovement, RoutedSwapFundsMovement.uncertain);
      expect(afterHandoff.retryPolicy, RoutedSwapRetryPolicy.wait);
    });

    test('BridgeFailed: funds left, hand to support', () async {
      final failure = (await failedWith(
        RoutedSwapRunError.bridgeFailed(
          substatusMessage: 'Manual support is required',
          providerExplorerUrl: 'https://scan.li.fi/tx/1',
        ),
      )).failure!;
      expect(failure.kind, RoutedSwapFailureKind.bridgeFailed);
      expect(failure.fundsMovement, RoutedSwapFundsMovement.sent);
      expect(failure.retryPolicy, RoutedSwapRetryPolicy.contactSupport);
      expect(failure.isRetryable, isFalse);
      expect(failure.sourceTxHash, startsWith('0x'));
      expect(failure.providerExplorerUrl, 'https://scan.li.fi/tx/1');
      expect(failure.providerRequestId, isNull);
    });

    test('PreflightRejected: the check decides the retry', () async {
      final expected = {
        'simulation': RoutedSwapRetryPolicy.retry,
        'target_allowlist': RoutedSwapRetryPolicy.contactSupport,
        'spender_allowlist': RoutedSwapRetryPolicy.contactSupport,
        'value_cap': RoutedSwapRetryPolicy.requote,
        'amount_bounds': RoutedSwapRetryPolicy.requote,
        'gas_bounds': RoutedSwapRetryPolicy.requote,
      };
      for (final MapEntry(key: check, value: policy) in expected.entries) {
        final failure = (await failedWith(
          RoutedSwapRunError.preflightRejected(check),
        )).failure!;
        expect(failure.kind, RoutedSwapFailureKind.preflightRejected);
        expect(failure.fundsMovement, RoutedSwapFundsMovement.none);
        expect(failure.retryPolicy, policy, reason: check);
        expect(failure.preflightCheck!.wire, check);
      }
    });

    test('fresh-quote failures: quote unavailable, nothing sent', () async {
      final noRoute = (await failedWith(
        RoutedSwapRunError.noRouteFound(
          reasons: const ['Amount too low (across)'],
          providerRequestId: 'req-1',
        ),
      )).failure!;
      expect(noRoute.kind, RoutedSwapFailureKind.quoteUnavailable);
      expect(noRoute.retryPolicy, RoutedSwapRetryPolicy.requote);
      expect(noRoute.noRouteReasons, ['Amount too low (across)']);
      expect(noRoute.providerRequestId, 'req-1');

      final limited = (await failedWith(
        RoutedSwapRunError.rateLimited(providerRequestId: 'req-2'),
      )).failure!;
      expect(limited.retryPolicy, RoutedSwapRetryPolicy.retry);
      expect(limited.providerRequestId, 'req-2');

      final provider = (await failedWith(
        RoutedSwapRunError.providerApiError('upstream'),
      )).failure!;
      expect(provider.message, 'upstream');
      expect(provider.retryPolicy, RoutedSwapRetryPolicy.retry);

      final bounds = (await failedWith(
        RoutedSwapRunError.amountOutOfBounds(
          param: 'amount',
          value: '0.1',
          min: '1',
          max: '9',
        ),
      )).failure!;
      expect(bounds.retryPolicy, RoutedSwapRetryPolicy.requote);
      expect(bounds.bounds!.min, Decimal.one);
      expect(bounds.bounds!.max, Decimal.parse('9'));

      for (final failure in [noRoute, limited, provider, bounds]) {
        expect(failure.fundsMovement, RoutedSwapFundsMovement.none);
        expect(failure.kind, RoutedSwapFailureKind.quoteUnavailable);
      }
    });

    test('InternalError: pre-broadcast only when watched there', () async {
      final early = (await failedWith(
        RoutedSwapRunError.internalError('Source wallet address changed'),
      )).failure!;
      expect(early.kind, RoutedSwapFailureKind.internalError);
      expect(early.fundsMovement, RoutedSwapFundsMovement.none);
      expect(early.retryPolicy, RoutedSwapRetryPolicy.retry);

      final handoff = (await failedWith(
        RoutedSwapRunError.internalError(
          'Broadcast handoff did not return a transaction hash',
        ),
        ladder: [
          ...signingTimeout,
          const RoutedSwapTick.broadcasting(withSourceTxHash: false),
        ],
      )).failure!;
      expect(handoff.fundsMovement, RoutedSwapFundsMovement.uncertain);
      expect(handoff.retryPolicy, RoutedSwapRetryPolicy.contactSupport);
    });

    test('TransportError before broadcast is retryable', () async {
      final failure = (await failedWith(
        RoutedSwapRunError.transportError(
          'Unable to reach routed swap provider',
        ),
      )).failure!;
      expect(failure.kind, RoutedSwapFailureKind.internalError);
      expect(failure.fundsMovement, RoutedSwapFundsMovement.none);
      expect(failure.retryPolicy, RoutedSwapRetryPolicy.retry);
    });

    test('AbortedOnRestart: nothing executed, safe to retry', () async {
      final (handle, fixture, _) = await started(
        RoutedSwapRun(autoAdvance: false),
      );
      fixture.restartKdf();
      final failure = (await handle.result.timeout(_timeout)).failure!;
      expect(failure.kind, RoutedSwapFailureKind.abortedOnRestart);
      expect(failure.fundsMovement, RoutedSwapFundsMovement.none);
      expect(failure.retryPolicy, RoutedSwapRetryPolicy.retry);
    });
  });

  group('receipts', () {
    Future<RoutedSwapProgress> finished(
      RoutedSwapRun run, {
      RoutedSwapQuote? quoted,
    }) async {
      final (handle, _, _) = await started(run, quoted: quoted);
      final result = await handle.result.timeout(_timeout);
      expect(result.phase, RoutedSwapPhase.finished);
      return result;
    }

    test('completed cross-chain is the only success', () async {
      final result = await finished(RoutedSwapRun());
      final receipt = result.receipt!;
      expect(receipt.outcome, RoutedSwapOutcome.completed);
      expect(result.isSuccess, isTrue);
      expect(receipt.assetId, usdc);
      expect(receipt.amount, Decimal.parse('100.21'));
      expect(receipt.partialReason, isNull);
      expect(result.sourceTxHash, startsWith('0x'));
      expect(result.destinationTxHash, startsWith('0x'));
      expect(result.explorerUrl, startsWith('https://'));
      expect(result.executedOffer!.guaranteedReceive, Decimal.parse('99.71'));
    });

    test('same-chain completes with no destination transaction', () async {
      final result = await finished(
        RoutedSwapRun(),
        quoted: route(crossChain: false),
      );
      expect(result.isSuccess, isTrue);
      expect(result.destinationTxHash, isNull);
      expect(result.receipt!.amount, Decimal.parse('100.21'));
    });

    test('partial below the minimum is not a success', () async {
      final result = await finished(
        RoutedSwapRun(
          outcome: RoutedSwapRunOutcome.partial,
          partialReason: 'below_minimum',
          receivedAmount: '98.4',
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(
        result.receipt!.partialReason,
        RoutedSwapPartialReason.belowMinimum,
      );
      expect(result.receipt!.assetId, usdc);
      expect(result.receipt!.amount, Decimal.parse('98.4'));
    });

    test('an intermediate token known only by symbol', () async {
      final result = await finished(
        RoutedSwapRun(
          outcome: RoutedSwapRunOutcome.partial,
          partialReason: 'intermediate_token',
          receivedSymbol: 'axlUSDC',
          receivedAmount: '100.1',
        ),
      );
      final receipt = result.receipt!;
      expect(receipt.partialReason, RoutedSwapPartialReason.intermediateToken);
      expect(receipt.assetId, isNull);
      expect(receipt.symbol, 'axlUSDC');
      expect(receipt.tokenLabel, 'axlUSDC');
    });

    test('a refund returns the source coin and is not a success', () async {
      final result = await finished(
        RoutedSwapRun(outcome: RoutedSwapRunOutcome.refunded),
      );
      expect(result.isSuccess, isFalse);
      expect(result.receipt!.outcome, RoutedSwapOutcome.refunded);
      expect(result.receipt!.assetId, usdt);
      expect(result.receipt!.amount, Decimal.parse('100.5'));
      expect(result.destinationTxHash, isNull);
    });
  });
}

const Duration _timeout = Duration(seconds: 5);

AssetId _asset(
  String id, {
  required int chainId,
  required int decimals,
  AssetId? parent,
}) => AssetId(
  id: id,
  name: id,
  symbol: AssetSymbol(assetConfigId: id),
  chainId: AssetChainId(chainId: chainId, decimalsValue: decimals),
  derivationPath: null,
  subClass: parent == null ? CoinSubClass.polygon : CoinSubClass.erc20,
  parentId: parent,
);

String _uuid(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

/// What a user could see change between two snapshots.
List<Object?> _key(RoutedSwapProgress p) => [
  p.phase,
  p.rawState,
  p.bridgeStage,
  p.providerStatusDetail,
  ...p.approvalTxHashes,
  p.sourceTxHash,
  p.destinationTxHash,
  p.receipt,
  p.failure?.errorType,
  p.delayedSince,
];

/// Lets fire-and-forget work (the final forget read) finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

/// An [ApiClient] over the scripted KDF that records requests and can fail
/// chosen calls the way a dropped connection does.
class _Client implements ApiClient {
  _Client(this._script);

  final KdfScript _script;
  final List<JsonMap> _requests = [];
  final Map<String, int> _failures = {};

  /// Throws from the next [times] calls to [method] before they reach KDF.
  void failNext(String method, {int times = 1}) {
    _failures[method] = (_failures[method] ?? 0) + times;
  }

  List<JsonMap> requestsFor(String method) =>
      _requests.where((r) => r['method'] == method).toList();

  List<JsonMap> paramsFor(String method) => [
    for (final request in requestsFor(method))
      request['params'] as JsonMap? ?? const {},
  ];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    _requests.add(request);
    final method = request['method'] as String;
    final failures = _failures[method] ?? 0;
    if (failures > 0) {
      _failures[method] = failures - 1;
      throw TimeoutException('scripted connection failure for $method');
    }
    final response = await _script.respondTo(request);
    if (response == null) throw StateError('nothing scripted for $method');
    return response;
  }
}
