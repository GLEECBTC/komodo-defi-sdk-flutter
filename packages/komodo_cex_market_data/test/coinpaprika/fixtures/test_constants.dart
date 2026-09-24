/// Common test constants and data used across CoinPaprika tests
library;

import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/src/coinpaprika/models/coinpaprika_coin.dart';
import 'package:komodo_cex_market_data/src/models/_models_index.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Common test constants
class TestConstants {
  TestConstants._();

  // Common coin IDs
  static const String bitcoinCoinId = 'btc-bitcoin';
  static const String ethereumCoinId = 'eth-ethereum';
  static const String inactiveCoinId = 'inactive-coin';
  static const String testCoinId = 'test-coin';

  // Common symbols
  static const String bitcoinSymbol = 'BTC';
  static const String ethereumSymbol = 'ETH';
  static const String inactiveSymbol = 'INACTIVE';
  static const String testSymbol = 'TEST';

  // Common names
  static const String bitcoinName = 'Bitcoin';
  static const String ethereumName = 'Ethereum';
  static const String inactiveName = 'Inactive Coin';
  static const String testName = 'Test Coin';

  // Common prices
  static const double bitcoinPrice = 50000.0;
  static const double ethereumPrice = 3000.0;
  static const double altcoinPrice = 1.50;

  // Common volumes
  static const double highVolume = 1000000.0;
  static const double mediumVolume = 500000.0;
  static const double lowVolume = 100000.0;

  // Common market caps
  static const double bitcoinMarketCap = 900000000000.0;
  static const double ethereumMarketCap = 350000000000.0;
  static const double smallMarketCap = 20000000.0;

  // Common percentage changes
  static const double positiveChange = 2.5;
  static const double negativeChange = -1.2;
  static const double highPositiveChange = 15.8;
  static const double highNegativeChange = -8.4;

  // Common supply values
  static const int bitcoinCirculatingSupply = 19000000;
  static const int bitcoinTotalSupply = 21000000;
  static const int bitcoinMaxSupply = 21000000;
  static const int ethereumCirculatingSupply = 120000000;

  // Common timestamps (as ISO strings for easy parsing)
  static const String currentTimestamp = '2024-01-01T12:00:00Z';
  static const String pastTimestamp = '2024-01-01T00:00:00Z';
  static const String futureTimestamp = '2024-01-02T00:00:00Z';

  // Common API URLs
  static const String baseUrl = 'api.coinpaprika.com';
  static const String apiVersion = '/v1';

  // Common intervals
  static const String interval1d = '1d';
  static const String interval1h = '1h';
  static const String interval24h = '24h';
  static const String interval5m = '5m';
  static const String interval15m = '15m';
  static const String interval30m = '30m';

  // Date formatting
  static const String dateFormat = '2024-01-01';
  static const String dateFormatWithSingleDigits = '2024-03-05';

  // Common quote currencies (as strings for API responses)
  static const String usdQuote = 'USD';
  static const String eurQuote = 'EUR';
  static const String gbpQuote = 'GBP';
  static const String btcQuote = 'BTC';
  static const String ethQuote = 'ETH';

  // Common supported currencies list
  static const List<QuoteCurrency> defaultSupportedCurrencies = [
    FiatCurrency.usd,
    FiatCurrency.eur,
    FiatCurrency.gbp,
    FiatCurrency.jpy,
    Cryptocurrency.btc,
    Cryptocurrency.eth,
  ];

  // Extended supported currencies list (42 currencies as mentioned in provider test)
  static const List<QuoteCurrency> extendedSupportedCurrencies = [
    // Fiat currencies
    FiatCurrency.usd,
    FiatCurrency.eur,
    FiatCurrency.gbp,
    FiatCurrency.jpy,
    FiatCurrency.cad,
    FiatCurrency.aud,
    FiatCurrency.chf,
    FiatCurrency.cny,
    FiatCurrency.sek,
    FiatCurrency.nok,
    FiatCurrency.mxn,
    FiatCurrency.sgd,
    FiatCurrency.hkd,
    FiatCurrency.inr,
    FiatCurrency.krw,
    FiatCurrency.rub,
    FiatCurrency.brl,
    FiatCurrency.zar,
    FiatCurrency.tryLira,
    FiatCurrency.nzd,
    FiatCurrency.pln,
    FiatCurrency.dkk,
    FiatCurrency.twd,
    FiatCurrency.thb,
    FiatCurrency.huf,
    FiatCurrency.czk,
    FiatCurrency.ils,
    FiatCurrency.clp,
    FiatCurrency.php,
    FiatCurrency.aed,
    FiatCurrency.cop,
    FiatCurrency.sar,
    FiatCurrency.myr,
    FiatCurrency.uah,
    FiatCurrency.lkr,
    FiatCurrency.mmk,
    FiatCurrency.idr,
    FiatCurrency.vnd,
    FiatCurrency.bdt,
    FiatCurrency.uah,
    // Cryptocurrencies
    Cryptocurrency.btc,
    Cryptocurrency.eth,
  ];
}

