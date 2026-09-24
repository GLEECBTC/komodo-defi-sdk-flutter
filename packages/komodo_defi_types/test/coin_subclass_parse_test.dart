import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  group('CoinSubClass.parse', () {
    test('resolves the Polygon config type label', () {
      // coins_config.json labels the 83 Polygon coins "Polygon" since the
      // MATIC -> POL rename. Before the enum member was renamed this only
      // resolved through the formatted-name substring fallback.
      expect(CoinSubClass.parse('Polygon'), CoinSubClass.polygon);
    });

    test('resolves the POL ticker', () {
      // Regression guard: 'pol' is a substring of 'simple ledger protocol',
      // so before `polygon` carried the POL ticker this returned
      // CoinSubClass.slp, which is an unsupported protocol.
      expect(CoinSubClass.parse('POL'), CoinSubClass.polygon);
    });

    test('keeps the PLG20 token standard suffix', () {
      expect(CoinSubClass.polygon.tokenStandardSuffix, 'PLG20');
      expect(CoinSubClass.parse('PLG20'), CoinSubClass.polygon);
    });

    test('resolves the POL platform and icon tickers', () {
      expect(CoinSubClass.polygon.ticker, 'POL');
      expect(CoinSubClass.polygon.iconTicker, 'POL');
    });

    test('resolves the pre-rename Matic type label', () {
      for (final label in ['Matic', 'MATIC', 'matic']) {
        expect(CoinSubClass.parse(label), CoinSubClass.polygon);
      }
    });
  });

  test('a Polygon token config stored before the rename still loads', () {
    // AssetAdapter persists the raw config and reads it back through
    // Asset.fromJson, so cached and custom tokens keep the old labels.
    final asset = Asset.fromJson(const {
      'coin': 'USDC-PLG20',
      'type': 'Matic',
      'name': 'USD Coin',
      'fname': 'USD Coin',
      'wallet_only': false,
      'mm2': 1,
      'chain_id': 137,
      'decimals': 6,
      'derivation_path': "m/44'/60'",
      'protocol': {
        'type': 'ERC20',
        'protocol_data': {
          'platform': 'MATIC',
          'contract_address': '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
        },
      },
      'contract_address': '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
      'parent_coin': 'MATIC',
      'swap_contract_address': '0x9130b257D37A52E52F21054c4DA3450c72f595CE',
      'fallback_swap_contract': '0x9130b257D37A52E52F21054c4DA3450c72f595CE',
      'nodes': <Map<String, dynamic>>[],
    });

    expect(asset.id.subClass, CoinSubClass.polygon);
    expect(asset.protocol.subClass, CoinSubClass.polygon);
  });
}
