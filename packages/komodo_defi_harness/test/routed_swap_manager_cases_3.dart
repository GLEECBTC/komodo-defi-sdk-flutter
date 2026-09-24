part of 'routed_swap_manager_test.dart';

void _cases3() {
  group('watch', () {
    test('returns the live session for a swap already followed', () async {
      final fixture = RoutedSwapFixture()
        ..quote(route())
        ..run(RoutedSwapRun(autoAdvance: false));
      final manager = _managerFor(_Client(fixture.build()));
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

      final watched = await _managerFor(
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

      final watched = await _managerFor(
        _Client(fixture.build()),
      ).watch(handle.uuid);
      expect(watched.latest.phase, RoutedSwapPhase.bridging);
      expect(watched.latest.canCancel, isFalse);

      fixture.finishPersisted(handle.uuid);
      final result = await watched.result.timeout(_timeout);
      expect(result.receipt!.outcome, RoutedSwapOutcome.completed);
    });

    test('throws NotFound for an unknown swap', () async {
      final manager = _managerFor(_Client(RoutedSwapFixture().build()));
      await expectLater(
        manager.watch('00000000-0000-4000-8000-00000000abcd'),
        throwsA(isA<RoutedSwapNotFoundException>()),
      );
    });

    test('a malformed uuid is the engine rejecting the request', () async {
      final manager = _managerFor(_Client(RoutedSwapFixture().build()));
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
      return (_managerFor(client), client);
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
}
