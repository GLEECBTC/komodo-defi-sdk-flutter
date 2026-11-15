// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'binance_24hr_ticker.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Binance24hrTicker {
  String get symbol;
  @DecimalConverter()
  Decimal get priceChange;
  @DecimalConverter()
  Decimal get priceChangePercent;
  @DecimalConverter()
  Decimal get weightedAvgPrice;
  @DecimalConverter()
  Decimal get prevClosePrice;
  @DecimalConverter()
  Decimal get lastPrice;
  @DecimalConverter()
  Decimal get lastQty;
  @DecimalConverter()
  Decimal get bidPrice;
  @DecimalConverter()
  Decimal get bidQty;
  @DecimalConverter()
  Decimal get askPrice;
  @DecimalConverter()
  Decimal get askQty;
  @DecimalConverter()
  Decimal get openPrice;
  @DecimalConverter()
  Decimal get highPrice;
  @DecimalConverter()
  Decimal get lowPrice;
  @DecimalConverter()
  Decimal get volume;
  @DecimalConverter()
  Decimal get quoteVolume;
  int get openTime;
  int get closeTime;
  int get firstId;
  int get lastId;
  int get count;

  /// Create a copy of Binance24hrTicker
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $Binance24hrTickerCopyWith<Binance24hrTicker> get copyWith =>
      _$Binance24hrTickerCopyWithImpl<Binance24hrTicker>(
        this as Binance24hrTicker,
        _$identity,
      );

  /// Serializes this Binance24hrTicker to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as Binance24hrTicker;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Binance24hrTicker &&
            (identical(other.symbol, _this.symbol) ||
                other.symbol == _this.symbol) &&
            (identical(other.priceChange, _this.priceChange) ||
                other.priceChange == _this.priceChange) &&
            (identical(other.priceChangePercent, _this.priceChangePercent) ||
                other.priceChangePercent == _this.priceChangePercent) &&
            (identical(other.weightedAvgPrice, _this.weightedAvgPrice) ||
                other.weightedAvgPrice == _this.weightedAvgPrice) &&
            (identical(other.prevClosePrice, _this.prevClosePrice) ||
                other.prevClosePrice == _this.prevClosePrice) &&
            (identical(other.lastPrice, _this.lastPrice) ||
                other.lastPrice == _this.lastPrice) &&
            (identical(other.lastQty, _this.lastQty) ||
                other.lastQty == _this.lastQty) &&
            (identical(other.bidPrice, _this.bidPrice) ||
                other.bidPrice == _this.bidPrice) &&
            (identical(other.bidQty, _this.bidQty) ||
                other.bidQty == _this.bidQty) &&
            (identical(other.askPrice, _this.askPrice) ||
                other.askPrice == _this.askPrice) &&
            (identical(other.askQty, _this.askQty) ||
                other.askQty == _this.askQty) &&
            (identical(other.openPrice, _this.openPrice) ||
                other.openPrice == _this.openPrice) &&
            (identical(other.highPrice, _this.highPrice) ||
                other.highPrice == _this.highPrice) &&
            (identical(other.lowPrice, _this.lowPrice) ||
                other.lowPrice == _this.lowPrice) &&
            (identical(other.volume, _this.volume) ||
                other.volume == _this.volume) &&
            (identical(other.quoteVolume, _this.quoteVolume) ||
                other.quoteVolume == _this.quoteVolume) &&
            (identical(other.openTime, _this.openTime) ||
                other.openTime == _this.openTime) &&
            (identical(other.closeTime, _this.closeTime) ||
                other.closeTime == _this.closeTime) &&
            (identical(other.firstId, _this.firstId) ||
                other.firstId == _this.firstId) &&
            (identical(other.lastId, _this.lastId) ||
                other.lastId == _this.lastId) &&
            (identical(other.count, _this.count) ||
                other.count == _this.count));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as Binance24hrTicker;
    return Object.hashAll([
      runtimeType,
      _this.symbol,
      _this.priceChange,
      _this.priceChangePercent,
      _this.weightedAvgPrice,
      _this.prevClosePrice,
      _this.lastPrice,
      _this.lastQty,
      _this.bidPrice,
      _this.bidQty,
      _this.askPrice,
      _this.askQty,
      _this.openPrice,
      _this.highPrice,
      _this.lowPrice,
      _this.volume,
      _this.quoteVolume,
      _this.openTime,
      _this.closeTime,
      _this.firstId,
      _this.lastId,
      _this.count,
    ]);
  }

  @override
  String toString() {
    final _this = this as Binance24hrTicker;
    return 'Binance24hrTicker(symbol: ${_this.symbol}, priceChange: ${_this.priceChange}, priceChangePercent: ${_this.priceChangePercent}, weightedAvgPrice: ${_this.weightedAvgPrice}, prevClosePrice: ${_this.prevClosePrice}, lastPrice: ${_this.lastPrice}, lastQty: ${_this.lastQty}, bidPrice: ${_this.bidPrice}, bidQty: ${_this.bidQty}, askPrice: ${_this.askPrice}, askQty: ${_this.askQty}, openPrice: ${_this.openPrice}, highPrice: ${_this.highPrice}, lowPrice: ${_this.lowPrice}, volume: ${_this.volume}, quoteVolume: ${_this.quoteVolume}, openTime: ${_this.openTime}, closeTime: ${_this.closeTime}, firstId: ${_this.firstId}, lastId: ${_this.lastId}, count: ${_this.count})';
  }
}

