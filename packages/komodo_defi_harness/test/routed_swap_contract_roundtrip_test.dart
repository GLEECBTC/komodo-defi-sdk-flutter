import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;

/// Parses everything the scripted KDF emits with the real SDK models, through
/// the same request pipeline production uses (`parseResponseJson`).
///
/// The fixture and the models are two independent readings of the engine.
/// Either could drift — a key renamed on one side, an optional treated as
/// required on the other — and every test built on top would keep passing
/// while the app broke against real KDF. This is the seam that catches it.
void main() {
  const from = 'USDT-PLG20';
  const to = 'USDC-ERC20';

  RoutedSwapQuote route({
    bool crossChain = true,
    RoutedSwapQuoteApproval? approval =
        const RoutedSwapQuoteApproval.noAllowance(
          gasCoin: 'MATIC',
          gasAmount: '0.0009',
        ),
  }) => RoutedSwapQuote(
    from: from,
    to: to,
    toAmount: '100.21',
    toAmountMin: '99.71',
    crossChain: crossChain,
    toolLogoUrl: 'https://li.fi/logos/stargate.png',
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
        coin: from,
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
    ],
    gasCosts: const [
      RoutedSwapQuoteGas(coin: 'MATIC', amount: '0.012', amountUsd: '0.01'),
    ],
  );

  Future<Map<String, dynamic>> call(
    KdfScript script,
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    final response = await script.respondTo({
      'mmrpc': '2.0',
      'method': method,
      'params': params,
    });
    if (response == null) fail('nothing scripted for $method');
    return response;
  }

  Future<int> start(KdfScript script) async {
    final json = await call(script, 'task::routed_swap::init', {
      'from': from,
      'to': to,
      'amount': '100.5',
      'min_to_amount': '99.71',
    });
    return rpc.RoutedSwapInitRequest(
      rpcPass: '',
      from: from,
      to: to,
      amount: '100.5',
      minToAmount: '99.71',
    ).parseResponseJson(json).taskId;
  }

  Future<rpc.RoutedSwapStatus> status(KdfScript script, int taskId) async {
    final json = await call(script, 'task::routed_swap::status', {
      'task_id': taskId,
      'forget_if_finished': false,
    });
    return rpc.RoutedSwapStatusRequest(
      rpcPass: '',
      taskId: taskId,
    ).parseResponseJson(json).details;
  }

  Future<List<rpc.RoutedSwapStatus>> drain(KdfScript script, int taskId) async {
    final seen = <rpc.RoutedSwapStatus>[];
    for (var i = 0; i < 50; i++) {
      seen.add(await status(script, taskId));
      if (seen.last.isTerminal) return seen;
    }
    fail('the run never reached a terminal result');
  }

  Future<rpc.RoutedSwapStatus> terminal(RoutedSwapRun run) async {
    final script = (RoutedSwapFixture()..run(run)).build();
    return (await drain(script, await start(script))).last;
  }

  Future<Object> thrownBy(Future<void> Function() parse) async {
    try {
      await parse();
    } on Object catch (e) {
      return e;
    }
    fail('parsed as a response');
  }

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

  test('every task error parses as a response, typed', () async {
    const atApproving = [
      RoutedSwapTick.fetchingQuote,
      RoutedSwapTick.checkingAllowance,
      RoutedSwapTick.approving(),
      RoutedSwapTick.approving('0xa1'),
    ];
    final cases = <(RoutedSwapRunError, List<RoutedSwapTick>?, Matcher)>[
      (
        RoutedSwapRunError.quoteWorsened(
          freshRoute: RoutedSwapQuote(
            from: from,
            to: to,
            toAmount: '98.8',
            toAmountMin: '98.31',
          ),
        ),
        null,
        isA<rpc.RoutedSwapQuoteWorsenedError>().having(
          (e) => e.freshRoute?.toMinimum.amount,
          'fresh minimum',
          '98.31',
        ),
      ),
      (
        RoutedSwapRunError.insufficientBalance(
          coin: 'MATIC',
          available: '0.001',
          requiredAmount: '0.0129',
        ),
        null,
        isA<rpc.RoutedSwapInsufficientBalanceError>().having(
          (e) => [e.coin, e.available, e.required],
          'shortfall',
          ['MATIC', '0.001', '0.0129'],
        ),
      ),
      (
        RoutedSwapRunError.approvalFailed('confirmed_allowance_insufficient'),
        null,
        isA<rpc.RoutedSwapApprovalFailedError>().having(
          (e) => e.reason,
          'reason',
          rpc.RoutedSwapApprovalFailureReason.confirmedAllowanceInsufficient,
        ),
      ),
      (
        RoutedSwapRunError.swapTxFailed('source_transaction_not_confirmed'),
        null,
        isA<rpc.RoutedSwapTxFailedError>()
            .having((e) => e.sourceTxHash, 'sourceTxHash', isNotNull)
            .having((e) => e.mayStillConfirm, 'mayStillConfirm', isTrue),
      ),
      (
        RoutedSwapRunError.signingRejected('unsupported_method'),
        null,
        isA<rpc.RoutedSwapSigningRejectedError>().having(
          (e) => e.reason,
          'reason',
          rpc.RoutedSwapSigningRejectionReason.unsupportedMethod,
        ),
      ),
      (
        RoutedSwapRunError.bridgeFailed(
          substatusMessage: 'stuck',
          providerExplorerUrl: 'https://scan.li.fi/tx/1',
        ),
        null,
        isA<rpc.RoutedSwapBridgeFailedError>()
            .having((e) => e.substatus, 'substatus', 'UNKNOWN_ERROR')
            .having((e) => e.substatusMessage, 'message', 'stuck')
            .having((e) => e.providerRequestId, 'providerRequestId', isNull),
      ),
      (
        RoutedSwapRunError.preflightRejected('simulation'),
        atApproving,
        isA<rpc.RoutedSwapPreflightRejectedError>().having(
          (e) => e.check,
          'check',
          rpc.RoutedSwapPreflightCheck.simulation,
        ),
      ),
      (
        RoutedSwapRunError.noRouteFound(providerRequestId: 'req'),
        null,
        isA<rpc.RoutedSwapNoRouteTaskError>()
            .having((e) => e.reasons, 'reasons', ['No route found'])
            .having((e) => e.providerRequestId, 'providerRequestId', 'req'),
      ),
      (
        RoutedSwapRunError.rateLimited(providerRequestId: 'req'),
        null,
        isA<rpc.RoutedSwapRateLimitedTaskError>().having(
          (e) => e.providerRequestId,
          'providerRequestId',
          'req',
        ),
      ),
      (
        RoutedSwapRunError.providerApiError('upstream'),
        null,
        isA<rpc.RoutedSwapProviderTaskError>().having(
          (e) => e.message,
          'message',
          'upstream',
        ),
      ),
      (
        RoutedSwapRunError.amountOutOfBounds(
          param: 'amount',
          value: '0.1',
          min: '1',
          max: '9',
        ),
        null,
        isA<rpc.RoutedSwapAmountOutOfBoundsTaskError>().having(
          (e) => [e.param, e.value, e.min, e.max],
          'bounds',
          ['amount', '0.1', '1', '9'],
        ),
      ),
      (
        RoutedSwapRunError.internalError('boom'),
        null,
        isA<rpc.RoutedSwapInternalTaskError>().having(
          (e) => e.message,
          'message',
          'boom',
        ),
      ),
      (
        RoutedSwapRunError.transportError('unreachable'),
        null,
        isA<rpc.RoutedSwapTransportTaskError>().having(
          (e) => e.message,
          'message',
          'unreachable',
        ),
      ),
    ];
    for (final (error, ladder, matcher) in cases) {
      final script =
          (RoutedSwapFixture()
                ..quote(route(approval: null))
                ..run(RoutedSwapRun(error: error, ladder: ladder)))
              .build();
      final seen = await drain(script, await start(script));
      final failed = seen.last as rpc.RoutedSwapErrored;

      expect(failed.errorType, error.errorType);
      expect(failed.error, matcher, reason: error.errorType);
      expect(failed.error, isNot(isA<rpc.RoutedSwapUnknownTaskError>()));
      expect(failed.uuid, seen.first.uuid);
      expect(failed.message, isNot(failed.errorType));
      final lastLive = seen[seen.length - 2] as rpc.RoutedSwapInProgress;
      expect(
        failed.executedRoute,
        lastLive.state == rpc.RoutedSwapState.fetchingQuote
            ? isNull
            : isNotNull,
        reason: '${error.errorType} raised at ${lastLive.rawState}',
      );
      if (failed.error case rpc.RoutedSwapTxFailedError(:final sourceTxHash)) {
        expect(sourceTxHash, lastLive.sourceTxHash);
      }
    }
  });

  test('status NoSuchTask and Internal throw typed exceptions', () async {
    final fixture = RoutedSwapFixture()..statusFailsInternally();
    final script = fixture.build();

    final internal = await thrownBy(
      () async =>
          rpc.RoutedSwapStatusRequest(rpcPass: '', taskId: 7).parseResponseJson(
            await call(script, 'task::routed_swap::status', {'task_id': 7}),
          ),
    );
    expect(internal, isA<rpc.RoutedSwapRpcException>());
    expect((internal as rpc.RoutedSwapRpcException).errorType, 'Internal');

    final missing = await thrownBy(
      () async =>
          rpc.RoutedSwapStatusRequest(rpcPass: '', taskId: 7).parseResponseJson(
            await call(script, 'task::routed_swap::status', {'task_id': 7}),
          ),
    );
    expect(
      missing,
      isA<rpc.RoutedSwapNoSuchTaskException>().having(
        (e) => e.taskId,
        'taskId',
        7,
      ),
    );
  });

  test('cancel: success, every refusal, and InternalError', () async {
    final fixture = RoutedSwapFixture()
      ..run(RoutedSwapRun(autoAdvance: false))
      ..run(RoutedSwapRun(autoAdvance: false))
      ..run(RoutedSwapRun(autoAdvance: false));
    final script = fixture.build();
    Future<Object> cancel(int taskId) => thrownBy(() async {
      final json = await call(script, 'task::routed_swap::cancel', {
        'task_id': taskId,
      });
      final response = rpc.RoutedSwapCancelRequest(
        rpcPass: '',
        taskId: taskId,
      ).parseResponseJson(json);
      throw _Accepted(response.result);
    });

    final cancellable = await start(script);
    expect(
      await cancel(cancellable),
      isA<_Accepted>().having((a) => a.result, 'result', 'success'),
    );
    expect(
      await cancel(cancellable),
      isA<rpc.RoutedSwapNoSuchTaskException>().having(
        (e) => e.taskId,
        'taskId',
        cancellable,
      ),
    );

    final broadcast = await start(script);
    fixture.advance(broadcast, steps: 3);
    expect(
      await cancel(broadcast),
      isA<rpc.RoutedSwapTaskAlreadyBroadcastException>().having(
        (e) => e.taskId,
        'taskId',
        broadcast,
      ),
    );

    final finished = await start(script);
    fixture.advance(finished, steps: 100);
    expect(
      await cancel(finished),
      isA<rpc.RoutedSwapTaskFinishedException>().having(
        (e) => e.taskId,
        'taskId',
        finished,
      ),
    );

    fixture.cancelFailsInternally();
    expect(
      await cancel(broadcast),
      isA<rpc.RoutedSwapInternalException>().having(
        (e) => e.detail,
        'detail',
        'Unable to persist routed swap state',
      ),
    );
  });

  test('history parses every entry, synthetic outcomes included', () async {
    final fixture = RoutedSwapFixture()
      ..quote(route())
      ..run(RoutedSwapRun(autoAdvance: false)) // completed
      ..run(RoutedSwapRun(autoAdvance: false)) // cancelled after approving
      ..run(RoutedSwapRun(autoAdvance: false)) // aborted on restart
      ..run(RoutedSwapRun(autoAdvance: false)) // still bridging after restart
      ..run(RoutedSwapRun(error: RoutedSwapRunError.rateLimited())); // errored
    final script = fixture.build();
    final completed = await start(script);
    fixture.advance(completed, steps: 100);
    final cancelled = await start(script);
    fixture.advance(cancelled, steps: 3);
    await call(script, 'task::routed_swap::cancel', {'task_id': cancelled});
    final aborted = await start(script);
    final bridging = await start(script);
    fixture.advance(bridging, steps: 8);
    final errored = await start(script);
    await drain(script, errored);
    fixture.restartKdf();

    final json = await call(script, 'routed_swap::history', {'limit': 3});
    final page = rpc.RoutedSwapHistoryRequest(
      rpcPass: '',
      limit: 3,
    ).parseResponseJson(json);
    expect(page.entries, hasLength(3));
    expect([page.total, page.limit, page.pageNumber], [5, 3, 1]);
    expect(page.totalPages, 2);
    expect(page.hasMore, isTrue);

    final all = rpc.RoutedSwapHistoryRequest(
      rpcPass: '',
    ).parseResponseJson(await call(script, 'routed_swap::history'));
    expect(all.entries, hasLength(5));
    final byUuid = {for (final entry in all.entries) entry.uuid: entry};
    rpc.RoutedSwapHistoryEntry entry(int taskId) =>
        byUuid[fixture.uuidOf(taskId)]!;

    expect(
      entry(completed).swap,
      isA<rpc.RoutedSwapFinished>().having(
        (s) => s.outcome,
        'outcome',
        rpc.RoutedSwapOutcome.completed,
      ),
    );
    expect(entry(completed).gasSpent.map((g) => g.coin), ['MATIC', 'MATIC']);
    expect(entry(completed).totalGasSpent.single.amount, '0.0155');
    expect(entry(completed).finishedAt, isNotNull);

    final cancelledSwap = entry(cancelled).swap as rpc.RoutedSwapErrored;
    expect(cancelledSwap.error, isA<rpc.RoutedSwapTaskCancelledError>());
    expect(cancelledSwap.executedRoute, isNotNull);
    expect(entry(cancelled).approvalTxHashes, hasLength(1));

    final abortedSwap = entry(aborted).swap as rpc.RoutedSwapErrored;
    expect(abortedSwap.error, isA<rpc.RoutedSwapAbortedOnRestartError>());
    expect(abortedSwap.executedRoute, isNull);

    expect(entry(bridging).isInFlight, isTrue);
    expect(entry(bridging).finishedAt, isNull);
    expect(
      (entry(bridging).swap as rpc.RoutedSwapInProgress).stage,
      rpc.RoutedSwapBridgeStage.destinationPending,
    );

    final erroredSwap = entry(errored).swap as rpc.RoutedSwapErrored;
    expect(erroredSwap.error, isA<rpc.RoutedSwapRateLimitedTaskError>());
    expect(entry(errored).requested.amount, '100.5');
    expect(entry(errored).minToAmountAccepted, '99.71');
  });

  test('history rejections throw typed exceptions', () async {
    final script = RoutedSwapFixture().build();
    final zero = await thrownBy(
      () async =>
          rpc.RoutedSwapHistoryRequest(rpcPass: '', limit: 0).parseResponseJson(
            await call(script, 'routed_swap::history', {'limit': 0}),
          ),
    );
    expect(
      zero,
      isA<rpc.RoutedSwapInvalidParamException>().having(
        (e) => e.param,
        'param',
        'limit',
      ),
    );

    final malformed = await thrownBy(
      () async => rpc.RoutedSwapHistoryRequest(rpcPass: '', uuid: 'nope')
          .parseResponseJson(
            await call(script, 'routed_swap::history', {'uuid': 'nope'}),
          ),
    );
    expect(
      malformed,
      isA<rpc.RoutedSwapUnknownRpcException>().having(
        (e) => e.errorType,
        'errorType',
        'InvalidRequest',
      ),
    );
  });

  test('the request builders never send what the engine rejects', () async {
    // The engine denies unknown fields and nulls; a request built by the SDK
    // must pass the fake's serde checks unchanged.
    final fixture = RoutedSwapFixture()
      ..supportedCoin(from, chainId: 137)
      ..quote(route())
      ..run(RoutedSwapRun());
    final script = fixture.build();
    for (final request in <rpc.BaseRequest<rpc.BaseResponse, Exception>>[
      rpc.RoutedSwapSupportedCoinsRequest(rpcPass: ''),
      rpc.RoutedSwapQuoteRequest(
        rpcPass: '',
        from: from,
        to: to,
        amount: '100.5',
        order: rpc.RoutedSwapOrder.fastest,
      ),
      rpc.RoutedSwapInitRequest(
        rpcPass: '',
        from: from,
        to: to,
        amount: '100.5',
        minToAmount: '99.71',
        slippage: 0.01,
      ),
      rpc.RoutedSwapStatusRequest(rpcPass: '', taskId: 1),
      rpc.RoutedSwapHistoryRequest(
        rpcPass: '',
        filter: rpc.RoutedSwapHistoryFilter.inFlight,
      ),
      rpc.RoutedSwapCancelRequest(rpcPass: '', taskId: 1),
    ]) {
      final response = await script.respondTo(request.toJson());
      expect(
        response!['error_type'],
        isNull,
        reason: '${request.method}: ${response['error']}',
      );
      request.parseResponseJson(response);
    }
  });
}

class _Accepted implements Exception {
  const _Accepted(this.result);

  final String result;
}
