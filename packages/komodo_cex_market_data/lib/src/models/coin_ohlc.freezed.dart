// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coin_ohlc.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;
Ohlc _$OhlcFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'coingecko':
      return CoinGeckoOhlc.fromJson(json);
    case 'binance':
      return BinanceOhlc.fromJson(json);
    case 'coinpaprika':
      return CoinPaprikaOhlc.fromJson(json);

    default:
      throw CheckedFromJsonException(
        json,
        'runtimeType',
        'Ohlc',
        'Invalid union type "${json['runtimeType']}"!',
      );
  }
}

/// @nodoc
mixin _$Ohlc {
  /// Opening price as a [Decimal] for precision
  @DecimalConverter()
  Decimal get open;

  /// Highest price reached during this period as a [Decimal]
  @DecimalConverter()
  Decimal get high;

  /// Lowest price reached during this period as a [Decimal]
  @DecimalConverter()
  Decimal get low;

  /// Closing price as a [Decimal] for precision
  @DecimalConverter()
  Decimal get close;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $OhlcCopyWith<Ohlc> get copyWith =>
      _$OhlcCopyWithImpl<Ohlc>(this as Ohlc, _$identity);

  /// Serializes this Ohlc to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as Ohlc;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Ohlc &&
            (identical(other.open, _this.open) || other.open == _this.open) &&
            (identical(other.high, _this.high) || other.high == _this.high) &&
            (identical(other.low, _this.low) || other.low == _this.low) &&
            (identical(other.close, _this.close) ||
                other.close == _this.close));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as Ohlc;
    return Object.hash(
      runtimeType,
      _this.open,
      _this.high,
      _this.low,
      _this.close,
    );
  }

  @override
  String toString() {
    final _this = this as Ohlc;
    return 'Ohlc(open: ${_this.open}, high: ${_this.high}, low: ${_this.low}, close: ${_this.close})';
  }
}

/// @nodoc
abstract mixin class $OhlcCopyWith<$Res> {
  factory $OhlcCopyWith(Ohlc value, $Res Function(Ohlc) _then) =
      _$OhlcCopyWithImpl;
  @useResult
  $Res call({
    @DecimalConverter() Decimal open,
    @DecimalConverter() Decimal high,
    @DecimalConverter() Decimal low,
    @DecimalConverter() Decimal close,
  });
}

/// @nodoc
class _$OhlcCopyWithImpl<$Res> implements $OhlcCopyWith<$Res> {
  _$OhlcCopyWithImpl(this._self, this._then);

