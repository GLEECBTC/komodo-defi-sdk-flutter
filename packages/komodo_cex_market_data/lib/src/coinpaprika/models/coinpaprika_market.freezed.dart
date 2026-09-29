// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coinpaprika_market.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CoinPaprikaMarket {

/// Exchange identifier (e.g., "binance")
 String get exchangeId;/// Exchange display name (e.g., "Binance")
 String get exchangeName;/// Trading pair (e.g., "BTC/USDT")
 String get pair;/// Base currency identifier (e.g., "btc-bitcoin")
 String get baseCurrencyId;/// Base currency name (e.g., "Bitcoin")
 String get baseCurrencyName;/// Quote currency identifier (e.g., "usdt-tether")
 String get quoteCurrencyId;/// Quote currency name (e.g., "Tether")
 String get quoteCurrencyName;/// Direct URL to the market on the exchange
 String? get marketUrl;/// Market category (e.g., "Spot")
 String get category;/// Fee type (e.g., "Percentage")
 String get feeType;/// Whether this market is considered an outlier
 bool get outlier;/// Adjusted 24h volume share percentage
@JsonKey(name: 'adjusted_volume_24h_share') double get adjustedVolume24hShare;/// Quote data for different currencies
 Map<String, CoinPaprikaQuote> get quotes;/// Last update timestamp as ISO 8601 string
 String get lastUpdated;
/// Create a copy of CoinPaprikaMarket
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoinPaprikaMarketCopyWith<CoinPaprikaMarket> get copyWith => _$CoinPaprikaMarketCopyWithImpl<CoinPaprikaMarket>(this as CoinPaprikaMarket, _$identity);

  /// Serializes this CoinPaprikaMarket to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoinPaprikaMarket&&(identical(other.exchangeId, exchangeId) || other.exchangeId == exchangeId)&&(identical(other.exchangeName, exchangeName) || other.exchangeName == exchangeName)&&(identical(other.pair, pair) || other.pair == pair)&&(identical(other.baseCurrencyId, baseCurrencyId) || other.baseCurrencyId == baseCurrencyId)&&(identical(other.baseCurrencyName, baseCurrencyName) || other.baseCurrencyName == baseCurrencyName)&&(identical(other.quoteCurrencyId, quoteCurrencyId) || other.quoteCurrencyId == quoteCurrencyId)&&(identical(other.quoteCurrencyName, quoteCurrencyName) || other.quoteCurrencyName == quoteCurrencyName)&&(identical(other.marketUrl, marketUrl) || other.marketUrl == marketUrl)&&(identical(other.category, category) || other.category == category)&&(identical(other.feeType, feeType) || other.feeType == feeType)&&(identical(other.outlier, outlier) || other.outlier == outlier)&&(identical(other.adjustedVolume24hShare, adjustedVolume24hShare) || other.adjustedVolume24hShare == adjustedVolume24hShare)&&const DeepCollectionEquality().equals(other.quotes, quotes)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,exchangeId,exchangeName,pair,baseCurrencyId,baseCurrencyName,quoteCurrencyId,quoteCurrencyName,marketUrl,category,feeType,outlier,adjustedVolume24hShare,const DeepCollectionEquality().hash(quotes),lastUpdated);

@override
String toString() {
  return 'CoinPaprikaMarket(exchangeId: $exchangeId, exchangeName: $exchangeName, pair: $pair, baseCurrencyId: $baseCurrencyId, baseCurrencyName: $baseCurrencyName, quoteCurrencyId: $quoteCurrencyId, quoteCurrencyName: $quoteCurrencyName, marketUrl: $marketUrl, category: $category, feeType: $feeType, outlier: $outlier, adjustedVolume24hShare: $adjustedVolume24hShare, quotes: $quotes, lastUpdated: $lastUpdated)';
}


}

