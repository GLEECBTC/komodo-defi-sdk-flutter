import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

/// A top-level MMRPC error as KDF serialises `MmError`.
JsonMap _error(String type, Object? data, {String? message = 'engine text'}) =>
    {
      'mmrpc': '2.0',
      'error': ?message,
      'error_path': 'routed_swap',
      'error_trace': 'routed_swap:1]',
      'error_type': type,
      'error_data': ?data,
      'id': null,
    };

RoutedSwapRpcException _parse(
  String type,
  Object? data, {
  String message = 'engine text',
}) => RoutedSwapRpcException.tryParse(_error(type, data, message: message))!;

class _Kdf implements ApiClient {
  _Kdf(this.response);

  final JsonMap response;
  final List<JsonMap> requests = [];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(request);
    return response;
  }
}

void main() {
  group('RoutedSwapRpcException.tryParse', () {
    test('answers null for anything that is not a typed error envelope', () {
      expect(
        RoutedSwapRpcException.tryParse({
          'mmrpc': '2.0',
          'result': {'routes': <Object>[]},
        }),
        isNull,
      );
      expect(
        RoutedSwapRpcException.tryParse({'error': 'plain legacy error'}),
        isNull,
      );
    });

    test('finds the envelope at the top, in result.details or in message', () {
      final inner = <String, dynamic>{
        'error': 'Coin ETH is not active',
        'error_type': 'CoinNotActive',
        'error_data': {'coin': 'ETH'},
      };
      for (final json in <JsonMap>[
        {'mmrpc': '2.0', ...inner},
        {
          'mmrpc': '2.0',
          'result': {'status': 'Error', 'details': inner},
        },
        {'message': inner},
      ]) {
        expect(
          RoutedSwapRpcException.tryParse(json),
          isA<RoutedSwapCoinNotActiveException>()
              .having((e) => e.coin, 'coin', 'ETH')
              .having((e) => e.message, 'message', 'Coin ETH is not active'),
        );
      }
    });

    test('request errors name the coin, pair or parameter', () {
      final coin = _parse('CoinNotActive', {'coin': 'FEE-INACTIVE'});
      expect(coin, isA<RoutedSwapCoinNotActiveException>());
      expect((coin as RoutedSwapCoinNotActiveException).coin, 'FEE-INACTIVE');
      expect(coin.errorType, 'CoinNotActive');
      expect(coin.errorData, {'coin': 'FEE-INACTIVE'});

      final pair =
          _parse('PairNotSupported', {
                'from': 'ETH',
                'to': 'BTC',
                'reason': 'BTC is not an EVM asset',
              })
              as RoutedSwapPairNotSupportedException;
      expect(
        [pair.from, pair.to, pair.reason],
        ['ETH', 'BTC', 'BTC is not an EVM asset'],
      );

      for (final param in ['provider', 'order', 'amount']) {
        final invalid =
            _parse('InvalidParam', {'param': param, 'reason': 'bad $param'})
                as RoutedSwapInvalidParamException;
        expect([invalid.param, invalid.reason], [param, 'bad $param']);
      }

      for (final param in ['amount', 'slippage']) {
        final bounds =
            _parse('AmountOutOfBounds', {
                  'param': param,
                  'value': '0.6',
                  'min': '0',
                  'max': '0.5',
                })
                as RoutedSwapAmountOutOfBoundsException;
        expect(
          [bounds.param, bounds.value, bounds.min, bounds.max],
          [param, '0.6', '0', '0.5'],
        );
      }
    });

    test('wallet and node errors carry their diagnostic detail', () {
      final address =
          _parse('MyAddressError', {
                'coin': 'ETH',
                'message': 'no enabled address',
              })
              as RoutedSwapMyAddressException;
      expect([address.coin, address.detail], ['ETH', 'no enabled address']);

      final config =
          _parse('InvalidConfig', {'message': 'lifi_api is invalid'})
              as RoutedSwapInvalidConfigException;
      expect(config.detail, 'lifi_api is invalid');

      final transport =
          _parse('TransportError', {'message': 'unreachable'})
              as RoutedSwapTransportException;
      expect(transport.detail, 'unreachable');

      final bare =
          _parse('InternalError', 'Unable to persist routed swap state')
              as RoutedSwapInternalException;
      expect(bare.detail, 'Unable to persist routed swap state');
      final wrapped =
          _parse('InternalError', {'message': 'history is unavailable'})
              as RoutedSwapInternalException;
      expect(wrapped.detail, 'history is unavailable');
    });

    test('provider errors keep the reasons and the support request id', () {
      final noRoute =
          _parse('NoRouteFound', {
                'reasons': ['no liquidity', 42, null, 'amount too low (hop)'],
                'provider_request_id': 'req-1',
              })
              as RoutedSwapNoRouteException;
      expect(noRoute.reasons, ['no liquidity', 'amount too low (hop)']);
      expect(noRoute.providerRequestId, 'req-1');

      final limited =
          _parse('RateLimited', {'provider_request_id': 'req-2'})
              as RoutedSwapRateLimitedException;
      expect(limited.providerRequestId, 'req-2');

      final provider =
          _parse('ProviderApiError', {
                'message': 'invalid transaction target',
                'provider_request_id': 'req-3',
              })
              as RoutedSwapProviderException;
      expect(provider.detail, 'invalid transaction target');
      expect(provider.providerRequestId, 'req-3');
    });

    test('task refusals read the task id bare or wrapped', () {
      final bare = _parse('NoSuchTask', 3) as RoutedSwapNoSuchTaskException;
      expect(bare.taskId, 3);
      final wrapped =
          _parse('NoSuchTask', {'task_id': 4}) as RoutedSwapNoSuchTaskException;
      expect(wrapped.taskId, 4);
      final absent =
          _parse('NoSuchTask', null) as RoutedSwapNoSuchTaskException;
      expect(absent.taskId, isNull);

      final finished =
          _parse('TaskFinished', {'task_id': 5})
              as RoutedSwapTaskFinishedException;
      expect(finished.taskId, 5);
      final broadcast =
          _parse('TaskAlreadyBroadcast', {'task_id': 6})
              as RoutedSwapTaskAlreadyBroadcastException;
      expect(broadcast.taskId, 6);
    });

    test('an unknown error type keeps its name and raw payload', () {
      final request = _parse('InvalidRequest', 'unknown field `client_id`');
      expect(request, isA<RoutedSwapUnknownRpcException>());
      expect(request.errorType, 'InvalidRequest');
      expect(request.errorData, 'unknown field `client_id`');
      expect(request.providerRequestId, isNull);

      final fromProvider = _parse('QuotaChanged', {
        'provider_request_id': 'req-4',
      });
      expect(fromProvider.providerRequestId, 'req-4');
      expect(_parse('QuotaChanged', {'other': 1}).providerRequestId, isNull);
    });

    test('falls back to the error type when the message is missing', () {
      final error = RoutedSwapRpcException.tryParse(
        _error('RateLimited', <String, dynamic>{}, message: null),
      )!;
      expect(error.message, 'RateLimited');
    });

    test('reads missing or malformed error_data as empty fields', () {
      final pair =
          _parse('PairNotSupported', 'oops')
              as RoutedSwapPairNotSupportedException;
      expect([pair.from, pair.to, pair.reason], ['', '', '']);
      expect(pair.errorData, 'oops');

      final bounds =
          _parse('AmountOutOfBounds', <String, dynamic>{})
              as RoutedSwapAmountOutOfBoundsException;
      expect(
        [bounds.param, bounds.value, bounds.min, bounds.max],
        ['', '', '', ''],
      );

      final noRoute =
          _parse('NoRouteFound', {'reasons': 'not a list'})
              as RoutedSwapNoRouteException;
      expect(noRoute.reasons, isEmpty);
      expect(noRoute.providerRequestId, isNull);

      final address =
          _parse('MyAddressError', null) as RoutedSwapMyAddressException;
      expect([address.coin, address.detail], ['', '']);
      expect(address.errorData, isNull);

      final gone = _parse('NoSuchTask', '7') as RoutedSwapNoSuchTaskException;
      expect(gone.taskId, isNull);
    });

    test('whole-number bounds are read as text', () {
      final bounds =
          _parse('AmountOutOfBounds', {
                'param': 'amount',
                'value': 5,
                'min': 1,
                'max': 10,
              })
              as RoutedSwapAmountOutOfBoundsException;
      expect([bounds.value, bounds.min, bounds.max], ['5', '1', '10']);
    });
  });

  group('exception behaviour', () {
    test(
      'only rate limits, provider, transport and internal are transient',
      () {
        const cases = <(String, bool)>[
          ('CoinNotActive', false),
          ('PairNotSupported', false),
          ('InvalidParam', false),
          ('AmountOutOfBounds', false),
          ('MyAddressError', false),
          ('InvalidConfig', false),
          ('NoRouteFound', false),
          ('RateLimited', true),
          ('ProviderApiError', true),
          ('TransportError', true),
          ('InternalError', true),
          ('NoSuchTask', false),
          ('TaskFinished', false),
          ('TaskAlreadyBroadcast', false),
          ('SomethingNew', false),
        ];
        for (final (type, transient) in cases) {
          expect(
            _parse(type, <String, dynamic>{}).isTransient,
            transient,
            reason: type,
          );
        }
      },
    );

    test('only provider-originated errors expose a support request id', () {
      const data = {'provider_request_id': 'req-1'};
      const cases = <(String, String?)>[
        ('CoinNotActive', null),
        ('InvalidParam', null),
        ('TransportError', null),
        ('InternalError', null),
        ('TaskFinished', null),
        ('NoRouteFound', 'req-1'),
        ('RateLimited', 'req-1'),
        ('ProviderApiError', 'req-1'),
        ('SomethingNew', 'req-1'),
      ];
      for (final (type, id) in cases) {
        expect(_parse(type, data).providerRequestId, id, reason: type);
      }
    });

    test('toString names the error type and the engine message', () {
      final error = _parse('TaskFinished', {
        'task_id': 3,
      }, message: 'Routed swap task is already finished: 3');
      expect(
        error.toString(),
        'RoutedSwapRpcException(TaskFinished): '
        'Routed swap task is already finished: 3',
      );
    });

    test('the constructors default their optional fields', () {
      const noRoute = RoutedSwapNoRouteException(message: 'none');
      expect(noRoute.errorType, 'NoRouteFound');
      expect(noRoute.reasons, isEmpty);
      expect(noRoute.providerRequestId, isNull);
      expect(noRoute.errorData, isNull);

      const gone = RoutedSwapNoSuchTaskException(message: 'gone');
      expect(gone.taskId, isNull);
      const unknown = RoutedSwapUnknownRpcException(
        errorType: 'Other',
        message: 'other',
      );
      expect(unknown.providerRequestId, isNull);
      expect(unknown.isTransient, isFalse);
    });
  });

  group('through the client', () {
    test(
      'a shared error name is typed as routed, not by the registry',
      () async {
        final noRoute = _Kdf(
          _error('NoRouteFound', {
            'reasons': ['no liquidity'],
            'provider_request_id': 'req-1',
          }, message: 'No route found'),
        );
        await expectLater(
          noRoute.rpc.routedSwap.quote(from: 'ETH', to: 'USDC', amount: '1'),
          throwsA(
            isA<RoutedSwapNoRouteException>().having(
              (e) => e.reasons,
              'reasons',
              ['no liquidity'],
            ),
          ),
        );

        final config = _Kdf(
          _error('InvalidConfig', {'message': 'lifi_api is invalid'}),
        );
        await expectLater(
          config.rpc.routedSwap.supportedCoins(),
          throwsA(isA<RoutedSwapInvalidConfigException>()),
        );
      },
    );

    test('a terminal task Error is a status response, not a throw', () async {
      final kdf = _Kdf({
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': {
            'uuid': 'u-1',
            'error_type': 'TaskCancelled',
            'error': 'Routed swap cancelled before broadcast',
          },
        },
      });

      final response = await kdf.rpc.routedSwap.status(3);

      expect(response.status, 'Error');
      expect(
        response.details,
        isA<RoutedSwapErrored>().having(
          (s) => s.error,
          'error',
          isA<RoutedSwapTaskCancelledError>(),
        ),
      );
      expect(kdf.requests.single['params'], {
        'task_id': 3,
        'forget_if_finished': false,
      });
    });

    test('NoSuchTask from status and cancel throws with the task id', () async {
      final status = _Kdf(_error('NoSuchTask', 3));
      await expectLater(
        status.rpc.routedSwap.status(3, forgetIfFinished: true),
        throwsA(
          isA<RoutedSwapNoSuchTaskException>().having(
            (e) => e.taskId,
            'taskId',
            3,
          ),
        ),
      );
      expect(status.requests.single['params'], {
        'task_id': 3,
        'forget_if_finished': true,
      });

      final cancel = _Kdf(_error('TaskAlreadyBroadcast', {'task_id': 3}));
      await expectLater(
        cancel.rpc.routedSwap.cancel(3),
        throwsA(isA<RoutedSwapTaskAlreadyBroadcastException>()),
      );
      expect(cancel.requests.single['method'], 'task::routed_swap::cancel');
    });
  });
}