  final Ohlc _self;
  final $Res Function(Ohlc) _then;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? open = null,
    Object? high = null,
    Object? low = null,
    Object? close = null,
  }) {
    return _then(
      _self.copyWith(
        open: null == open
            ? _self.open
            : open // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        high: null == high
            ? _self.high
            : high // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        low: null == low
            ? _self.low
            : low // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        close: null == close
            ? _self.close
            : close // ignore: cast_nullable_to_non_nullable
                  as Decimal,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [Ohlc].
extension OhlcPatterns on Ohlc {
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

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(CoinGeckoOhlc value)? coingecko,
    TResult Function(BinanceOhlc value)? binance,
    TResult Function(CoinPaprikaOhlc value)? coinpaprika,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case CoinGeckoOhlc() when coingecko != null:
        return coingecko(_that);
      case BinanceOhlc() when binance != null:
        return binance(_that);
      case CoinPaprikaOhlc() when coinpaprika != null:
        return coinpaprika(_that);
      case _:
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

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(CoinGeckoOhlc value) coingecko,
    required TResult Function(BinanceOhlc value) binance,
    required TResult Function(CoinPaprikaOhlc value) coinpaprika,
  }) {
    final _that = this;
    switch (_that) {
      case CoinGeckoOhlc():
        return coingecko(_that);
      case BinanceOhlc():
        return binance(_that);
      case CoinPaprikaOhlc():
        return coinpaprika(_that);
      case _:
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

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(CoinGeckoOhlc value)? coingecko,
    TResult? Function(BinanceOhlc value)? binance,
    TResult? Function(CoinPaprikaOhlc value)? coinpaprika,
  }) {
    final _that = this;
    switch (_that) {
      case CoinGeckoOhlc() when coingecko != null:
        return coingecko(_that);
      case BinanceOhlc() when binance != null:
        return binance(_that);
      case CoinPaprikaOhlc() when coinpaprika != null:
        return coinpaprika(_that);
      case _:
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

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
      int timestamp,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
    )?
    coingecko,
    TResult Function(
      int openTime,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
      int closeTime,
      @DecimalConverter() Decimal? volume,
      @DecimalConverter() Decimal? quoteAssetVolume,
      int? numberOfTrades,
      @DecimalConverter() Decimal? takerBuyBaseAssetVolume,
      @DecimalConverter() Decimal? takerBuyQuoteAssetVolume,
    )?
    binance,
    TResult Function(
      int timeOpen,
      int timeClose,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
      @DecimalConverter() Decimal? volume,
      @DecimalConverter() Decimal? marketCap,
    )?
    coinpaprika,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case CoinGeckoOhlc() when coingecko != null:
        return coingecko(
          _that.timestamp,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
        );
      case BinanceOhlc() when binance != null:
        return binance(
          _that.openTime,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
          _that.closeTime,
          _that.volume,
          _that.quoteAssetVolume,
          _that.numberOfTrades,
          _that.takerBuyBaseAssetVolume,
          _that.takerBuyQuoteAssetVolume,
        );
      case CoinPaprikaOhlc() when coinpaprika != null:
        return coinpaprika(
          _that.timeOpen,
          _that.timeClose,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
          _that.volume,
          _that.marketCap,
        );
      case _:
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

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
      int timestamp,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
    )
    coingecko,
    required TResult Function(
      int openTime,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
      int closeTime,
      @DecimalConverter() Decimal? volume,
      @DecimalConverter() Decimal? quoteAssetVolume,
      int? numberOfTrades,
      @DecimalConverter() Decimal? takerBuyBaseAssetVolume,
      @DecimalConverter() Decimal? takerBuyQuoteAssetVolume,
    )
    binance,
    required TResult Function(
      int timeOpen,
      int timeClose,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
      @DecimalConverter() Decimal? volume,
      @DecimalConverter() Decimal? marketCap,
    )
    coinpaprika,
  }) {
    final _that = this;
    switch (_that) {
      case CoinGeckoOhlc():
        return coingecko(
          _that.timestamp,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
        );
      case BinanceOhlc():
        return binance(
          _that.openTime,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
          _that.closeTime,
          _that.volume,
          _that.quoteAssetVolume,
          _that.numberOfTrades,
          _that.takerBuyBaseAssetVolume,
          _that.takerBuyQuoteAssetVolume,
        );
      case CoinPaprikaOhlc():
        return coinpaprika(
          _that.timeOpen,
          _that.timeClose,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
          _that.volume,
          _that.marketCap,
        );
      case _:
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

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
      int timestamp,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
    )?
    coingecko,
    TResult? Function(
      int openTime,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
      int closeTime,
      @DecimalConverter() Decimal? volume,
      @DecimalConverter() Decimal? quoteAssetVolume,
      int? numberOfTrades,
      @DecimalConverter() Decimal? takerBuyBaseAssetVolume,
      @DecimalConverter() Decimal? takerBuyQuoteAssetVolume,
    )?
    binance,
    TResult? Function(
      int timeOpen,
      int timeClose,
      @DecimalConverter() Decimal open,
      @DecimalConverter() Decimal high,
      @DecimalConverter() Decimal low,
      @DecimalConverter() Decimal close,
      @DecimalConverter() Decimal? volume,
      @DecimalConverter() Decimal? marketCap,
    )?
    coinpaprika,
  }) {
    final _that = this;
    switch (_that) {
      case CoinGeckoOhlc() when coingecko != null:
        return coingecko(
          _that.timestamp,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
        );
      case BinanceOhlc() when binance != null:
        return binance(
          _that.openTime,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
          _that.closeTime,
          _that.volume,
          _that.quoteAssetVolume,
          _that.numberOfTrades,
          _that.takerBuyBaseAssetVolume,
          _that.takerBuyQuoteAssetVolume,
        );
      case CoinPaprikaOhlc() when coinpaprika != null:
        return coinpaprika(
          _that.timeOpen,
          _that.timeClose,
          _that.open,
          _that.high,
          _that.low,
          _that.close,
          _that.volume,
          _that.marketCap,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class CoinGeckoOhlc implements Ohlc {
  const CoinGeckoOhlc({
    required this.timestamp,
    @DecimalConverter() required this.open,
    @DecimalConverter() required this.high,
    @DecimalConverter() required this.low,
    @DecimalConverter() required this.close,
    String? $type,
  }) : $type = $type ?? 'coingecko';
  factory CoinGeckoOhlc.fromJson(Map<String, dynamic> json) =>
      _$CoinGeckoOhlcFromJson(json);

  /// Unix timestamp in milliseconds for this data point
  final int timestamp;

  /// Opening price as a [Decimal] for precision
  @override
  @DecimalConverter()
  final Decimal open;

  /// Highest price reached during this period as a [Decimal]
  @override
  @DecimalConverter()
  final Decimal high;

  /// Lowest price reached during this period as a [Decimal]
  @override
  @DecimalConverter()
  final Decimal low;

  /// Closing price as a [Decimal] for precision
  @override
  @DecimalConverter()
  final Decimal close;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CoinGeckoOhlcCopyWith<CoinGeckoOhlc> get copyWith =>
      _$CoinGeckoOhlcCopyWithImpl<CoinGeckoOhlc>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$CoinGeckoOhlcToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CoinGeckoOhlc &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.open, open) || other.open == open) &&
            (identical(other.high, high) || other.high == high) &&
            (identical(other.low, low) || other.low == low) &&
            (identical(other.close, close) || other.close == close));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, timestamp, open, high, low, close);
  }

  @override
  String toString() {
    return 'Ohlc.coingecko(timestamp: $timestamp, open: $open, high: $high, low: $low, close: $close)';
  }
}

