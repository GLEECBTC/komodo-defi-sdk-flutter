import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  group('withdraw request serialization', () {
    test('serializes Tendermint fee requests as CosmosGas', () {
      final request = WithdrawInitRequest(
        rpcPass: 'rpc-pass',
        params: WithdrawParameters(
          asset: 'ATOM',
          toAddress: 'cosmos1destination',
          amount: Decimal.parse('0.1'),
          fee: FeeInfo.tendermint(
            coin: 'ATOM',
            amount: Decimal.parse('0.038553'),
            gasLimit: 100000,
          ),
        ),
      );

      final json = request.toJson();
      final params = json['params'] as Map<String, dynamic>;
      final fee = params['fee'] as Map<String, dynamic>;

      expect(fee['type'], equals('CosmosGas'));
      expect(fee['coin'], equals('ATOM'));
      expect(fee['gas_limit'], equals(100000));
      expect(
        (fee['gas_price'] as num).toDouble(),
        closeTo(0.00000038553, 1e-18),
      );
    });
  });
}
