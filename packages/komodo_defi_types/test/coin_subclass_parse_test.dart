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

    test('uses the POL platform ticker', () {
      expect(CoinSubClass.polygon.ticker, 'POL');
    });

    test('keeps the matic icon file until the coins mainline carries POL', () {
      // `iconTicker` names an icon file, not a coin. `matic.png` exists both
      // before and after the rename (upstream keeps it for MATIC-ERC20 and
      // MATIC-BEP20); `pol.png` only exists after. Flip this once the rename
      // is on the coins mainline and `pol.png` is on the CDN.
      expect(CoinSubClass.polygon.iconTicker, 'MATIC');
    });
  });
}