/// @nodoc
abstract mixin class $CoinGeckoOhlcCopyWith<$Res>
    implements $OhlcCopyWith<$Res> {
  factory $CoinGeckoOhlcCopyWith(
    CoinGeckoOhlc value,
    $Res Function(CoinGeckoOhlc) _then,
  ) = _$CoinGeckoOhlcCopyWithImpl;
  @override
  @useResult
  $Res call({
    int timestamp,
    @DecimalConverter() Decimal open,
    @DecimalConverter() Decimal high,
    @DecimalConverter() Decimal low,
    @DecimalConverter() Decimal close,
  });
}

/// @nodoc
class _$CoinGeckoOhlcCopyWithImpl<$Res>
    implements $CoinGeckoOhlcCopyWith<$Res> {
  _$CoinGeckoOhlcCopyWithImpl(this._self, this._then);

  final CoinGeckoOhlc _self;
  final $Res Function(CoinGeckoOhlc) _then;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? timestamp = null,
    Object? open = null,
    Object? high = null,
    Object? low = null,
    Object? close = null,
  }) {
    return _then(
      CoinGeckoOhlc(
        timestamp: null == timestamp
            ? _self.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as int,
        open: null == open
            ? _self.open
            : open // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        high: null == high
            ? _self.high
            : high // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        low: null == low
            ? _self.low
            : low // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        close: null == close
            ? _self.close
            : close // ignore: cast_nullable_to_non_nullable
                  as Decimal,
      ),
    );
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class BinanceOhlc implements Ohlc {
  const BinanceOhlc({
    required this.openTime,
    @DecimalConverter() required this.open,
    @DecimalConverter() required this.high,
    @DecimalConverter() required this.low,
    @DecimalConverter() required this.close,
    required this.closeTime,
    @DecimalConverter() this.volume,
    @DecimalConverter() this.quoteAssetVolume,
    this.numberOfTrades,
    @DecimalConverter() this.takerBuyBaseAssetVolume,
    @DecimalConverter() this.takerBuyQuoteAssetVolume,
    String? $type,
  }) : $type = $type ?? 'binance';
  factory BinanceOhlc.fromJson(Map<String, dynamic> json) =>
      _$BinanceOhlcFromJson(json);

  /// Unix timestamp in milliseconds when this kline opened
  final int openTime;

  /// Opening price as a [Decimal] for precision
  @override
  @DecimalConverter()
  final Decimal open;

  /// Highest price reached during this kline as a [Decimal]
  @override
  @DecimalConverter()
  final Decimal high;

  /// Lowest price reached during this kline as a [Decimal]
  @override
  @DecimalConverter()
  final Decimal low;

  /// Closing price as a [Decimal] for precision
  @override
  @DecimalConverter()
  final Decimal close;

  /// Unix timestamp in milliseconds when this kline closed
  final int closeTime;

  /// Trading volume during this kline as a [Decimal]
  @DecimalConverter()
  final Decimal? volume;

  /// Quote asset volume during this kline as a [Decimal]
  @DecimalConverter()
  final Decimal? quoteAssetVolume;

  /// Number of trades executed during this kline
  final int? numberOfTrades;

  /// Volume of the asset bought by takers during this kline as a [Decimal]
  @DecimalConverter()
  final Decimal? takerBuyBaseAssetVolume;

  /// Quote asset volume of the asset bought by takers during this kline as a [Decimal]
  @DecimalConverter()
  final Decimal? takerBuyQuoteAssetVolume;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $BinanceOhlcCopyWith<BinanceOhlc> get copyWith =>
      _$BinanceOhlcCopyWithImpl<BinanceOhlc>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$BinanceOhlcToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is BinanceOhlc &&
            (identical(other.openTime, openTime) ||
                other.openTime == openTime) &&
            (identical(other.open, open) || other.open == open) &&
            (identical(other.high, high) || other.high == high) &&
            (identical(other.low, low) || other.low == low) &&
            (identical(other.close, close) || other.close == close) &&
            (identical(other.closeTime, closeTime) ||
                other.closeTime == closeTime) &&
            (identical(other.volume, volume) || other.volume == volume) &&
            (identical(other.quoteAssetVolume, quoteAssetVolume) ||
                other.quoteAssetVolume == quoteAssetVolume) &&
            (identical(other.numberOfTrades, numberOfTrades) ||
                other.numberOfTrades == numberOfTrades) &&
            (identical(
                  other.takerBuyBaseAssetVolume,
                  takerBuyBaseAssetVolume,
                ) ||
                other.takerBuyBaseAssetVolume == takerBuyBaseAssetVolume) &&
            (identical(
                  other.takerBuyQuoteAssetVolume,
                  takerBuyQuoteAssetVolume,
                ) ||
                other.takerBuyQuoteAssetVolume == takerBuyQuoteAssetVolume));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      openTime,
      open,
      high,
      low,
      close,
      closeTime,
      volume,
      quoteAssetVolume,
      numberOfTrades,
      takerBuyBaseAssetVolume,
      takerBuyQuoteAssetVolume,
    );
  }

  @override
  String toString() {
    return 'Ohlc.binance(openTime: $openTime, open: $open, high: $high, low: $low, close: $close, closeTime: $closeTime, volume: $volume, quoteAssetVolume: $quoteAssetVolume, numberOfTrades: $numberOfTrades, takerBuyBaseAssetVolume: $takerBuyBaseAssetVolume, takerBuyQuoteAssetVolume: $takerBuyQuoteAssetVolume)';
  }
}

