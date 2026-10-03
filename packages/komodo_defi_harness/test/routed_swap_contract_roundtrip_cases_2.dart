part of 'routed_swap_contract_roundtrip_test.dart';

void _cases2() {
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
