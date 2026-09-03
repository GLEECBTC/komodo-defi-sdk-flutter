import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_record_codec.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'transaction_fixtures.dart';

Transaction _roundTrip(Transaction transaction) =>
    TransactionRecordCodec.decode(TransactionRecordCodec.encode(transaction));

void main() {
  group('transaction round trip', () {
    test('preserves an entire transaction by value equality', () {
      final original = testTransaction(
        internalId: 'tx-0',
        id: 'a-different-id',
        confirmations: 7,
        blockHeight: 900,
        receivedByMe: Decimal.parse('1.25'),
        spentByMe: Decimal.parse('0.5'),
        totalAmount: Decimal.parse('1.75'),
        from: const ['from-a', 'from-b'],
        to: const ['to-a'],
        memo: 'a memo',
      );

      expect(_roundTrip(original), original);
    });

    test('preserves DateTime isUtc as well as the instant', () {
      // Transaction is Equatable with timestamp among its props, and
      // DateTime.== compares isUtc. TransactionInfoExtension.asTransaction
      // produces LOCAL times while the merge tests use UTC ones, so both
      // shapes exist in the wild and both must survive.
      for (final timestamp in [
        DateTime.utc(2026, 7, 10, 11, 12, 13, 140, 150),
        DateTime(2026, 7, 10, 11, 12, 13, 140, 150),
      ]) {
        final restored = _roundTrip(testTransaction(timestamp: timestamp));
        expect(restored.timestamp, timestamp);
        expect(restored.timestamp.isUtc, timestamp.isUtc);
        expect(
          restored.timestamp.microsecondsSinceEpoch,
          timestamp.microsecondsSinceEpoch,
        );
      }
    });

    test('preserves the epoch-zero timestamp used for pending rows', () {
      // TransactionListReconciler treats epoch 0 as "unconfirmed" and sorts it
      // to the top, so this value must not drift.
      final pending = DateTime.fromMillisecondsSinceEpoch(0);
      expect(
        _roundTrip(testTransaction(timestamp: pending)).timestamp,
        pending,
      );
    });

    test('preserves from and to ordering', () {
      // Transaction.props compares these lists element-wise.
      final original = testTransaction(
        from: const ['c', 'a', 'b'],
        to: const ['z', 'y'],
      );
      final restored = _roundTrip(original);
      expect(restored.from, ['c', 'a', 'b']);
      expect(restored.to, ['z', 'y']);
    });

    test('preserves empty address lists and null optional fields', () {
      final original = testTransaction(
        from: const [],
        to: const [],
        txHash: null,
        memo: null,
        confirmations: 0,
        blockHeight: 0,
      );
      final restored = _roundTrip(original);
      expect(restored, original);
      expect(restored.txHash, isNull);
      expect(restored.memo, isNull);
      expect(restored.fee, isNull);
    });

    test('preserves multi-byte unicode in a memo', () {
      final original = testTransaction(memo: 'メモ \u{1F600} café');
      expect(_roundTrip(original).memo, original.memo);
    });

    test('preserves decimal scale and precision', () {
      for (final value in [
        Decimal.parse('0.000000000000000000000000000001'),
        Decimal.parse('12345678901234567890.12345678901234567890'),
        Decimal.parse('12.50'),
        Decimal.zero,
      ]) {
        final restored = _roundTrip(
          testTransaction(
            receivedByMe: value,
            spentByMe: Decimal.zero,
            totalAmount: value,
          ),
        );
        expect(restored.balanceChanges.receivedByMe, value);
        expect(restored.balanceChanges.totalAmount, value);
      }
    });

    test('preserves a negative net balance change', () {
      final restored = _roundTrip(
        testTransaction(
          receivedByMe: Decimal.zero,
          spentByMe: Decimal.parse('3.5'),
          totalAmount: Decimal.parse('3.5'),
        ),
      );
      expect(restored.balanceChanges.netChange, Decimal.parse('-3.5'));
      expect(restored.balanceChanges.isIncoming, isFalse);
    });
  });

  group('asset identity', () {
    test('the reconstructed asset id equals the live one', () {
      // AssetId.props is [id, subClass.formatted, chainId.formattedChainId],
      // so a StoredChainId still compares equal to the concrete subtype.
      final original = testTransaction();
      final restored = _roundTrip(original);

      expect(restored.assetId, original.assetId);
      expect(restored.assetId.hashCode, original.assetId.hashCode);
      expect(restored, original);
    });

    test('scoped decoding returns the caller supplied asset id', () {
      // The live instance keeps parentId linkage, the concrete ChainId subtype
      // and the symbol's price-provider ids, none of which a reconstruction
      // can fully recover.
      final parent = testAssetId(id: 'TRX', subClass: CoinSubClass.trx);
      final child = testAssetId(parentId: parent);
      final original = testTransaction(assetId: child);

      final restored = TransactionRecordCodec.decode(
        TransactionRecordCodec.encode(original),
        scopedAssetId: child,
      );

      expect(identical(restored.assetId, child), isTrue);
      expect(restored.assetId.parentId, parent);
      expect(restored.assetId.isChildAsset, isTrue);
      expect(restored.assetId.chainId.decimals, 6);
    });

    test('unscoped decoding keeps chain decimals but drops parent linkage', () {
      final parent = testAssetId(id: 'TRX', subClass: CoinSubClass.trx);
      final child = testAssetId(parentId: parent);
      final restored = _roundTrip(testTransaction(assetId: child));

      expect(restored.assetId, child, reason: 'still equal by props');
      expect(restored.assetId.chainId.decimals, 6);
      expect(restored.assetId.parentId, isNull);
    });

    test('preserves all five AssetSymbol fields', () {
      // AssetId.toJson nests these and AssetSymbol.fromConfig reads them at the
      // top level, so the wire codec silently nulls all four external ids.
      final symbol = AssetSymbol(
        assetConfigId: 'USDT-TRC20',
        coinPaprikaId: 'usdt-tether',
        coinGeckoId: 'tether',
        liveCoinWatchId: 'USDT',
        binanceId: 'USDT',
      );
      final restored = _roundTrip(
        testTransaction(assetId: testAssetId(symbol: symbol)),
      );

      expect(restored.assetId.symbol.assetConfigId, 'USDT-TRC20');
      expect(restored.assetId.symbol.coinPaprikaId, 'usdt-tether');
      expect(restored.assetId.symbol.coinGeckoId, 'tether');
      expect(restored.assetId.symbol.liveCoinWatchId, 'USDT');
      expect(restored.assetId.symbol.binanceId, 'USDT');
    });

    test('preserves every CoinSubClass', () {
      // Regression guard for persisting subClass.formatted instead of the enum
      // name. CoinSubClass.parse strips '_-  ' from its input but matches
      // against un-sanitized formatted names, so multi-word names such as
      // 'Komodo Smart Chain' resolve to nothing, and 'Ethereum' (erc20)
      // resolves to ethereumClassic.
      for (final subClass in CoinSubClass.values) {
        final restored = _roundTrip(
          testTransaction(assetId: testAssetId(subClass: subClass)),
        );
        expect(
          restored.assetId.subClass,
          subClass,
          reason: 'lost ${subClass.name} (formatted: ${subClass.formatted})',
        );
      }
    });

    test('preserves non-integer chain ids', () {
      final tendermint = testAssetId(
        id: 'ATOM',
        subClass: CoinSubClass.tendermint,
        chainId: TendermintChainId(
          accountPrefix: 'cosmos',
          chainId: 'cosmoshub-4',
          chainRegistryName: 'cosmoshub',
          decimalsValue: 6,
        ),
      );
      final restored = _roundTrip(testTransaction(assetId: tendermint));

      expect(restored.assetId, tendermint);
      expect(
        restored.assetId.chainId.formattedChainId,
        'cosmoshub:cosmoshub-4',
      );
      expect(restored.assetId.chainId.decimals, 6);
    });

    test('falls back to unknown for an unrecognised sub class', () {
      final encoded =
          jsonDecode(TransactionRecordCodec.encode(testTransaction()))
              as Map<String, Object?>;
      (encoded['asset']! as Map<String, Object?>)['sub_class'] =
          'notARealClass';

      final restored = TransactionRecordCodec.decodeFromMap(encoded);
      expect(restored.assetId.subClass, CoinSubClass.unknown);
    });
  });

  group('fee round trip', () {
    final fees = <String, FeeInfo>{
      'utxoFixed': FeeInfo.utxoFixed(
        coin: 'BTC',
        amount: Decimal.parse('0.0001'),
      ),
      'utxoPerKbyte': FeeInfo.utxoPerKbyte(
        coin: 'BTC',
        amount: Decimal.parse('0.00012345'),
      ),
      'ethGas': FeeInfo.ethGas(
        coin: 'ETH',
        gasPrice: Decimal.parse('0.000000003'),
        gas: 21000,
      ),
      'ethGas with total': FeeInfo.ethGas(
        coin: 'ETH',
        gasPrice: Decimal.parse('0.000000003'),
        gas: 21000,
        totalGasFee: Decimal.parse('0.000063'),
      ),
      'ethGasEip1559': FeeInfo.ethGasEip1559(
        coin: 'ETH',
        maxFeePerGas: Decimal.parse('0.000000003'),
        maxPriorityFeePerGas: Decimal.parse('0.000000001'),
        gas: 21000,
      ),
      'ethGasEip1559 with total': FeeInfo.ethGasEip1559(
        coin: 'ETH',
        maxFeePerGas: Decimal.parse('0.000000003'),
        maxPriorityFeePerGas: Decimal.parse('0.000000001'),
        gas: 21000,
        totalGasFee: Decimal.parse('0.000063'),
      ),
      'qrc20Gas': FeeInfo.qrc20Gas(
        coin: 'QTUM',
        gasPrice: Decimal.parse('0.000000004'),
        gasLimit: 250000,
      ),
      'qrc20Gas with total': FeeInfo.qrc20Gas(
        coin: 'QTUM',
        gasPrice: Decimal.parse('0.000000004'),
        gasLimit: 250000,
        totalGasFee: Decimal.parse('0.001'),
      ),
      'cosmosGas': FeeInfo.cosmosGas(
        coin: 'IRIS',
        gasPrice: Decimal.parse('0.05'),
        gasLimit: 100000,
      ),
      'tendermint': FeeInfo.tendermint(
        coin: 'IRIS',
        amount: Decimal.parse('0.038553'),
        gasLimit: 100000,
      ),
      'tron': FeeInfo.tron(
        coin: 'TRX',
        bandwidthUsed: 268,
        energyUsed: 14000,
        bandwidthFee: Decimal.parse('0.268'),
        energyFee: Decimal.parse('5.88'),
      ),
      'tron with optionals': FeeInfo.tron(
        coin: 'TRX',
        bandwidthUsed: 268,
        energyUsed: 14000,
        bandwidthFee: Decimal.parse('0.268'),
        energyFee: Decimal.parse('5.88'),
        accountCreationFee: Decimal.parse('1.1'),
        totalFeeAmount: Decimal.parse('7.248'),
      ),
      'tronGasless': FeeInfo.tronGasless(
        coin: 'USDT-TRC20',
        feeMethod: 'gasless',
        providerName: 'gasfree',
        gasfreeAddress: 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird',
        transferFee: Decimal.parse('2.000000'),
        totalTokenFee: Decimal.parse('2.000000'),
        signedMaxFee: Decimal.parse('5.000000'),
      ),
      'tronGasless with activation': FeeInfo.tronGasless(
        coin: 'USDT-TRC20',
        feeMethod: 'gasless',
        providerName: 'gasfree',
        gasfreeAddress: 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird',
        transferFee: Decimal.parse('2.000000'),
        totalTokenFee: Decimal.parse('3.000000'),
        signedMaxFee: Decimal.parse('5.000000'),
        activationFee: Decimal.parse('1.000000'),
      ),
      'sia': FeeInfo.sia(
        coin: 'SC',
        amount: Decimal.parse('0.000010000000000000000000'),
        policy: 'Fixed',
      ),
    };

    for (final entry in fees.entries) {
      test('${entry.key} survives intact', () {
        final restored = _roundTrip(testTransaction(fee: entry.value));
        expect(restored.fee, entry.value);
        expect(restored.fee.runtimeType, entry.value.runtimeType);
        expect(restored.fee!.totalFee, entry.value.totalFee);
      });
    }

    test('every FeeInfo variant is covered by this suite', () {
      // FeeInfo is sealed, so encode() fails to compile when a variant is
      // added. This keeps the *test* table honest at the same time.
      expect(
        fees.values.map((fee) => fee.runtimeType).toSet(),
        hasLength(10),
        reason: 'one case per FeeInfo variant',
      );
    });

    test('tendermint does not decode back as cosmosGas', () {
      // FeeInfoTendermint.toJson emits "type": "CosmosGas", so the wire codec
      // changes the variant and re-derives amount as amount/gasLimit through a
      // double. Tagging by the Dart variant avoids both.
      final original =
          FeeInfo.tendermint(
                coin: 'IRIS',
                amount: Decimal.parse('0.038553'),
                gasLimit: 100000,
              )
              as FeeInfoTendermint;
      final restored = _roundTrip(testTransaction(fee: original)).fee;

      expect(restored, isA<FeeInfoTendermint>());
      expect((restored! as FeeInfoTendermint).amount, original.amount);
    });

    test('tendermint with a zero gas limit keeps its amount', () {
      // The wire codec divides by gasLimit and writes 0.0 when it is zero,
      // silently zeroing the fee.
      final original = FeeInfo.tendermint(
        coin: 'IRIS',
        amount: Decimal.parse('0.038553'),
        gasLimit: 0,
      );
      expect(_roundTrip(testTransaction(fee: original)).fee, original);
    });

    test('qrc20Gas keeps gas price precision beyond double', () {
      final original =
          FeeInfo.qrc20Gas(
                coin: 'QTUM',
                gasPrice: Decimal.parse('0.000000004000000001234567'),
                gasLimit: 250000,
              )
              as FeeInfoQrc20Gas;
      final restored =
          _roundTrip(testTransaction(fee: original)).fee! as FeeInfoQrc20Gas;

      expect(restored.gasPrice, original.gasPrice);
      expect(
        restored.gasPrice.toString(),
        '0.000000004000000001234567',
        reason: 'toDouble() would have truncated this',
      );
    });

    test('cosmosGas keeps gas price precision beyond double', () {
      final original =
          FeeInfo.cosmosGas(
                coin: 'IRIS',
                gasPrice: Decimal.parse('0.050000000000000001'),
                gasLimit: 100000,
              )
              as FeeInfoCosmosGas;
      final restored =
          _roundTrip(testTransaction(fee: original)).fee! as FeeInfoCosmosGas;
      expect(restored.gasPrice, original.gasPrice);
    });

    test('tronGasless preserves a zero activation fee', () {
      // FeeInfo.fromJson rejects activationFee <= 0 outright, so a stored zero
      // would be unrepresentable through the wire codec.
      final original = FeeInfo.tronGasless(
        coin: 'USDT-TRC20',
        feeMethod: 'gasless',
        providerName: 'gasfree',
        gasfreeAddress: 'T-address',
        transferFee: Decimal.parse('2'),
        totalTokenFee: Decimal.parse('2'),
        signedMaxFee: Decimal.parse('5'),
        activationFee: Decimal.zero,
      );
      final restored = _roundTrip(testTransaction(fee: original)).fee;

      expect(restored, original);
      expect((restored! as FeeInfoTronGasless).activationFee, Decimal.zero);
    });

    test('tronGasless preserves non-canonical method and provider', () {
      // fromJson hard-requires "gasless"/"gasfree"; storage must not re-impose
      // wire validation on an already-validated object.
      final original = FeeInfo.tronGasless(
        coin: 'USDT-TRC20',
        feeMethod: 'sponsored',
        providerName: 'some-other-relay',
        gasfreeAddress: 'T-address',
        transferFee: Decimal.parse('2'),
        totalTokenFee: Decimal.parse('2'),
        signedMaxFee: Decimal.parse('5'),
      );
      expect(_roundTrip(testTransaction(fee: original)).fee, original);
    });
  });

  group('failure handling', () {
    test('rejects a record from a newer schema', () {
      final encoded =
          jsonDecode(TransactionRecordCodec.encode(testTransaction()))
              as Map<String, Object?>;
      encoded['v'] = TransactionRecordCodec.currentVersion + 1;

      expect(
        () => TransactionRecordCodec.decodeFromMap(encoded),
        throwsA(isA<TransactionRecordVersionException>()),
      );
    });

    test('rejects an unknown fee kind', () {
      expect(
        () => FeeRecordCodec.decode({'k': 'notARealFee'}),
        throwsA(isA<TransactionRecordFormatException>()),
      );
    });

    test('rejects malformed JSON', () {
      expect(
        () => TransactionRecordCodec.decode('{not json'),
        throwsA(isA<TransactionRecordFormatException>()),
      );
    });

    test('rejects a JSON value that is not an object', () {
      expect(
        () => TransactionRecordCodec.decode('[]'),
        throwsA(isA<TransactionRecordFormatException>()),
      );
    });

    test('rejects records with missing or mistyped fields', () {
      for (final mutate in <void Function(Map<String, Object?>)>[
        (json) => json.remove('internal_id'),
        (json) => json['ts_us'] = 'not-a-number',
        (json) => json['ts_utc'] = 'not-a-bool',
        (json) => json['from'] = 'not-a-list',
        (json) => json['from'] = [1, 2],
        (json) => json['balance'] = 'not-an-object',
        (json) =>
            (json['balance']! as Map<String, Object?>)['net'] = 'not-a-decimal',
      ]) {
        final encoded =
            jsonDecode(TransactionRecordCodec.encode(testTransaction()))
                as Map<String, Object?>;
        mutate(encoded);
        expect(
          () => TransactionRecordCodec.decodeFromMap(encoded),
          throwsA(isA<TransactionRecordFormatException>()),
        );
      }
    });
  });

  group('why this codec exists', () {
    test('Transaction.toJson does not round-trip through fromJson', () {
      // Pins the reason the SDK cannot simply persist Transaction.toJson.
      // If this ever starts passing, the wire codec has been made symmetric
      // and this codec's justification should be revisited.
      expect(
        () => Transaction.fromJson(testTransaction().toJson()),
        throwsA(anything),
      );
    });
  });
}
