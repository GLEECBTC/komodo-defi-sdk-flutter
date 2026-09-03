import 'package:komodo_defi_sdk/src/addresses/address_operations.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
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

Map<String, dynamic> _utxoConfig() => {
  'coin': 'KMD',
  'type': 'UTXO',
  'name': 'Komodo',
  'fname': 'Komodo',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'/0'",
  'protocol': {'type': 'UTXO'},
};

class _RecordingApiClient implements ApiClient {
  final List<JsonMap> requests = <JsonMap>[];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(Map<String, dynamic>.from(request));
    return {
      'result': {'is_valid': true},
    };
  }
}

void main() {
  group('AddressOperations.validateAddress', () {
    test('uses TRX platform coin for TRC20 token address validation', () async {
      final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
      final token = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
      final client = _RecordingApiClient();
      final operations = AddressOperations(client);

      final result = await operations.validateAddress(
        asset: token,
        address: 'TVUvVSHBKPi8jNANj214YmFBV4qSzdPcBz',
      );

      expect(result.isValid, isTrue);
      expect(client.requests, hasLength(1));
      expect(client.requests.single['method'], 'validateaddress');
      expect(client.requests.single['coin'], 'TRX');
      expect(client.requests.single['address'], result.address);
    });

    test('uses asset coin for non-TRC20 address validation', () async {
      final asset = Asset.fromJson(_utxoConfig(), knownIds: const {});
      final client = _RecordingApiClient();
      final operations = AddressOperations(client);

      await operations.validateAddress(
        asset: asset,
        address: 'R9jEwJ3nHqDbQeKsAt8Y9b7KQbNfxg5oMo',
      );

      expect(client.requests, hasLength(1));
      expect(client.requests.single['method'], 'validateaddress');
      expect(client.requests.single['coin'], 'KMD');
    });
  });
}
