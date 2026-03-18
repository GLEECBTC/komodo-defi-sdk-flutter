import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('FeeInfo EthGas serialization', () {
    test('should serialize EthGas with correct type', () {
      final feeInfo = FeeInfo.ethGas(
        coin: 'ETH',
        gasPrice: Decimal.parse('0.000000003'),
        gas: 21000,
      );

      final json = feeInfo.toJson();

      expect(json['type'], equals('EthGas'));
      expect(json['coin'], equals('ETH'));
      expect(json['gas_price'], equals('0.000000003'));
      expect(json['gas'], equals(21000));
    });

    test('should deserialize EthGas from JSON', () {
      final json = {
        'type': 'EthGas',
        'coin': 'ETH',
        'gas_price': '0.000000003',
        'gas': 21000,
      };

      final feeInfo = FeeInfo.fromJson(json);

      expect(feeInfo, isA<FeeInfoEthGas>());
      final ethGas = feeInfo as FeeInfoEthGas;
      expect(ethGas.coin, equals('ETH'));
      expect(ethGas.gasPrice, equals(Decimal.parse('0.000000003')));
      expect(ethGas.gas, equals(21000));
    });

    test('should handle backward compatibility with Eth type', () {
      final json = {
        'type': 'Eth', // Old format
        'coin': 'ETH',
        'gas_price': '0.000000003',
        'gas': 21000,
      };

      final feeInfo = FeeInfo.fromJson(json);

      expect(feeInfo, isA<FeeInfoEthGas>());
      final ethGas = feeInfo as FeeInfoEthGas;
      expect(ethGas.coin, equals('ETH'));
      expect(ethGas.gasPrice, equals(Decimal.parse('0.000000003')));
      expect(ethGas.gas, equals(21000));
    });
  });

  group('FeeInfo Tron serialization', () {
    test('should serialize Tron fee details with correct type', () {
      final feeInfo = FeeInfo.tron(
        coin: 'TRX',
        bandwidthUsed: 345,
        energyUsed: 29650,
        bandwidthFee: Decimal.parse('0.345'),
        energyFee: Decimal.parse('12.453'),
        totalFeeAmount: Decimal.parse('12.798'),
      );

      final json = feeInfo.toJson();

      expect(json['type'], equals('Tron'));
      expect(json['coin'], equals('TRX'));
      expect(json['bandwidth_used'], equals(345));
      expect(json['energy_used'], equals(29650));
      expect(json['bandwidth_fee'], equals('0.345'));
      expect(json['energy_fee'], equals('12.453'));
      expect(json['total_fee'], equals('12.798'));
    });

    test('should deserialize Tron fee details from JSON', () {
      final json = {
        'type': 'Tron',
        'coin': 'TRX',
        'bandwidth_used': 267,
        'energy_used': 0,
        'bandwidth_fee': '0.267',
        'energy_fee': '0',
        'total_fee': '0.267',
      };

      final feeInfo = FeeInfo.fromJson(json);

      expect(feeInfo, isA<FeeInfoTron>());
      final tronFee = feeInfo as FeeInfoTron;
      expect(tronFee.coin, equals('TRX'));
      expect(tronFee.bandwidthUsed, equals(267));
      expect(tronFee.energyUsed, equals(0));
      expect(tronFee.bandwidthFee, equals(Decimal.parse('0.267')));
      expect(tronFee.energyFee, equals(Decimal.zero));
      expect(tronFee.totalFeeAmount, equals(Decimal.parse('0.267')));
      expect(tronFee.totalFee, equals(Decimal.parse('0.267')));
    });
  });

  group('FeeInfo Tendermint compatibility', () {
    test('should serialize Tendermint fees as CosmosGas for requests', () {
      final feeInfo = FeeInfo.tendermint(
        coin: 'ATOM',
        amount: Decimal.parse('0.038553'),
        gasLimit: 100000,
      );

      final json = feeInfo.toJson();

      expect(json['type'], equals('CosmosGas'));
      expect(json['coin'], equals('ATOM'));
      expect(json['gas_limit'], equals(100000));
      expect(
        (json['gas_price'] as num).toDouble(),
        closeTo(0.00000038553, 1e-18),
      );
    });

    test(
      'should serialize Tendermint fees with zero gas limit as zero gas price',
      () {
        final feeInfo = FeeInfo.tendermint(
          coin: 'ATOM',
          amount: Decimal.parse('0.038553'),
          gasLimit: 0,
        );

        final json = feeInfo.toJson();

        expect(json['type'], equals('CosmosGas'));
        expect(json['gas_limit'], equals(0));
        expect(json['gas_price'], equals(0.0));
      },
    );

    test('should deserialize Tendermint fee details from response JSON', () {
      final json = {
        'type': 'Tendermint',
        'coin': 'ATOM',
        'amount': '0.038553',
        'gas_limit': 100000,
      };

      final feeInfo = FeeInfo.fromJson(json);

      expect(feeInfo, isA<FeeInfoTendermint>());
      final tendermintFee = feeInfo as FeeInfoTendermint;
      expect(tendermintFee.coin, equals('ATOM'));
      expect(tendermintFee.amount, equals(Decimal.parse('0.038553')));
      expect(tendermintFee.gasLimit, equals(100000));
      expect(tendermintFee.totalFee, equals(Decimal.parse('0.038553')));
    });
  });
}
