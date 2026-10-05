import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

part 'routed_swap_live_capture_payloads.dart';

/// Parses what the pinned engine actually sent, with the real SDK models.
///
/// The wire-golden suite is written from the engine's source; this one is
/// recorded from the engine itself, so it catches what reading the source
/// cannot — envelope keys the source never mentions (`"id": null`), provider
/// fee rows in a token other than the pair's, and the local errors' real
/// `error_data` shapes.

void main() {
  group('live capture: success responses', () {
    test('supported_coins lists every activated EVM coin', () async {
      final manager = _manager({
        'routed_swap::supported_coins': _supportedCoins,
      });
      expect(await manager.eligibleAssets(), {eth, pol, usdc, usdcPol});
      final parsed = rpc.RoutedSwapSupportedCoinsResponse.parse(
        _json(_supportedCoins),
      );
      expect(parsed.skipped, 0);
    });

    test(
      'a same-chain quote becomes an instant, approval-free offer',
      () async {
        final manager = _manager({'routed_swap::quote': _quoteSameChain});
        final offer = await manager.quote(
          from: eth,
          to: usdc,
          amount: Decimal.parse('0.05'),
        );
        expect(offer.isCrossChain, isFalse);
        expect(offer.sellAmount, Decimal.parse('0.05'));
        expect(offer.expectedReceive, Decimal.parse('132.767617'));
        // The provider's 132.103779 less the 0.3% guard margin.
        expect(offer.guaranteedReceive, Decimal.parse('131.707467'));
        expect(offer.estimatedDuration, Duration.zero);
        expect(offer.approval, isNull);
        expect(offer.fromAddress, offer.toAddress);
        expect(offer.legs.single.type, rpc.RoutedSwapStepType.swap);
        final fee = offer.costs.firstWhere(
          (c) => c.kind == RoutedSwapCostKind.providerFee,
        );
        expect(fee.assetId, eth);
        expect(fee.isDeductedFromReceive, isTrue);
        expect(offer.networkFees.single.assetId, eth);
        expect(
          offer.networkFees.single.amount,
          Decimal.parse('0.000563343781000275'),
        );
      },
    );

    test('a cross-chain quote keeps fees charged in a third token', () async {
      final manager = _manager({'routed_swap::quote': _quoteCrossChain});
      final offer = await manager.quote(
        from: pol,
        to: usdc,
        amount: Decimal.parse('50'),
      );
      expect(offer.isCrossChain, isTrue);
      expect(offer.estimatedDuration, const Duration(seconds: 2));
      expect(offer.legs.map((l) => l.type), [
        rpc.RoutedSwapStepType.swap,
        rpc.RoutedSwapStepType.cross,
      ]);
      expect(offer.legs.last.fromChainId, 137);
      expect(offer.legs.last.toChainId, 1);
      final relayer = offer.costs.where((c) => c.assetId == usdcPol);
      expect(relayer, hasLength(2));
      expect(relayer.every((c) => c.isDeductedFromReceive), isTrue);
      expect(offer.networkFees.single.assetId, pol);
    });

    test('an empty history page parses', () {
      final page = rpc.RoutedSwapHistoryResponse.parse(_json(_historyEmpty));
      expect(page.entries, isEmpty);
      expect(page.total, 0);
      expect(page.totalPages, 0);
    });
  });

  group('live capture: typed errors', () {
    test('an approval estimate the node refused is a transport error', () {
      final error = _quoteError(_approvalEstimateFailed);
      expect(error, isA<rpc.RoutedSwapTransportException>());
      expect(
        (error as rpc.RoutedSwapTransportException).detail,
        'Unable to estimate source-chain approval cost',
      );
    });

    test('a chain the provider does not serve is a provider error', () {
      // GLEEC's chain reaches the provider, which rejects it: the engine does
      // not check the provider's chain list before quoting.
      final error = _quoteError(_gleecChainRejected);
      expect(error, isA<rpc.RoutedSwapProviderException>());
      expect(error.providerRequestId, 'c0bdfaee-3321-4ef2-a80a-b06df1d68113');
    });

    test('a non-EVM coin is rejected locally as an unsupported pair', () {
      final error = _quoteError(_nonEvmPair);
      expect(error, isA<rpc.RoutedSwapPairNotSupportedException>());
      final pair = error as rpc.RoutedSwapPairNotSupportedException;
      expect(
        [pair.from, pair.to, pair.reason],
        ['KMD', 'ETH', 'KMD is not an EVM asset'],
      );
    });

    test('an inactive coin names itself', () {
      final error = _quoteError(_inactiveCoin);
      expect((error as rpc.RoutedSwapCoinNotActiveException).coin, 'BTC');
    });

    test('invalid parameters name the parameter', () {
      final decimals = _quoteError(_tooManyDecimals);
      expect((decimals as rpc.RoutedSwapInvalidParamException).param, 'amount');
      final provider = _quoteError(_unknownProvider);
      expect(
        (provider as rpc.RoutedSwapInvalidParamException).param,
        'provider',
      );
    });

    test('slippage over the cap is an out-of-bounds error on slippage', () {
      // Not on the amount: a caller mapping every bound to the amount would
      // tell the user to change the wrong number.
      final error = _quoteError(_slippageOutOfBounds);
      final bounds = error as rpc.RoutedSwapAmountOutOfBoundsException;
      expect(bounds.param, 'slippage');
      expect(bounds.max, '0.5');
    });

    test('a null optional field is a request error with string data', () {
      final error = _quoteError(_nullOptional);
      expect(error, isA<rpc.RoutedSwapUnknownRpcException>());
      expect(error.errorType, 'InvalidRequest');
      expect(error.errorData, isA<String>());
    });

    test('status for an unknown task carries the id as a bare number', () {
      rpc.RoutedSwapRpcException? error;
      try {
        rpc.RoutedSwapStatusRequest(
          rpcPass: '',
          taskId: 987654,
        ).parseResponseJson(_json(_statusNoSuchTask));
      } on rpc.RoutedSwapRpcException catch (e) {
        error = e;
      }
      expect(error, isA<rpc.RoutedSwapNoSuchTaskException>());
      expect((error! as rpc.RoutedSwapNoSuchTaskException).taskId, 987654);
    });
  });

  group('live capture: round trips', () {
    test('every captured success response writes itself back', () {
      final history = rpc.RoutedSwapHistoryResponse.parse(_json(_historyEmpty));
      expect(history.toJson(), _json(_historyEmpty)..remove('id'));
      final page = rpc.RoutedSwapHistoryResponse.parse(_wire(history.toJson()));
      expect(page.mmrpc, history.mmrpc);
      expect(page.entries, history.entries);
      expect(
        [page.total, page.limit, page.pageNumber, page.totalPages],
        [0, 10, 1, 0],
      );

      for (final raw in [_quoteSameChain, _quoteCrossChain]) {
        final quote = rpc.RoutedSwapQuoteResponse.parse(_json(raw));
        expect(quote.toJson(), _json(raw)..remove('id'));
        expect(
          rpc.RoutedSwapQuoteResponse.parse(_wire(quote.toJson())).routes,
          quote.routes,
        );
      }

      final coins = rpc.RoutedSwapSupportedCoinsResponse.parse(
        _json(_supportedCoins),
      );
      expect(coins.toJson(), _json(_supportedCoins)..remove('id'));
    });

    // No status or non-empty history was captured: the capture wallet held no
    // funds, so no swap ever ran. The envelopes below are the contract's; the
    // routes inside them are the engine's own.
    test('status and history around a captured route read back equal', () {
      for (final raw in [_quoteSameChain, _quoteCrossChain]) {
        final route = _capturedRoute(raw);
        final from = route['from'] as JsonMap;
        final to = route['to'] as JsonMap;
        final swaps = <String, JsonMap>{
          'InProgress': {
            'uuid': _swapUuid,
            'provider': 'lifi',
            'executed_route': route,
            'state': 'WaitingSourceConfirmation',
            'source_tx_hash': _sourceHash,
          },
          'Ok': {
            'uuid': _swapUuid,
            'provider': 'lifi',
            'executed_route': route,
            'outcome': 'completed',
            'received': {'coin': to['coin'], 'amount': to['amount']},
            'source_tx_hash': _sourceHash,
          },
          'Error': {
            'uuid': _swapUuid,
            'provider': 'lifi',
            'error_type': 'QuoteWorsened',
            'error': 'Fresh route is below the accepted minimum',
            'error_data': {'fresh_route': route},
          },
        };

        for (final MapEntry(key: status, value: details) in swaps.entries) {
          final response = rpc.RoutedSwapStatusResponse.parse({
            'mmrpc': '2.0',
            'result': {'status': status, 'details': details},
            'id': null,
          });
          final json = response.toJson();
          expect((json['result'] as JsonMap)['details'], details);
          final again = rpc.RoutedSwapStatusResponse.parse(_wire(json));
          expect(again.status, status);
          expect(again.details, response.details);
        }

        final result = <String, dynamic>{
          'entries': [
            for (final MapEntry(key: status, value: details) in swaps.entries)
              {
                'created_at': 1790600000,
                'updated_at': 1790600060,
                if (status != 'InProgress') 'finished_at': 1790600060,
                'requested': {
                  'from': from['coin'],
                  'to': to['coin'],
                  'amount': from['amount'],
                },
                'min_to_amount_accepted': to['amount_min'],
                'approval_tx_hashes': <String>[],
                'gas_spent': <JsonMap>[],
                'total_gas_spent': <JsonMap>[],
                'swap': {'status': status, 'details': details},
              },
          ],
          'total': 3,
          'limit': 10,
          'page_number': 1,
          'total_pages': 1,
        };
        final history = rpc.RoutedSwapHistoryResponse.parse({
          'mmrpc': '2.0',
          'result': result,
          'id': null,
        });
        expect(history.toJson(), {'mmrpc': '2.0', 'result': result});
        expect(
          rpc.RoutedSwapHistoryResponse.parse(_wire(history.toJson())).entries,
          history.entries,
        );
      }
    });
  });
}

