import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

// Gas funding, measured payouts and GasEstimationFailed, as KDF 667045c and
// gleec-specs#2 at 2880c32 report them.

/// A native ETH sell whose route reports its gas [total] per row.
JsonMap _nativeRoute(List<JsonMap> total, {List<JsonMap> fees = const []}) =>
    routeJson(
      from: 'ETH',
      fromAmount: '2',
      gasCosts: const [
        {'coin': 'ETH', 'amount': '0.0005'},
      ],
      totalGasCosts: total,
      feeCosts: fees,
    );

ScriptedKdf _quoting(JsonMap route) => ScriptedKdf()
  ..always(
    'routed_swap::quote',
    (_) => ok({
      'routes': [route],
    }),
  );

JsonMap _finished({JsonMap? received, JsonMap? providerReceived}) => {
  'status': 'Ok',
  'details': {
    'uuid': uuidOf(1),
    'provider': 'lifi',
    'executed_route': routeJson(),
    'outcome': 'completed',
    'received': ?received,
    'provider_received': ?providerReceived,
    'source_tx_hash': '0xsource',
    'dest_tx_hash': '0xdest',
  },
};

JsonMap _gasEstimationFailed() => failedWith(
  uuidOf(1),
  'GasEstimationFailed',
  data: {'coin': 'ETH', 'message': 'Unable to estimate source-chain gas costs'},
  route: routeJson(),
);

RoutedSwapProgress _first(JsonMap status) => fakeAsync((async) {
  final kdf = ScriptedKdf();
  final handle = startSwap(async, kdf, managerFor(kdf), first: status);
  return handle.latest;
});

void main() {
  group('the network fee', () {
    test('carries the required balance from the engine totals', () async {
      final kdf = _quoting(
        _nativeRoute(const [
          {'coin': 'ETH', 'amount': '0.0005', 'required_balance': '0.0016'},
        ]),
      );
      final offer = await managerFor(
        kdf,
      ).quote(from: eth, to: usdt, amount: d('2'));
      final fee = offer.networkFees.single;
      expect(fee.amount, d('0.0005'));
      expect(fee.requiredBalance, d('0.0016'));
    });

    test('sums the required balance over rows of the same coin', () async {
      final kdf = _quoting(
        _nativeRoute(const [
          {'coin': 'ETH', 'amount': '0.0005', 'required_balance': '0.0016'},
          {'coin': 'ETH', 'amount': '0.0001', 'required_balance': '0.0004'},
        ]),
      );
      final offer = await managerFor(
        kdf,
      ).quote(from: eth, to: usdt, amount: d('2'));
      expect(offer.networkFees.single.amount, d('0.0006'));
      expect(offer.networkFees.single.requiredBalance, d('0.002'));
    });

    test('has none when any row of the coin lacks it', () async {
      final kdf = _quoting(
        _nativeRoute(const [
          {'coin': 'ETH', 'amount': '0.0005', 'required_balance': '0.0016'},
          {'coin': 'ETH', 'amount': '0.0001'},
        ]),
      );
      final offer = await managerFor(
        kdf,
      ).quote(from: eth, to: usdt, amount: d('2'));
      expect(offer.networkFees.single.requiredBalance, isNull);
    });
  });

  test(
    'Max keeps the KDF amount and reports funding without a multiplier',
    () async {
      final kdf = _quoting(
        _nativeRoute([
          {'coin': 'ETH', 'amount': '0.0005', 'required_balance': '0.0016'},
        ]),
      );
      final max = await managerFor(
        kdf,
      ).maxSellAmount(from: eth, to: usdt, balance: d('2'));
      expect(max.amount, d(max.offer!.route.from.amount));
      expect(max.reservedForFees, d('0.0016'));
      expect(kdf.paramsFor('routed_swap::quote').single['max'], isTrue);
      expect(
        kdf.paramsFor('routed_swap::quote').single,
        isNot(contains('amount')),
      );
    },
  );

  group('a finished swap', () {
    test('a measured payout is the receipt amount', () {
      final receipt = _first(
        _finished(
          received: {'coin': 'USDT-PLG20', 'amount': '99.4'},
          providerReceived: {'coin': 'USDT-PLG20', 'amount': '99.45'},
        ),
      ).receipt!;
      expect(receipt.amount, d('99.4'));
      expect(receipt.isMeasured, isTrue);
      expect(receipt.assetId, usdt);
      expect(receipt.reported!.amount, d('99.45'));
      expect(receipt.reported!.assetId, usdt);
    });

    test('a payout KDF could not measure keeps only the report', () {
      final progress = _first(
        _finished(providerReceived: {'symbol': 'USDT', 'amount': '99.45'}),
      );
      final receipt = progress.receipt!;
      expect(progress.isSuccess, isTrue);
      expect(receipt.amount, isNull);
      expect(receipt.isMeasured, isFalse);
      expect(receipt.assetId, isNull);
      expect(receipt.reported!.amount, d('99.45'));
      expect(receipt.reported!.assetId, isNull);
      expect(receipt.tokenLabel, 'USDT');
    });

    test('a swap with neither amount still finishes', () {
      final receipt = _first(_finished()).receipt!;
      expect(receipt.amount, isNull);
      expect(receipt.reported, isNull);
      expect(receipt.isSuccess, isTrue);
      expect(receipt.tokenLabel, isEmpty);
    });

    test('a bridge carries the provider report while KDF measures', () {
      final status = inProgress(
        uuidOf(1),
        'TrackingBridge',
        route: routeJson(),
        sourceTxHash: '0xsource',
        stage: 'destination_pending',
      );
      (status['details'] as JsonMap)['provider_received'] = {
        'coin': 'USDT-PLG20',
        'amount': '99.45',
      };
      final progress = _first(status);
      expect(progress.phase, RoutedSwapPhase.bridging);
      expect(progress.receipt, isNull);
      expect(progress.providerReported!.amount, d('99.45'));
      expect(progress.providerReported!.assetId, usdt);
    });
  });

  group('GasEstimationFailed', () {
    test('names the coin, was not sent and may be retried', () {
      final failure = _first(_gasEstimationFailed()).failure!;
      expect(failure.kind, RoutedSwapFailureKind.gasEstimationFailed);
      expect(failure.gasCoin, 'ETH');
      expect(failure.errorType, 'GasEstimationFailed');
      expect(failure.retryPolicy, RoutedSwapRetryPolicy.retry);
      expect(failure.fundsMovement, RoutedSwapFundsMovement.none);
      expect(failure.isRetryable, isTrue);
    });

    test('after an approval, the approval gas counts as spent', () {
      fakeAsync((async) {
        final kdf = ScriptedKdf()
          ..always(
            'routed_swap::history',
            (_) => historyAnswer([
              entryJson(
                _gasEstimationFailed(),
                finishedAt: 1754784010,
                approvals: const ['0xapprove'],
              ),
            ]),
          );
        final handle = awaited(async, managerFor(kdf).watch(uuidOf(1)));
        final failure = handle.latest.failure!;
        expect(failure.kind, RoutedSwapFailureKind.gasEstimationFailed);
        expect(failure.fundsMovement, RoutedSwapFundsMovement.feesOnly);
        expect(failure.fundsUntouched, isFalse);
      });
    });

    test('a coin left empty on the wire is not named', () {
      final failure = _first(
        failedWith(
          uuidOf(1),
          'GasEstimationFailed',
          data: {'message': 'Unable to estimate source-chain gas costs'},
        ),
      ).failure!;
      expect(failure.gasCoin, isNull);
    });
  });
}
