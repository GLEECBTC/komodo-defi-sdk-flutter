import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _erc20Config() => {
  'coin': 'ETH',
  'type': 'ETH',
  'name': 'Ethereum',
  'fname': 'Ethereum',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 1,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 1},
  },
  'nodes': <Map<String, dynamic>>[],
};

void main() {
  group('feeEstimationSupportForProtocol', () {
    test('TRX platform assets are explicitly unsupported', () {
      final protocol = ProtocolClass.fromJson(_trxConfig());

      expect(
        feeEstimationSupportForProtocol(protocol),
        FeeEstimationSupport.unsupported,
      );
    });

    test('TRC20 tokens are explicitly unsupported', () {
      final protocol = ProtocolClass.fromJson(_trc20Config());

      expect(
        feeEstimationSupportForProtocol(protocol),
        FeeEstimationSupport.unsupported,
      );
    });

    test('supported EVM protocols still classify as gas-estimated', () {
      final protocol = ProtocolClass.fromJson(_erc20Config());

      expect(
        feeEstimationSupportForProtocol(protocol),
        FeeEstimationSupport.evmGas,
      );
    });
  });
}