/// @nodoc
abstract mixin class $BinanceOhlcCopyWith<$Res> implements $OhlcCopyWith<$Res> {
  factory $BinanceOhlcCopyWith(
    BinanceOhlc value,
    $Res Function(BinanceOhlc) _then,
  ) = _$BinanceOhlcCopyWithImpl;
  @override
  @useResult
  $Res call({
    int openTime,
    @DecimalConverter() Decimal open,
    @DecimalConverter() Decimal high,
    @DecimalConverter() Decimal low,
    @DecimalConverter() Decimal close,
    int closeTime,
    @DecimalConverter() Decimal? volume,
    @DecimalConverter() Decimal? quoteAssetVolume,
    int? numberOfTrades,
    @DecimalConverter() Decimal? takerBuyBaseAssetVolume,
    @DecimalConverter() Decimal? takerBuyQuoteAssetVolume,
  });
}

/// @nodoc
class _$BinanceOhlcCopyWithImpl<$Res> implements $BinanceOhlcCopyWith<$Res> {
  _$BinanceOhlcCopyWithImpl(this._self, this._then);

  final BinanceOhlc _self;
  final $Res Function(BinanceOhlc) _then;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? openTime = null,
    Object? open = null,
    Object? high = null,
    Object? low = null,
    Object? close = null,
    Object? closeTime = null,
    Object? volume = freezed,
    Object? quoteAssetVolume = freezed,
    Object? numberOfTrades = freezed,
    Object? takerBuyBaseAssetVolume = freezed,
    Object? takerBuyQuoteAssetVolume = freezed,
  }) {
    return _then(
      BinanceOhlc(
        openTime: null == openTime
            ? _self.openTime
            : openTime // ignore: cast_nullable_to_non_nullable
                  as int,
        open: null == open
            ? _self.open
            : open // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        high: null == high
            ? _self.high
            : high // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        low: null == low
            ? _self.low
            : low // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        close: null == close
            ? _self.close
            : close // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        closeTime: null == closeTime
            ? _self.closeTime
            : closeTime // ignore: cast_nullable_to_non_nullable
                  as int,
        volume: freezed == volume
            ? _self.volume
            : volume // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        quoteAssetVolume: freezed == quoteAssetVolume
            ? _self.quoteAssetVolume
            : quoteAssetVolume // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        numberOfTrades: freezed == numberOfTrades
            ? _self.numberOfTrades
            : numberOfTrades // ignore: cast_nullable_to_non_nullable
                  as int?,
        takerBuyBaseAssetVolume: freezed == takerBuyBaseAssetVolume
            ? _self.takerBuyBaseAssetVolume
            : takerBuyBaseAssetVolume // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        takerBuyQuoteAssetVolume: freezed == takerBuyQuoteAssetVolume
            ? _self.takerBuyQuoteAssetVolume
            : takerBuyQuoteAssetVolume // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
      ),
    );
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class CoinPaprikaOhlc implements Ohlc {
  const CoinPaprikaOhlc({
    required this.timeOpen,
    required this.timeClose,
    @DecimalConverter() required this.open,
    @DecimalConverter() required this.high,
    @DecimalConverter() required this.low,
    @DecimalConverter() required this.close,
    @DecimalConverter() this.volume,
    @DecimalConverter() this.marketCap,
    String? $type,
  }) : $type = $type ?? 'coinpaprika';
  factory CoinPaprikaOhlc.fromJson(Map<String, dynamic> json) =>
      _$CoinPaprikaOhlcFromJson(json);

  /// Unix timestamp in milliseconds when this period opened
  final int timeOpen;

  /// Unix timestamp in milliseconds when this period closed
  final int timeClose;

  /// Opening price as a [Decimal] for precision
  @override
  @DecimalConverter()
  final Decimal open;

  /// Highest price reached during this period as a [Decimal]
  @override
  @DecimalConverter()
  final Decimal high;

  /// Lowest price reached during this period as a [Decimal]
  @override
  @DecimalConverter()
  final Decimal low;

  /// Closing price as a [Decimal] for precision
  @override
  @DecimalConverter()
  final Decimal close;

  /// Trading volume during this period as a [Decimal]
  @DecimalConverter()
  final Decimal? volume;

  /// Market capitalization as a [Decimal]
  @DecimalConverter()
  final Decimal? marketCap;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CoinPaprikaOhlcCopyWith<CoinPaprikaOhlc> get copyWith =>
      _$CoinPaprikaOhlcCopyWithImpl<CoinPaprikaOhlc>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$CoinPaprikaOhlcToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CoinPaprikaOhlc &&
            (identical(other.timeOpen, timeOpen) ||
                other.timeOpen == timeOpen) &&
            (identical(other.timeClose, timeClose) ||
                other.timeClose == timeClose) &&
            (identical(other.open, open) || other.open == open) &&
            (identical(other.high, high) || other.high == high) &&
            (identical(other.low, low) || other.low == low) &&
            (identical(other.close, close) || other.close == close) &&
            (identical(other.volume, volume) || other.volume == volume) &&
            (identical(other.marketCap, marketCap) ||
                other.marketCap == marketCap));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      timeOpen,
      timeClose,
      open,
      high,
      low,
      close,
      volume,
      marketCap,
    );
  }

  @override
  String toString() {
    return 'Ohlc.coinpaprika(timeOpen: $timeOpen, timeClose: $timeClose, open: $open, high: $high, low: $low, close: $close, volume: $volume, marketCap: $marketCap)';
  }
}