/// @nodoc
abstract mixin class $CoinPaprikaMarketCopyWith<$Res>  {
  factory $CoinPaprikaMarketCopyWith(CoinPaprikaMarket value, $Res Function(CoinPaprikaMarket) _then) = _$CoinPaprikaMarketCopyWithImpl;
@useResult
$Res call({
 String exchangeId, String exchangeName, String pair, String baseCurrencyId, String baseCurrencyName, String quoteCurrencyId, String quoteCurrencyName, String? marketUrl, String category, String feeType, bool outlier,@JsonKey(name: 'adjusted_volume_24h_share') double adjustedVolume24hShare, Map<String, CoinPaprikaQuote> quotes, String lastUpdated
});




}
/// @nodoc
class _$CoinPaprikaMarketCopyWithImpl<$Res>
    implements $CoinPaprikaMarketCopyWith<$Res> {
  _$CoinPaprikaMarketCopyWithImpl(this._self, this._then);

  final CoinPaprikaMarket _self;
  final $Res Function(CoinPaprikaMarket) _then;

/// Create a copy of CoinPaprikaMarket
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? exchangeId = null,Object? exchangeName = null,Object? pair = null,Object? baseCurrencyId = null,Object? baseCurrencyName = null,Object? quoteCurrencyId = null,Object? quoteCurrencyName = null,Object? marketUrl = freezed,Object? category = null,Object? feeType = null,Object? outlier = null,Object? adjustedVolume24hShare = null,Object? quotes = null,Object? lastUpdated = null,}) {
  return _then(_self.copyWith(
exchangeId: null == exchangeId ? _self.exchangeId : exchangeId // ignore: cast_nullable_to_non_nullable
as String,exchangeName: null == exchangeName ? _self.exchangeName : exchangeName // ignore: cast_nullable_to_non_nullable
as String,pair: null == pair ? _self.pair : pair // ignore: cast_nullable_to_non_nullable
as String,baseCurrencyId: null == baseCurrencyId ? _self.baseCurrencyId : baseCurrencyId // ignore: cast_nullable_to_non_nullable
as String,baseCurrencyName: null == baseCurrencyName ? _self.baseCurrencyName : baseCurrencyName // ignore: cast_nullable_to_non_nullable
as String,quoteCurrencyId: null == quoteCurrencyId ? _self.quoteCurrencyId : quoteCurrencyId // ignore: cast_nullable_to_non_nullable
as String,quoteCurrencyName: null == quoteCurrencyName ? _self.quoteCurrencyName : quoteCurrencyName // ignore: cast_nullable_to_non_nullable
as String,marketUrl: freezed == marketUrl ? _self.marketUrl : marketUrl // ignore: cast_nullable_to_non_nullable
as String?,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,feeType: null == feeType ? _self.feeType : feeType // ignore: cast_nullable_to_non_nullable
as String,outlier: null == outlier ? _self.outlier : outlier // ignore: cast_nullable_to_non_nullable
as bool,adjustedVolume24hShare: null == adjustedVolume24hShare ? _self.adjustedVolume24hShare : adjustedVolume24hShare // ignore: cast_nullable_to_non_nullable
as double,quotes: null == quotes ? _self.quotes : quotes // ignore: cast_nullable_to_non_nullable
as Map<String, CoinPaprikaQuote>,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CoinPaprikaMarket].
extension CoinPaprikaMarketPatterns on CoinPaprikaMarket {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CoinPaprikaMarket value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CoinPaprikaMarket() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CoinPaprikaMarket value)  $default,){
final _that = this;
switch (_that) {
case _CoinPaprikaMarket():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CoinPaprikaMarket value)?  $default,){
final _that = this;
switch (_that) {
case _CoinPaprikaMarket() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String exchangeId,  String exchangeName,  String pair,  String baseCurrencyId,  String baseCurrencyName,  String quoteCurrencyId,  String quoteCurrencyName,  String? marketUrl,  String category,  String feeType,  bool outlier, @JsonKey(name: 'adjusted_volume_24h_share')  double adjustedVolume24hShare,  Map<String, CoinPaprikaQuote> quotes,  String lastUpdated)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CoinPaprikaMarket() when $default != null:
return $default(_that.exchangeId,_that.exchangeName,_that.pair,_that.baseCurrencyId,_that.baseCurrencyName,_that.quoteCurrencyId,_that.quoteCurrencyName,_that.marketUrl,_that.category,_that.feeType,_that.outlier,_that.adjustedVolume24hShare,_that.quotes,_that.lastUpdated);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String exchangeId,  String exchangeName,  String pair,  String baseCurrencyId,  String baseCurrencyName,  String quoteCurrencyId,  String quoteCurrencyName,  String? marketUrl,  String category,  String feeType,  bool outlier, @JsonKey(name: 'adjusted_volume_24h_share')  double adjustedVolume24hShare,  Map<String, CoinPaprikaQuote> quotes,  String lastUpdated)  $default,) {final _that = this;
switch (_that) {
case _CoinPaprikaMarket():
return $default(_that.exchangeId,_that.exchangeName,_that.pair,_that.baseCurrencyId,_that.baseCurrencyName,_that.quoteCurrencyId,_that.quoteCurrencyName,_that.marketUrl,_that.category,_that.feeType,_that.outlier,_that.adjustedVolume24hShare,_that.quotes,_that.lastUpdated);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String exchangeId,  String exchangeName,  String pair,  String baseCurrencyId,  String baseCurrencyName,  String quoteCurrencyId,  String quoteCurrencyName,  String? marketUrl,  String category,  String feeType,  bool outlier, @JsonKey(name: 'adjusted_volume_24h_share')  double adjustedVolume24hShare,  Map<String, CoinPaprikaQuote> quotes,  String lastUpdated)?  $default,) {final _that = this;
switch (_that) {
case _CoinPaprikaMarket() when $default != null:
return $default(_that.exchangeId,_that.exchangeName,_that.pair,_that.baseCurrencyId,_that.baseCurrencyName,_that.quoteCurrencyId,_that.quoteCurrencyName,_that.marketUrl,_that.category,_that.feeType,_that.outlier,_that.adjustedVolume24hShare,_that.quotes,_that.lastUpdated);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _CoinPaprikaMarket implements CoinPaprikaMarket {
  const _CoinPaprikaMarket({required this.exchangeId, required this.exchangeName, required this.pair, required this.baseCurrencyId, required this.baseCurrencyName, required this.quoteCurrencyId, required this.quoteCurrencyName, this.marketUrl, required this.category, required this.feeType, required this.outlier, @JsonKey(name: 'adjusted_volume_24h_share') required this.adjustedVolume24hShare, required final  Map<String, CoinPaprikaQuote> quotes, required this.lastUpdated}): _quotes = quotes;
  factory _CoinPaprikaMarket.fromJson(Map<String, dynamic> json) => _$CoinPaprikaMarketFromJson(json);

/// Exchange identifier (e.g., "binance")
@override final  String exchangeId;
/// Exchange display name (e.g., "Binance")
@override final  String exchangeName;
/// Trading pair (e.g., "BTC/USDT")
@override final  String pair;
/// Base currency identifier (e.g., "btc-bitcoin")
@override final  String baseCurrencyId;
/// Base currency name (e.g., "Bitcoin")
@override final  String baseCurrencyName;
/// Quote currency identifier (e.g., "usdt-tether")
@override final  String quoteCurrencyId;
/// Quote currency name (e.g., "Tether")
@override final  String quoteCurrencyName;
/// Direct URL to the market on the exchange
@override final  String? marketUrl;
/// Market category (e.g., "Spot")
@override final  String category;
/// Fee type (e.g., "Percentage")
@override final  String feeType;
/// Whether this market is considered an outlier
@override final  bool outlier;
/// Adjusted 24h volume share percentage
@override@JsonKey(name: 'adjusted_volume_24h_share') final  double adjustedVolume24hShare;
/// Quote data for different currencies
 final  Map<String, CoinPaprikaQuote> _quotes;
/// Quote data for different currencies
@override Map<String, CoinPaprikaQuote> get quotes {
  if (_quotes is EqualUnmodifiableMapView) return _quotes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_quotes);
}

/// Last update timestamp as ISO 8601 string
@override final  String lastUpdated;

/// Create a copy of CoinPaprikaMarket
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CoinPaprikaMarketCopyWith<_CoinPaprikaMarket> get copyWith => __$CoinPaprikaMarketCopyWithImpl<_CoinPaprikaMarket>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CoinPaprikaMarketToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CoinPaprikaMarket&&(identical(other.exchangeId, exchangeId) || other.exchangeId == exchangeId)&&(identical(other.exchangeName, exchangeName) || other.exchangeName == exchangeName)&&(identical(other.pair, pair) || other.pair == pair)&&(identical(other.baseCurrencyId, baseCurrencyId) || other.baseCurrencyId == baseCurrencyId)&&(identical(other.baseCurrencyName, baseCurrencyName) || other.baseCurrencyName == baseCurrencyName)&&(identical(other.quoteCurrencyId, quoteCurrencyId) || other.quoteCurrencyId == quoteCurrencyId)&&(identical(other.quoteCurrencyName, quoteCurrencyName) || other.quoteCurrencyName == quoteCurrencyName)&&(identical(other.marketUrl, marketUrl) || other.marketUrl == marketUrl)&&(identical(other.category, category) || other.category == category)&&(identical(other.feeType, feeType) || other.feeType == feeType)&&(identical(other.outlier, outlier) || other.outlier == outlier)&&(identical(other.adjustedVolume24hShare, adjustedVolume24hShare) || other.adjustedVolume24hShare == adjustedVolume24hShare)&&const DeepCollectionEquality().equals(other._quotes, _quotes)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,exchangeId,exchangeName,pair,baseCurrencyId,baseCurrencyName,quoteCurrencyId,quoteCurrencyName,marketUrl,category,feeType,outlier,adjustedVolume24hShare,const DeepCollectionEquality().hash(_quotes),lastUpdated);

@override
String toString() {
  return 'CoinPaprikaMarket(exchangeId: $exchangeId, exchangeName: $exchangeName, pair: $pair, baseCurrencyId: $baseCurrencyId, baseCurrencyName: $baseCurrencyName, quoteCurrencyId: $quoteCurrencyId, quoteCurrencyName: $quoteCurrencyName, marketUrl: $marketUrl, category: $category, feeType: $feeType, outlier: $outlier, adjustedVolume24hShare: $adjustedVolume24hShare, quotes: $quotes, lastUpdated: $lastUpdated)';
}


}

