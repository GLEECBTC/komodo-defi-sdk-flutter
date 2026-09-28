// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coinpaprika_ticker_quote.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CoinPaprikaTickerQuote {

/// Current price in the quote currency
 double get price;/// 24-hour trading volume
@JsonKey(name: 'volume_24h') double get volume24h;/// 24-hour volume change percentage
@JsonKey(name: 'volume_24h_change_24h') double get volume24hChange24h;/// Market capitalization
 double get marketCap;/// 24-hour market cap change percentage
@JsonKey(name: 'market_cap_change_24h') double get marketCapChange24h;/// Price change percentage in the last 15 minutes
@JsonKey(name: 'percent_change_15m') double get percentChange15m;/// Price change percentage in the last 30 minutes
@JsonKey(name: 'percent_change_30m') double get percentChange30m;/// Price change percentage in the last 1 hour
@JsonKey(name: 'percent_change_1h') double get percentChange1h;/// Price change percentage in the last 6 hours
@JsonKey(name: 'percent_change_6h') double get percentChange6h;/// Price change percentage in the last 12 hours
@JsonKey(name: 'percent_change_12h') double get percentChange12h;/// Price change percentage in the last 24 hours
@JsonKey(name: 'percent_change_24h') double get percentChange24h;/// Price change percentage in the last 7 days
@JsonKey(name: 'percent_change_7d') double get percentChange7d;/// Price change percentage in the last 30 days
@JsonKey(name: 'percent_change_30d') double get percentChange30d;/// Price change percentage in the last 1 year
@JsonKey(name: 'percent_change_1y') double get percentChange1y;/// All-time high price (nullable)
 double? get athPrice;/// Date of all-time high (nullable)
 DateTime? get athDate;/// Percentage from all-time high price (nullable)
 double? get percentFromPriceAth;
/// Create a copy of CoinPaprikaTickerQuote
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoinPaprikaTickerQuoteCopyWith<CoinPaprikaTickerQuote> get copyWith => _$CoinPaprikaTickerQuoteCopyWithImpl<CoinPaprikaTickerQuote>(this as CoinPaprikaTickerQuote, _$identity);

  /// Serializes this CoinPaprikaTickerQuote to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoinPaprikaTickerQuote&&(identical(other.price, price) || other.price == price)&&(identical(other.volume24h, volume24h) || other.volume24h == volume24h)&&(identical(other.volume24hChange24h, volume24hChange24h) || other.volume24hChange24h == volume24hChange24h)&&(identical(other.marketCap, marketCap) || other.marketCap == marketCap)&&(identical(other.marketCapChange24h, marketCapChange24h) || other.marketCapChange24h == marketCapChange24h)&&(identical(other.percentChange15m, percentChange15m) || other.percentChange15m == percentChange15m)&&(identical(other.percentChange30m, percentChange30m) || other.percentChange30m == percentChange30m)&&(identical(other.percentChange1h, percentChange1h) || other.percentChange1h == percentChange1h)&&(identical(other.percentChange6h, percentChange6h) || other.percentChange6h == percentChange6h)&&(identical(other.percentChange12h, percentChange12h) || other.percentChange12h == percentChange12h)&&(identical(other.percentChange24h, percentChange24h) || other.percentChange24h == percentChange24h)&&(identical(other.percentChange7d, percentChange7d) || other.percentChange7d == percentChange7d)&&(identical(other.percentChange30d, percentChange30d) || other.percentChange30d == percentChange30d)&&(identical(other.percentChange1y, percentChange1y) || other.percentChange1y == percentChange1y)&&(identical(other.athPrice, athPrice) || other.athPrice == athPrice)&&(identical(other.athDate, athDate) || other.athDate == athDate)&&(identical(other.percentFromPriceAth, percentFromPriceAth) || other.percentFromPriceAth == percentFromPriceAth));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,price,volume24h,volume24hChange24h,marketCap,marketCapChange24h,percentChange15m,percentChange30m,percentChange1h,percentChange6h,percentChange12h,percentChange24h,percentChange7d,percentChange30d,percentChange1y,athPrice,athDate,percentFromPriceAth);

