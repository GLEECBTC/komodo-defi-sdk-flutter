// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coinpaprika_market.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CoinPaprikaMarket _$CoinPaprikaMarketFromJson(Map<String, dynamic> json) =>
    _CoinPaprikaMarket(
      exchangeId: json['exchange_id'] as String,
      exchangeName: json['exchange_name'] as String,
      pair: json['pair'] as String,
      baseCurrencyId: json['base_currency_id'] as String,
      baseCurrencyName: json['base_currency_name'] as String,
      quoteCurrencyId: json['quote_currency_id'] as String,
      quoteCurrencyName: json['quote_currency_name'] as String,
      marketUrl: json['market_url'] as String?,
      category: json['category'] as String,
      feeType: json['fee_type'] as String,
      outlier: json['outlier'] as bool,
      adjustedVolume24hShare: (json['adjusted_volume_24h_share'] as num)
          .toDouble(),
      quotes: (json['quotes'] as Map<String, dynamic>).map(
        (k, e) =>
            MapEntry(k, CoinPaprikaQuote.fromJson(e as Map<String, dynamic>)),
      ),
      lastUpdated: json['last_updated'] as String,
    );

Map<String, dynamic> _$CoinPaprikaMarketToJson(_CoinPaprikaMarket instance) =>
    <String, dynamic>{
      'exchange_id': instance.exchangeId,
      'exchange_name': instance.exchangeName,
      'pair': instance.pair,
      'base_currency_id': instance.baseCurrencyId,
      'base_currency_name': instance.baseCurrencyName,
      'quote_currency_id': instance.quoteCurrencyId,
      'quote_currency_name': instance.quoteCurrencyName,
      'market_url': instance.marketUrl,
      'category': instance.category,
      'fee_type': instance.feeType,
      'outlier': instance.outlier,
      'adjusted_volume_24h_share': instance.adjustedVolume24hShare,
      'quotes': instance.quotes,
      'last_updated': instance.lastUpdated,
    };

_CoinPaprikaQuote _$CoinPaprikaQuoteFromJson(Map<String, dynamic> json) =>
    _CoinPaprikaQuote(
      price: const NonNullableDecimalConverter().fromJson(json['price']),
      volume24h: const NonNullableDecimalConverter().fromJson(
        json['volume_24h'],
      ),
    );

Map<String, dynamic> _$CoinPaprikaQuoteToJson(
  _CoinPaprikaQuote instance,
) => <String, dynamic>{
  'price': const NonNullableDecimalConverter().toJson(instance.price),
  'volume_24h': const NonNullableDecimalConverter().toJson(instance.volume24h),
};
