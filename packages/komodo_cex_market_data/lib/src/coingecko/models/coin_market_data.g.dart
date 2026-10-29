// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coin_market_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CoinMarketData _$CoinMarketDataFromJson(Map<String, dynamic> json) =>
    _CoinMarketData(
      id: json['id'] as String?,
      symbol: json['symbol'] as String?,
      name: json['name'] as String?,
      image: json['image'] as String?,
      currentPrice: const DecimalConverter().fromJson(json['current_price']),
      marketCap: const DecimalConverter().fromJson(json['market_cap']),
      marketCapRank: const DecimalConverter().fromJson(json['market_cap_rank']),
      fullyDilutedValuation: const DecimalConverter().fromJson(
        json['fully_diluted_valuation'],
      ),
      totalVolume: const DecimalConverter().fromJson(json['total_volume']),
      high24h: const DecimalConverter().fromJson(json['high_24h']),
      low24h: const DecimalConverter().fromJson(json['low_24h']),
      priceChange24h: const DecimalConverter().fromJson(
        json['price_change_24h'],
      ),
      priceChangePercentage24h: const DecimalConverter().fromJson(
        json['price_change_percentage_24h'],
      ),
      marketCapChange24h: const DecimalConverter().fromJson(
        json['market_cap_change_24h'],
      ),
      marketCapChangePercentage24h: const DecimalConverter().fromJson(
        json['market_cap_change_percentage_24h'],
      ),
      circulatingSupply: const DecimalConverter().fromJson(
        json['circulating_supply'],
      ),
      totalSupply: const DecimalConverter().fromJson(json['total_supply']),
      maxSupply: const DecimalConverter().fromJson(json['max_supply']),
      ath: const DecimalConverter().fromJson(json['ath']),
      athChangePercentage: const DecimalConverter().fromJson(
        json['ath_change_percentage'],
      ),
      athDate: json['ath_date'] == null
          ? null
          : DateTime.parse(json['ath_date'] as String),
      atl: const DecimalConverter().fromJson(json['atl']),
      atlChangePercentage: const DecimalConverter().fromJson(
        json['atl_change_percentage'],
      ),
      atlDate: json['atl_date'] == null
          ? null
          : DateTime.parse(json['atl_date'] as String),
      roi: json['roi'],
      lastUpdated: json['last_updated'] == null
          ? null
          : DateTime.parse(json['last_updated'] as String),
    );

Map<String, dynamic> _$CoinMarketDataToJson(
  _CoinMarketData instance,
) => <String, dynamic>{
  'id': instance.id,
  'symbol': instance.symbol,
  'name': instance.name,
  'image': instance.image,
  'current_price': const DecimalConverter().toJson(instance.currentPrice),
  'market_cap': const DecimalConverter().toJson(instance.marketCap),
  'market_cap_rank': const DecimalConverter().toJson(instance.marketCapRank),
  'fully_diluted_valuation': const DecimalConverter().toJson(
    instance.fullyDilutedValuation,
  ),
  'total_volume': const DecimalConverter().toJson(instance.totalVolume),
  'high_24h': const DecimalConverter().toJson(instance.high24h),
  'low_24h': const DecimalConverter().toJson(instance.low24h),
  'price_change_24h': const DecimalConverter().toJson(instance.priceChange24h),
  'price_change_percentage_24h': const DecimalConverter().toJson(
    instance.priceChangePercentage24h,
  ),
  'market_cap_change_24h': const DecimalConverter().toJson(
    instance.marketCapChange24h,
  ),
  'market_cap_change_percentage_24h': const DecimalConverter().toJson(
    instance.marketCapChangePercentage24h,
  ),
  'circulating_supply': const DecimalConverter().toJson(
    instance.circulatingSupply,
  ),
  'total_supply': const DecimalConverter().toJson(instance.totalSupply),
  'max_supply': const DecimalConverter().toJson(instance.maxSupply),
  'ath': const DecimalConverter().toJson(instance.ath),
  'ath_change_percentage': const DecimalConverter().toJson(
    instance.athChangePercentage,
  ),
  'ath_date': instance.athDate?.toIso8601String(),
  'atl': const DecimalConverter().toJson(instance.atl),
  'atl_change_percentage': const DecimalConverter().toJson(
    instance.atlChangePercentage,
  ),
  'atl_date': instance.atlDate?.toIso8601String(),
  'roi': instance.roi,
  'last_updated': instance.lastUpdated?.toIso8601String(),
};
