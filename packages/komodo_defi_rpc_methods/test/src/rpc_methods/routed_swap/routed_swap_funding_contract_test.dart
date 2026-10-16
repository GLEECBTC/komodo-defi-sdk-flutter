import 'dart:convert';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

// The contract fields KDF added with measured payouts, L2 fee accounting and
// gas funding (gleec-specs#2 at 2880c32; KDF 667045c).

const String _uuid = '0d4dbd0c-5a4e-4b7f-9c1d-2e3f4a5b6c7d';

/// [json] after a trip through JSON text, as a stored or exported copy.
JsonMap _wire(JsonMap json) => jsonDecode(jsonEncode(json)) as JsonMap;

const JsonMap _route = {
  'provider': 'lifi',
  'from': {'coin': 'USDT-PLG20', 'amount': '100'},
  'to': {'coin': 'USDT-ERC20', 'amount': '99.8', 'amount_min': '99.3'},
  'tool': {'key': 'stargateV2', 'name': 'StargateV2'},
  'kind': 'cross_chain',
  'approval': {
    'required': true,
    'tx_count': 1,
    'reason': 'no_allowance',
    'spender': '0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE',
    'gas_costs': [
      {'coin': 'POL', 'amount': '0.0009', 'amount_usd': '0.00045'},
    ],
  },
  'total_gas_costs': [
    {
      'coin': 'POL',
      'amount': '0.0129',
      'required_balance': '0.02',
      'amount_usd': '0.00645',
    },
  ],
  'gas_costs': [
    {'coin': 'POL', 'amount': '0.012', 'amount_usd': '0.006'},
  ],
};

JsonMap _ok({
  String outcome = 'completed',
  JsonMap? received,
  JsonMap? providerReceived,
  String? destTxHash,
}) => {
  'uuid': _uuid,
  'provider': 'lifi',
  'executed_route': _route,
  'outcome': outcome,
  'received': ?received,
  'provider_received': ?providerReceived,
  'source_tx_hash': '0xsource',
  'dest_tx_hash': ?destTxHash,
};

