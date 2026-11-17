import 'dart:async';

import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'solana_fixtures.dart';

class _Client extends Mock implements ApiClient {}

class _Events extends Mock implements KdfEventStreamingService {}

void main() {
  test(
    'SOL platform streams share registration and route asset payloads',
    () async {
      final client = _Client();
      final events = _Events();
      final history = StreamController<TxHistoryEvent>.broadcast(sync: true);
      final balance = StreamController<BalanceEvent>.broadcast(sync: true);
      final disconnected = StreamController<KdfEventDisconnection>.broadcast(
        sync: true,
      );
      final requests = <Map<String, dynamic>>[];
      when(() => events.txHistoryEvents).thenAnswer((_) => history.stream);
      when(() => events.balanceEvents).thenAnswer((_) => balance.stream);
      when(() => events.disconnections).thenAnswer((_) => disconnected.stream);
      when(() => events.firstByteReceived).thenAnswer((_) async {});
      when(() => events.isConnected).thenReturn(true);
      when(() => events.connectIfNeeded()).thenAnswer((_) {});
      when(() => events.disconnect()).thenAnswer((_) async {});
      when(() => client.executeRpc(any())).thenAnswer((call) async {
        final request = call.positionalArguments.single as Map<String, dynamic>;
        requests.add(request);
        if (request['method'] == 'stream::disable') {
          return {
            'mmrpc': '2.0',
            'result': {'result': 'Success'},
          };
        }
        final kind = request['method'] == 'stream::balance::enable'
            ? 'BALANCE'
            : 'TX_HISTORY';
        return {
          'mmrpc': '2.0',
          'result': {'streamer_id': '$kind:TESTSOL'},
        };
      });
      final manager = EventStreamingManager(
        client: client,
        eventService: events,
      );
      addTearDown(() async {
        await manager.dispose();
        await history.close();
        await balance.close();
        await disconnected.close();
      });
      final solRows = <TxHistoryEvent>[];
      final tokenRows = <TxHistoryEvent>[];
      final sol = await manager.subscribeToTxHistory(coin: 'TESTSOL');
      sol.onData(solRows.add);
      final token = await manager.subscribeToTxHistory(
        coin: 'TESTUSDC-TESTSOL',
        streamerCoin: 'TESTSOL',
      );
      token.onData(tokenRows.add);
      expect(
        requests.where((r) => r['method'] == 'stream::tx_history::enable'),
        hasLength(1),
      );
      final parsed =
          KdfEvent.parseAll({
                '_type': 'TX_HISTORY:TESTSOL',
                'message': solanaHistoryRow(),
              }).single
              as TxHistoryEvent;
      history.add(parsed);
      await pumpEventQueue();
      expect(solRows, isEmpty);
      expect(tokenRows.single.coin, 'TESTUSDC-TESTSOL');
      expect(
        tokenRows.single.transactions.single.txHash,
        'AbCdeF123Base58Signature',
      );
      expect(tokenRows.single.transactions.single.memo, isNull);
      await token.cancel();
      expect(requests.where((r) => r['method'] == 'stream::disable'), isEmpty);
      await sol.cancel();
      expect(
        requests.where((r) => r['method'] == 'stream::disable'),
        hasLength(1),
      );
      final solBalance = await manager.subscribeToBalance(coin: 'TESTSOL');
      final tokenBalance = await manager.subscribeToBalance(
        coin: 'TESTUSDC-TESTSOL',
        streamerCoin: 'TESTSOL',
      );
      final received = <BalanceEvent>[];
      tokenBalance.onData(received.add);
      for (final event in KdfEvent.parseAll({
        '_type': 'BALANCE:TESTSOL',
        'message': [
          {
            'ticker': 'TESTSOL',
            'balance': {'spendable': '0.1', 'unspendable': '0'},
          },
          {
            'ticker': 'TESTUSDC-TESTSOL',
            'balance': {'spendable': '1.234567', 'unspendable': '0'},
          },
        ],
      })) {
        balance.add(event as BalanceEvent);
      }
      await pumpEventQueue();
      expect(received.single.balance.spendable.toString(), '1.234567');
      expect(
        requests.where((r) => r['method'] == 'stream::balance::enable'),
        hasLength(1),
      );
      final errors = <Object>[];
      solBalance.onError(errors.add);
      tokenBalance.onError(errors.add);
      disconnected.add(
        const KdfEventDisconnection(
          KdfEventDisconnectionKind.transportRegistrationsDropped,
        ),
      );
      await pumpEventQueue();
      expect(errors, hasLength(2));
      await solBalance.cancel();
      await tokenBalance.cancel();
      final reconnected = await manager.subscribeToBalance(
        coin: 'TESTUSDC-TESTSOL',
        streamerCoin: 'TESTSOL',
      );
      expect(
        requests.where((r) => r['method'] == 'stream::balance::enable'),
        hasLength(2),
      );
      await reconnected.cancel();
    },
  );
}
