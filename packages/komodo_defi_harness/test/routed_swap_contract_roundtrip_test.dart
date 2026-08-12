import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;

/// Parses the scripted fake KDF's responses with the real SDK models.
///
/// The fixture and the SDK models are two independent readings of the same
/// unimplemented contract. Either could drift — a field renamed on one side,
/// an optional treated as required on the other — and every test built on top
/// would keep passing while the app broke against real KDF. This is the seam
/// that catches that, and it is the reason the fixture was written before the
/// models.
void main() {
  const from = 'USDT-PLG20';
  const to = 'USDC-ERC20';

  Future<Map<String, dynamic>> call(
    KdfScript script,
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    final response = await script.respondTo({
      'method': method,
      'params': params,
    });
    if (response == null) fail('nothing scripted for $method');
    return response;
  }

  Future<int> startSwap(KdfScript script) async {
    final init = await call(script, 'task::routed_swap::init', {
      'from': from,
      'to': to,
      'amount': '100.5',
      'min_to_amount': '99.71',
    });
    return rpc.NewTaskResponse.parse(init).taskId;
  }

  test(
    'quote parses into a route with a distinct guaranteed minimum',
    () async {
      final fixture = RoutedSwapFixture()
        ..quote(
          const RoutedSwapQuote(
            from: from,
            to: to,
            amount: '100.5',
            toAmount: '100.21',
            toAmountMin: '99.71',
            feeCosts: [
              {
                'name': 'LIFI Fixed Fee',
                'coin': from,
                'amount': '0.05',
                'amount_usd': '0.05',
                'included': true,
              },
            ],
            gasCosts: [
              {'coin': 'MATIC', 'amount': '0.012', 'amount_usd': '0.01'},
            ],
          ),
        );

      final json = await call(fixture.build(), 'routed_swap::quote', {
        'from': from,
        'to': to,
        'amount': '100.5',
      });
      final route = rpc.RoutedSwapQuoteResponse.parse(json).best!;

      expect(route.provider, 'lifi');
      expect(route.from.coin, from);
      expect(route.to.amount, '100.21');
      // The two must not collapse into one another. `to` is what the user is
      // likely to get; `toMinimum` is what they are promised, and it is the one
      // the UI headlines and `init` guards on.
      expect(route.toMinimum.amount, '99.71');
      expect(route.kind, rpc.RoutedSwapRouteKind.crossChain);
      expect(route.feeCosts.single.included, isTrue);
      expect(route.feeCosts.single.amount.coin, from);
      expect(route.gasCosts.single.amount.coin, 'MATIC');
    },
  );

  test('supported_coins parses', () async {
    final fixture = RoutedSwapFixture()
      ..supportedCoin(from, chainId: 137)
      ..supportedCoin('ETH', chainId: 1);

    final json = await call(fixture.build(), 'routed_swap::supported_coins');
    final parsed = rpc.RoutedSwapSupportedCoinsResponse.parse(json);

    expect(parsed.provider, 'lifi');
    expect(parsed.coins.map((c) => c.coin), containsAll([from, 'ETH']));
    expect(parsed.coins.firstWhere((c) => c.coin == from).chainId, 137);
  });

  test(
    'every in-progress state parses and agrees on the cancel boundary',
    () async {
      final fixture = RoutedSwapFixture()
        ..run(RoutedSwapRun(approveTxHash: '0xapproval'));
      final script = fixture.build();
      final taskId = await startSwap(script);

      final seen = <rpc.RoutedSwapState>[];
      for (var i = 0; i < RoutedSwapState.values.length; i++) {
        final json = await call(script, 'task::routed_swap::status', {
          'task_id': taskId,
          'forget_if_finished': false,
        });
        final status = rpc.RoutedSwapStatusResponse.parse(json).details;
        status as rpc.RoutedSwapInProgress;

        expect(
          status.state,
          isNot(rpc.RoutedSwapState.unknown),
          reason:
              'the fixture emitted "${status.rawState}", which the SDK '
              'enum does not know — the two readings have diverged',
        );
        expect(status.uuid, isNotEmpty);
        seen.add(status.state);
      }

      expect(seen, rpc.RoutedSwapState.values.take(seen.length));

      // Both halves must agree on where cancellation stops being possible.
      // If they disagree the app offers a cancel KDF will refuse, or hides
      // one that would have worked.
      final cancellable = seen.where((s) => s.isCancellable).toList();
      expect(cancellable, [
        rpc.RoutedSwapState.fetchingQuote,
        rpc.RoutedSwapState.checkingAllowance,
        rpc.RoutedSwapState.approving,
        rpc.RoutedSwapState.signing,
      ]);
    },
  );

  test(
    'a terminal Ok parses as success only when the outcome earns it',
    () async {
      for (final entry in {
        RoutedSwapOutcome.completed: true,
        RoutedSwapOutcome.partial: false,
        RoutedSwapOutcome.refunded: false,
      }.entries) {
        final fixture = RoutedSwapFixture()
          ..run(
            RoutedSwapRun(
              outcome: entry.key,
              states: const [RoutedSwapState.fetchingQuote],
            ),
          );
        final script = fixture.build();
        final taskId = await startSwap(script);
        await call(script, 'task::routed_swap::status', {
          'task_id': taskId,
          'forget_if_finished': false,
        });
        final json = await call(script, 'task::routed_swap::status', {
          'task_id': taskId,
          'forget_if_finished': false,
        });

        final status = rpc.RoutedSwapStatusResponse.parse(json).details;
        status as rpc.RoutedSwapSuccess;

        expect(status.outcome.wire, entry.key.wire);
        expect(
          status.outcome.isSuccess,
          entry.value,
          reason:
              '${entry.key.wire} must ${entry.value ? '' : 'not '}render as a '
              'completed swap',
        );
      }
    },
  );

  test('a token with no KDF ticker never poses as a tradable asset', () async {
    final fixture = RoutedSwapFixture()
      ..run(
        RoutedSwapRun(
          outcome: RoutedSwapOutcome.partial,
          receivedSymbol: 'axlUSDC',
          receivedAmount: '98.40',
          states: const [RoutedSwapState.fetchingQuote],
        ),
      );
    final script = fixture.build();
    final taskId = await startSwap(script);
    await call(script, 'task::routed_swap::status', {'task_id': taskId});
    final json = await call(script, 'task::routed_swap::status', {
      'task_id': taskId,
      'forget_if_finished': false,
    });

    final status =
        rpc.RoutedSwapStatusResponse.parse(json).details
            as rpc.RoutedSwapSuccess;

    expect(status.received.isKnownAsset, isFalse);
    expect(status.received.coin, isNull);
    expect(status.received.label, 'axlUSDC');
  });

  test(
    'a terminal Error parses as a response, not a thrown exception',
    () async {
      // task::*::status returns terminal failures inside a normal result
      // envelope. Without shouldParseErrorAsResponse the base layer throws,
      // and the GUI loses the uuid and error_data it needs to explain what
      // happened.
      final fixture = RoutedSwapFixture()
        ..run(
          RoutedSwapRun(
            error: RoutedSwapTaskError.insufficientBalance(
              coin: 'MATIC',
              available: '0.001',
              required_: '0.014',
            ),
            states: const [RoutedSwapState.fetchingQuote],
          ),
        );
      final script = fixture.build();
      final taskId = await startSwap(script);
      await call(script, 'task::routed_swap::status', {'task_id': taskId});
      final json = await call(script, 'task::routed_swap::status', {
        'task_id': taskId,
        'forget_if_finished': false,
      });

      final request = rpc.RoutedSwapStatusRequest(rpcPass: '', taskId: taskId);
      expect(
        request.shouldParseErrorAsResponse(json),
        isTrue,
        reason: 'a terminal task Error must not be raised as a top-level error',
      );

      final status =
          rpc.RoutedSwapStatusResponse.parse(json).details
              as rpc.RoutedSwapFailure;

      expect(status.errorType, 'InsufficientBalance');
      expect(status.uuid, isNotEmpty);
      expect(status.errorData['coin'], 'MATIC');
      expect(status.errorData['required'], '0.014');
      expect(
        status.nothingWasSent,
        isTrue,
        reason:
            'an insufficient balance is caught before anything is broadcast',
      );
    },
  );

  test('an unknown error variant degrades instead of throwing', () async {
    // A KDF newer than the app will emit variants this build has never seen.
    // Stranding the user mid-swap is not an option, so parsing must survive it
    // — but it must also refuse to claim their funds are safe.
    final json = {
      'mmrpc': '2.0',
      'result': {
        'status': 'Error',
        'details': {
          'uuid': 'abc',
          'provider': 'lifi',
          'error': 'Something new went wrong',
          'error_type': 'SomeFutureVariant',
          'error_data': {'detail': 'x'},
        },
      },
    };

    final status =
        rpc.RoutedSwapStatusResponse.parse(json).details
            as rpc.RoutedSwapFailure;

    expect(status.errorType, 'SomeFutureVariant');
    expect(status.message, 'Something new went wrong');
    expect(
      status.nothingWasSent,
      isFalse,
      reason:
          'an unrecognised failure must never be reported as "nothing was '
          'sent" — that is the one claim that must not be guessed',
    );
  });

  test('an unknown in-progress state is treated as post-broadcast', () async {
    final json = {
      'mmrpc': '2.0',
      'result': {
        'status': 'InProgress',
        'details': {
          'uuid': 'abc',
          'provider': 'lifi',
          'state': 'SomeFutureState',
        },
      },
    };

    final status =
        rpc.RoutedSwapStatusResponse.parse(json).details
            as rpc.RoutedSwapInProgress;

    expect(status.state, rpc.RoutedSwapState.unknown);
    expect(status.rawState, 'SomeFutureState');
    // Refusing a cancel that might have worked is recoverable; offering one
    // that cannot is not.
    expect(status.state.isCancellable, isFalse);
  });

  test('history parses into the provisional entry model', () async {
    final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
    final script = fixture.build();
    await startSwap(script);

    final json = await call(script, 'routed_swap::history', {
      'status_filter': 'in_flight',
    });
    final page = rpc.RoutedSwapHistoryResponse.parse(json);

    expect(page.total, 1);
    final entry = page.entries.single;
    expect(entry.provider, 'lifi');
    expect(entry.isInFlight, isTrue);
    expect(entry.sent.coin, from);
    expect(entry.sent.amount, '100.5');
    expect(entry.createdAt, greaterThan(0));
  });

  test("cancel parses KDF's acknowledgement", () async {
    final fixture = RoutedSwapFixture()..run(RoutedSwapRun());
    final script = fixture.build();
    final taskId = await startSwap(script);

    final json = await call(script, 'task::routed_swap::cancel', {
      'task_id': taskId,
    });

    expect(rpc.RoutedSwapCancelResponse.parse(json).result, 'success');
  });
}
