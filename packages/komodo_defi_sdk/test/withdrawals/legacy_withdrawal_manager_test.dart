import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/activation/activation_policy.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../transaction_history/transaction_fixtures.dart';

class _MockApiClient extends Mock implements ApiClient {}

final _asset = testAssetId(id: 'ATOM', subClass: CoinSubClass.tendermint);

WithdrawResult _signed() => WithdrawResult(
  txHex: 'signed-hex',
  txHash: 'signed-hash',
  from: const ['sender'],
  to: const ['recipient'],
  balanceChanges: BalanceChanges(
    netChange: Decimal.parse('-1'),
    receivedByMe: Decimal.zero,
    spentByMe: Decimal.one,
    totalAmount: Decimal.one,
  ),
  blockHeight: 0,
  timestamp: 0,
  fee: FeeInfo.tendermint(
    coin: 'ATOM',
    amount: Decimal.parse('0.01'),
    gasLimit: 100000,
  ),
  coin: 'ATOM',
);

void main() {
  late ApiClient client;
  late List<String> methods;
  late LegacyWithdrawalManager manager;
  late bool restricted;

  void ensureAllowed() {
    if (restricted) {
      throw ActivationPolicyException(_asset, ActivationPolicyStatus.ready);
    }
  }

  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  setUp(() {
    client = _MockApiClient();
    methods = [];
    restricted = false;
    when(() => client.executeRpc(any())).thenAnswer((invocation) async {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      methods.add(request['method'] as String);
      return request['method'] == 'withdraw'
          ? {
              'mmrpc': '2.0',
              'result': {'status': 'Ok', 'details': _signed().toJson()},
            }
          : {'tx_hash': 'broadcast-hash'};
    });
    manager = LegacyWithdrawalManager(client);
  });

  /// Holds the stream on each event before [holdAfter], restricts the asset,
  /// then resumes and returns the error that ends the stream.
  Future<Object?> errorAfterHolding(
    Stream<WithdrawalProgress> stream,
    int holdAfter,
  ) async {
    final events = StreamIterator(stream);
    for (var i = 0; i < holdAfter; i++) {
      expect(await events.moveNext(), isTrue);
    }
    restricted = true;
    try {
      await events.moveNext();
      return null;
    } on Object catch (error) {
      return error;
    } finally {
      await events.cancel();
    }
  }

  final restrictedError = isA<SdkError>().having(
    (error) => error.source,
    'source',
    isA<ActivationPolicyException>(),
  );

  test('execution does not broadcast after a held progress event', () async {
    final error = await errorAfterHolding(
      manager.executeWithdrawal(
        _signed(),
        'ATOM',
        beforeBroadcast: ensureAllowed,
      ),
      1,
    );

    expect(error, restrictedError);
    expect(methods, isEmpty);
  });

  test('one-shot withdrawal signs but does not broadcast', () async {
    final error = await errorAfterHolding(
      manager.withdraw(
        WithdrawParameters(
          asset: 'ATOM',
          toAddress: 'recipient',
          amount: Decimal.one,
        ),
        beforeBroadcast: ensureAllowed,
      ),
      2,
    );

    expect(error, restrictedError);
    expect(methods, ['withdraw']);
  });
}
