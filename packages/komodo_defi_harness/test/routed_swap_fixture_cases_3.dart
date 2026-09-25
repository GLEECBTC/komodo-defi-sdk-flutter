part of 'routed_swap_fixture_test.dart';

void _cases3() {
  group('terminal Error', () {
    Future<Map<String, dynamic>> failed(
      RoutedSwapRunError error, {
      RoutedSwapQuote? executed,
      List<RoutedSwapTick>? ladder,
    }) async {
      final result = await terminal(
        RoutedSwapRun(route: executed, error: error, ladder: ladder),
      );
      expect(result['status'], 'Error');
      final details = _map(result['details']);
      _expectNoNulls(details);
      expect(details['uuid'], isA<String>());
      expect(details['provider'], 'lifi');
      expect(details['error_path'], isA<String>());
      expect(details['error_trace'], isA<String>());
      final data = details['error_data'];
      if (data is Map) {
        expect(
          data.containsKey('uuid'),
          isFalse,
          reason: 'uuid is hoisted beside error_type, never in error_data',
        );
      }
      return details;
    }

    test('QuoteWorsened carries the fresh route and no executed one', () async {
      final fresh = route(toAmount: '98.8', toAmountMin: '98.31');
      final details = await failed(
        RoutedSwapRunError.quoteWorsened(freshRoute: fresh),
      );
      expect(details['error_type'], 'QuoteWorsened');
      expect(details['error'], 'Fresh route is below the accepted minimum');
      expect(details.containsKey('executed_route'), isFalse);
      expect(details['error_data'], {
        'fresh_route': fresh.toJson(amount: '100.5'),
      });
    });

    test('a route below the guard fails QuoteWorsened on its own', () async {
      // Passing the expected amount as min_to_amount instead of the minimum
      // is caught here exactly as the engine's guard catches it.
      final fixture = RoutedSwapFixture()..quote(route());
      final result = await terminal(
        RoutedSwapRun(),
        fixture: fixture,
        minToAmount: '100.21',
      );
      expect(_map(result['details'])['error_type'], 'QuoteWorsened');
    });

    test('fresh-quote errors carry no executed_route', () async {
      for (final error in [
        RoutedSwapRunError.noRouteFound(providerRequestId: 'req'),
        RoutedSwapRunError.rateLimited(),
        RoutedSwapRunError.providerApiError('upstream'),
        RoutedSwapRunError.amountOutOfBounds(
          param: 'amount',
          value: '0.1',
          min: '1',
          max: '100',
        ),
        RoutedSwapRunError.transportError(
          'Unable to reach routed swap provider',
        ),
      ]) {
        final details = await failed(error);
        expect(
          details.containsKey('executed_route'),
          isFalse,
          reason: error.errorType,
        );
      }
    });

    test('errors after FetchingQuote carry executed_route', () async {
      final expected = <RoutedSwapRunError, Map<String, dynamic>>{
        RoutedSwapRunError.insufficientBalance(
          coin: 'MATIC',
          available: '0.001',
          requiredAmount: '0.0159',
        ): {
          'error':
              'Insufficient MATIC balance: available 0.001, required 0.0159',
          'error_data': {
            'coin': 'MATIC',
            'available': '0.001',
            'required': '0.0159',
          },
        },
        RoutedSwapRunError.preflightRejected('target_allowlist'): {
          'error':
              'Routed swap preflight rejected by the target_allowlist check',
          'error_data': {'check': 'target_allowlist'},
        },
        RoutedSwapRunError.approvalFailed('approval_transaction_failed'): {
          'error': 'Token approval failed: approval_transaction_failed',
          'error_data': {'reason': 'approval_transaction_failed'},
        },
        RoutedSwapRunError.signingRejected('user_rejected'): {
          'error': 'Wallet rejected the routed swap transaction: user_rejected',
          'error_data': {'reason': 'user_rejected'},
        },
        RoutedSwapRunError.internalError('Source wallet address changed'): {
          'error': 'Source wallet address changed',
          'error_data': {'message': 'Source wallet address changed'},
        },
      };
      for (final MapEntry(key: error, value: wire) in expected.entries) {
        final details = await failed(error);
        expect(details['executed_route'], isA<Map<String, dynamic>>());
        expect(details['error_type'], error.errorType);
        expect(details['error'], wire['error']);
        expect(details['error_data'], wire['error_data']);
      }
    });

    test('SwapTxFailed names the source transaction', () async {
      for (final reason in [
        'source_transaction_reverted',
        'source_transaction_not_confirmed',
      ]) {
        final details = await failed(RoutedSwapRunError.swapTxFailed(reason));
        final data = _map(details['error_data']);
        expect(data.keys.toSet(), {'source_tx_hash', 'reason'});
        expect(data['reason'], reason);
        expect(
          details['error'],
          'Routed swap transaction ${data['source_tx_hash']} failed: $reason',
        );
      }
    });

    test(
      'BridgeFailed omits absent fields and never has a request id',
      () async {
        final bare = await failed(
          RoutedSwapRunError.bridgeFailed(substatus: null),
        );
        expect(_map(bare['error_data']).keys, ['source_tx_hash']);

        final full = await failed(
          RoutedSwapRunError.bridgeFailed(
            substatusMessage: 'Manual support is required',
            providerExplorerUrl: 'https://scan.li.fi/tx/0x1',
          ),
        );
        expect(full['error_data'], {
          'source_tx_hash': _map(full['error_data'])['source_tx_hash'],
          'substatus': 'UNKNOWN_ERROR',
          'substatus_message': 'Manual support is required',
          'provider_explorer_url': 'https://scan.li.fi/tx/0x1',
        });
      },
    );

    test('InternalError is legal after Broadcasting', () async {
      final details = await failed(
        RoutedSwapRunError.internalError(
          'Broadcast handoff did not return a transaction hash',
        ),
        ladder: const [
          RoutedSwapTick.fetchingQuote,
          RoutedSwapTick.checkingAllowance,
          RoutedSwapTick.signing,
          RoutedSwapTick.broadcasting(withSourceTxHash: false),
        ],
      );
      expect(details['executed_route'], isA<Map<String, dynamic>>());
    });
  });

  group('stage guards', () {
    const preBroadcast = [
      RoutedSwapTick.fetchingQuote,
      RoutedSwapTick.checkingAllowance,
      RoutedSwapTick.signing,
    ];
    const confirming = [
      ...preBroadcast,
      RoutedSwapTick.broadcasting(),
      RoutedSwapTick.waitingSourceConfirmation,
    ];
    const tracking = [...confirming, RoutedSwapTick.trackingBridge()];

    void impossible(
      String why,
      RoutedSwapRunError? error,
      List<RoutedSwapTick> ladder, {
      RoutedSwapQuote? executed,
    }) {
      expect(
        () => RoutedSwapRun(route: executed, error: error, ladder: ladder),
        throwsArgumentError,
        reason: why,
      );
    }

    test('refuses errors raised where the engine cannot raise them', () {
      impossible(
        'fresh-quote errors happen while FetchingQuote',
        RoutedSwapRunError.rateLimited(),
        preBroadcast,
      );
      impossible(
        'balances are checked before any approval or signing',
        RoutedSwapRunError.insufficientBalance(
          coin: 'MATIC',
          available: '0',
          requiredAmount: '1',
        ),
        preBroadcast,
      );
      impossible(
        'preflight runs before Signing',
        RoutedSwapRunError.preflightRejected('simulation'),
        preBroadcast,
      );
      impossible(
        'approvals fail at Approving',
        RoutedSwapRunError.approvalFailed('approval_broadcast_failed'),
        preBroadcast,
      );
      impossible(
        'a failed approval transaction was broadcast, so it has a hash',
        RoutedSwapRunError.approvalFailed('approval_transaction_failed'),
        const [
          RoutedSwapTick.fetchingQuote,
          RoutedSwapTick.checkingAllowance,
          RoutedSwapTick.approving(),
        ],
      );
      impossible(
        'the source transaction fails at WaitingSourceConfirmation',
        RoutedSwapRunError.swapTxFailed('source_transaction_reverted'),
        preBroadcast,
      );
      impossible(
        'a confirmed source transaction cannot fail later',
        RoutedSwapRunError.swapTxFailed('source_transaction_reverted'),
        tracking,
      );
      impossible(
        'BridgeFailed happens while tracking',
        RoutedSwapRunError.bridgeFailed(),
        confirming,
      );
      impossible(
        'same-chain swaps never track a bridge',
        RoutedSwapRunError.bridgeFailed(),
        tracking,
        executed: route(crossChain: false),
      );
      impossible(
        'transport problems after broadcast keep tracking',
        RoutedSwapRunError.transportError('socket closed'),
        confirming,
      );
      impossible(
        'a local signer broadcasting with a hash cannot be rejected',
        RoutedSwapRunError.signingRejected('timeout'),
        [...preBroadcast, const RoutedSwapTick.broadcasting()],
      );
      impossible(
        'an Ok outcome needs a confirmed source transaction',
        null,
        preBroadcast,
      );
    });

    test('accepts the external-wallet exceptions', () {
      expect(
        () => RoutedSwapRun(
          error: RoutedSwapRunError.signingRejected('timeout'),
          ladder: [
            ...preBroadcast,
            const RoutedSwapTick.broadcasting(withSourceTxHash: false),
          ],
        ),
        returnsNormally,
      );
      expect(
        () => RoutedSwapRun(
          error: RoutedSwapRunError.internalError('handoff failed'),
          ladder: tracking,
        ),
        returnsNormally,
      );
    });

    test('refuses a ladder the engine cannot persist', () {
      impossible('init persists FetchingQuote first', null, const [
        RoutedSwapTick.checkingAllowance,
      ]);
      impossible('states only move forward', null, const [
        RoutedSwapTick.fetchingQuote,
        RoutedSwapTick.signing,
      ]);
      impossible(
        'the first Approving precedes any broadcast approval',
        RoutedSwapRunError.approvalFailed('approval_broadcast_failed'),
        const [
          RoutedSwapTick.fetchingQuote,
          RoutedSwapTick.checkingAllowance,
          RoutedSwapTick.approving('0xa'),
        ],
      );
      impossible('the first TrackingBridge is bare', null, [
        ...confirming,
        const RoutedSwapTick.trackingBridge(substatus: 'PENDING'),
      ]);
      expect(
        () => RoutedSwapRun(
          outcome: RoutedSwapRunOutcome.completed,
          error: RoutedSwapRunError.rateLimited(),
        ),
        throwsArgumentError,
      );
      expect(
        () => RoutedSwapRun(outcome: RoutedSwapRunOutcome.partial),
        throwsArgumentError,
      );
      expect(
        () => RoutedSwapRunError.bridgeFailed(substatus: 'REFUND_IN_PROGRESS'),
        throwsArgumentError,
      );
    });

    test('a route below the guard cannot reach a later error', () async {
      final fixture = RoutedSwapFixture()..quote(route());
      await expectLater(
        terminal(
          RoutedSwapRun(
            error: RoutedSwapRunError.insufficientBalance(
              coin: 'MATIC',
              available: '0',
              requiredAmount: '1',
            ),
          ),
          fixture: fixture,
          minToAmount: '100.21',
        ),
        throwsArgumentError,
      );
    });

    test('non-positive amounts are init rejections to script', () async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun())).build();
      await expectLater(start(script, minToAmount: '0'), throwsArgumentError);
      final malformed = await call(script, 'task::routed_swap::init', {
        'from': from,
        'to': to,
        'amount': 'lots',
        'min_to_amount': '1',
      });
      expect(malformed['error_type'], 'InvalidRequest');
    });

    test('QuoteWorsened needs a fresh minimum below the guard', () async {
      await expectLater(
        terminal(
          RoutedSwapRun(
            error: RoutedSwapRunError.quoteWorsened(freshRoute: route()),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('forget_if_finished', () {
    Future<(KdfScript, int)> finishedTask() async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun())).build();
      final taskId = await start(script);
      await drain(script, taskId);
      return (script, taskId);
    }

    test('defaults to true and forgets the terminal result', () async {
      final (script, taskId) = await finishedTask();
      final read = await poll(script, taskId, forget: null);
      expect(_map(read['result'])['status'], 'Ok');

      final again = await poll(script, taskId);
      expect(again['error_type'], 'NoSuchTask');
      expect(again.containsKey('result'), isFalse);
    });

    test('false keeps the terminal result readable', () async {
      final (script, taskId) = await finishedTask();
      final first = await poll(script, taskId);
      final second = await poll(script, taskId);
      expect(first['result'], second['result']);
    });

    test('an in-progress read never forgets', () async {
      final script = (RoutedSwapFixture()..run(RoutedSwapRun())).build();
      final taskId = await start(script);
      await poll(script, taskId, forget: true);
      final again = await poll(script, taskId, forget: true);
      expect(_map(again['result'])['status'], 'InProgress');
    });

    test('an unknown task is NoSuchTask with the bare id', () async {
      final response = await poll(RoutedSwapFixture().build(), 99);
      expect(response['error_type'], 'NoSuchTask');
      expect(response['error_data'], 99);
      expect(response['error'], "No such task '99'");
    });
  });
}