/// Predefined test data for common scenarios
class TestData {
  TestData._();

  /// Standard Bitcoin coin data
  static const CoinPaprikaCoin bitcoinCoin = CoinPaprikaCoin(
    id: TestConstants.bitcoinCoinId,
    name: TestConstants.bitcoinName,
    symbol: TestConstants.bitcoinSymbol,
    rank: 1,
    isNew: false,
    isActive: true,
    type: 'coin',
  );

  /// Standard Ethereum coin data
  static const CoinPaprikaCoin ethereumCoin = CoinPaprikaCoin(
    id: TestConstants.ethereumCoinId,
    name: TestConstants.ethereumName,
    symbol: TestConstants.ethereumSymbol,
    rank: 2,
    isNew: false,
    isActive: true,
    type: 'coin',
  );

  /// Inactive coin data for testing filtering
  static const CoinPaprikaCoin inactiveCoin = CoinPaprikaCoin(
    id: TestConstants.inactiveCoinId,
    name: TestConstants.inactiveName,
    symbol: TestConstants.inactiveSymbol,
    rank: 999,
    isNew: false,
    isActive: false,
    type: 'coin',
  );

  /// Standard active coins list (excluding inactive coins)
  static const List<CoinPaprikaCoin> activeCoins = [
    bitcoinCoin,
    ethereumCoin,
  ];

  /// Full coins list including inactive coins
  static const List<CoinPaprikaCoin> allCoins = [
    bitcoinCoin,
    ethereumCoin,
    inactiveCoin,
  ];

  /// Standard AssetId for Bitcoin with coinPaprikaId
  static final AssetId bitcoinAsset = AssetId(
    id: TestConstants.bitcoinSymbol,
    name: TestConstants.bitcoinName,
    symbol: AssetSymbol(
      assetConfigId: TestConstants.bitcoinSymbol,
      coinPaprikaId: TestConstants.bitcoinCoinId,
    ),
    chainId: AssetChainId(chainId: 0),
    derivationPath: null,
    subClass: CoinSubClass.utxo,
  );

  /// Standard AssetId for Ethereum with coinPaprikaId
  static final AssetId ethereumAsset = AssetId(
    id: TestConstants.ethereumSymbol,
    name: TestConstants.ethereumName,
    symbol: AssetSymbol(
      assetConfigId: TestConstants.ethereumSymbol,
      coinPaprikaId: TestConstants.ethereumCoinId,
    ),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.erc20,
  );

  /// AssetId without coinPaprikaId for testing unsupported assets
  static final AssetId unsupportedAsset = AssetId(
    id: TestConstants.bitcoinSymbol,
    name: TestConstants.bitcoinName,
    symbol: AssetSymbol(
      assetConfigId: TestConstants.bitcoinSymbol,
      // No coinPaprikaId
    ),
    chainId: AssetChainId(chainId: 0),
    derivationPath: null,
    subClass: CoinSubClass.utxo,
  );

  /// Common test dates
  static final DateTime testDate = DateTime.parse(TestConstants.currentTimestamp);
  static final DateTime pastDate = DateTime.parse(TestConstants.pastTimestamp);
  static final DateTime futureDate = DateTime.parse(TestConstants.futureTimestamp);

  /// UTC test dates
  static final DateTime testDateUtc = DateTime.parse(TestConstants.currentTimestamp).toUtc();
  static final DateTime pastDateUtc = DateTime.parse(TestConstants.pastTimestamp).toUtc();

  /// Common Decimal values
  static final Decimal bitcoinPriceDecimal = Decimal.fromInt(TestConstants.bitcoinPrice.toInt());
  static final Decimal ethereumPriceDecimal = Decimal.fromInt(TestConstants.ethereumPrice.toInt());
  static final Decimal altcoinPriceDecimal = Decimal.parse(TestConstants.altcoinPrice.toString());

  /// Common volume Decimal values
  static final Decimal highVolumeDecimal = Decimal.fromInt(TestConstants.highVolume.toInt());
  static final Decimal mediumVolumeDecimal = Decimal.fromInt(TestConstants.mediumVolume.toInt());

  /// Common market cap Decimal values
  static final Decimal bitcoinMarketCapDecimal = Decimal.fromInt(TestConstants.bitcoinMarketCap.toInt());
  static final Decimal ethereumMarketCapDecimal = Decimal.fromInt(TestConstants.ethereumMarketCap.toInt());

  /// Standard percentage change Decimal values
  static final Decimal positiveChangeDecimal = Decimal.parse(TestConstants.positiveChange.toString());
  static final Decimal negativeChangeDecimal = Decimal.parse(TestConstants.negativeChange.toString());
}