const String _swapUuid = '6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f';
const String _sourceHash =
    '0x1111111111111111111111111111111111111111111111111111111111111111';

/// A captured quote's route: the shape of `executed_route` and `fresh_route`.
JsonMap _capturedRoute(String quote) =>
    ((_json(quote)['result'] as JsonMap)['routes'] as List).single as JsonMap;

/// [json] after a trip through JSON text, as a stored or exported copy.
JsonMap _wire(JsonMap json) => jsonDecode(jsonEncode(json)) as JsonMap;

final eth = _asset('ETH', chainId: 1, decimals: 18);
final usdc = _asset('USDC-ERC20', chainId: 1, decimals: 6, parent: eth);
final pol = _asset('POL', chainId: 137, decimals: 18);
final usdcPol = _asset('USDC-PLG20', chainId: 137, decimals: 6, parent: pol);
final _assets = {
  for (final a in [eth, usdc, pol, usdcPol]) a.id: a,
};

AssetId _asset(
  String id, {
  required int chainId,
  required int decimals,
  AssetId? parent,
}) => AssetId(
  id: id,
  name: id,
  symbol: AssetSymbol(assetConfigId: id),
  chainId: AssetChainId(chainId: chainId, decimalsValue: decimals),
  derivationPath: null,
  subClass: CoinSubClass.erc20,
  parentId: parent,
);

JsonMap _json(String raw) => jsonDecode(raw) as JsonMap;

rpc.RoutedSwapRpcException _quoteError(String raw) {
  try {
    rpc.RoutedSwapQuoteRequest(
      rpcPass: '',
      from: 'ETH',
      to: 'USDC-ERC20',
      amount: '1',
    ).parseResponseJson(_json(raw));
  } on rpc.RoutedSwapRpcException catch (e) {
    return e;
  }
  fail('parsed as a response: $raw');
}

RoutedSwapManager _manager(Map<String, String> responses) {
  final manager = RoutedSwapManager(
    client: _Replay(responses),
    resolveAsset: (ticker) => _assets[ticker],
  );
  addTearDown(manager.dispose);
  return manager;
}

/// Answers each method with its captured response.
class _Replay implements ApiClient {
  _Replay(this._responses);

  final Map<String, String> _responses;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    final raw = _responses[request['method']];
    if (raw == null) throw StateError('nothing captured for $request');
    return _json(raw);
  }
}