/// @nodoc
abstract mixin class $Binance24hrTickerCopyWith<$Res> {
  factory $Binance24hrTickerCopyWith(
    Binance24hrTicker value,
    $Res Function(Binance24hrTicker) _then,
  ) = _$Binance24hrTickerCopyWithImpl;
  @useResult
  $Res call({
    String symbol,
    @DecimalConverter() Decimal priceChange,
    @DecimalConverter() Decimal priceChangePercent,
    @DecimalConverter() Decimal weightedAvgPrice,
    @DecimalConverter() Decimal prevClosePrice,
    @DecimalConverter() Decimal lastPrice,
    @DecimalConverter() Decimal lastQty,
    @DecimalConverter() Decimal bidPrice,
    @DecimalConverter() Decimal bidQty,
    @DecimalConverter() Decimal askPrice,
    @DecimalConverter() Decimal askQty,
    @DecimalConverter() Decimal openPrice,
    @DecimalConverter() Decimal highPrice,
    @DecimalConverter() Decimal lowPrice,
    @DecimalConverter() Decimal volume,
    @DecimalConverter() Decimal quoteVolume,
    int openTime,
    int closeTime,
    int firstId,
    int lastId,
    int count,
  });
}

/// @nodoc
class _$Binance24hrTickerCopyWithImpl<$Res>
    implements $Binance24hrTickerCopyWith<$Res> {
  _$Binance24hrTickerCopyWithImpl(this._self, this._then);

  final Binance24hrTicker _self;
  final $Res Function(Binance24hrTicker) _then;

  /// Create a copy of Binance24hrTicker
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? symbol = null,
    Object? priceChange = null,
    Object? priceChangePercent = null,
    Object? weightedAvgPrice = null,
    Object? prevClosePrice = null,
    Object? lastPrice = null,
    Object? lastQty = null,
    Object? bidPrice = null,
    Object? bidQty = null,
    Object? askPrice = null,
    Object? askQty = null,
    Object? openPrice = null,
    Object? highPrice = null,
    Object? lowPrice = null,
    Object? volume = null,
    Object? quoteVolume = null,
    Object? openTime = null,
    Object? closeTime = null,
    Object? firstId = null,
    Object? lastId = null,
    Object? count = null,
  }) {
    return _then(
      Binance24hrTicker(
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        priceChange: null == priceChange
            ? _self.priceChange
            : priceChange // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        priceChangePercent: null == priceChangePercent
            ? _self.priceChangePercent
            : priceChangePercent // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        weightedAvgPrice: null == weightedAvgPrice
            ? _self.weightedAvgPrice
            : weightedAvgPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        prevClosePrice: null == prevClosePrice
            ? _self.prevClosePrice
            : prevClosePrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lastPrice: null == lastPrice
            ? _self.lastPrice
            : lastPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lastQty: null == lastQty
            ? _self.lastQty
            : lastQty // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        bidPrice: null == bidPrice
            ? _self.bidPrice
            : bidPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        bidQty: null == bidQty
            ? _self.bidQty
            : bidQty // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        askPrice: null == askPrice
            ? _self.askPrice
            : askPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        askQty: null == askQty
            ? _self.askQty
            : askQty // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        openPrice: null == openPrice
            ? _self.openPrice
            : openPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        highPrice: null == highPrice
            ? _self.highPrice
            : highPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lowPrice: null == lowPrice
            ? _self.lowPrice
            : lowPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        volume: null == volume
            ? _self.volume
            : volume // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        quoteVolume: null == quoteVolume
            ? _self.quoteVolume
            : quoteVolume // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        openTime: null == openTime
            ? _self.openTime
            : openTime // ignore: cast_nullable_to_non_nullable
                  as int,
        closeTime: null == closeTime
            ? _self.closeTime
            : closeTime // ignore: cast_nullable_to_non_nullable
                  as int,
        firstId: null == firstId
            ? _self.firstId
            : firstId // ignore: cast_nullable_to_non_nullable
                  as int,
        lastId: null == lastId
            ? _self.lastId
            : lastId // ignore: cast_nullable_to_non_nullable
                  as int,
        count: null == count
            ? _self.count
            : count // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [Binance24hrTicker].
extension Binance24hrTickerPatterns on Binance24hrTicker {
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
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_Binance24hrTicker value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Binance24hrTicker() when $default != null:
        return $default(_that);
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
  TResult map<TResult extends Object?>(
    TResult Function(_Binance24hrTicker value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Binance24hrTicker():
        return $default(_that);
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
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_Binance24hrTicker value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Binance24hrTicker() when $default != null:
        return $default(_that);
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
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
      String symbol,
      @DecimalConverter() Decimal priceChange,
      @DecimalConverter() Decimal priceChangePercent,
      @DecimalConverter() Decimal weightedAvgPrice,
      @DecimalConverter() Decimal prevClosePrice,
      @DecimalConverter() Decimal lastPrice,
      @DecimalConverter() Decimal lastQty,
      @DecimalConverter() Decimal bidPrice,
      @DecimalConverter() Decimal bidQty,
      @DecimalConverter() Decimal askPrice,
      @DecimalConverter() Decimal askQty,
      @DecimalConverter() Decimal openPrice,
      @DecimalConverter() Decimal highPrice,
      @DecimalConverter() Decimal lowPrice,
      @DecimalConverter() Decimal volume,
      @DecimalConverter() Decimal quoteVolume,
      int openTime,
      int closeTime,
      int firstId,
      int lastId,
      int count,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Binance24hrTicker() when $default != null:
        return $default(
          _that.symbol,
          _that.priceChange,
          _that.priceChangePercent,
          _that.weightedAvgPrice,
          _that.prevClosePrice,
          _that.lastPrice,
          _that.lastQty,
          _that.bidPrice,
          _that.bidQty,
          _that.askPrice,
          _that.askQty,
          _that.openPrice,
          _that.highPrice,
          _that.lowPrice,
          _that.volume,
          _that.quoteVolume,
          _that.openTime,
          _that.closeTime,
          _that.firstId,
          _that.lastId,
          _that.count,
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
  TResult when<TResult extends Object?>(
    TResult Function(
      String symbol,
      @DecimalConverter() Decimal priceChange,
      @DecimalConverter() Decimal priceChangePercent,
      @DecimalConverter() Decimal weightedAvgPrice,
      @DecimalConverter() Decimal prevClosePrice,
      @DecimalConverter() Decimal lastPrice,
      @DecimalConverter() Decimal lastQty,
      @DecimalConverter() Decimal bidPrice,
      @DecimalConverter() Decimal bidQty,
      @DecimalConverter() Decimal askPrice,
      @DecimalConverter() Decimal askQty,
      @DecimalConverter() Decimal openPrice,
      @DecimalConverter() Decimal highPrice,
      @DecimalConverter() Decimal lowPrice,
      @DecimalConverter() Decimal volume,
      @DecimalConverter() Decimal quoteVolume,
      int openTime,
      int closeTime,
      int firstId,
      int lastId,
      int count,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Binance24hrTicker():
        return $default(
          _that.symbol,
          _that.priceChange,
          _that.priceChangePercent,
          _that.weightedAvgPrice,
          _that.prevClosePrice,
          _that.lastPrice,
          _that.lastQty,
          _that.bidPrice,
          _that.bidQty,
          _that.askPrice,
          _that.askQty,
          _that.openPrice,
          _that.highPrice,
          _that.lowPrice,
          _that.volume,
          _that.quoteVolume,
          _that.openTime,
          _that.closeTime,
          _that.firstId,
          _that.lastId,
          _that.count,
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
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
      String symbol,
      @DecimalConverter() Decimal priceChange,
      @DecimalConverter() Decimal priceChangePercent,
      @DecimalConverter() Decimal weightedAvgPrice,
      @DecimalConverter() Decimal prevClosePrice,
      @DecimalConverter() Decimal lastPrice,
      @DecimalConverter() Decimal lastQty,
      @DecimalConverter() Decimal bidPrice,
      @DecimalConverter() Decimal bidQty,
      @DecimalConverter() Decimal askPrice,
      @DecimalConverter() Decimal askQty,
      @DecimalConverter() Decimal openPrice,
      @DecimalConverter() Decimal highPrice,
      @DecimalConverter() Decimal lowPrice,
      @DecimalConverter() Decimal volume,
      @DecimalConverter() Decimal quoteVolume,
      int openTime,
      int closeTime,
      int firstId,
      int lastId,
      int count,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Binance24hrTicker() when $default != null:
        return $default(
          _that.symbol,
          _that.priceChange,
          _that.priceChangePercent,
          _that.weightedAvgPrice,
          _that.prevClosePrice,
          _that.lastPrice,
          _that.lastQty,
          _that.bidPrice,
          _that.bidQty,
          _that.askPrice,
          _that.askQty,
          _that.openPrice,
          _that.highPrice,
          _that.lowPrice,
          _that.volume,
          _that.quoteVolume,
          _that.openTime,
          _that.closeTime,
          _that.firstId,
          _that.lastId,
          _that.count,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _Binance24hrTicker implements Binance24hrTicker {
  const _Binance24hrTicker({
    required this.symbol,
    @DecimalConverter() required this.priceChange,
    @DecimalConverter() required this.priceChangePercent,
    @DecimalConverter() required this.weightedAvgPrice,
    @DecimalConverter() required this.prevClosePrice,
    @DecimalConverter() required this.lastPrice,
    @DecimalConverter() required this.lastQty,
    @DecimalConverter() required this.bidPrice,
    @DecimalConverter() required this.bidQty,
    @DecimalConverter() required this.askPrice,
    @DecimalConverter() required this.askQty,
    @DecimalConverter() required this.openPrice,
    @DecimalConverter() required this.highPrice,
    @DecimalConverter() required this.lowPrice,
    @DecimalConverter() required this.volume,
    @DecimalConverter() required this.quoteVolume,
    required this.openTime,
    required this.closeTime,
    required this.firstId,
    required this.lastId,
    required this.count,
  });
  factory _Binance24hrTicker.fromJson(Map<String, dynamic> json) =>
      _$Binance24hrTickerFromJson(json);

  @override
  final String symbol;
  @override
  @DecimalConverter()
  final Decimal priceChange;
  @override
  @DecimalConverter()
  final Decimal priceChangePercent;
  @override
  @DecimalConverter()
  final Decimal weightedAvgPrice;
  @override
  @DecimalConverter()
  final Decimal prevClosePrice;
  @override
  @DecimalConverter()
  final Decimal lastPrice;
  @override
  @DecimalConverter()
  final Decimal lastQty;
  @override
  @DecimalConverter()
  final Decimal bidPrice;
  @override
  @DecimalConverter()
  final Decimal bidQty;
  @override
  @DecimalConverter()
  final Decimal askPrice;
  @override
  @DecimalConverter()
  final Decimal askQty;
  @override
  @DecimalConverter()
  final Decimal openPrice;
  @override
  @DecimalConverter()
  final Decimal highPrice;
  @override
  @DecimalConverter()
  final Decimal lowPrice;
  @override
  @DecimalConverter()
  final Decimal volume;
  @override
  @DecimalConverter()
  final Decimal quoteVolume;
  @override
  final int openTime;
  @override
  final int closeTime;
  @override
  final int firstId;
  @override
  final int lastId;
  @override
  final int count;

  /// Create a copy of Binance24hrTicker
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$Binance24hrTickerCopyWith<_Binance24hrTicker> get copyWith =>
      __$Binance24hrTickerCopyWithImpl<_Binance24hrTicker>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$Binance24hrTickerToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Binance24hrTicker &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.priceChange, priceChange) ||
                other.priceChange == priceChange) &&
            (identical(other.priceChangePercent, priceChangePercent) ||
                other.priceChangePercent == priceChangePercent) &&
            (identical(other.weightedAvgPrice, weightedAvgPrice) ||
                other.weightedAvgPrice == weightedAvgPrice) &&
            (identical(other.prevClosePrice, prevClosePrice) ||
                other.prevClosePrice == prevClosePrice) &&
            (identical(other.lastPrice, lastPrice) ||
                other.lastPrice == lastPrice) &&
            (identical(other.lastQty, lastQty) || other.lastQty == lastQty) &&
            (identical(other.bidPrice, bidPrice) ||
                other.bidPrice == bidPrice) &&
            (identical(other.bidQty, bidQty) || other.bidQty == bidQty) &&
            (identical(other.askPrice, askPrice) ||
                other.askPrice == askPrice) &&
            (identical(other.askQty, askQty) || other.askQty == askQty) &&
            (identical(other.openPrice, openPrice) ||
                other.openPrice == openPrice) &&
            (identical(other.highPrice, highPrice) ||
                other.highPrice == highPrice) &&
            (identical(other.lowPrice, lowPrice) ||
                other.lowPrice == lowPrice) &&
            (identical(other.volume, volume) || other.volume == volume) &&
            (identical(other.quoteVolume, quoteVolume) ||
                other.quoteVolume == quoteVolume) &&
            (identical(other.openTime, openTime) ||
                other.openTime == openTime) &&
            (identical(other.closeTime, closeTime) ||
                other.closeTime == closeTime) &&
            (identical(other.firstId, firstId) || other.firstId == firstId) &&
            (identical(other.lastId, lastId) || other.lastId == lastId) &&
            (identical(other.count, count) || other.count == count));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hashAll([
      runtimeType,
      symbol,
      priceChange,
      priceChangePercent,
      weightedAvgPrice,
      prevClosePrice,
      lastPrice,
      lastQty,
      bidPrice,
      bidQty,
      askPrice,
      askQty,
      openPrice,
      highPrice,
      lowPrice,
      volume,
      quoteVolume,
      openTime,
      closeTime,
      firstId,
      lastId,
      count,
    ]);
  }

  @override
  String toString() {
    return 'Binance24hrTicker(symbol: $symbol, priceChange: $priceChange, priceChangePercent: $priceChangePercent, weightedAvgPrice: $weightedAvgPrice, prevClosePrice: $prevClosePrice, lastPrice: $lastPrice, lastQty: $lastQty, bidPrice: $bidPrice, bidQty: $bidQty, askPrice: $askPrice, askQty: $askQty, openPrice: $openPrice, highPrice: $highPrice, lowPrice: $lowPrice, volume: $volume, quoteVolume: $quoteVolume, openTime: $openTime, closeTime: $closeTime, firstId: $firstId, lastId: $lastId, count: $count)';
  }
}

/// @nodoc
abstract mixin class _$Binance24hrTickerCopyWith<$Res>
    implements $Binance24hrTickerCopyWith<$Res> {
  factory _$Binance24hrTickerCopyWith(
    _Binance24hrTicker value,
    $Res Function(_Binance24hrTicker) _then,
  ) = __$Binance24hrTickerCopyWithImpl;
  @override
  @useResult
  $Res call({
    String symbol,
    @DecimalConverter() Decimal priceChange,
    @DecimalConverter() Decimal priceChangePercent,
    @DecimalConverter() Decimal weightedAvgPrice,
    @DecimalConverter() Decimal prevClosePrice,
    @DecimalConverter() Decimal lastPrice,
    @DecimalConverter() Decimal lastQty,
    @DecimalConverter() Decimal bidPrice,
    @DecimalConverter() Decimal bidQty,
    @DecimalConverter() Decimal askPrice,
    @DecimalConverter() Decimal askQty,
    @DecimalConverter() Decimal openPrice,
    @DecimalConverter() Decimal highPrice,
    @DecimalConverter() Decimal lowPrice,
    @DecimalConverter() Decimal volume,
    @DecimalConverter() Decimal quoteVolume,
    int openTime,
    int closeTime,
    int firstId,
    int lastId,
    int count,
  });
}

/// @nodoc
class __$Binance24hrTickerCopyWithImpl<$Res>
    implements _$Binance24hrTickerCopyWith<$Res> {
  __$Binance24hrTickerCopyWithImpl(this._self, this._then);

  final _Binance24hrTicker _self;
  final $Res Function(_Binance24hrTicker) _then;

  /// Create a copy of Binance24hrTicker
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? symbol = null,
    Object? priceChange = null,
    Object? priceChangePercent = null,
    Object? weightedAvgPrice = null,
    Object? prevClosePrice = null,
    Object? lastPrice = null,
    Object? lastQty = null,
    Object? bidPrice = null,
    Object? bidQty = null,
    Object? askPrice = null,
    Object? askQty = null,
    Object? openPrice = null,
    Object? highPrice = null,
    Object? lowPrice = null,
    Object? volume = null,
    Object? quoteVolume = null,
    Object? openTime = null,
    Object? closeTime = null,
    Object? firstId = null,
    Object? lastId = null,
    Object? count = null,
  }) {
    return _then(
      _Binance24hrTicker(
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        priceChange: null == priceChange
            ? _self.priceChange
            : priceChange // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        priceChangePercent: null == priceChangePercent
            ? _self.priceChangePercent
            : priceChangePercent // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        weightedAvgPrice: null == weightedAvgPrice
            ? _self.weightedAvgPrice
            : weightedAvgPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        prevClosePrice: null == prevClosePrice
            ? _self.prevClosePrice
            : prevClosePrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lastPrice: null == lastPrice
            ? _self.lastPrice
            : lastPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lastQty: null == lastQty
            ? _self.lastQty
            : lastQty // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        bidPrice: null == bidPrice
            ? _self.bidPrice
            : bidPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        bidQty: null == bidQty
            ? _self.bidQty
            : bidQty // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        askPrice: null == askPrice
            ? _self.askPrice
            : askPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        askQty: null == askQty
            ? _self.askQty
            : askQty // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        openPrice: null == openPrice
            ? _self.openPrice
            : openPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        highPrice: null == highPrice
            ? _self.highPrice
            : highPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lowPrice: null == lowPrice
            ? _self.lowPrice
            : lowPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        volume: null == volume
            ? _self.volume
            : volume // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        quoteVolume: null == quoteVolume
            ? _self.quoteVolume
            : quoteVolume // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        openTime: null == openTime
            ? _self.openTime
            : openTime // ignore: cast_nullable_to_non_nullable
                  as int,
        closeTime: null == closeTime
            ? _self.closeTime
            : closeTime // ignore: cast_nullable_to_non_nullable
                  as int,
        firstId: null == firstId
            ? _self.firstId
            : firstId // ignore: cast_nullable_to_non_nullable
                  as int,
        lastId: null == lastId
            ? _self.lastId
            : lastId // ignore: cast_nullable_to_non_nullable
                  as int,
        count: null == count
            ? _self.count
            : count // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}
