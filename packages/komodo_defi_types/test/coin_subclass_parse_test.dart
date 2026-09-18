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
  });
}
