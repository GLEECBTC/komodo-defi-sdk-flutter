// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coin_market_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CoinMarketData {

 String? get id; String? get symbol; String? get name; String? get image;@DecimalConverter() Decimal? get currentPrice;@DecimalConverter() Decimal? get marketCap;@DecimalConverter() Decimal? get marketCapRank;@DecimalConverter() Decimal? get fullyDilutedValuation;@DecimalConverter() Decimal? get totalVolume;@JsonKey(name: 'high_24h')@DecimalConverter() Decimal? get high24h;@JsonKey(name: 'low_24h')@DecimalConverter() Decimal? get low24h;@JsonKey(name: 'price_change_24h')@DecimalConverter() Decimal? get priceChange24h;@JsonKey(name: 'price_change_percentage_24h')@DecimalConverter() Decimal? get priceChangePercentage24h;@JsonKey(name: 'market_cap_change_24h')@DecimalConverter() Decimal? get marketCapChange24h;@JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter() Decimal? get marketCapChangePercentage24h;@DecimalConverter() Decimal? get circulatingSupply;@DecimalConverter() Decimal? get totalSupply;@DecimalConverter() Decimal? get maxSupply;@DecimalConverter() Decimal? get ath;@DecimalConverter() Decimal? get athChangePercentage; DateTime? get athDate;@DecimalConverter() Decimal? get atl;@DecimalConverter() Decimal? get atlChangePercentage; DateTime? get atlDate; dynamic get roi; DateTime? get lastUpdated;
/// Create a copy of CoinMarketData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoinMarketDataCopyWith<CoinMarketData> get copyWith => _$CoinMarketDataCopyWithImpl<CoinMarketData>(this as CoinMarketData, _$identity);

  /// Serializes this CoinMarketData to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoinMarketData&&(identical(other.id, id) || other.id == id)&&(identical(other.symbol, symbol) || other.symbol == symbol)&&(identical(other.name, name) || other.name == name)&&(identical(other.image, image) || other.image == image)&&(identical(other.currentPrice, currentPrice) || other.currentPrice == currentPrice)&&(identical(other.marketCap, marketCap) || other.marketCap == marketCap)&&(identical(other.marketCapRank, marketCapRank) || other.marketCapRank == marketCapRank)&&(identical(other.fullyDilutedValuation, fullyDilutedValuation) || other.fullyDilutedValuation == fullyDilutedValuation)&&(identical(other.totalVolume, totalVolume) || other.totalVolume == totalVolume)&&(identical(other.high24h, high24h) || other.high24h == high24h)&&(identical(other.low24h, low24h) || other.low24h == low24h)&&(identical(other.priceChange24h, priceChange24h) || other.priceChange24h == priceChange24h)&&(identical(other.priceChangePercentage24h, priceChangePercentage24h) || other.priceChangePercentage24h == priceChangePercentage24h)&&(identical(other.marketCapChange24h, marketCapChange24h) || other.marketCapChange24h == marketCapChange24h)&&(identical(other.marketCapChangePercentage24h, marketCapChangePercentage24h) || other.marketCapChangePercentage24h == marketCapChangePercentage24h)&&(identical(other.circulatingSupply, circulatingSupply) || other.circulatingSupply == circulatingSupply)&&(identical(other.totalSupply, totalSupply) || other.totalSupply == totalSupply)&&(identical(other.maxSupply, maxSupply) || other.maxSupply == maxSupply)&&(identical(other.ath, ath) || other.ath == ath)&&(identical(other.athChangePercentage, athChangePercentage) || other.athChangePercentage == athChangePercentage)&&(identical(other.athDate, athDate) || other.athDate == athDate)&&(identical(other.atl, atl) || other.atl == atl)&&(identical(other.atlChangePercentage, atlChangePercentage) || other.atlChangePercentage == atlChangePercentage)&&(identical(other.atlDate, atlDate) || other.atlDate == atlDate)&&const DeepCollectionEquality().equals(other.roi, roi)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,symbol,name,image,currentPrice,marketCap,marketCapRank,fullyDilutedValuation,totalVolume,high24h,low24h,priceChange24h,priceChangePercentage24h,marketCapChange24h,marketCapChangePercentage24h,circulatingSupply,totalSupply,maxSupply,ath,athChangePercentage,athDate,atl,atlChangePercentage,atlDate,const DeepCollectionEquality().hash(roi),lastUpdated]);