void main() {
  group('gas funding on a quote', () {
    test('a total carries the required balance, an itemized row none', () {
      final route = RoutedSwapRoute.fromJson(_route);
      final total = route.totalGasCosts.single;
      expect(total.amount.amount, '0.0129');
      expect(total.requiredBalance, '0.02');
      expect(total.amountUsd, '0.00645');
      expect(route.gasCosts.single.requiredBalance, isNull);
      expect(route.approval!.gasCosts.single.requiredBalance, isNull);
      expect(route.approval!.gasCosts.single.amountUsd, '0.00045');
    });

    test('the required balance survives a round trip, and only on totals', () {
      final route = RoutedSwapRoute.fromJson(_route);
      final json = _wire(route.toJson());
      expect(json['total_gas_costs'], [
        {
          'coin': 'POL',
          'amount': '0.0129',
          'required_balance': '0.02',
          'amount_usd': '0.00645',
        },
      ]);
      expect(
        (json['gas_costs'] as List).single,
        isNot(contains('required_balance')),
      );
      expect(RoutedSwapRoute.fromJson(json), route);
    });

    test('an engine older than the funding contract reports none', () {
      final route = RoutedSwapRoute.fromJson({
        ..._route,
        'total_gas_costs': [
          {'coin': 'POL', 'amount': '0.0129'},
        ],
      });
      expect(route.totalGasCosts.single.requiredBalance, isNull);
      expect(
        route.totalGasCosts.single,
        isNot(RoutedSwapRoute.fromJson(_route).totalGasCosts.single),
      );
    });
  });

  group('a bridge the provider reports finished', () {
    const tracking = {
      'uuid': _uuid,
      'provider': 'lifi',
      'state': 'TrackingBridge',
      'executed_route': _route,
      'source_tx_hash': '0xsource',
      'stage': 'destination_pending',
      'execution_duration_s': 95,
      'provider_received': {'coin': 'USDT-ERC20', 'amount': '99.71'},
    };

    test('carries the provider report while KDF measures', () {
      final status =
          RoutedSwapStatus.parse('InProgress', tracking)
              as RoutedSwapInProgress;
      expect(status.providerReceived!.coin, 'USDT-ERC20');
      expect(status.providerReceived!.amount, '99.71');
      expect(
        RoutedSwapStatus.parse('InProgress', _wire(status.toJson())),
        status,
      );
    });

    test('has no report before the provider gives one', () {
      final status =
          RoutedSwapStatus.parse(
                'InProgress',
                {...tracking}..remove('provider_received'),
              )
              as RoutedSwapInProgress;
      expect(status.providerReceived, isNull);
      expect(status.toJson(), isNot(contains('provider_received')));
    });
  });

  group('a terminal Ok', () {
    test('keeps the measured and the reported payouts apart', () {
      final status =
          RoutedSwapStatus.parse(
                'Ok',
                _ok(
                  received: {'coin': 'USDT-ERC20', 'amount': '99.69'},
                  providerReceived: {'coin': 'USDT-ERC20', 'amount': '99.71'},
                  destTxHash: '0xdest',
                ),
              )
              as RoutedSwapFinished;
      expect(status.received!.amount, '99.69');
      expect(status.providerReceived!.amount, '99.71');
      expect(RoutedSwapStatus.parse('Ok', _wire(status.toJson())), status);
    });

    test('reads a payout KDF could not measure, from the report alone', () {
      final status =
          RoutedSwapStatus.parse(
                'Ok',
                _ok(
                  providerReceived: {'symbol': 'USDT', 'amount': '99.71'},
                  destTxHash: '0xdest',
                ),
              )
              as RoutedSwapFinished;
      expect(status.outcome, RoutedSwapOutcome.completed);
      expect(status.received, isNull);
      expect(status.providerReceived!.isKnownAsset, isFalse);
      final json = status.toJson();
      expect(json, isNot(contains('received')));
      expect(RoutedSwapStatus.parse('Ok', _wire(json)), status);
    });

    test('reads a same-chain swap with neither amount', () {
      final status = RoutedSwapStatus.parse('Ok', _ok()) as RoutedSwapFinished;
      expect(status.outcome.isSuccess, isTrue);
      expect(status.received, isNull);
      expect(status.providerReceived, isNull);
      expect(status.destTxHash, isNull);
    });

    test('reads a refund KDF could not measure as a refund', () {
      final status =
          RoutedSwapStatus.parse('Ok', _ok(outcome: 'refunded'))
              as RoutedSwapFinished;
      expect(status.outcome, RoutedSwapOutcome.refunded);
      expect(status.outcome.isSuccess, isFalse);
      expect(status.received, isNull);
    });

    test('a history entry keeps both amounts inside its swap', () {
      final entry = RoutedSwapHistoryEntry.fromJson({
        'created_at': 1,
        'updated_at': 2,
        'finished_at': 2,
        'requested': {
          'from': 'USDT-PLG20',
          'to': 'USDT-ERC20',
          'amount': '100',
        },
        'min_to_amount_accepted': '99.3',
        'approval_tx_hashes': ['0xapprove'],
        'gas_spent': [
          {'tx_hash': '0xsource', 'coin': 'POL', 'amount': '0.011'},
        ],
        'total_gas_spent': [
          {'coin': 'POL', 'amount': '0.011'},
        ],
        'swap': {
          'status': 'Ok',
          'details': _ok(
            providerReceived: {'coin': 'USDT-ERC20', 'amount': '99.71'},
            destTxHash: '0xdest',
          ),
        },
      });
      final swap = entry.swap as RoutedSwapFinished;
      expect(swap.received, isNull);
      expect(swap.providerReceived!.amount, '99.71');
      expect(RoutedSwapHistoryEntry.fromJson(_wire(entry.toJson())), entry);
    });
  });

  group('GasEstimationFailed', () {
    test('as a terminal task error, names the coin and was not sent', () {
      final error =
          RoutedSwapTaskError.parse('GasEstimationFailed', {
                'coin': 'POL',
                'message': 'Unable to estimate source-chain gas costs',
              })
              as RoutedSwapGasEstimationFailedTaskError;
      expect(error.coin, 'POL');
      expect(error.message, 'Unable to estimate source-chain gas costs');
      expect(error.errorType, 'GasEstimationFailed');
      expect(error.isPreBroadcast, isTrue);
      expect(error.providerRequestId, isNull);
      expect(
        RoutedSwapTaskError.parse(error.errorType, _wire(error.toJson())),
        error,
      );
    });

    test('inside a status read, arrives as an ordinary Error result', () {
      final status =
          RoutedSwapStatus.parse('Error', {
                'uuid': _uuid,
                'provider': 'lifi',
                'executed_route': _route,
                'error_type': 'GasEstimationFailed',
                'error': 'Unable to estimate source-chain gas costs',
                'error_data': {
                  'coin': 'POL',
                  'message': 'Unable to estimate source-chain gas costs',
                },
              })
              as RoutedSwapErrored;
      expect(status.error, isA<RoutedSwapGasEstimationFailedTaskError>());
      expect(RoutedSwapStatus.parse('Error', _wire(status.toJson())), status);
    });

    test('as a quote error, is typed and transient', () {
      final error =
          RoutedSwapRpcException.tryParse({
                'mmrpc': '2.0',
                'error': 'Unable to estimate source-chain approval cost',
                'error_type': 'GasEstimationFailed',
                'error_data': {
                  'coin': 'ETH',
                  'message': 'Unable to estimate source-chain approval cost',
                },
                'id': null,
              })
              as RoutedSwapGasEstimationFailedException;
      expect(error.coin, 'ETH');
      expect(error.detail, 'Unable to estimate source-chain approval cost');
      expect(error.errorType, 'GasEstimationFailed');
      expect(error.isTransient, isTrue);
      expect(error.providerRequestId, isNull);
    });
  });
}
