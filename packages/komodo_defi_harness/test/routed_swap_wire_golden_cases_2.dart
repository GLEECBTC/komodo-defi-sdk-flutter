part of 'routed_swap_wire_golden_test.dart';

void _cases2() {
  group('task::routed_swap::status in progress', () {
    rpc.RoutedSwapInProgress inProgress(Map<String, dynamic> details) =>
        _status('InProgress', details) as rpc.RoutedSwapInProgress;

    test('FetchingQuote carries no executed route yet', () {
      final status = inProgress({
        'state': 'FetchingQuote',
        'uuid': _uuid,
        'provider': 'lifi',
      });
      expect(status.state, rpc.RoutedSwapState.fetchingQuote);
      expect(status.uuid, _uuid);
      expect(status.provider, 'lifi');
      expect(status.executedRoute, isNull);
      expect(status.state.isCancellable, isTrue);
    });

    test('every later state carries the executed route', () {
      for (final state in [
        'CheckingAllowance',
        'Approving',
        'Signing',
        'Broadcasting',
      ]) {
        final status = inProgress({
          'state': state,
          'uuid': _uuid,
          'provider': 'lifi',
          'executed_route': _nativeRoute,
        });
        expect(status.rawState, state);
        expect(status.state, isNot(rpc.RoutedSwapState.unknown));
        expect(
          status.executedRoute,
          rpc.RoutedSwapRoute.fromJson(_nativeRoute),
        );
        expect(status.sourceTxHash, isNull);
      }
    });

    test('Approving gains the approval hash once broadcast', () {
      final status = inProgress({
        'state': 'Approving',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _erc20Route,
        'approve_tx_hash': _approveHash,
      });
      expect(status.approveTxHash, _approveHash);
      expect(status.state.isCancellable, isTrue);
    });

    test('Broadcasting and confirmation carry the source hash', () {
      final broadcasting = inProgress({
        'state': 'Broadcasting',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
      });
      expect(broadcasting.sourceTxHash, _sourceHash);
      expect(broadcasting.state.isCancellable, isFalse);

      final waiting = inProgress({
        'state': 'WaitingSourceConfirmation',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
      });
      expect(waiting.state, rpc.RoutedSwapState.waitingSourceConfirmation);
      expect(waiting.sourceTxHash, _sourceHash);
    });

    test('TrackingBridge: the bare first poll, then provider detail', () {
      final first = inProgress({
        'state': 'TrackingBridge',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
        'stage': 'unknown',
        'execution_duration_s': 31,
      });
      expect(first.stage, rpc.RoutedSwapBridgeStage.unknown);
      expect(first.substatus, isNull);
      expect(first.providerExplorerUrl, isNull);
      expect(first.executionDurationS, 31);

      final pending = inProgress({
        'state': 'TrackingBridge',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
        'stage': 'destination_pending',
        'substatus': 'WAIT_DESTINATION_TRANSACTION',
        'substatus_message': 'Waiting for the destination transaction.',
        'provider_explorer_url': 'https://scan.li.fi/tx/$_sourceHash',
        'execution_duration_s': 31,
      });
      expect(pending.stage, rpc.RoutedSwapBridgeStage.destinationPending);
      expect(pending.substatus, 'WAIT_DESTINATION_TRANSACTION');
      expect(pending.substatusMessage, startsWith('Waiting'));
      expect(pending.providerExplorerUrl, endsWith(_sourceHash));

      for (final (wire, stage) in [
        ('bridging', rpc.RoutedSwapBridgeStage.bridging),
        ('refund_pending', rpc.RoutedSwapBridgeStage.refundPending),
        ('teleporting', rpc.RoutedSwapBridgeStage.unknown),
      ]) {
        final status = inProgress({
          'state': 'TrackingBridge',
          'uuid': _uuid,
          'provider': 'lifi',
          'executed_route': _nativeRoute,
          'source_tx_hash': _sourceHash,
          'stage': wire,
          'execution_duration_s': 31,
        });
        expect(status.stage, stage);
        expect(status.rawStage, wire);
      }
    });

    test('action_required carries action_url (not emitted in v1)', () {
      final status = inProgress({
        'state': 'TrackingBridge',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
        'stage': 'action_required',
        'action_url': 'https://li.fi/act',
        'execution_duration_s': 31,
      });
      expect(status.stage, rpc.RoutedSwapBridgeStage.actionRequired);
      expect(status.actionUrl, 'https://li.fi/act');
    });
  });

  group('task::routed_swap::status Ok', () {
    rpc.RoutedSwapFinished finished(Map<String, dynamic> details) =>
        _status('Ok', details) as rpc.RoutedSwapFinished;

    test('completed cross-chain', () {
      final status = finished({
        'outcome': 'completed',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'received': {'coin': 'USDC-POLYGON', 'amount': '2'},
        'source_tx_hash': _sourceHash,
        'dest_tx_hash': _destHash,
        'provider_explorer_url': 'https://scan.li.fi/tx/$_sourceHash',
      });
      expect(status.outcome, rpc.RoutedSwapOutcome.completed);
      expect(status.outcome.isSuccess, isTrue);
      expect(status.partialReason, isNull);
      expect(status.received.coin, 'USDC-POLYGON');
      expect(status.received.amount, '2');
      expect(status.sourceTxHash, _sourceHash);
      expect(status.destTxHash, _destHash);
      expect(status.executedRoute, isNotNull);
    });

    test('completed same-chain has no destination hash nor link', () {
      final status = finished({
        'outcome': 'completed',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'received': {'coin': 'USDT-ETH', 'amount': '2'},
        'source_tx_hash': _sourceHash,
      });
      expect(status.destTxHash, isNull);
      expect(status.providerExplorerUrl, isNull);
    });

    test('partial carries partial_reason and is not a success', () {
      final below = finished({
        'outcome': 'partial',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'partial_reason': 'below_minimum',
        'received': {'coin': 'USDC-POLYGON', 'amount': '1.5'},
        'source_tx_hash': _sourceHash,
        'dest_tx_hash': _destHash,
      });
      expect(below.outcome.isSuccess, isFalse);
      expect(below.partialReason, rpc.RoutedSwapPartialReason.belowMinimum);

      final intermediate = finished({
        'outcome': 'partial',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'partial_reason': 'intermediate_token',
        'received': {'symbol': 'axlUSDC', 'amount': '1.99'},
        'source_tx_hash': _sourceHash,
        'dest_tx_hash': _destHash,
      });
      expect(
        intermediate.partialReason,
        rpc.RoutedSwapPartialReason.intermediateToken,
      );
      expect(intermediate.received.isKnownAsset, isFalse);
      expect(intermediate.received.label, 'axlUSDC');
    });

    test('refunded returns the source coin, with no destination hash', () {
      final status = finished({
        'outcome': 'refunded',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'received': {'coin': 'ETH', 'amount': '1'},
        'source_tx_hash': _sourceHash,
        'provider_explorer_url': 'https://scan.li.fi/tx/$_sourceHash',
      });
      expect(status.outcome, rpc.RoutedSwapOutcome.refunded);
      expect(status.outcome.isSuccess, isFalse);
      expect(status.received.coin, 'ETH');
      expect(status.destTxHash, isNull);
    });
  });
}