@override
String toString() {
  return 'CoinMarketData(id: $id, symbol: $symbol, name: $name, image: $image, currentPrice: $currentPrice, marketCap: $marketCap, marketCapRank: $marketCapRank, fullyDilutedValuation: $fullyDilutedValuation, totalVolume: $totalVolume, high24h: $high24h, low24h: $low24h, priceChange24h: $priceChange24h, priceChangePercentage24h: $priceChangePercentage24h, marketCapChange24h: $marketCapChange24h, marketCapChangePercentage24h: $marketCapChangePercentage24h, circulatingSupply: $circulatingSupply, totalSupply: $totalSupply, maxSupply: $maxSupply, ath: $ath, athChangePercentage: $athChangePercentage, athDate: $athDate, atl: $atl, atlChangePercentage: $atlChangePercentage, atlDate: $atlDate, roi: $roi, lastUpdated: $lastUpdated)';
}


}

/// @nodoc
abstract mixin class $CoinMarketDataCopyWith<$Res>  {
  factory $CoinMarketDataCopyWith(CoinMarketData value, $Res Function(CoinMarketData) _then) = _$CoinMarketDataCopyWithImpl;
@useResult
$Res call({
 String? id, String? symbol, String? name, String? image,@DecimalConverter() Decimal? currentPrice,@DecimalConverter() Decimal? marketCap,@DecimalConverter() Decimal? marketCapRank,@DecimalConverter() Decimal? fullyDilutedValuation,@DecimalConverter() Decimal? totalVolume,@JsonKey(name: 'high_24h')@DecimalConverter() Decimal? high24h,@JsonKey(name: 'low_24h')@DecimalConverter() Decimal? low24h,@JsonKey(name: 'price_change_24h')@DecimalConverter() Decimal? priceChange24h,@JsonKey(name: 'price_change_percentage_24h')@DecimalConverter() Decimal? priceChangePercentage24h,@JsonKey(name: 'market_cap_change_24h')@DecimalConverter() Decimal? marketCapChange24h,@JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter() Decimal? marketCapChangePercentage24h,@DecimalConverter() Decimal? circulatingSupply,@DecimalConverter() Decimal? totalSupply,@DecimalConverter() Decimal? maxSupply,@DecimalConverter() Decimal? ath,@DecimalConverter() Decimal? athChangePercentage, DateTime? athDate,@DecimalConverter() Decimal? atl,@DecimalConverter() Decimal? atlChangePercentage, DateTime? atlDate, dynamic roi, DateTime? lastUpdated
});




}
/// @nodoc
class _$CoinMarketDataCopyWithImpl<$Res>
    implements $CoinMarketDataCopyWith<$Res> {
  _$CoinMarketDataCopyWithImpl(this._self, this._then);

  final CoinMarketData _self;
  final $Res Function(CoinMarketData) _then;

/// Create a copy of CoinMarketData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? symbol = freezed,Object? name = freezed,Object? image = freezed,Object? currentPrice = freezed,Object? marketCap = freezed,Object? marketCapRank = freezed,Object? fullyDilutedValuation = freezed,Object? totalVolume = freezed,Object? high24h = freezed,Object? low24h = freezed,Object? priceChange24h = freezed,Object? priceChangePercentage24h = freezed,Object? marketCapChange24h = freezed,Object? marketCapChangePercentage24h = freezed,Object? circulatingSupply = freezed,Object? totalSupply = freezed,Object? maxSupply = freezed,Object? ath = freezed,Object? athChangePercentage = freezed,Object? athDate = freezed,Object? atl = freezed,Object? atlChangePercentage = freezed,Object? atlDate = freezed,Object? roi = freezed,Object? lastUpdated = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,symbol: freezed == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,image: freezed == image ? _self.image : image // ignore: cast_nullable_to_non_nullable
as String?,currentPrice: freezed == currentPrice ? _self.currentPrice : currentPrice // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCap: freezed == marketCap ? _self.marketCap : marketCap // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCapRank: freezed == marketCapRank ? _self.marketCapRank : marketCapRank // ignore: cast_nullable_to_non_nullable
as Decimal?,fullyDilutedValuation: freezed == fullyDilutedValuation ? _self.fullyDilutedValuation : fullyDilutedValuation // ignore: cast_nullable_to_non_nullable
as Decimal?,totalVolume: freezed == totalVolume ? _self.totalVolume : totalVolume // ignore: cast_nullable_to_non_nullable
as Decimal?,high24h: freezed == high24h ? _self.high24h : high24h // ignore: cast_nullable_to_non_nullable
as Decimal?,low24h: freezed == low24h ? _self.low24h : low24h // ignore: cast_nullable_to_non_nullable
as Decimal?,priceChange24h: freezed == priceChange24h ? _self.priceChange24h : priceChange24h // ignore: cast_nullable_to_non_nullable
as Decimal?,priceChangePercentage24h: freezed == priceChangePercentage24h ? _self.priceChangePercentage24h : priceChangePercentage24h // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCapChange24h: freezed == marketCapChange24h ? _self.marketCapChange24h : marketCapChange24h // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCapChangePercentage24h: freezed == marketCapChangePercentage24h ? _self.marketCapChangePercentage24h : marketCapChangePercentage24h // ignore: cast_nullable_to_non_nullable
as Decimal?,circulatingSupply: freezed == circulatingSupply ? _self.circulatingSupply : circulatingSupply // ignore: cast_nullable_to_non_nullable
as Decimal?,totalSupply: freezed == totalSupply ? _self.totalSupply : totalSupply // ignore: cast_nullable_to_non_nullable
as Decimal?,maxSupply: freezed == maxSupply ? _self.maxSupply : maxSupply // ignore: cast_nullable_to_non_nullable
as Decimal?,ath: freezed == ath ? _self.ath : ath // ignore: cast_nullable_to_non_nullable
as Decimal?,athChangePercentage: freezed == athChangePercentage ? _self.athChangePercentage : athChangePercentage // ignore: cast_nullable_to_non_nullable
as Decimal?,athDate: freezed == athDate ? _self.athDate : athDate // ignore: cast_nullable_to_non_nullable
as DateTime?,atl: freezed == atl ? _self.atl : atl // ignore: cast_nullable_to_non_nullable
as Decimal?,atlChangePercentage: freezed == atlChangePercentage ? _self.atlChangePercentage : atlChangePercentage // ignore: cast_nullable_to_non_nullable
as Decimal?,atlDate: freezed == atlDate ? _self.atlDate : atlDate // ignore: cast_nullable_to_non_nullable
as DateTime?,roi: freezed == roi ? _self.roi : roi // ignore: cast_nullable_to_non_nullable
as dynamic,lastUpdated: freezed == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [CoinMarketData].
extension CoinMarketDataPatterns on CoinMarketData {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CoinMarketData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CoinMarketData() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CoinMarketData value)  $default,){
final _that = this;
switch (_that) {
case _CoinMarketData():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CoinMarketData value)?  $default,){
final _that = this;
switch (_that) {
case _CoinMarketData() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? id,  String? symbol,  String? name,  String? image, @DecimalConverter()  Decimal? currentPrice, @DecimalConverter()  Decimal? marketCap, @DecimalConverter()  Decimal? marketCapRank, @DecimalConverter()  Decimal? fullyDilutedValuation, @DecimalConverter()  Decimal? totalVolume, @JsonKey(name: 'high_24h')@DecimalConverter()  Decimal? high24h, @JsonKey(name: 'low_24h')@DecimalConverter()  Decimal? low24h, @JsonKey(name: 'price_change_24h')@DecimalConverter()  Decimal? priceChange24h, @JsonKey(name: 'price_change_percentage_24h')@DecimalConverter()  Decimal? priceChangePercentage24h, @JsonKey(name: 'market_cap_change_24h')@DecimalConverter()  Decimal? marketCapChange24h, @JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter()  Decimal? marketCapChangePercentage24h, @DecimalConverter()  Decimal? circulatingSupply, @DecimalConverter()  Decimal? totalSupply, @DecimalConverter()  Decimal? maxSupply, @DecimalConverter()  Decimal? ath, @DecimalConverter()  Decimal? athChangePercentage,  DateTime? athDate, @DecimalConverter()  Decimal? atl, @DecimalConverter()  Decimal? atlChangePercentage,  DateTime? atlDate,  dynamic roi,  DateTime? lastUpdated)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CoinMarketData() when $default != null:
return $default(_that.id,_that.symbol,_that.name,_that.image,_that.currentPrice,_that.marketCap,_that.marketCapRank,_that.fullyDilutedValuation,_that.totalVolume,_that.high24h,_that.low24h,_that.priceChange24h,_that.priceChangePercentage24h,_that.marketCapChange24h,_that.marketCapChangePercentage24h,_that.circulatingSupply,_that.totalSupply,_that.maxSupply,_that.ath,_that.athChangePercentage,_that.athDate,_that.atl,_that.atlChangePercentage,_that.atlDate,_that.roi,_that.lastUpdated);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? id,  String? symbol,  String? name,  String? image, @DecimalConverter()  Decimal? currentPrice, @DecimalConverter()  Decimal? marketCap, @DecimalConverter()  Decimal? marketCapRank, @DecimalConverter()  Decimal? fullyDilutedValuation, @DecimalConverter()  Decimal? totalVolume, @JsonKey(name: 'high_24h')@DecimalConverter()  Decimal? high24h, @JsonKey(name: 'low_24h')@DecimalConverter()  Decimal? low24h, @JsonKey(name: 'price_change_24h')@DecimalConverter()  Decimal? priceChange24h, @JsonKey(name: 'price_change_percentage_24h')@DecimalConverter()  Decimal? priceChangePercentage24h, @JsonKey(name: 'market_cap_change_24h')@DecimalConverter()  Decimal? marketCapChange24h, @JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter()  Decimal? marketCapChangePercentage24h, @DecimalConverter()  Decimal? circulatingSupply, @DecimalConverter()  Decimal? totalSupply, @DecimalConverter()  Decimal? maxSupply, @DecimalConverter()  Decimal? ath, @DecimalConverter()  Decimal? athChangePercentage,  DateTime? athDate, @DecimalConverter()  Decimal? atl, @DecimalConverter()  Decimal? atlChangePercentage,  DateTime? atlDate,  dynamic roi,  DateTime? lastUpdated)  $default,) {final _that = this;
switch (_that) {
case _CoinMarketData():
return $default(_that.id,_that.symbol,_that.name,_that.image,_that.currentPrice,_that.marketCap,_that.marketCapRank,_that.fullyDilutedValuation,_that.totalVolume,_that.high24h,_that.low24h,_that.priceChange24h,_that.priceChangePercentage24h,_that.marketCapChange24h,_that.marketCapChangePercentage24h,_that.circulatingSupply,_that.totalSupply,_that.maxSupply,_that.ath,_that.athChangePercentage,_that.athDate,_that.atl,_that.atlChangePercentage,_that.atlDate,_that.roi,_that.lastUpdated);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? id,  String? symbol,  String? name,  String? image, @DecimalConverter()  Decimal? currentPrice, @DecimalConverter()  Decimal? marketCap, @DecimalConverter()  Decimal? marketCapRank, @DecimalConverter()  Decimal? fullyDilutedValuation, @DecimalConverter()  Decimal? totalVolume, @JsonKey(name: 'high_24h')@DecimalConverter()  Decimal? high24h, @JsonKey(name: 'low_24h')@DecimalConverter()  Decimal? low24h, @JsonKey(name: 'price_change_24h')@DecimalConverter()  Decimal? priceChange24h, @JsonKey(name: 'price_change_percentage_24h')@DecimalConverter()  Decimal? priceChangePercentage24h, @JsonKey(name: 'market_cap_change_24h')@DecimalConverter()  Decimal? marketCapChange24h, @JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter()  Decimal? marketCapChangePercentage24h, @DecimalConverter()  Decimal? circulatingSupply, @DecimalConverter()  Decimal? totalSupply, @DecimalConverter()  Decimal? maxSupply, @DecimalConverter()  Decimal? ath, @DecimalConverter()  Decimal? athChangePercentage,  DateTime? athDate, @DecimalConverter()  Decimal? atl, @DecimalConverter()  Decimal? atlChangePercentage,  DateTime? atlDate,  dynamic roi,  DateTime? lastUpdated)?  $default,) {final _that = this;
switch (_that) {
case _CoinMarketData() when $default != null:
return $default(_that.id,_that.symbol,_that.name,_that.image,_that.currentPrice,_that.marketCap,_that.marketCapRank,_that.fullyDilutedValuation,_that.totalVolume,_that.high24h,_that.low24h,_that.priceChange24h,_that.priceChangePercentage24h,_that.marketCapChange24h,_that.marketCapChangePercentage24h,_that.circulatingSupply,_that.totalSupply,_that.maxSupply,_that.ath,_that.athChangePercentage,_that.athDate,_that.atl,_that.atlChangePercentage,_that.atlDate,_that.roi,_that.lastUpdated);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _CoinMarketData implements CoinMarketData {
  const _CoinMarketData({this.id, this.symbol, this.name, this.image, @DecimalConverter() this.currentPrice, @DecimalConverter() this.marketCap, @DecimalConverter() this.marketCapRank, @DecimalConverter() this.fullyDilutedValuation, @DecimalConverter() this.totalVolume, @JsonKey(name: 'high_24h')@DecimalConverter() this.high24h, @JsonKey(name: 'low_24h')@DecimalConverter() this.low24h, @JsonKey(name: 'price_change_24h')@DecimalConverter() this.priceChange24h, @JsonKey(name: 'price_change_percentage_24h')@DecimalConverter() this.priceChangePercentage24h, @JsonKey(name: 'market_cap_change_24h')@DecimalConverter() this.marketCapChange24h, @JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter() this.marketCapChangePercentage24h, @DecimalConverter() this.circulatingSupply, @DecimalConverter() this.totalSupply, @DecimalConverter() this.maxSupply, @DecimalConverter() this.ath, @DecimalConverter() this.athChangePercentage, this.athDate, @DecimalConverter() this.atl, @DecimalConverter() this.atlChangePercentage, this.atlDate, this.roi, this.lastUpdated});
  factory _CoinMarketData.fromJson(Map<String, dynamic> json) => _$CoinMarketDataFromJson(json);

@override final  String? id;
@override final  String? symbol;
@override final  String? name;
@override final  String? image;
@override@DecimalConverter() final  Decimal? currentPrice;
@override@DecimalConverter() final  Decimal? marketCap;
@override@DecimalConverter() final  Decimal? marketCapRank;
@override@DecimalConverter() final  Decimal? fullyDilutedValuation;
@override@DecimalConverter() final  Decimal? totalVolume;
@override@JsonKey(name: 'high_24h')@DecimalConverter() final  Decimal? high24h;
@override@JsonKey(name: 'low_24h')@DecimalConverter() final  Decimal? low24h;
@override@JsonKey(name: 'price_change_24h')@DecimalConverter() final  Decimal? priceChange24h;
@override@JsonKey(name: 'price_change_percentage_24h')@DecimalConverter() final  Decimal? priceChangePercentage24h;
@override@JsonKey(name: 'market_cap_change_24h')@DecimalConverter() final  Decimal? marketCapChange24h;
@override@JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter() final  Decimal? marketCapChangePercentage24h;
@override@DecimalConverter() final  Decimal? circulatingSupply;
@override@DecimalConverter() final  Decimal? totalSupply;
@override@DecimalConverter() final  Decimal? maxSupply;
@override@DecimalConverter() final  Decimal? ath;
@override@DecimalConverter() final  Decimal? athChangePercentage;
@override final  DateTime? athDate;
@override@DecimalConverter() final  Decimal? atl;
@override@DecimalConverter() final  Decimal? atlChangePercentage;
@override final  DateTime? atlDate;
@override final  dynamic roi;
@override final  DateTime? lastUpdated;

/// Create a copy of CoinMarketData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CoinMarketDataCopyWith<_CoinMarketData> get copyWith => __$CoinMarketDataCopyWithImpl<_CoinMarketData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CoinMarketDataToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CoinMarketData&&(identical(other.id, id) || other.id == id)&&(identical(other.symbol, symbol) || other.symbol == symbol)&&(identical(other.name, name) || other.name == name)&&(identical(other.image, image) || other.image == image)&&(identical(other.currentPrice, currentPrice) || other.currentPrice == currentPrice)&&(identical(other.marketCap, marketCap) || other.marketCap == marketCap)&&(identical(other.marketCapRank, marketCapRank) || other.marketCapRank == marketCapRank)&&(identical(other.fullyDilutedValuation, fullyDilutedValuation) || other.fullyDilutedValuation == fullyDilutedValuation)&&(identical(other.totalVolume, totalVolume) || other.totalVolume == totalVolume)&&(identical(other.high24h, high24h) || other.high24h == high24h)&&(identical(other.low24h, low24h) || other.low24h == low24h)&&(identical(other.priceChange24h, priceChange24h) || other.priceChange24h == priceChange24h)&&(identical(other.priceChangePercentage24h, priceChangePercentage24h) || other.priceChangePercentage24h == priceChangePercentage24h)&&(identical(other.marketCapChange24h, marketCapChange24h) || other.marketCapChange24h == marketCapChange24h)&&(identical(other.marketCapChangePercentage24h, marketCapChangePercentage24h) || other.marketCapChangePercentage24h == marketCapChangePercentage24h)&&(identical(other.circulatingSupply, circulatingSupply) || other.circulatingSupply == circulatingSupply)&&(identical(other.totalSupply, totalSupply) || other.totalSupply == totalSupply)&&(identical(other.maxSupply, maxSupply) || other.maxSupply == maxSupply)&&(identical(other.ath, ath) || other.ath == ath)&&(identical(other.athChangePercentage, athChangePercentage) || other.athChangePercentage == athChangePercentage)&&(identical(other.athDate, athDate) || other.athDate == athDate)&&(identical(other.atl, atl) || other.atl == atl)&&(identical(other.atlChangePercentage, atlChangePercentage) || other.atlChangePercentage == atlChangePercentage)&&(identical(other.atlDate, atlDate) || other.atlDate == atlDate)&&const DeepCollectionEquality().equals(other.roi, roi)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,symbol,name,image,currentPrice,marketCap,marketCapRank,fullyDilutedValuation,totalVolume,high24h,low24h,priceChange24h,priceChangePercentage24h,marketCapChange24h,marketCapChangePercentage24h,circulatingSupply,totalSupply,maxSupply,ath,athChangePercentage,athDate,atl,atlChangePercentage,atlDate,const DeepCollectionEquality().hash(roi),lastUpdated]);

@override
String toString() {
  return 'CoinMarketData(id: $id, symbol: $symbol, name: $name, image: $image, currentPrice: $currentPrice, marketCap: $marketCap, marketCapRank: $marketCapRank, fullyDilutedValuation: $fullyDilutedValuation, totalVolume: $totalVolume, high24h: $high24h, low24h: $low24h, priceChange24h: $priceChange24h, priceChangePercentage24h: $priceChangePercentage24h, marketCapChange24h: $marketCapChange24h, marketCapChangePercentage24h: $marketCapChangePercentage24h, circulatingSupply: $circulatingSupply, totalSupply: $totalSupply, maxSupply: $maxSupply, ath: $ath, athChangePercentage: $athChangePercentage, athDate: $athDate, atl: $atl, atlChangePercentage: $atlChangePercentage, atlDate: $atlDate, roi: $roi, lastUpdated: $lastUpdated)';
}


}

/// @nodoc
abstract mixin class _$CoinMarketDataCopyWith<$Res> implements $CoinMarketDataCopyWith<$Res> {
  factory _$CoinMarketDataCopyWith(_CoinMarketData value, $Res Function(_CoinMarketData) _then) = __$CoinMarketDataCopyWithImpl;
@override @useResult
$Res call({
 String? id, String? symbol, String? name, String? image,@DecimalConverter() Decimal? currentPrice,@DecimalConverter() Decimal? marketCap,@DecimalConverter() Decimal? marketCapRank,@DecimalConverter() Decimal? fullyDilutedValuation,@DecimalConverter() Decimal? totalVolume,@JsonKey(name: 'high_24h')@DecimalConverter() Decimal? high24h,@JsonKey(name: 'low_24h')@DecimalConverter() Decimal? low24h,@JsonKey(name: 'price_change_24h')@DecimalConverter() Decimal? priceChange24h,@JsonKey(name: 'price_change_percentage_24h')@DecimalConverter() Decimal? priceChangePercentage24h,@JsonKey(name: 'market_cap_change_24h')@DecimalConverter() Decimal? marketCapChange24h,@JsonKey(name: 'market_cap_change_percentage_24h')@DecimalConverter() Decimal? marketCapChangePercentage24h,@DecimalConverter() Decimal? circulatingSupply,@DecimalConverter() Decimal? totalSupply,@DecimalConverter() Decimal? maxSupply,@DecimalConverter() Decimal? ath,@DecimalConverter() Decimal? athChangePercentage, DateTime? athDate,@DecimalConverter() Decimal? atl,@DecimalConverter() Decimal? atlChangePercentage, DateTime? atlDate, dynamic roi, DateTime? lastUpdated
});




}
/// @nodoc
class __$CoinMarketDataCopyWithImpl<$Res>
    implements _$CoinMarketDataCopyWith<$Res> {
  __$CoinMarketDataCopyWithImpl(this._self, this._then);

  final _CoinMarketData _self;
  final $Res Function(_CoinMarketData) _then;

/// Create a copy of CoinMarketData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? symbol = freezed,Object? name = freezed,Object? image = freezed,Object? currentPrice = freezed,Object? marketCap = freezed,Object? marketCapRank = freezed,Object? fullyDilutedValuation = freezed,Object? totalVolume = freezed,Object? high24h = freezed,Object? low24h = freezed,Object? priceChange24h = freezed,Object? priceChangePercentage24h = freezed,Object? marketCapChange24h = freezed,Object? marketCapChangePercentage24h = freezed,Object? circulatingSupply = freezed,Object? totalSupply = freezed,Object? maxSupply = freezed,Object? ath = freezed,Object? athChangePercentage = freezed,Object? athDate = freezed,Object? atl = freezed,Object? atlChangePercentage = freezed,Object? atlDate = freezed,Object? roi = freezed,Object? lastUpdated = freezed,}) {
  return _then(_CoinMarketData(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,symbol: freezed == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,image: freezed == image ? _self.image : image // ignore: cast_nullable_to_non_nullable
as String?,currentPrice: freezed == currentPrice ? _self.currentPrice : currentPrice // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCap: freezed == marketCap ? _self.marketCap : marketCap // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCapRank: freezed == marketCapRank ? _self.marketCapRank : marketCapRank // ignore: cast_nullable_to_non_nullable
as Decimal?,fullyDilutedValuation: freezed == fullyDilutedValuation ? _self.fullyDilutedValuation : fullyDilutedValuation // ignore: cast_nullable_to_non_nullable
as Decimal?,totalVolume: freezed == totalVolume ? _self.totalVolume : totalVolume // ignore: cast_nullable_to_non_nullable
as Decimal?,high24h: freezed == high24h ? _self.high24h : high24h // ignore: cast_nullable_to_non_nullable
as Decimal?,low24h: freezed == low24h ? _self.low24h : low24h // ignore: cast_nullable_to_non_nullable
as Decimal?,priceChange24h: freezed == priceChange24h ? _self.priceChange24h : priceChange24h // ignore: cast_nullable_to_non_nullable
as Decimal?,priceChangePercentage24h: freezed == priceChangePercentage24h ? _self.priceChangePercentage24h : priceChangePercentage24h // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCapChange24h: freezed == marketCapChange24h ? _self.marketCapChange24h : marketCapChange24h // ignore: cast_nullable_to_non_nullable
as Decimal?,marketCapChangePercentage24h: freezed == marketCapChangePercentage24h ? _self.marketCapChangePercentage24h : marketCapChangePercentage24h // ignore: cast_nullable_to_non_nullable
as Decimal?,circulatingSupply: freezed == circulatingSupply ? _self.circulatingSupply : circulatingSupply // ignore: cast_nullable_to_non_nullable
as Decimal?,totalSupply: freezed == totalSupply ? _self.totalSupply : totalSupply // ignore: cast_nullable_to_non_nullable
as Decimal?,maxSupply: freezed == maxSupply ? _self.maxSupply : maxSupply // ignore: cast_nullable_to_non_nullable
as Decimal?,ath: freezed == ath ? _self.ath : ath // ignore: cast_nullable_to_non_nullable
as Decimal?,athChangePercentage: freezed == athChangePercentage ? _self.athChangePercentage : athChangePercentage // ignore: cast_nullable_to_non_nullable
as Decimal?,athDate: freezed == athDate ? _self.athDate : athDate // ignore: cast_nullable_to_non_nullable
as DateTime?,atl: freezed == atl ? _self.atl : atl // ignore: cast_nullable_to_non_nullable
as Decimal?,atlChangePercentage: freezed == atlChangePercentage ? _self.atlChangePercentage : atlChangePercentage // ignore: cast_nullable_to_non_nullable
as Decimal?,atlDate: freezed == atlDate ? _self.atlDate : atlDate // ignore: cast_nullable_to_non_nullable
as DateTime?,roi: freezed == roi ? _self.roi : roi // ignore: cast_nullable_to_non_nullable
as dynamic,lastUpdated: freezed == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
