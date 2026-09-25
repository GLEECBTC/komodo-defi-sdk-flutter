part of 'routed_swap_contract_roundtrip_test.dart';

void _cases1() {
  test('supported_coins parses', () async {
    final fixture = RoutedSwapFixture()
      ..supportedCoin(from, chainId: 137)
      ..supportedCoin('ETH', chainId: 1);
    final json = await call(fixture.build(), 'routed_swap::supported_coins');
    final parsed = rpc.RoutedSwapSupportedCoinsRequest(
      rpcPass: '',
    ).parseResponseJson(json);

    expect(parsed.provider, 'lifi');
    expect(parsed.coins.map((c) => c.coin), ['ETH', from]);
    expect(parsed.coins.last.chainId, 137);
  });

  test('a quote parses back into exactly the scripted route', () async {
    final scripted = route();
    final json = await call(
      (RoutedSwapFixture()..quote(scripted)).build(),
      'routed_swap::quote',
      {'from': from, 'to': to, 'amount': '100.5'},
    );
    final parsed = rpc.RoutedSwapQuoteRequest(
      rpcPass: '',
      from: from,
      to: to,
      amount: '100.5',
    ).parseResponseJson(json).best!;

    expect(parsed.toJson(), scripted.toJson(amount: '100.5'));
    expect(parsed.toMinimum.amount, '99.71');
    expect(parsed.to.amount, '100.21');
    expect(parsed.kind, rpc.RoutedSwapRouteKind.crossChain);
    expect(parsed.approval!.reason, rpc.RoutedSwapApprovalReason.noAllowance);
    expect(parsed.approval!.spender, RoutedSwapQuoteApproval.lifiDiamond);
    expect(parsed.fromAddress, RoutedSwapQuote.defaultAddress);
    expect(parsed.toAddress, parsed.fromAddress);
    expect(parsed.feeCosts.last.amount.isKnownAsset, isFalse);
    expect(parsed.totalGasCosts.single.amount.amount, '0.0129');
    expect(parsed.totalGasCosts.single.amountUsd, isNull);
    expect(parsed.steps.map((s) => s.stepType), [
      rpc.RoutedSwapStepType.swap,
      rpc.RoutedSwapStepType.cross,
    ]);
  });

  test('every quote error parses into its typed exception', () async {
    final expected = <RoutedSwapQuoteError, TypeMatcher<Object>>{
      RoutedSwapQuoteError.coinNotActive(
        to,
      ): isA<rpc.RoutedSwapCoinNotActiveException>().having(
        (e) => e.coin,
        'coin',
        to,
      ),
      RoutedSwapQuoteError.pairNotSupported(
        from,
        to,
        'why',
      ): isA<rpc.RoutedSwapPairNotSupportedException>().having(
        (e) => [e.from, e.to, e.reason],
        'pair',
        [from, to, 'why'],
      ),
      RoutedSwapQuoteError.invalidParam(
        'amount',
        'why',
      ): isA<rpc.RoutedSwapInvalidParamException>().having(
        (e) => e.param,
        'param',
        'amount',
      ),
      RoutedSwapQuoteError.amountOutOfBounds(
        param: 'amount',
        value: '0',
        min: '0.000001',
        max: '1000',
      ): isA<rpc.RoutedSwapAmountOutOfBoundsException>().having(
        (e) => [e.value, e.min, e.max],
        'bounds',
        ['0', '0.000001', '1000'],
      ),
      RoutedSwapQuoteError.myAddressError(
        from,
        'no enabled address',
      ): isA<rpc.RoutedSwapMyAddressException>().having(
        (e) => e.detail,
        'detail',
        'no enabled address',
      ),
      RoutedSwapQuoteError.invalidConfig(
        'bad lifi_api',
      ): isA<rpc.RoutedSwapInvalidConfigException>().having(
        (e) => e.detail,
        'detail',
        'bad lifi_api',
      ),
      RoutedSwapQuoteError.noRouteFound(
        reasons: const ['too low (across)'],
        providerRequestId: 'req',
      ): isA<rpc.RoutedSwapNoRouteException>()
          .having((e) => e.reasons, 'reasons', ['too low (across)'])
          .having((e) => e.providerRequestId, 'providerRequestId', 'req'),
      RoutedSwapQuoteError.rateLimited():
          isA<rpc.RoutedSwapRateLimitedException>().having(
            (e) => e.providerRequestId,
            'providerRequestId',
            isNull,
          ),
      RoutedSwapQuoteError.providerApiError(
        'upstream',
        providerRequestId: 'r',
      ): isA<rpc.RoutedSwapProviderException>()
          .having((e) => e.detail, 'detail', 'upstream')
          .having((e) => e.providerRequestId, 'providerRequestId', 'r'),
      RoutedSwapQuoteError.transportError(
        'unreachable',
      ): isA<rpc.RoutedSwapTransportException>().having(
        (e) => e.detail,
        'detail',
        'unreachable',
      ),
      RoutedSwapQuoteError.internalError(
        'boom',
      ): isA<rpc.RoutedSwapInternalException>().having(
        (e) => e.detail,
        'detail',
        'boom',
      ),
    };
    for (final MapEntry(key: error, value: matcher) in expected.entries) {
      final script = (RoutedSwapFixture()..quoteFails(from, to, error)).build();
      final json = await call(script, 'routed_swap::quote', {
        'from': from,
        'to': to,
        'amount': '1',
      });
      final thrown = await thrownBy(
        () async => rpc.RoutedSwapQuoteRequest(
          rpcPass: '',
          from: from,
          to: to,
          amount: '1',
        ).parseResponseJson(json),
      );
      expect(thrown, matcher, reason: error.errorType);
      expect((thrown as rpc.RoutedSwapRpcException).message, error.message);
    }
  });

  test('a pre-task init rejection throws the typed exception', () async {
    final script =
        (RoutedSwapFixture()..initFails(
              RoutedSwapQuoteError.pairNotSupported(from, 'BTC', 'not EVM'),
            ))
            .build();
    final json = await call(script, 'task::routed_swap::init', {
      'from': from,
      'to': 'BTC',
      'amount': '1',
      'min_to_amount': '1',
    });
    final thrown = await thrownBy(
      () async => rpc.RoutedSwapInitRequest(
        rpcPass: '',
        from: from,
        to: 'BTC',
        amount: '1',
        minToAmount: '1',
      ).parseResponseJson(json),
    );
    expect(thrown, isA<rpc.RoutedSwapPairNotSupportedException>());
  });

  test('every in-progress state parses; both sides agree on cancel', () async {
    final script =
        (RoutedSwapFixture()
              ..quote(
                route(
                  approval: const RoutedSwapQuoteApproval.zeroReset(
                    gasCoin: 'MATIC',
                    gasAmount: '0.0018',
                  ),
                ),
              )
              ..run(RoutedSwapRun()))
            .build();
    final taskId = await start(script);
    final seen = await drain(script, taskId);
    final inProgress = seen.whereType<rpc.RoutedSwapInProgress>().toList();
    final executed = rpc.RoutedSwapRoute.fromJson(
      route(
        approval: const RoutedSwapQuoteApproval.zeroReset(
          gasCoin: 'MATIC',
          gasAmount: '0.0018',
        ),
      ).toJson(amount: '100.5'),
    );

    expect(inProgress.map((s) => s.state).toSet(), {
      for (final state in rpc.RoutedSwapState.values)
        if (state != rpc.RoutedSwapState.unknown) state,
    });
    for (final s in inProgress) {
      expect(s.uuid, seen.first.uuid);
      expect(
        s.executedRoute,
        s.state == rpc.RoutedSwapState.fetchingQuote ? isNull : executed,
      );
    }
    expect(
      inProgress
          .where((s) => s.state.isCancellable)
          .map((s) => s.state)
          .toSet(),
      {
        rpc.RoutedSwapState.fetchingQuote,
        rpc.RoutedSwapState.checkingAllowance,
        rpc.RoutedSwapState.approving,
        rpc.RoutedSwapState.signing,
      },
    );

    final approvals = inProgress
        .map((s) => s.approveTxHash)
        .whereType<String>()
        .toSet();
    expect(approvals, hasLength(2));

    final tracking = inProgress
        .where((s) => s.state == rpc.RoutedSwapState.trackingBridge)
        .toList();
    expect(tracking.map((s) => s.stage), [
      rpc.RoutedSwapBridgeStage.unknown,
      rpc.RoutedSwapBridgeStage.destinationPending,
      rpc.RoutedSwapBridgeStage.destinationPending,
    ]);
    expect(tracking.map((s) => s.rawStage), everyElement(isNotNull));
    expect(tracking.first.substatus, isNull);
    expect(tracking.last.substatus, 'COMPLETED');
    expect(tracking.last.executionDurationS, 95);
    expect(tracking.last.providerExplorerUrl, startsWith('https://'));
    expect(
      inProgress
          .where((s) => s.state.index >= rpc.RoutedSwapState.broadcasting.index)
          .map((s) => s.sourceTxHash)
          .toSet(),
      hasLength(1),
    );
  });

  test('every Ok outcome parses with its receipt', () async {
    final completed = await terminal(RoutedSwapRun()) as rpc.RoutedSwapFinished;
    expect(completed.outcome, rpc.RoutedSwapOutcome.completed);
    expect(completed.outcome.isSuccess, isTrue);
    expect(completed.received.coin, to);
    expect(completed.destTxHash, isNotNull);
    expect(completed.executedRoute, isNotNull);

    final sameChain =
        await terminal(RoutedSwapRun(route: route(crossChain: false)))
            as rpc.RoutedSwapFinished;
    expect(sameChain.received.amount, '100.21');
    expect(sameChain.destTxHash, isNull);
    expect(sameChain.providerExplorerUrl, isNull);

    final below =
        await terminal(
              RoutedSwapRun(
                outcome: RoutedSwapRunOutcome.partial,
                partialReason: 'below_minimum',
                receivedAmount: '98.4',
              ),
            )
            as rpc.RoutedSwapFinished;
    expect(below.outcome.isSuccess, isFalse);
    expect(below.partialReason, rpc.RoutedSwapPartialReason.belowMinimum);

    final symbol =
        await terminal(
              RoutedSwapRun(
                outcome: RoutedSwapRunOutcome.partial,
                partialReason: 'intermediate_token',
                receivedSymbol: 'axlUSDC',
                receivedAmount: '100.1',
              ),
            )
            as rpc.RoutedSwapFinished;
    expect(symbol.partialReason, rpc.RoutedSwapPartialReason.intermediateToken);
    expect(symbol.received.isKnownAsset, isFalse);
    expect(symbol.received.label, 'axlUSDC');

    final refunded =
        await terminal(RoutedSwapRun(outcome: RoutedSwapRunOutcome.refunded))
            as rpc.RoutedSwapFinished;
    expect(refunded.outcome, rpc.RoutedSwapOutcome.refunded);
    expect(refunded.received.coin, from);
    expect(refunded.destTxHash, isNull);
  });
}
