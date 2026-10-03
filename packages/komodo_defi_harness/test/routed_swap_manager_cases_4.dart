part of 'routed_swap_manager_test.dart';

void _cases4() {
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
