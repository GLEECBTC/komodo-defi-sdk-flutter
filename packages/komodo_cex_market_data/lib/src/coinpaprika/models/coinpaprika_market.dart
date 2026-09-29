import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:komodo_cex_market_data/src/models/json_converters.dart';

part 'coinpaprika_market.freezed.dart';
part 'coinpaprika_market.g.dart';

/// Represents market data for a coin from CoinPaprika's markets endpoint.
@freezed
abstract class CoinPaprikaMarket with _$CoinPaprikaMarket {
  /// Creates a CoinPaprika market instance.
  // FieldRename.snake would read `adjusted_volume24h_share`, but CoinPaprika
  // sends `adjusted_volume_24h_share`, so that key is set explicitly.
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory CoinPaprikaMarket({
    /// Exchange identifier (e.g., "binance")
    required String exchangeId,

    /// Exchange display name (e.g., "Binance")
    required String exchangeName,

    /// Trading pair (e.g., "BTC/USDT")
    required String pair,

    /// Base currency identifier (e.g., "btc-bitcoin")
    required String baseCurrencyId,

    /// Base currency name (e.g., "Bitcoin")
    required String baseCurrencyName,

    /// Quote currency identifier (e.g., "usdt-tether")
    required String quoteCurrencyId,

    /// Quote currency name (e.g., "Tether")
    required String quoteCurrencyName,

    /// Direct URL to the market on the exchange
    String? marketUrl,

    /// Market category (e.g., "Spot")
    required String category,

    /// Fee type (e.g., "Percentage")
    required String feeType,

    /// Whether this market is considered an outlier
    required bool outlier,

    /// Adjusted 24h volume share percentage
    @JsonKey(name: 'adjusted_volume_24h_share')
    required double adjustedVolume24hShare,

    /// Quote data for different currencies
    required Map<String, CoinPaprikaQuote> quotes,

    /// Last update timestamp as ISO 8601 string
    required String lastUpdated,
  }) = _CoinPaprikaMarket;

  /// Creates a CoinPaprika market instance from JSON.
  factory CoinPaprikaMarket.fromJson(Map<String, dynamic> json) =>
      _$CoinPaprikaMarketFromJson(json);
}

/// Represents price and volume data for a specific quote currency.
@freezed
abstract class CoinPaprikaQuote with _$CoinPaprikaQuote {
  /// Creates a CoinPaprika quote instance.
  const factory CoinPaprikaQuote({
    /// Current price as a [Decimal] for precision
    @NonNullableDecimalConverter() required Decimal price,

    /// 24-hour trading volume as a [Decimal]
    @JsonKey(name: 'volume_24h')
    @NonNullableDecimalConverter()
    required Decimal volume24h,
  }) = _CoinPaprikaQuote;

  /// Creates a CoinPaprika quote instance from JSON.
  factory CoinPaprikaQuote.fromJson(Map<String, dynamic> json) =>
      _$CoinPaprikaQuoteFromJson(json);
}

/// Extension providing convenient accessors for CoinPaprika market data.
extension CoinPaprikaMarketGetters on CoinPaprikaMarket {
  /// Gets the last updated time as a [DateTime].
  DateTime get lastUpdatedDateTime => DateTime.parse(lastUpdated);

  /// Gets a quote for a specific currency key.
  CoinPaprikaQuote? getQuoteFor(String currencyKey) {
    return quotes[currencyKey.toUpperCase()];
  }
}
