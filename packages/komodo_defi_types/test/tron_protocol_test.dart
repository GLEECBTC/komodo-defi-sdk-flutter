import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRC-20',
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

void main() {
  group('TRON protocol parsing', () {
    test('AssetId.parse prefers protocol.type over top-level type for TRX', () {
      final assetId = AssetId.parse(_trxConfig(), knownIds: const {});

      expect(assetId.id, 'TRX');
      expect(assetId.subClass, CoinSubClass.trx);
      expect(assetId.displayName, 'TRON');
    });

    test('ProtocolClass.fromJson parses TRX without EVM swap contracts', () {
      final protocol = ProtocolClass.fromJson(_trxConfig());

      expect(protocol, isA<TrxProtocol>());
      expect(protocol.subClass, CoinSubClass.trx);
      expect((protocol as TrxProtocol).nodes, isEmpty);
      expect(protocol.network, 'Mainnet');
      expect(protocol.supportsTxHistoryStreaming(isChildAsset: false), isTrue);
    });

    test('Asset.fromJson links TRC20 child asset to TRX parent', () {
      final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
      final child = Asset.fromJson(_trc20Config(), knownIds: {parent.id});

      expect(child.id.subClass, CoinSubClass.trc20);
      expect(child.protocol, isA<Trc20Protocol>());
      expect(child.id.parentId, parent.id);
      expect(parent.id.subClass.canBeParentOf(child.id.subClass), isTrue);
      expect(child.supportsBalanceStreaming, isTrue);
      expect(child.supportsTxHistoryStreaming, isTrue);
    });
  });
}