/// @nodoc
abstract mixin class $CoinPaprikaOhlcCopyWith<$Res>
    implements $OhlcCopyWith<$Res> {
  factory $CoinPaprikaOhlcCopyWith(
    CoinPaprikaOhlc value,
    $Res Function(CoinPaprikaOhlc) _then,
  ) = _$CoinPaprikaOhlcCopyWithImpl;
  @override
  @useResult
  $Res call({
    int timeOpen,
    int timeClose,
    @DecimalConverter() Decimal open,
    @DecimalConverter() Decimal high,
    @DecimalConverter() Decimal low,
    @DecimalConverter() Decimal close,
    @DecimalConverter() Decimal? volume,
    @DecimalConverter() Decimal? marketCap,
  });
}

/// @nodoc
class _$CoinPaprikaOhlcCopyWithImpl<$Res>
    implements $CoinPaprikaOhlcCopyWith<$Res> {
  _$CoinPaprikaOhlcCopyWithImpl(this._self, this._then);

  final CoinPaprikaOhlc _self;
  final $Res Function(CoinPaprikaOhlc) _then;

  /// Create a copy of Ohlc
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? timeOpen = null,
    Object? timeClose = null,
    Object? open = null,
    Object? high = null,
    Object? low = null,
    Object? close = null,
    Object? volume = freezed,
    Object? marketCap = freezed,
  }) {
    return _then(
      CoinPaprikaOhlc(
        timeOpen: null == timeOpen
            ? _self.timeOpen
            : timeOpen // ignore: cast_nullable_to_non_nullable
                  as int,
        timeClose: null == timeClose
            ? _self.timeClose
            : timeClose // ignore: cast_nullable_to_non_nullable
                  as int,
        open: null == open
            ? _self.open
            : open // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        high: null == high
            ? _self.high
            : high // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        low: null == low
            ? _self.low
            : low // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        close: null == close
            ? _self.close
            : close // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        volume: freezed == volume
            ? _self.volume
            : volume // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        marketCap: freezed == marketCap
            ? _self.marketCap
            : marketCap // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
      ),
    );
  }
}
