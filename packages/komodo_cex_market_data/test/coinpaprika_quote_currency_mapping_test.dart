import 'package:komodo_cex_market_data/src/coinpaprika/data/coinpaprika_cex_provider.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:test/test.dart';

/// Simple test to validate that quote currency mapping works correctly
/// for CoinPaprika API calls. This ensures USDT maps to USD, EURS maps to EUR, etc.
void main() {
  group('CoinPaprika Quote Currency Mapping Validation', () {
    test('USDT should map to USD in coinPaprikaId', () {
      // Verify that USDT stablecoin returns 'usdt' as coinPaprikaId
      expect(Stablecoin.usdt.coinPaprikaId, equals('usdt'));

      // Verify that the underlying fiat is USD
      expect(Stablecoin.usdt.underlyingFiat.coinPaprikaId, equals('usd'));
    });

    test('USDC should map to USD in coinPaprikaId', () {
      expect(Stablecoin.usdc.coinPaprikaId, equals('usdc'));
      expect(Stablecoin.usdc.underlyingFiat.coinPaprikaId, equals('usd'));
    });

    test('EURS should map to EUR in coinPaprikaId', () {
      expect(Stablecoin.eurs.coinPaprikaId, equals('eurs'));
      expect(Stablecoin.eurs.underlyingFiat.coinPaprikaId, equals('eur'));
    });

    test('GBPT should map to GBP in coinPaprikaId', () {
      expect(Stablecoin.gbpt.coinPaprikaId, equals('gbpt'));
      expect(Stablecoin.gbpt.underlyingFiat.coinPaprikaId, equals('gbp'));
    });

    test('fiat currencies should return themselves', () {
      expect(FiatCurrency.usd.coinPaprikaId, equals('usd'));
      expect(FiatCurrency.eur.coinPaprikaId, equals('eur'));
      expect(FiatCurrency.gbp.coinPaprikaId, equals('gbp'));
    });

    test('cryptocurrencies should return themselves', () {
      expect(Cryptocurrency.btc.coinPaprikaId, equals('btc'));
      expect(Cryptocurrency.eth.coinPaprikaId, equals('eth'));
    });

    test('stablecoin mapping behavior using when method', () {
      // Test that the when method correctly maps stablecoins to underlying fiat
      final mappedUsdt = Stablecoin.usdt.when(
        fiat: (_, __) => Stablecoin.usdt,
        stablecoin: (_, __, underlyingFiat) => underlyingFiat,
        crypto: (_, __) => Stablecoin.usdt,
        commodity: (_, __) => Stablecoin.usdt,
      );

      expect(mappedUsdt, equals(FiatCurrency.usd));
      expect(mappedUsdt.coinPaprikaId, equals('usd'));
    });

    test('fiat currency preservation using when method', () {
      // Test that fiat currencies are preserved as-is
      final preservedUsd = FiatCurrency.usd.when(
        fiat: (_, __) => FiatCurrency.usd,
        stablecoin: (_, __, underlyingFiat) => underlyingFiat,
        crypto: (_, __) => FiatCurrency.usd,
        commodity: (_, __) => FiatCurrency.usd,
      );

      expect(preservedUsd, equals(FiatCurrency.usd));
      expect(preservedUsd.coinPaprikaId, equals('usd'));
    });

    test('cryptocurrency preservation using when method', () {
      // Test that cryptocurrencies are preserved as-is
      final preservedBtc = Cryptocurrency.btc.when(
        fiat: (_, __) => Cryptocurrency.btc,
        stablecoin: (_, __, underlyingFiat) => underlyingFiat,
        crypto: (_, __) => Cryptocurrency.btc,
        commodity: (_, __) => Cryptocurrency.btc,
      );

      expect(preservedBtc, equals(Cryptocurrency.btc));
      expect(preservedBtc.coinPaprikaId, equals('btc'));
    });

    test('multiple USD stablecoins should all map to USD', () {
      final usdStablecoins = [
        Stablecoin.usdt,
        Stablecoin.usdc,
        Stablecoin.dai,
        Stablecoin.busd,
        Stablecoin.tusd,
      ];

      for (final stablecoin in usdStablecoins) {
        expect(
          stablecoin.underlyingFiat.coinPaprikaId,
          equals('usd'),
          reason: '${stablecoin.symbol} should have USD as underlying fiat',
        );
      }
    });

    test('coinPaprikaQuoteCurrency maps stablecoins to their fiat', () {
      expect(
        Stablecoin.usdt.coinPaprikaQuoteCurrency.coinPaprikaId,
        equals('usd'),
        reason: 'USDT should map to USD',
      );

      expect(
        Stablecoin.eurs.coinPaprikaQuoteCurrency.coinPaprikaId,
        equals('eur'),
        reason: 'EURS should map to EUR',
      );

      expect(
        FiatCurrency.usd.coinPaprikaQuoteCurrency.coinPaprikaId,
        equals('usd'),
        reason: 'USD should remain USD',
      );

      expect(
        Cryptocurrency.btc.coinPaprikaQuoteCurrency.coinPaprikaId,
        equals('btc'),
        reason: 'BTC should remain BTC',
      );

      expect(
        Commodity.xau.coinPaprikaQuoteCurrency.coinPaprikaId,
        equals('xau'),
        reason: 'XAU should remain XAU',
      );
    });
  });
}
