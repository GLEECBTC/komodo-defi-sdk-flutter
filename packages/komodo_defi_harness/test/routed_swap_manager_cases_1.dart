part of 'routed_swap_manager_test.dart';

void _cases1() {
  group('eligibleAssets', () {
    test('lists only supported coins the wallet can resolve', () async {
      final fixture = RoutedSwapFixture()
        ..supportedCoin('USDT-PLG20', chainId: 137)
        ..supportedCoin('USDC-ERC20', chainId: 1)
        ..supportedCoin('FEE-INACTIVE', chainId: 137);
      final manager = _managerFor(_Client(fixture.build()));

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
      offer = await _managerFor(client).quote(
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
      final manager = _managerFor(_Client(fixture.build()));

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
      final max = await _managerFor(
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
      final max = await _managerFor(
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
      final manager = _managerFor(_Client(fixture.build()));
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
      final manager = _managerFor(client);
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
      final manager = _managerFor(client);

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
      final manager = _managerFor(client);

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
      final manager = _managerFor(client);

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
      final manager = _managerFor(client);

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
      final manager = _managerFor(_Client(fixture.build()));

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
}