@override
String toString() {
  return 'CoinPaprikaTickerQuote(price: $price, volume24h: $volume24h, volume24hChange24h: $volume24hChange24h, marketCap: $marketCap, marketCapChange24h: $marketCapChange24h, percentChange15m: $percentChange15m, percentChange30m: $percentChange30m, percentChange1h: $percentChange1h, percentChange6h: $percentChange6h, percentChange12h: $percentChange12h, percentChange24h: $percentChange24h, percentChange7d: $percentChange7d, percentChange30d: $percentChange30d, percentChange1y: $percentChange1y, athPrice: $athPrice, athDate: $athDate, percentFromPriceAth: $percentFromPriceAth)';
}


}

/// @nodoc
abstract mixin class $CoinPaprikaTickerQuoteCopyWith<$Res>  {
  factory $CoinPaprikaTickerQuoteCopyWith(CoinPaprikaTickerQuote value, $Res Function(CoinPaprikaTickerQuote) _then) = _$CoinPaprikaTickerQuoteCopyWithImpl;
@useResult
$Res call({
 double price,@JsonKey(name: 'volume_24h') double volume24h,@JsonKey(name: 'volume_24h_change_24h') double volume24hChange24h, double marketCap,@JsonKey(name: 'market_cap_change_24h') double marketCapChange24h,@JsonKey(name: 'percent_change_15m') double percentChange15m,@JsonKey(name: 'percent_change_30m') double percentChange30m,@JsonKey(name: 'percent_change_1h') double percentChange1h,@JsonKey(name: 'percent_change_6h') double percentChange6h,@JsonKey(name: 'percent_change_12h') double percentChange12h,@JsonKey(name: 'percent_change_24h') double percentChange24h,@JsonKey(name: 'percent_change_7d') double percentChange7d,@JsonKey(name: 'percent_change_30d') double percentChange30d,@JsonKey(name: 'percent_change_1y') double percentChange1y, double? athPrice, DateTime? athDate, double? percentFromPriceAth
});




}
/// @nodoc
class _$CoinPaprikaTickerQuoteCopyWithImpl<$Res>
    implements $CoinPaprikaTickerQuoteCopyWith<$Res> {
  _$CoinPaprikaTickerQuoteCopyWithImpl(this._self, this._then);

  final CoinPaprikaTickerQuote _self;
  final $Res Function(CoinPaprikaTickerQuote) _then;

/// Create a copy of CoinPaprikaTickerQuote
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? price = null,Object? volume24h = null,Object? volume24hChange24h = null,Object? marketCap = null,Object? marketCapChange24h = null,Object? percentChange15m = null,Object? percentChange30m = null,Object? percentChange1h = null,Object? percentChange6h = null,Object? percentChange12h = null,Object? percentChange24h = null,Object? percentChange7d = null,Object? percentChange30d = null,Object? percentChange1y = null,Object? athPrice = freezed,Object? athDate = freezed,Object? percentFromPriceAth = freezed,}) {
  return _then(_self.copyWith(
price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,volume24h: null == volume24h ? _self.volume24h : volume24h // ignore: cast_nullable_to_non_nullable
as double,volume24hChange24h: null == volume24hChange24h ? _self.volume24hChange24h : volume24hChange24h // ignore: cast_nullable_to_non_nullable
as double,marketCap: null == marketCap ? _self.marketCap : marketCap // ignore: cast_nullable_to_non_nullable
as double,marketCapChange24h: null == marketCapChange24h ? _self.marketCapChange24h : marketCapChange24h // ignore: cast_nullable_to_non_nullable
as double,percentChange15m: null == percentChange15m ? _self.percentChange15m : percentChange15m // ignore: cast_nullable_to_non_nullable
as double,percentChange30m: null == percentChange30m ? _self.percentChange30m : percentChange30m // ignore: cast_nullable_to_non_nullable
as double,percentChange1h: null == percentChange1h ? _self.percentChange1h : percentChange1h // ignore: cast_nullable_to_non_nullable
as double,percentChange6h: null == percentChange6h ? _self.percentChange6h : percentChange6h // ignore: cast_nullable_to_non_nullable
as double,percentChange12h: null == percentChange12h ? _self.percentChange12h : percentChange12h // ignore: cast_nullable_to_non_nullable
as double,percentChange24h: null == percentChange24h ? _self.percentChange24h : percentChange24h // ignore: cast_nullable_to_non_nullable
as double,percentChange7d: null == percentChange7d ? _self.percentChange7d : percentChange7d // ignore: cast_nullable_to_non_nullable
as double,percentChange30d: null == percentChange30d ? _self.percentChange30d : percentChange30d // ignore: cast_nullable_to_non_nullable
as double,percentChange1y: null == percentChange1y ? _self.percentChange1y : percentChange1y // ignore: cast_nullable_to_non_nullable
as double,athPrice: freezed == athPrice ? _self.athPrice : athPrice // ignore: cast_nullable_to_non_nullable
as double?,athDate: freezed == athDate ? _self.athDate : athDate // ignore: cast_nullable_to_non_nullable
as DateTime?,percentFromPriceAth: freezed == percentFromPriceAth ? _self.percentFromPriceAth : percentFromPriceAth // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [CoinPaprikaTickerQuote].
extension CoinPaprikaTickerQuotePatterns on CoinPaprikaTickerQuote {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CoinPaprikaTickerQuote value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CoinPaprikaTickerQuote() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CoinPaprikaTickerQuote value)  $default,){
final _that = this;
switch (_that) {
case _CoinPaprikaTickerQuote():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CoinPaprikaTickerQuote value)?  $default,){
final _that = this;
switch (_that) {
case _CoinPaprikaTickerQuote() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double price, @JsonKey(name: 'volume_24h')  double volume24h, @JsonKey(name: 'volume_24h_change_24h')  double volume24hChange24h,  double marketCap, @JsonKey(name: 'market_cap_change_24h')  double marketCapChange24h, @JsonKey(name: 'percent_change_15m')  double percentChange15m, @JsonKey(name: 'percent_change_30m')  double percentChange30m, @JsonKey(name: 'percent_change_1h')  double percentChange1h, @JsonKey(name: 'percent_change_6h')  double percentChange6h, @JsonKey(name: 'percent_change_12h')  double percentChange12h, @JsonKey(name: 'percent_change_24h')  double percentChange24h, @JsonKey(name: 'percent_change_7d')  double percentChange7d, @JsonKey(name: 'percent_change_30d')  double percentChange30d, @JsonKey(name: 'percent_change_1y')  double percentChange1y,  double? athPrice,  DateTime? athDate,  double? percentFromPriceAth)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CoinPaprikaTickerQuote() when $default != null:
return $default(_that.price,_that.volume24h,_that.volume24hChange24h,_that.marketCap,_that.marketCapChange24h,_that.percentChange15m,_that.percentChange30m,_that.percentChange1h,_that.percentChange6h,_that.percentChange12h,_that.percentChange24h,_that.percentChange7d,_that.percentChange30d,_that.percentChange1y,_that.athPrice,_that.athDate,_that.percentFromPriceAth);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double price, @JsonKey(name: 'volume_24h')  double volume24h, @JsonKey(name: 'volume_24h_change_24h')  double volume24hChange24h,  double marketCap, @JsonKey(name: 'market_cap_change_24h')  double marketCapChange24h, @JsonKey(name: 'percent_change_15m')  double percentChange15m, @JsonKey(name: 'percent_change_30m')  double percentChange30m, @JsonKey(name: 'percent_change_1h')  double percentChange1h, @JsonKey(name: 'percent_change_6h')  double percentChange6h, @JsonKey(name: 'percent_change_12h')  double percentChange12h, @JsonKey(name: 'percent_change_24h')  double percentChange24h, @JsonKey(name: 'percent_change_7d')  double percentChange7d, @JsonKey(name: 'percent_change_30d')  double percentChange30d, @JsonKey(name: 'percent_change_1y')  double percentChange1y,  double? athPrice,  DateTime? athDate,  double? percentFromPriceAth)  $default,) {final _that = this;
switch (_that) {
case _CoinPaprikaTickerQuote():
return $default(_that.price,_that.volume24h,_that.volume24hChange24h,_that.marketCap,_that.marketCapChange24h,_that.percentChange15m,_that.percentChange30m,_that.percentChange1h,_that.percentChange6h,_that.percentChange12h,_that.percentChange24h,_that.percentChange7d,_that.percentChange30d,_that.percentChange1y,_that.athPrice,_that.athDate,_that.percentFromPriceAth);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double price, @JsonKey(name: 'volume_24h')  double volume24h, @JsonKey(name: 'volume_24h_change_24h')  double volume24hChange24h,  double marketCap, @JsonKey(name: 'market_cap_change_24h')  double marketCapChange24h, @JsonKey(name: 'percent_change_15m')  double percentChange15m, @JsonKey(name: 'percent_change_30m')  double percentChange30m, @JsonKey(name: 'percent_change_1h')  double percentChange1h, @JsonKey(name: 'percent_change_6h')  double percentChange6h, @JsonKey(name: 'percent_change_12h')  double percentChange12h, @JsonKey(name: 'percent_change_24h')  double percentChange24h, @JsonKey(name: 'percent_change_7d')  double percentChange7d, @JsonKey(name: 'percent_change_30d')  double percentChange30d, @JsonKey(name: 'percent_change_1y')  double percentChange1y,  double? athPrice,  DateTime? athDate,  double? percentFromPriceAth)?  $default,) {final _that = this;
switch (_that) {
case _CoinPaprikaTickerQuote() when $default != null:
return $default(_that.price,_that.volume24h,_that.volume24hChange24h,_that.marketCap,_that.marketCapChange24h,_that.percentChange15m,_that.percentChange30m,_that.percentChange1h,_that.percentChange6h,_that.percentChange12h,_that.percentChange24h,_that.percentChange7d,_that.percentChange30d,_that.percentChange1y,_that.athPrice,_that.athDate,_that.percentFromPriceAth);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _CoinPaprikaTickerQuote implements CoinPaprikaTickerQuote {
  const _CoinPaprikaTickerQuote({required this.price, @JsonKey(name: 'volume_24h') this.volume24h = 0.0, @JsonKey(name: 'volume_24h_change_24h') this.volume24hChange24h = 0.0, this.marketCap = 0.0, @JsonKey(name: 'market_cap_change_24h') this.marketCapChange24h = 0.0, @JsonKey(name: 'percent_change_15m') this.percentChange15m = 0.0, @JsonKey(name: 'percent_change_30m') this.percentChange30m = 0.0, @JsonKey(name: 'percent_change_1h') this.percentChange1h = 0.0, @JsonKey(name: 'percent_change_6h') this.percentChange6h = 0.0, @JsonKey(name: 'percent_change_12h') this.percentChange12h = 0.0, @JsonKey(name: 'percent_change_24h') this.percentChange24h = 0.0, @JsonKey(name: 'percent_change_7d') this.percentChange7d = 0.0, @JsonKey(name: 'percent_change_30d') this.percentChange30d = 0.0, @JsonKey(name: 'percent_change_1y') this.percentChange1y = 0.0, this.athPrice, this.athDate, this.percentFromPriceAth});
  factory _CoinPaprikaTickerQuote.fromJson(Map<String, dynamic> json) => _$CoinPaprikaTickerQuoteFromJson(json);

/// Current price in the quote currency
@override final  double price;
/// 24-hour trading volume
@override@JsonKey(name: 'volume_24h') final  double volume24h;
/// 24-hour volume change percentage
@override@JsonKey(name: 'volume_24h_change_24h') final  double volume24hChange24h;
/// Market capitalization
@override@JsonKey() final  double marketCap;
/// 24-hour market cap change percentage
@override@JsonKey(name: 'market_cap_change_24h') final  double marketCapChange24h;
/// Price change percentage in the last 15 minutes
@override@JsonKey(name: 'percent_change_15m') final  double percentChange15m;
/// Price change percentage in the last 30 minutes
@override@JsonKey(name: 'percent_change_30m') final  double percentChange30m;
/// Price change percentage in the last 1 hour
@override@JsonKey(name: 'percent_change_1h') final  double percentChange1h;
/// Price change percentage in the last 6 hours
@override@JsonKey(name: 'percent_change_6h') final  double percentChange6h;
/// Price change percentage in the last 12 hours
@override@JsonKey(name: 'percent_change_12h') final  double percentChange12h;
/// Price change percentage in the last 24 hours
@override@JsonKey(name: 'percent_change_24h') final  double percentChange24h;
/// Price change percentage in the last 7 days
@override@JsonKey(name: 'percent_change_7d') final  double percentChange7d;
/// Price change percentage in the last 30 days
@override@JsonKey(name: 'percent_change_30d') final  double percentChange30d;
/// Price change percentage in the last 1 year
@override@JsonKey(name: 'percent_change_1y') final  double percentChange1y;
/// All-time high price (nullable)
@override final  double? athPrice;
/// Date of all-time high (nullable)
@override final  DateTime? athDate;
/// Percentage from all-time high price (nullable)
@override final  double? percentFromPriceAth;

/// Create a copy of CoinPaprikaTickerQuote
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CoinPaprikaTickerQuoteCopyWith<_CoinPaprikaTickerQuote> get copyWith => __$CoinPaprikaTickerQuoteCopyWithImpl<_CoinPaprikaTickerQuote>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CoinPaprikaTickerQuoteToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CoinPaprikaTickerQuote&&(identical(other.price, price) || other.price == price)&&(identical(other.volume24h, volume24h) || other.volume24h == volume24h)&&(identical(other.volume24hChange24h, volume24hChange24h) || other.volume24hChange24h == volume24hChange24h)&&(identical(other.marketCap, marketCap) || other.marketCap == marketCap)&&(identical(other.marketCapChange24h, marketCapChange24h) || other.marketCapChange24h == marketCapChange24h)&&(identical(other.percentChange15m, percentChange15m) || other.percentChange15m == percentChange15m)&&(identical(other.percentChange30m, percentChange30m) || other.percentChange30m == percentChange30m)&&(identical(other.percentChange1h, percentChange1h) || other.percentChange1h == percentChange1h)&&(identical(other.percentChange6h, percentChange6h) || other.percentChange6h == percentChange6h)&&(identical(other.percentChange12h, percentChange12h) || other.percentChange12h == percentChange12h)&&(identical(other.percentChange24h, percentChange24h) || other.percentChange24h == percentChange24h)&&(identical(other.percentChange7d, percentChange7d) || other.percentChange7d == percentChange7d)&&(identical(other.percentChange30d, percentChange30d) || other.percentChange30d == percentChange30d)&&(identical(other.percentChange1y, percentChange1y) || other.percentChange1y == percentChange1y)&&(identical(other.athPrice, athPrice) || other.athPrice == athPrice)&&(identical(other.athDate, athDate) || other.athDate == athDate)&&(identical(other.percentFromPriceAth, percentFromPriceAth) || other.percentFromPriceAth == percentFromPriceAth));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,price,volume24h,volume24hChange24h,marketCap,marketCapChange24h,percentChange15m,percentChange30m,percentChange1h,percentChange6h,percentChange12h,percentChange24h,percentChange7d,percentChange30d,percentChange1y,athPrice,athDate,percentFromPriceAth);

@override
String toString() {
  return 'CoinPaprikaTickerQuote(price: $price, volume24h: $volume24h, volume24hChange24h: $volume24hChange24h, marketCap: $marketCap, marketCapChange24h: $marketCapChange24h, percentChange15m: $percentChange15m, percentChange30m: $percentChange30m, percentChange1h: $percentChange1h, percentChange6h: $percentChange6h, percentChange12h: $percentChange12h, percentChange24h: $percentChange24h, percentChange7d: $percentChange7d, percentChange30d: $percentChange30d, percentChange1y: $percentChange1y, athPrice: $athPrice, athDate: $athDate, percentFromPriceAth: $percentFromPriceAth)';
}


}

/// @nodoc
abstract mixin class _$CoinPaprikaTickerQuoteCopyWith<$Res> implements $CoinPaprikaTickerQuoteCopyWith<$Res> {
  factory _$CoinPaprikaTickerQuoteCopyWith(_CoinPaprikaTickerQuote value, $Res Function(_CoinPaprikaTickerQuote) _then) = __$CoinPaprikaTickerQuoteCopyWithImpl;
@override @useResult
$Res call({
 double price,@JsonKey(name: 'volume_24h') double volume24h,@JsonKey(name: 'volume_24h_change_24h') double volume24hChange24h, double marketCap,@JsonKey(name: 'market_cap_change_24h') double marketCapChange24h,@JsonKey(name: 'percent_change_15m') double percentChange15m,@JsonKey(name: 'percent_change_30m') double percentChange30m,@JsonKey(name: 'percent_change_1h') double percentChange1h,@JsonKey(name: 'percent_change_6h') double percentChange6h,@JsonKey(name: 'percent_change_12h') double percentChange12h,@JsonKey(name: 'percent_change_24h') double percentChange24h,@JsonKey(name: 'percent_change_7d') double percentChange7d,@JsonKey(name: 'percent_change_30d') double percentChange30d,@JsonKey(name: 'percent_change_1y') double percentChange1y, double? athPrice, DateTime? athDate, double? percentFromPriceAth
});




}
/// @nodoc
class __$CoinPaprikaTickerQuoteCopyWithImpl<$Res>
    implements _$CoinPaprikaTickerQuoteCopyWith<$Res> {
  __$CoinPaprikaTickerQuoteCopyWithImpl(this._self, this._then);

  final _CoinPaprikaTickerQuote _self;
  final $Res Function(_CoinPaprikaTickerQuote) _then;

/// Create a copy of CoinPaprikaTickerQuote
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? price = null,Object? volume24h = null,Object? volume24hChange24h = null,Object? marketCap = null,Object? marketCapChange24h = null,Object? percentChange15m = null,Object? percentChange30m = null,Object? percentChange1h = null,Object? percentChange6h = null,Object? percentChange12h = null,Object? percentChange24h = null,Object? percentChange7d = null,Object? percentChange30d = null,Object? percentChange1y = null,Object? athPrice = freezed,Object? athDate = freezed,Object? percentFromPriceAth = freezed,}) {
  return _then(_CoinPaprikaTickerQuote(
price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,volume24h: null == volume24h ? _self.volume24h : volume24h // ignore: cast_nullable_to_non_nullable
as double,volume24hChange24h: null == volume24hChange24h ? _self.volume24hChange24h : volume24hChange24h // ignore: cast_nullable_to_non_nullable
as double,marketCap: null == marketCap ? _self.marketCap : marketCap // ignore: cast_nullable_to_non_nullable
as double,marketCapChange24h: null == marketCapChange24h ? _self.marketCapChange24h : marketCapChange24h // ignore: cast_nullable_to_non_nullable
as double,percentChange15m: null == percentChange15m ? _self.percentChange15m : percentChange15m // ignore: cast_nullable_to_non_nullable
as double,percentChange30m: null == percentChange30m ? _self.percentChange30m : percentChange30m // ignore: cast_nullable_to_non_nullable
as double,percentChange1h: null == percentChange1h ? _self.percentChange1h : percentChange1h // ignore: cast_nullable_to_non_nullable
as double,percentChange6h: null == percentChange6h ? _self.percentChange6h : percentChange6h // ignore: cast_nullable_to_non_nullable
as double,percentChange12h: null == percentChange12h ? _self.percentChange12h : percentChange12h // ignore: cast_nullable_to_non_nullable
as double,percentChange24h: null == percentChange24h ? _self.percentChange24h : percentChange24h // ignore: cast_nullable_to_non_nullable
as double,percentChange7d: null == percentChange7d ? _self.percentChange7d : percentChange7d // ignore: cast_nullable_to_non_nullable
as double,percentChange30d: null == percentChange30d ? _self.percentChange30d : percentChange30d // ignore: cast_nullable_to_non_nullable
as double,percentChange1y: null == percentChange1y ? _self.percentChange1y : percentChange1y // ignore: cast_nullable_to_non_nullable
as double,athPrice: freezed == athPrice ? _self.athPrice : athPrice // ignore: cast_nullable_to_non_nullable
as double?,athDate: freezed == athDate ? _self.athDate : athDate // ignore: cast_nullable_to_non_nullable
as DateTime?,percentFromPriceAth: freezed == percentFromPriceAth ? _self.percentFromPriceAth : percentFromPriceAth // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
