import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

const JsonMap _minimalRoute = {
  'from': {'coin': 'ETH', 'amount': '1'},
  'to': {'coin': 'USDC-POLYGON', 'amount': '2', 'amount_min': '1.9'},
  'tool': {'key': 'across', 'name': 'Across V4'},
  'kind': 'same_chain',
};

const JsonMap _fullRoute = {
  'from': {'coin': 'ETH', 'amount': '1'},
  'to': {'coin': 'USDC-POLYGON', 'amount': '2', 'amount_min': '1.9'},
  'tool': {'key': 'across', 'name': 'Across V4'},
  'provider': 'lifi',
  'kind': 'cross_chain',
  'from_address': '0xwallet',
  'to_address': '0xwallet',
  'approval': {
    'required': true,
    'tx_count': 2,
    'reason': 'zero_reset',
    'spender': '0xdiamond',
    'gas_costs': [
      {'coin': 'ETH', 'amount': '0.0001'},
    ],
  },
  'total_gas_costs': [
    {'coin': 'ETH', 'amount': '0.0101', 'amount_usd': '20'},
  ],
  'steps': [
    {'type': 'swap', 'tool': '1inch', 'chain_id': 1},
  ],
  'fee_costs': [
    {
      'name': 'LIFI Fee',
      'symbol': 'axlUSDC',
      'amount': '0.1',
      'included': true,
    },
  ],
  'gas_costs': [
    {'coin': 'ETH', 'amount': '0.01', 'amount_usd': '20'},
  ],
  'execution_duration_s': 31,
};

JsonMap _extended(JsonMap base, JsonMap extra) => {...base, ...extra};

JsonMap _replaced(String key, Object value) =>
    {..._minimalRoute}..[key] = value;

