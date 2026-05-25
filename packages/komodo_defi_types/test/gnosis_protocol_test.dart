import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Map<String, dynamic> _xdaiConfig() => {
  'coin': 'XDAI',
  'type': 'Gnosis',
  'name': 'xDAI',
  'fname': 'Gnosis',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 100,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 100},
  },
  'swap_contract_address': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'fallback_swap_contract': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'nodes': [
    {'url': 'https://rpc.gnosischain.com'},
  ],
};

Map<String, dynamic> _usdcGnoConfig() => {
  'coin': 'USDC-GNO',
  'type': 'Gnosis',
  'name': 'USD Coin',
  'fname': 'USD Coin',
  'wallet_only': true,
  'mm2': 1,
  'chain_id': 100,
  'decimals': 6,
  'required_confirmations': 3,
  'protocol': {
    'type': 'ETH',
    'protocol_data': {
      'platform': 'XDAI',
      'contract_address': '0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0',
      'decimals': 6,
    },
  },
  'contract_address': '0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0',
  'parent_coin': 'XDAI',
  'swap_contract_address': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'fallback_swap_contract': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
  'nodes': [
    {'url': 'https://rpc.gnosischain.com'},
  ],
};

void main() {
  group('Gnosis protocol parsing', () {
    test('CoinSubClass exposes canonical Gnosis metadata', () {
      expect(CoinSubClass.parse('Gnosis'), CoinSubClass.gnosis);
      expect(CoinSubClass.gnosis.ticker, 'XDAI');
      expect(CoinSubClass.gnosis.iconTicker, 'XDAI');
      expect(CoinSubClass.gnosis.formatted, 'Gnosis');
      expect(CoinSubClass.gnosis.tokenStandardSuffix, 'GNO');
      expect(evmCoinSubClasses, contains(CoinSubClass.gnosis));
    });

    test('XDAI parses as an EVM platform asset', () {
      final asset = Asset.fromJson(_xdaiConfig(), knownIds: const {});

      expect(asset.id.id, 'XDAI');
      expect(asset.id.subClass, CoinSubClass.gnosis);
      expect(asset.id.parentId, isNull);
      expect(asset.protocol, isA<Erc20Protocol>());
      expect(asset.protocol.subClass, CoinSubClass.gnosis);
      expect(asset.supportsBalanceStreaming, isTrue);
      expect(asset.supportsTxHistoryStreaming, isFalse);
    });

    test('USDC-GNO links to XDAI and keeps the Gnosis subclass', () {
      final parent = Asset.fromJson(_xdaiConfig(), knownIds: const {});
      final child = Asset.fromJson(_usdcGnoConfig(), knownIds: {parent.id});

      expect(child.id.id, 'USDC-GNO');
      expect(child.id.parentId, parent.id);
      expect(child.id.subClass, CoinSubClass.gnosis);
      expect(child.protocol, isA<Erc20Protocol>());
      expect(parent.id.subClass.canBeParentOf(child.id.subClass), isTrue);
      expect(child.id.subClass.canBeChildOf(parent.id.subClass), isTrue);
      expect(child.protocol.contractAddress, isNotNull);
    });
  });
}
