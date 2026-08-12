import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Drives [RoutedSwapManager] against the scripted KDF.
///
/// The manager exists to absorb the parts of the contract that are easy to get
/// wrong — closing the window before a swap becomes recoverable, never
/// destroying a terminal result, treating the event stream as a hint, and
/// resolving a vanished task from the durable record instead of reporting a
/// failure the user did not have. Each of those is asserted here, because none
/// of them are visible from the type signatures.
void main() {
  AssetId assetId(String id, {AssetId? parent}) => AssetId(
    id: id,
    name: id,
    symbol: AssetSymbol(assetConfigId: id),
    chainId: AssetChainId(chainId: 137),
    derivationPath: null,
    subClass: parent == null ? CoinSubClass.utxo : CoinSubClass.erc20,
    parentId: parent,
  );

  final matic = assetId('MATIC');
  final usdt = assetId('USDT-PLG20', parent: matic);
  final usdc = assetId('USDC-ERC20', parent: matic);

  final assets = {
    for (final a in [matic, usdt, usdc]) a.id: a,
  };

  RoutedSwapManager managerFor(
    RoutedSwapFixture fixture, {
    Stream<void> Function(int)? nudges,
  }) {
    final script = fixture.build();
    return RoutedSwapManager(
      client: _ScriptedClient(script),
      resolveAsset: (ticker) => assets[ticker],
      taskNudges: nudges,
      // Keep the suite fast; the cadence itself is not under test.
      pollInterval: const Duration(milliseconds: 5),
      streamStaleAfter: const Duration(milliseconds: 1),
    );
  }

  RoutedSwapFixture fixtureWithQuote() => RoutedSwapFixture()
    ..supportedCoin('USDT-PLG20', chainId: 137)
    ..supportedCoin('USDC-ERC20', chainId: 1)
    ..quote(
      const RoutedSwapQuote(
        from: 'USDT-PLG20',
        to: 'USDC-ERC20',
        amount: '100.5',
        toAmount: '100.21',
        toAmountMin: '99.71',
        feeCosts: [
          {
            'name': 'LIFI Fixed Fee',
            'coin': 'USDT-PLG20',
            'amount': '0.05',
            'included': true,
          },
        ],
        gasCosts: [
          {'coin': 'MATIC', 'amount': '0.012'},
        ],
      ),
    );

  Future<RoutedSwapOffer> offerFrom(RoutedSwapManager manager) =>
      manager.quote(from: usdt, to: usdc, amount: Decimal.parse('100.5'));

  group('quote', () {
    test('separates the guaranteed receive from the expected one', () async {
      final manager = managerFor(fixtureWithQuote());
      final offer = await offerFrom(manager);

      expect(offer.expectedReceive, Decimal.parse('100.21'));
      expect(offer.guaranteedReceive, Decimal.parse('99.71'));
      expect(offer.slippageAllowance, Decimal.parse('0.50'));
      expect(offer.isCrossChain, isTrue);
    });

    test('flags undisclosed approval gas when selling a token', () async {
      final manager = managerFor(fixtureWithQuote());
      final offer = await offerFrom(manager);

      // The quote never says whether an approval is coming, so any total built
      // from the disclosed costs is a floor. The UI has to be told that.
      expect(offer.mayRequireApproval, isTrue);
    });

    test('does not flag approval gas when selling a native coin', () async {
      final fixture = RoutedSwapFixture()
        ..quote(
          const RoutedSwapQuote(
            from: 'MATIC',
            to: 'USDC-ERC20',
            amount: '10',
            toAmount: '9.9',
            toAmountMin: '9.8',
          ),
        );
      final manager = managerFor(fixture);

      final offer = await manager.quote(
        from: matic,
        to: usdc,
        amount: Decimal.parse('10'),
      );

      expect(offer.mayRequireApproval, isFalse);
    });

    test('excludes already-deducted fees from the additional total', () async {
      final manager = managerFor(fixtureWithQuote());
      final offer = await offerFrom(manager);

      // The provider fee is marked included, i.e. already subtracted from the
      // receive amount. Counting it again would overstate what the swap costs.
      final additional = offer.additionalCostsByToken;
      expect(additional.containsKey('USDT-PLG20'), isFalse);
      expect(additional['MATIC'], Decimal.parse('0.012'));
    });
  });

  group('start', () {
    test('resolves the durable id before returning', () async {
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final manager = managerFor(fixture);
      final offer = await offerFrom(manager);

      final swap = await manager.start(offer);

      // The window between init and the first status read is where a swap is
      // unrecoverable. Closing it in the SDK means no caller can forget to.
      expect(swap.uuid, isNotEmpty);
      await manager.dispose();
    });

    test('guards execution with the minimum the user was shown', () async {
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final script = fixture.build();
      final client = _ScriptedClient(script);
      final manager = RoutedSwapManager(
        client: client,
        resolveAsset: (ticker) => assets[ticker],
        pollInterval: const Duration(milliseconds: 5),
      );

      final offer = await manager.quote(
        from: usdt,
        to: usdc,
        amount: Decimal.parse('100.5'),
      );
      await manager.start(offer);

      final init = client.requestsFor('task::routed_swap::init').single;
      final params = init['params'] as Map<String, dynamic>;
      expect(
        params['min_to_amount'],
        '99.71',
        reason:
            'the guard must be the guaranteed receive; sending the expected '
            'receive instead would reject nearly every swap',
      );
      await manager.dispose();
    });

    test('reaches a terminal snapshot through the progress stream', () async {
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));

      final seen = <RoutedSwapPhase>[];
      final terminal = await swap.progress
          .map((p) {
            seen.add(p.phase);
            return p;
          })
          .firstWhere((p) => p.isTerminal);

      expect(terminal.isSuccess, isTrue);
      expect(terminal.receipt!.outcome.wire, 'completed');
      expect(seen.first, RoutedSwapPhase.preparing);
      expect(seen, contains(RoutedSwapPhase.bridging));
      await manager.dispose();
    });
  });

  group('terminal outcomes', () {
    test('a refund is terminal but is not a success', () async {
      final fixture = fixtureWithQuote()
        ..run(
          RoutedSwapRun(
            outcome: RoutedSwapOutcome.refunded,
            receivedCoin: 'USDT-PLG20',
            receivedAmount: '99.10',
            states: const [RoutedSwapState.fetchingQuote],
          ),
        );
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));

      final terminal = await swap.result;

      expect(terminal.isTerminal, isTrue);
      expect(
        terminal.isSuccess,
        isFalse,
        reason: 'a refund means the swap did not happen',
      );
      expect(terminal.receipt!.assetId, usdt);
      await manager.dispose();
    });

    test('a price move carries a re-priced offer ready to accept', () async {
      const fresh = RoutedSwapQuote(
        from: 'USDT-PLG20',
        to: 'USDC-ERC20',
        amount: '100.5',
        toAmount: '98.80',
        toAmountMin: '98.31',
      );
      final fixture = fixtureWithQuote()
        ..run(
          RoutedSwapRun(
            error: RoutedSwapTaskError.quoteWorsened(freshRoute: fresh),
          ),
        );
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));

      final terminal = await swap.result;
      final failure = terminal.failure!;

      expect(failure.kind, RoutedSwapFailureKind.priceMoved);
      expect(failure.fundsUntouched, isTrue);
      expect(failure.isRetryable, isTrue);
      // Without this the "price changed" prompt has to re-quote from scratch,
      // and the number the user accepts is not the one that was rejected.
      expect(failure.freshOffer, isNotNull);
      expect(failure.freshOffer!.guaranteedReceive, Decimal.parse('98.31'));
      await manager.dispose();
    });

    test('an unrecognised failure never claims the funds are safe', () async {
      final fixture = fixtureWithQuote()
        ..run(
          RoutedSwapRun(
            error: RoutedSwapTaskError.bridgeFailed(txHash: '0xabc'),
          ),
        );
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));

      final failure = (await swap.result).failure!;

      expect(failure.kind, RoutedSwapFailureKind.bridgeFailed);
      expect(failure.fundsUntouched, isFalse);
      expect(failure.isRetryable, isFalse);
      await manager.dispose();
    });
  });

  group('cancellation', () {
    test('is refused once the transaction has been handed over', () async {
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));

      await swap.progress.firstWhere(
        (p) => p.phase == RoutedSwapPhase.bridging,
      );

      await expectLater(
        swap.cancel(),
        throwsA(isA<RoutedSwapNotCancellableException>()),
      );
      await manager.dispose();
    });
  });

  group('recovery', () {
    test('a vanished task resolves from the durable record', () async {
      // A task can disappear for reasons that have nothing to do with the
      // swap: it was forgotten, cancelled, or lost to a restart. Surfacing a
      // raw NoSuchTask would tell the user their swap failed when it may be
      // running perfectly well.
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));

      await swap.progress.firstWhere(
        (p) => p.phase == RoutedSwapPhase.bridging,
      );
      fixture.restartKdf();

      // The record survives, so the stream must keep describing the swap
      // rather than erroring.
      final recovered = await manager.inFlight();
      expect(recovered.map((p) => p.uuid), contains(swap.uuid));
      expect(recovered.single.canCancel, isFalse);
      await manager.dispose();
    });

    test('a pre-broadcast restart reports funds untouched', () async {
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));
      fixture.restartKdf();

      final history = await manager.history();
      final entry = history.firstWhere((p) => p.uuid == swap.uuid);

      expect(entry.phase, RoutedSwapPhase.failed);
      expect(entry.failure!.kind, RoutedSwapFailureKind.abortedOnRestart);
      expect(entry.failure!.fundsUntouched, isTrue);
      expect(entry.failure!.isRetryable, isTrue);
      await manager.dispose();
    });

    test('watch replays a finished swap by uuid', () async {
      final fixture = fixtureWithQuote()
        ..run(RoutedSwapRun(states: const [RoutedSwapState.fetchingQuote]));
      final manager = managerFor(fixture);
      final swap = await manager.start(await offerFrom(manager));
      await swap.result;
      await manager.dispose();

      final replayed = await manager.watch(swap.uuid);
      final progress = await replayed.progress.first;

      expect(progress.uuid, swap.uuid);
      expect(progress.isTerminal, isTrue);
    });

    test('watch throws for an unknown swap', () async {
      final manager = managerFor(fixtureWithQuote());
      await expectLater(
        manager.watch('nope'),
        throwsA(isA<RoutedSwapNotFoundException>()),
      );
    });
  });

  group('event stream', () {
    test('progress completes even when no events ever arrive', () async {
      // KDF drops task events on a slow client, and a stream-driven UI that
      // waits for one would hang with the user's money in a bridge.
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final manager = managerFor(
        fixture,
        nudges: (_) => const Stream<void>.empty(),
      );
      final swap = await manager.start(await offerFrom(manager));

      final terminal = await swap.result.timeout(const Duration(seconds: 5));

      expect(terminal.isSuccess, isTrue);
      await manager.dispose();
    });

    test('a failing event stream does not break the swap', () async {
      final fixture = fixtureWithQuote()..run(RoutedSwapRun());
      final manager = managerFor(
        fixture,
        nudges: (_) => Stream<void>.error(StateError('sse down')),
      );
      final swap = await manager.start(await offerFrom(manager));

      final terminal = await swap.result.timeout(const Duration(seconds: 5));

      expect(terminal.isSuccess, isTrue);
      await manager.dispose();
    });
  });
}

/// An [ApiClient] backed by the scripted fake KDF, recording what was sent.
class _ScriptedClient implements ApiClient {
  _ScriptedClient(this._script);

  final KdfScript _script;
  final List<JsonMap> _requests = [];

  List<JsonMap> requestsFor(String method) =>
      _requests.where((r) => r['method'] == method).toList();

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    _requests.add(request);
    final response = await _script.respondTo(request);
    if (response == null) {
      throw StateError('nothing scripted for ${request['method']}');
    }
    return response;
  }
}