void main() {
  group('route parts', () {
    test('a ticker is an asset; a provider symbol is display text only', () {
      final coin = RoutedSwapAmount.fromJson(const {
        'coin': 'ETH',
        'amount': '1',
      });
      expect(coin.isKnownAsset, isTrue);
      expect(coin.label, 'ETH');
      expect(coin.toJson(), {'coin': 'ETH', 'amount': '1'});

      final symbol = RoutedSwapAmount.fromJson(const {
        'symbol': 'axlUSDC',
        'amount': '2',
      });
      expect(symbol.isKnownAsset, isFalse);
      expect(symbol.label, 'axlUSDC');
      expect(symbol.toJson(), {'symbol': 'axlUSDC', 'amount': '2'});
      expect(symbol, const RoutedSwapAmount(amount: '2', symbol: 'axlUSDC'));
    });

    test('a tool omits an absent logo', () {
      const bare = {'key': 'across', 'name': 'Across V4'};
      expect(RoutedSwapTool.fromJson(bare).logoUrl, isNull);
      expect(RoutedSwapTool.fromJson(bare).toJson(), bare);
      const logo = {...bare, 'logo_url': 'https://cdn.example/logo.svg'};
      expect(RoutedSwapTool.fromJson(logo).toJson(), logo);
      expect(
        RoutedSwapTool.fromJson(bare),
        isNot(RoutedSwapTool.fromJson(logo)),
      );
    });

    test('a fee is charged on top unless marked included', () {
      final fee = RoutedSwapFeeCost.fromJson(const {
        'name': 'Protocol fee',
        'coin': 'ETH',
        'amount': '0.1',
      });
      expect(fee.included, isFalse);
      expect(fee.amountUsd, isNull);
      expect(fee.toJson(), {
        'name': 'Protocol fee',
        'coin': 'ETH',
        'amount': '0.1',
        'included': false,
      });
      const priced = {
        'name': 'LIFI Fee',
        'coin': 'ETH',
        'amount': '0.1',
        'amount_usd': '0.2',
        'included': true,
      };
      expect(RoutedSwapFeeCost.fromJson(priced).toJson(), priced);
      expect(fee, isNot(RoutedSwapFeeCost.fromJson(priced)));
    });

    test('gas keeps its token and an optional USD value', () {
      const priced = {'coin': 'ETH', 'amount': '0.01', 'amount_usd': '20'};
      final gas = RoutedSwapGasCost.fromJson(priced);
      expect(gas.amount.coin, 'ETH');
      expect(gas.amountUsd, '20');
      expect(gas.toJson(), priced);
      expect(
        RoutedSwapGasCost.fromJson(const {'coin': 'ETH', 'amount': '0.01'}),
        isNot(gas),
      );
    });

    test('an approval defaults to one exact approval of unknown reason', () {
      final approval = RoutedSwapApproval.fromJson(const {
        'reason': 'permit2',
        'gas_costs': [
          {'coin': 'ETH', 'amount': '0.0001'},
          'not a gas row',
        ],
      });
      expect(approval.required, isTrue);
      expect(approval.txCount, 1);
      expect(approval.reason, RoutedSwapApprovalReason.unknown);
      expect(approval.resetsFirst, isFalse);
      expect(approval.spender, isEmpty);
      expect(approval.gasCosts.single.amount.amount, '0.0001');
      expect(approval.toJson()['reason'], '');

      for (final reason in RoutedSwapApprovalReason.values) {
        expect(RoutedSwapApprovalReason.parse(reason.wire), reason);
      }
      expect(
        RoutedSwapApprovalReason.parse(null),
        RoutedSwapApprovalReason.unknown,
      );
    });

    test('a step keeps its raw type so a new leg is still reportable', () {
      final step = RoutedSwapStep.fromJson(const {'type': 'teleport'});
      expect(step.type, 'teleport');
      expect(step.stepType, RoutedSwapStepType.unknown);
      expect(step.tool, isEmpty);
      expect(step.toJson(), {'type': 'teleport', 'tool': ''});

      const cross = {
        'type': 'cross',
        'tool': 'across',
        'from_chain_id': 1,
        'to_chain_id': 137,
      };
      expect(RoutedSwapStep.fromJson(cross).stepType, RoutedSwapStepType.cross);
      expect(RoutedSwapStep.fromJson(cross).toJson(), cross);
      for (final type in RoutedSwapStepType.values) {
        expect(RoutedSwapStepType.parse(type.wire), type);
      }
    });

    test('supported coins compare by ticker and chain', () {
      final coin = RoutedSwapSupportedCoin.fromJson(const {
        'coin': 'ETH',
        'chain_id': 1,
      });
      expect(coin, const RoutedSwapSupportedCoin(coin: 'ETH', chainId: 1));
      expect(
        coin.hashCode,
        const RoutedSwapSupportedCoin(coin: 'ETH', chainId: 1).hashCode,
      );
      expect(
        coin,
        isNot(const RoutedSwapSupportedCoin(coin: 'ETH', chainId: 10)),
      );
    });
  });

  group('a route', () {
    test('defaults the provider and tolerates absent optional parts', () {
      final route = RoutedSwapRoute.fromJson(_minimalRoute);
      expect(route.provider, 'lifi');
      expect(route.kind, RoutedSwapRouteKind.sameChain);
      expect(route.to.amount, '2');
      expect(route.toMinimum.amount, '1.9');
      expect(route.toMinimum.coin, 'USDC-POLYGON');
      expect(route.approval, isNull);
      expect(route.fromAddress, isNull);
      expect(route.executionDurationS, isNull);
      expect([
        route.steps,
        route.feeCosts,
        route.gasCosts,
        route.totalGasCosts,
      ], everyElement(isEmpty));
      expect(RoutedSwapRoute.fromJson(route.toJson()), route);
    });

    test('round-trips every part and skips list rows that are not objects', () {
      final route = RoutedSwapRoute.fromJson({
        ..._fullRoute,
        'gas_costs': [...(_fullRoute['gas_costs'] as List), 'not a gas row', 3],
      });
      expect(route.gasCosts, hasLength(1));
      expect(route.approval!.resetsFirst, isTrue);
      expect(route.toJson(), _fullRoute);
      expect(route, RoutedSwapRoute.fromJson(_fullRoute));
      expect(route.hashCode, RoutedSwapRoute.fromJson(_fullRoute).hashCode);
      expect(route, isNot(RoutedSwapRoute.fromJson(_minimalRoute)));
    });

    test(
      'a route missing an amount, its minimum or its tool is unreadable',
      () {
        for (final key in ['from', 'to', 'tool', 'kind']) {
          expect(
            () => RoutedSwapRoute.fromJson({..._minimalRoute}..remove(key)),
            throwsArgumentError,
            reason: key,
          );
        }
        expect(
          () => RoutedSwapRoute.fromJson(
            _replaced('to', const {'coin': 'USDC-POLYGON', 'amount': '2'}),
          ),
          throwsArgumentError,
        );
      },
    );

    test('a kind this build does not know is kept as unknown', () {
      final route = RoutedSwapRoute.fromJson(_replaced('kind', 'multi_hop'));
      expect(route.kind, RoutedSwapRouteKind.unknown);
    });
  });

  group('routed_swap::quote', () {
    test('sends only the options it is given', () {
      final bare = RoutedSwapQuoteRequest(
        rpcPass: '',
        from: 'ETH',
        to: 'USDC-POLYGON',
        amount: '1',
      ).toJson();
      expect(bare['method'], 'routed_swap::quote');
      expect(bare['params'], {
        'from': 'ETH',
        'to': 'USDC-POLYGON',
        'amount': '1',
      });

      final full = RoutedSwapQuoteRequest(
        rpcPass: '',
        from: 'ETH',
        to: 'USDC-POLYGON',
        amount: '1',
        slippage: 0.01,
        order: RoutedSwapOrder.fastest,
        provider: 'lifi',
      ).toJson();
      expect(full['params'], {
        'from': 'ETH',
        'to': 'USDC-POLYGON',
        'amount': '1',
        'slippage': 0.01,
        'order': 'fastest',
        'provider': 'lifi',
      });
      expect(RoutedSwapOrder.cheapest.wire, 'cheapest');
    });

    test('the response reads its routes and serialises them back', () {
      final response = RoutedSwapQuoteResponse.parse({
        'result': {
          'routes': [_fullRoute, 'not a route'],
        },
      });
      expect(response.mmrpc, '2.0');
      expect(response.routes, hasLength(1));
      expect(response.best, response.routes.single);
      expect(response.toJson(), {
        'mmrpc': '2.0',
        'result': {
          'routes': [_fullRoute],
        },
      });
      expect(
        RoutedSwapQuoteResponse.parse(response.toJson()).routes,
        response.routes,
      );
    });

    test('no routes means no best route; a missing list is malformed', () {
      final empty = RoutedSwapQuoteResponse.parse({
        'result': {'routes': <Object>[]},
      });
      expect(empty.best, isNull);
      expect(
        () => RoutedSwapQuoteResponse.parse({'result': <String, dynamic>{}}),
        throwsArgumentError,
      );
    });
  });

  group('routed_swap::supported_coins', () {
    test('sends the provider only when set', () {
      expect(
        RoutedSwapSupportedCoinsRequest(rpcPass: '').toJson()['params'],
        isEmpty,
      );
      expect(
        RoutedSwapSupportedCoinsRequest(
          rpcPass: '',
          provider: 'lifi',
        ).toJson()['params'],
        {'provider': 'lifi'},
      );
    });

    test('the response defaults the provider and lists what it read', () {
      final response = RoutedSwapSupportedCoinsResponse.parse({
        'result': {
          'coins': [
            {'coin': 'ETH', 'chain_id': 1},
            {'coin': 'BAD'},
          ],
        },
      });
      expect(response.mmrpc, '2.0');
      expect(response.provider, 'lifi');
      expect(response.skipped, 1);
      expect(response.toJson(), {
        'mmrpc': '2.0',
        'result': {
          'provider': 'lifi',
          'coins': [
            {'coin': 'ETH', 'chain_id': 1},
          ],
        },
      });
      expect(
        RoutedSwapSupportedCoinsResponse(
          mmrpc: '2.0',
          provider: 'lifi',
          coins: const [],
        ).skipped,
        0,
      );
    });
  });

  group('task::routed_swap::init and cancel', () {
    test('init sends the accepted minimum and every option given', () {
      final bare = RoutedSwapInitRequest(
        rpcPass: '',
        from: 'ETH',
        to: 'USDC-POLYGON',
        amount: '1',
        minToAmount: '1.9',
      ).toJson();
      expect(bare['method'], 'task::routed_swap::init');
      expect(bare['params'], {
        'from': 'ETH',
        'to': 'USDC-POLYGON',
        'amount': '1',
        'min_to_amount': '1.9',
      });

      final full = RoutedSwapInitRequest(
        rpcPass: '',
        from: 'ETH',
        to: 'USDC-POLYGON',
        amount: '1',
        minToAmount: '1.9',
        slippage: 0.02,
        order: RoutedSwapOrder.cheapest,
        provider: 'lifi',
        clientId: 4,
      ).toJson();
      expect(full['params'], {
        'from': 'ETH',
        'to': 'USDC-POLYGON',
        'amount': '1',
        'min_to_amount': '1.9',
        'slippage': 0.02,
        'order': 'cheapest',
        'provider': 'lifi',
        'client_id': 4,
      });
    });

    test('cancel names the task and reads any acknowledgement', () {
      final request = RoutedSwapCancelRequest(rpcPass: '', taskId: 3);
      expect(request.toJson()['method'], 'task::routed_swap::cancel');
      expect(request.toJson()['params'], {'task_id': 3});

      String ack(Object? result) =>
          RoutedSwapCancelResponse.parse({'result': result}).result;
      expect(ack('success'), 'success');
      expect(ack({'result': 'accepted'}), 'accepted');
      expect(ack(<String, dynamic>{}), 'success');
      expect(ack(null), 'success');
      expect(ack(1), '1');

      final response = RoutedSwapCancelResponse.parse({'result': 'success'});
      expect(response.mmrpc, '2.0');
      expect(response.toJson(), {'mmrpc': '2.0', 'result': 'success'});
    });
  });

  group('forward compatibility', () {
    test('fields a newer engine adds are ignored', () {
      expect(
        RoutedSwapRoute.fromJson(
          _extended(_fullRoute, const {
            'route_id': 'r-1',
            'insurance': {'covered': true},
          }),
        ),
        RoutedSwapRoute.fromJson(_fullRoute),
      );
      const signing = {'uuid': 'u-1', 'state': 'Signing'};
      expect(
        RoutedSwapStatus.parse(
          'InProgress',
          _extended(signing, const {'signer': 'walletconnect'}),
        ),
        RoutedSwapStatus.parse('InProgress', signing),
      );
      const short = {'coin': 'ETH', 'available': '1', 'required': '2'};
      expect(
        RoutedSwapTaskError.parse(
          'InsufficientBalance',
          _extended(short, const {'shortfall_usd': '5'}),
        ),
        RoutedSwapTaskError.parse('InsufficientBalance', short),
      );
      expect(
        RoutedSwapRpcException.tryParse(const {
          'mmrpc': '2.0',
          'error': 'Routed swap provider rate limit exceeded',
          'error_type': 'RateLimited',
          'error_data': {'retry_after_s': 30},
          'error_hint': 'slow down',
        }),
        isA<RoutedSwapRateLimitedException>(),
      );
    });

    test('a wrongly typed optional field reads as absent', () {
      final route = RoutedSwapRoute.fromJson(
        _replaced('execution_duration_s', 'soon'),
      );
      expect(route.executionDurationS, isNull);

      final approval = RoutedSwapApproval.fromJson(const {
        'required': 'yes',
        'tx_count': 'two',
      });
      expect(approval.required, isTrue);
      expect(approval.txCount, 1);

      final fee = RoutedSwapFeeCost.fromJson(const {
        'name': 'Protocol fee',
        'coin': 'ETH',
        'amount': '0.1',
        'included': 'yes',
      });
      expect(fee.included, isFalse);
    });
  });
}
