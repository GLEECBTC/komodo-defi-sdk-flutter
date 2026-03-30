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
  'explorer_url': 'https://tronscan.org/',
  'explorer_tx_url': '#/transaction/',
  'explorer_address_url': '#/address/',
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
  'explorer_url': 'https://tronscan.org/',
  'explorer_tx_url': '#/transaction/',
  'explorer_address_url': '#/address/',
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

Map<String, dynamic> _avaxConfig() => {
  'coin': 'AVAX',
  'type': 'AVX-20',
  'name': 'Avalanche',
  'fname': 'Avalanche',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 43114,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 43114},
  },
  'swap_contract_address': '0x9130b257D37A52E52F21054c4DA3450c72f595CE',
  'fallback_swap_contract': '0x9130b257D37A52E52F21054c4DA3450c72f595CE',
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _bnbConfig() => {
  'coin': 'BNB',
  'type': 'BEP-20',
  'name': 'BNB Smart Chain',
  'fname': 'BNB Smart Chain',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 56,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 56},
  },
  'swap_contract_address': '0xeDc5b89Fe1f0382F9E4316069971D90a0951DB31',
  'fallback_swap_contract': '0xeDc5b89Fe1f0382F9E4316069971D90a0951DB31',
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _arrrBep20Config() => {
  'coin': 'ARRR-BEP20',
  'type': 'BEP-20',
  'name': 'Pirate',
  'fname': 'Pirate',
  'wallet_only': true,
  'mm2': 1,
  'chain_id': 56,
  'decimals': 8,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ERC20',
    'protocol_data': {
      'platform': 'BNB',
      'contract_address': '0xCDAF240C90F989847c56aC9Dee754F76F41c5833',
    },
  },
  'contract_address': '0xCDAF240C90F989847c56aC9Dee754F76F41c5833',
  'parent_coin': 'BNB',
  'swap_contract_address': '0xeDc5b89Fe1f0382F9E4316069971D90a0951DB31',
  'fallback_swap_contract': '0xeDc5b89Fe1f0382F9E4316069971D90a0951DB31',
  'nodes': <Map<String, dynamic>>[],
};

void main() {
  group('TRON protocol parsing', () {
    test('AssetId.parse uses top-level type for TRX platform assets', () {
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
      expect(protocol.supportsTxHistoryStreaming(isChildAsset: false), isFalse);
      expect(
        protocol.explorerTxUrl('abc123')?.toString(),
        'https://tronscan.org/#/transaction/abc123',
      );
      expect(
        protocol.explorerAddressUrl('TAddress123')?.toString(),
        'https://tronscan.org/#/address/TAddress123',
      );
    });

    test('Asset.fromJson links TRC20 child asset to TRX parent', () {
      final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
      final child = Asset.fromJson(_trc20Config(), knownIds: {parent.id});

      expect(child.id.subClass, CoinSubClass.trc20);
      expect(child.protocol, isA<Trc20Protocol>());
      expect(child.id.parentId, parent.id);
      expect(parent.id.subClass.canBeParentOf(child.id.subClass), isTrue);
      expect(child.supportsBalanceStreaming, isTrue);
      expect(child.supportsTxHistoryStreaming, isFalse);
      expect(
        child.protocol.explorerTxUrl('def456')?.toString(),
        'https://tronscan.org/#/transaction/def456',
      );
      expect(
        child.protocol.explorerAddressUrl('TTokenAddress456')?.toString(),
        'https://tronscan.org/#/address/TTokenAddress456',
      );
    });

    test('TRC20 child assets use the TRX badge icon ticker', () {
      expect(CoinSubClass.trc20.iconTicker, 'TRX');
    });

    test('non-TRON platform assets keep top-level subtype precedence', () {
      final assetId = AssetId.parse(_avaxConfig(), knownIds: const {});
      final protocol = ProtocolClass.fromJson(_avaxConfig());

      expect(assetId.subClass, CoinSubClass.avx20);
      expect(protocol, isA<Erc20Protocol>());
      expect(protocol.subClass, CoinSubClass.avx20);
    });

    test('non-TRON token assets keep top-level subtype precedence', () {
      final parent = Asset.fromJson(_bnbConfig(), knownIds: const {});
      final child = Asset.fromJson(_arrrBep20Config(), knownIds: {parent.id});

      expect(child.id.subClass, CoinSubClass.bep20);
      expect(child.protocol, isA<Erc20Protocol>());
      expect(child.protocol.subClass, CoinSubClass.bep20);
      expect(child.id.parentId, parent.id);
    });
  });
}