/// @nodoc
abstract mixin class _$CoinPaprikaMarketCopyWith<$Res> implements $CoinPaprikaMarketCopyWith<$Res> {
  factory _$CoinPaprikaMarketCopyWith(_CoinPaprikaMarket value, $Res Function(_CoinPaprikaMarket) _then) = __$CoinPaprikaMarketCopyWithImpl;
@override @useResult
$Res call({
 String exchangeId, String exchangeName, String pair, String baseCurrencyId, String baseCurrencyName, String quoteCurrencyId, String quoteCurrencyName, String? marketUrl, String category, String feeType, bool outlier,@JsonKey(name: 'adjusted_volume_24h_share') double adjustedVolume24hShare, Map<String, CoinPaprikaQuote> quotes, String lastUpdated
});




}
/// @nodoc
class __$CoinPaprikaMarketCopyWithImpl<$Res>
    implements _$CoinPaprikaMarketCopyWith<$Res> {
  __$CoinPaprikaMarketCopyWithImpl(this._self, this._then);

  final _CoinPaprikaMarket _self;
  final $Res Function(_CoinPaprikaMarket) _then;

/// Create a copy of CoinPaprikaMarket
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? exchangeId = null,Object? exchangeName = null,Object? pair = null,Object? baseCurrencyId = null,Object? baseCurrencyName = null,Object? quoteCurrencyId = null,Object? quoteCurrencyName = null,Object? marketUrl = freezed,Object? category = null,Object? feeType = null,Object? outlier = null,Object? adjustedVolume24hShare = null,Object? quotes = null,Object? lastUpdated = null,}) {
  return _then(_CoinPaprikaMarket(
exchangeId: null == exchangeId ? _self.exchangeId : exchangeId // ignore: cast_nullable_to_non_nullable
as String,exchangeName: null == exchangeName ? _self.exchangeName : exchangeName // ignore: cast_nullable_to_non_nullable
as String,pair: null == pair ? _self.pair : pair // ignore: cast_nullable_to_non_nullable
as String,baseCurrencyId: null == baseCurrencyId ? _self.baseCurrencyId : baseCurrencyId // ignore: cast_nullable_to_non_nullable
as String,baseCurrencyName: null == baseCurrencyName ? _self.baseCurrencyName : baseCurrencyName // ignore: cast_nullable_to_non_nullable
as String,quoteCurrencyId: null == quoteCurrencyId ? _self.quoteCurrencyId : quoteCurrencyId // ignore: cast_nullable_to_non_nullable
as String,quoteCurrencyName: null == quoteCurrencyName ? _self.quoteCurrencyName : quoteCurrencyName // ignore: cast_nullable_to_non_nullable
as String,marketUrl: freezed == marketUrl ? _self.marketUrl : marketUrl // ignore: cast_nullable_to_non_nullable
as String?,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,feeType: null == feeType ? _self.feeType : feeType // ignore: cast_nullable_to_non_nullable
as String,outlier: null == outlier ? _self.outlier : outlier // ignore: cast_nullable_to_non_nullable
as bool,adjustedVolume24hShare: null == adjustedVolume24hShare ? _self.adjustedVolume24hShare : adjustedVolume24hShare // ignore: cast_nullable_to_non_nullable
as double,quotes: null == quotes ? _self._quotes : quotes // ignore: cast_nullable_to_non_nullable
as Map<String, CoinPaprikaQuote>,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$CoinPaprikaQuote {

/// Current price as a [Decimal] for precision
@NonNullableDecimalConverter() Decimal get price;/// 24-hour trading volume as a [Decimal]
@JsonKey(name: 'volume_24h')@NonNullableDecimalConverter() Decimal get volume24h;
/// Create a copy of CoinPaprikaQuote
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoinPaprikaQuoteCopyWith<CoinPaprikaQuote> get copyWith => _$CoinPaprikaQuoteCopyWithImpl<CoinPaprikaQuote>(this as CoinPaprikaQuote, _$identity);

  /// Serializes this CoinPaprikaQuote to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoinPaprikaQuote&&(identical(other.price, price) || other.price == price)&&(identical(other.volume24h, volume24h) || other.volume24h == volume24h));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,price,volume24h);

@override
String toString() {
  return 'CoinPaprikaQuote(price: $price, volume24h: $volume24h)';
}


}

/// @nodoc
abstract mixin class $CoinPaprikaQuoteCopyWith<$Res>  {
  factory $CoinPaprikaQuoteCopyWith(CoinPaprikaQuote value, $Res Function(CoinPaprikaQuote) _then) = _$CoinPaprikaQuoteCopyWithImpl;
@useResult
$Res call({
@NonNullableDecimalConverter() Decimal price,@JsonKey(name: 'volume_24h')@NonNullableDecimalConverter() Decimal volume24h
});




}
/// @nodoc
class _$CoinPaprikaQuoteCopyWithImpl<$Res>
    implements $CoinPaprikaQuoteCopyWith<$Res> {
  _$CoinPaprikaQuoteCopyWithImpl(this._self, this._then);

  final CoinPaprikaQuote _self;
  final $Res Function(CoinPaprikaQuote) _then;

/// Create a copy of CoinPaprikaQuote
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? price = null,Object? volume24h = null,}) {
  return _then(_self.copyWith(
price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as Decimal,volume24h: null == volume24h ? _self.volume24h : volume24h // ignore: cast_nullable_to_non_nullable
as Decimal,
  ));
}

}


/// Adds pattern-matching-related methods to [CoinPaprikaQuote].
extension CoinPaprikaQuotePatterns on CoinPaprikaQuote {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CoinPaprikaQuote value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CoinPaprikaQuote() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CoinPaprikaQuote value)  $default,){
final _that = this;
switch (_that) {
case _CoinPaprikaQuote():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CoinPaprikaQuote value)?  $default,){
final _that = this;
switch (_that) {
case _CoinPaprikaQuote() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@NonNullableDecimalConverter()  Decimal price, @JsonKey(name: 'volume_24h')@NonNullableDecimalConverter()  Decimal volume24h)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CoinPaprikaQuote() when $default != null:
return $default(_that.price,_that.volume24h);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@NonNullableDecimalConverter()  Decimal price, @JsonKey(name: 'volume_24h')@NonNullableDecimalConverter()  Decimal volume24h)  $default,) {final _that = this;
switch (_that) {
case _CoinPaprikaQuote():
return $default(_that.price,_that.volume24h);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@NonNullableDecimalConverter()  Decimal price, @JsonKey(name: 'volume_24h')@NonNullableDecimalConverter()  Decimal volume24h)?  $default,) {final _that = this;
switch (_that) {
case _CoinPaprikaQuote() when $default != null:
return $default(_that.price,_that.volume24h);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CoinPaprikaQuote implements CoinPaprikaQuote {
  const _CoinPaprikaQuote({@NonNullableDecimalConverter() required this.price, @JsonKey(name: 'volume_24h')@NonNullableDecimalConverter() required this.volume24h});
  factory _CoinPaprikaQuote.fromJson(Map<String, dynamic> json) => _$CoinPaprikaQuoteFromJson(json);

/// Current price as a [Decimal] for precision
@override@NonNullableDecimalConverter() final  Decimal price;
/// 24-hour trading volume as a [Decimal]
@override@JsonKey(name: 'volume_24h')@NonNullableDecimalConverter() final  Decimal volume24h;

/// Create a copy of CoinPaprikaQuote
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CoinPaprikaQuoteCopyWith<_CoinPaprikaQuote> get copyWith => __$CoinPaprikaQuoteCopyWithImpl<_CoinPaprikaQuote>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CoinPaprikaQuoteToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CoinPaprikaQuote&&(identical(other.price, price) || other.price == price)&&(identical(other.volume24h, volume24h) || other.volume24h == volume24h));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,price,volume24h);

@override
String toString() {
  return 'CoinPaprikaQuote(price: $price, volume24h: $volume24h)';
}


}

/// @nodoc
abstract mixin class _$CoinPaprikaQuoteCopyWith<$Res> implements $CoinPaprikaQuoteCopyWith<$Res> {
  factory _$CoinPaprikaQuoteCopyWith(_CoinPaprikaQuote value, $Res Function(_CoinPaprikaQuote) _then) = __$CoinPaprikaQuoteCopyWithImpl;
@override @useResult
$Res call({
@NonNullableDecimalConverter() Decimal price,@JsonKey(name: 'volume_24h')@NonNullableDecimalConverter() Decimal volume24h
});




}
/// @nodoc
class __$CoinPaprikaQuoteCopyWithImpl<$Res>
    implements _$CoinPaprikaQuoteCopyWith<$Res> {
  __$CoinPaprikaQuoteCopyWithImpl(this._self, this._then);

  final _CoinPaprikaQuote _self;
  final $Res Function(_CoinPaprikaQuote) _then;

/// Create a copy of CoinPaprikaQuote
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? price = null,Object? volume24h = null,}) {
  return _then(_CoinPaprikaQuote(
price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as Decimal,volume24h: null == volume24h ? _self.volume24h : volume24h // ignore: cast_nullable_to_non_nullable
as Decimal,
  ));
}


}

// dart format on
