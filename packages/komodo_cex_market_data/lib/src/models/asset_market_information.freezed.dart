// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'asset_market_information.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AssetMarketInformation {
  String get ticker;
  @DecimalConverter()
  Decimal get lastPrice;
  @TimestampConverter()
  DateTime? get lastUpdatedTimestamp;
  @CexDataProviderConverter()
  CexDataProvider? get priceProvider;
  @JsonKey(name: 'change_24h')
  @DecimalConverter()
  Decimal? get change24h;
  @JsonKey(name: 'change_24h_provider')
  @CexDataProviderConverter()
  CexDataProvider? get change24hProvider;
  @DecimalConverter()
  Decimal? get volume24h;
  @CexDataProviderConverter()
  CexDataProvider? get volumeProvider;

  /// Create a copy of AssetMarketInformation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AssetMarketInformationCopyWith<AssetMarketInformation> get copyWith =>
      _$AssetMarketInformationCopyWithImpl<AssetMarketInformation>(
        this as AssetMarketInformation,
        _$identity,
      );

  /// Serializes this AssetMarketInformation to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as AssetMarketInformation;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AssetMarketInformation &&
            (identical(other.ticker, _this.ticker) ||
                other.ticker == _this.ticker) &&
            (identical(other.lastPrice, _this.lastPrice) ||
                other.lastPrice == _this.lastPrice) &&
            (identical(
                  other.lastUpdatedTimestamp,
                  _this.lastUpdatedTimestamp,
                ) ||
                other.lastUpdatedTimestamp == _this.lastUpdatedTimestamp) &&
            (identical(other.priceProvider, _this.priceProvider) ||
                other.priceProvider == _this.priceProvider) &&
            (identical(other.change24h, _this.change24h) ||
                other.change24h == _this.change24h) &&
            (identical(other.change24hProvider, _this.change24hProvider) ||
                other.change24hProvider == _this.change24hProvider) &&
            (identical(other.volume24h, _this.volume24h) ||
                other.volume24h == _this.volume24h) &&
            (identical(other.volumeProvider, _this.volumeProvider) ||
                other.volumeProvider == _this.volumeProvider));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as AssetMarketInformation;
    return Object.hash(
      runtimeType,
      _this.ticker,
      _this.lastPrice,
      _this.lastUpdatedTimestamp,
      _this.priceProvider,
      _this.change24h,
      _this.change24hProvider,
      _this.volume24h,
      _this.volumeProvider,
    );
  }

  @override
  String toString() {
    final _this = this as AssetMarketInformation;
    return 'AssetMarketInformation(ticker: ${_this.ticker}, lastPrice: ${_this.lastPrice}, lastUpdatedTimestamp: ${_this.lastUpdatedTimestamp}, priceProvider: ${_this.priceProvider}, change24h: ${_this.change24h}, change24hProvider: ${_this.change24hProvider}, volume24h: ${_this.volume24h}, volumeProvider: ${_this.volumeProvider})';
  }
}

/// @nodoc
abstract mixin class $AssetMarketInformationCopyWith<$Res> {
  factory $AssetMarketInformationCopyWith(
    AssetMarketInformation value,
    $Res Function(AssetMarketInformation) _then,
  ) = _$AssetMarketInformationCopyWithImpl;
  @useResult
  $Res call({
    String ticker,
    @DecimalConverter() Decimal lastPrice,
    @TimestampConverter() DateTime? lastUpdatedTimestamp,
    @CexDataProviderConverter() CexDataProvider? priceProvider,
    @JsonKey(name: 'change_24h') @DecimalConverter() Decimal? change24h,
    @JsonKey(name: 'change_24h_provider')
    @CexDataProviderConverter()
    CexDataProvider? change24hProvider,
    @DecimalConverter() Decimal? volume24h,
    @CexDataProviderConverter() CexDataProvider? volumeProvider,
  });
}

/// @nodoc
class _$AssetMarketInformationCopyWithImpl<$Res>
    implements $AssetMarketInformationCopyWith<$Res> {
  _$AssetMarketInformationCopyWithImpl(this._self, this._then);

  final AssetMarketInformation _self;
  final $Res Function(AssetMarketInformation) _then;

  /// Create a copy of AssetMarketInformation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ticker = null,
    Object? lastPrice = null,
    Object? lastUpdatedTimestamp = freezed,
    Object? priceProvider = freezed,
    Object? change24h = freezed,
    Object? change24hProvider = freezed,
    Object? volume24h = freezed,
    Object? volumeProvider = freezed,
  }) {
    return _then(
      AssetMarketInformation(
        ticker: null == ticker
            ? _self.ticker
            : ticker // ignore: cast_nullable_to_non_nullable
                  as String,
        lastPrice: null == lastPrice
            ? _self.lastPrice
            : lastPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lastUpdatedTimestamp: freezed == lastUpdatedTimestamp
            ? _self.lastUpdatedTimestamp
            : lastUpdatedTimestamp // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        priceProvider: freezed == priceProvider
            ? _self.priceProvider
            : priceProvider // ignore: cast_nullable_to_non_nullable
                  as CexDataProvider?,
        change24h: freezed == change24h
            ? _self.change24h
            : change24h // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        change24hProvider: freezed == change24hProvider
            ? _self.change24hProvider
            : change24hProvider // ignore: cast_nullable_to_non_nullable
                  as CexDataProvider?,
        volume24h: freezed == volume24h
            ? _self.volume24h
            : volume24h // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        volumeProvider: freezed == volumeProvider
            ? _self.volumeProvider
            : volumeProvider // ignore: cast_nullable_to_non_nullable
                  as CexDataProvider?,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [AssetMarketInformation].
extension AssetMarketInformationPatterns on AssetMarketInformation {
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
    TResult Function(_AssetMarketInformation value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AssetMarketInformation() when $default != null:
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
    TResult Function(_AssetMarketInformation value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetMarketInformation():
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
    TResult? Function(_AssetMarketInformation value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetMarketInformation() when $default != null:
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
      String ticker,
      @DecimalConverter() Decimal lastPrice,
      @TimestampConverter() DateTime? lastUpdatedTimestamp,
      @CexDataProviderConverter() CexDataProvider? priceProvider,
      @JsonKey(name: 'change_24h') @DecimalConverter() Decimal? change24h,
      @JsonKey(name: 'change_24h_provider')
      @CexDataProviderConverter()
      CexDataProvider? change24hProvider,
      @DecimalConverter() Decimal? volume24h,
      @CexDataProviderConverter() CexDataProvider? volumeProvider,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AssetMarketInformation() when $default != null:
        return $default(
          _that.ticker,
          _that.lastPrice,
          _that.lastUpdatedTimestamp,
          _that.priceProvider,
          _that.change24h,
          _that.change24hProvider,
          _that.volume24h,
          _that.volumeProvider,
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
      String ticker,
      @DecimalConverter() Decimal lastPrice,
      @TimestampConverter() DateTime? lastUpdatedTimestamp,
      @CexDataProviderConverter() CexDataProvider? priceProvider,
      @JsonKey(name: 'change_24h') @DecimalConverter() Decimal? change24h,
      @JsonKey(name: 'change_24h_provider')
      @CexDataProviderConverter()
      CexDataProvider? change24hProvider,
      @DecimalConverter() Decimal? volume24h,
      @CexDataProviderConverter() CexDataProvider? volumeProvider,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetMarketInformation():
        return $default(
          _that.ticker,
          _that.lastPrice,
          _that.lastUpdatedTimestamp,
          _that.priceProvider,
          _that.change24h,
          _that.change24hProvider,
          _that.volume24h,
          _that.volumeProvider,
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
      String ticker,
      @DecimalConverter() Decimal lastPrice,
      @TimestampConverter() DateTime? lastUpdatedTimestamp,
      @CexDataProviderConverter() CexDataProvider? priceProvider,
      @JsonKey(name: 'change_24h') @DecimalConverter() Decimal? change24h,
      @JsonKey(name: 'change_24h_provider')
      @CexDataProviderConverter()
      CexDataProvider? change24hProvider,
      @DecimalConverter() Decimal? volume24h,
      @CexDataProviderConverter() CexDataProvider? volumeProvider,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetMarketInformation() when $default != null:
        return $default(
          _that.ticker,
          _that.lastPrice,
          _that.lastUpdatedTimestamp,
          _that.priceProvider,
          _that.change24h,
          _that.change24hProvider,
          _that.volume24h,
          _that.volumeProvider,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _AssetMarketInformation implements AssetMarketInformation {
  const _AssetMarketInformation({
    required this.ticker,
    @DecimalConverter() required this.lastPrice,
    @TimestampConverter() this.lastUpdatedTimestamp,
    @CexDataProviderConverter() this.priceProvider,
    @JsonKey(name: 'change_24h') @DecimalConverter() this.change24h,
    @JsonKey(name: 'change_24h_provider')
    @CexDataProviderConverter()
    this.change24hProvider,
    @DecimalConverter() this.volume24h,
    @CexDataProviderConverter() this.volumeProvider,
  });
  factory _AssetMarketInformation.fromJson(Map<String, dynamic> json) =>
      _$AssetMarketInformationFromJson(json);

  @override
  final String ticker;
  @override
  @DecimalConverter()
  final Decimal lastPrice;
  @override
  @TimestampConverter()
  final DateTime? lastUpdatedTimestamp;
  @override
  @CexDataProviderConverter()
  final CexDataProvider? priceProvider;
  @override
  @JsonKey(name: 'change_24h')
  @DecimalConverter()
  final Decimal? change24h;
  @override
  @JsonKey(name: 'change_24h_provider')
  @CexDataProviderConverter()
  final CexDataProvider? change24hProvider;
  @override
  @DecimalConverter()
  final Decimal? volume24h;
  @override
  @CexDataProviderConverter()
  final CexDataProvider? volumeProvider;

  /// Create a copy of AssetMarketInformation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AssetMarketInformationCopyWith<_AssetMarketInformation> get copyWith =>
      __$AssetMarketInformationCopyWithImpl<_AssetMarketInformation>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$AssetMarketInformationToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AssetMarketInformation &&
            (identical(other.ticker, ticker) || other.ticker == ticker) &&
            (identical(other.lastPrice, lastPrice) ||
                other.lastPrice == lastPrice) &&
            (identical(other.lastUpdatedTimestamp, lastUpdatedTimestamp) ||
                other.lastUpdatedTimestamp == lastUpdatedTimestamp) &&
            (identical(other.priceProvider, priceProvider) ||
                other.priceProvider == priceProvider) &&
            (identical(other.change24h, change24h) ||
                other.change24h == change24h) &&
            (identical(other.change24hProvider, change24hProvider) ||
                other.change24hProvider == change24hProvider) &&
            (identical(other.volume24h, volume24h) ||
                other.volume24h == volume24h) &&
            (identical(other.volumeProvider, volumeProvider) ||
                other.volumeProvider == volumeProvider));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      ticker,
      lastPrice,
      lastUpdatedTimestamp,
      priceProvider,
      change24h,
      change24hProvider,
      volume24h,
      volumeProvider,
    );
  }

  @override
  String toString() {
    return 'AssetMarketInformation(ticker: $ticker, lastPrice: $lastPrice, lastUpdatedTimestamp: $lastUpdatedTimestamp, priceProvider: $priceProvider, change24h: $change24h, change24hProvider: $change24hProvider, volume24h: $volume24h, volumeProvider: $volumeProvider)';
  }
}

/// @nodoc
abstract mixin class _$AssetMarketInformationCopyWith<$Res>
    implements $AssetMarketInformationCopyWith<$Res> {
  factory _$AssetMarketInformationCopyWith(
    _AssetMarketInformation value,
    $Res Function(_AssetMarketInformation) _then,
  ) = __$AssetMarketInformationCopyWithImpl;
  @override
  @useResult
  $Res call({
    String ticker,
    @DecimalConverter() Decimal lastPrice,
    @TimestampConverter() DateTime? lastUpdatedTimestamp,
    @CexDataProviderConverter() CexDataProvider? priceProvider,
    @JsonKey(name: 'change_24h') @DecimalConverter() Decimal? change24h,
    @JsonKey(name: 'change_24h_provider')
    @CexDataProviderConverter()
    CexDataProvider? change24hProvider,
    @DecimalConverter() Decimal? volume24h,
    @CexDataProviderConverter() CexDataProvider? volumeProvider,
  });
}

/// @nodoc
class __$AssetMarketInformationCopyWithImpl<$Res>
    implements _$AssetMarketInformationCopyWith<$Res> {
  __$AssetMarketInformationCopyWithImpl(this._self, this._then);

  final _AssetMarketInformation _self;
  final $Res Function(_AssetMarketInformation) _then;

  /// Create a copy of AssetMarketInformation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? ticker = null,
    Object? lastPrice = null,
    Object? lastUpdatedTimestamp = freezed,
    Object? priceProvider = freezed,
    Object? change24h = freezed,
    Object? change24hProvider = freezed,
    Object? volume24h = freezed,
    Object? volumeProvider = freezed,
  }) {
    return _then(
      _AssetMarketInformation(
        ticker: null == ticker
            ? _self.ticker
            : ticker // ignore: cast_nullable_to_non_nullable
                  as String,
        lastPrice: null == lastPrice
            ? _self.lastPrice
            : lastPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        lastUpdatedTimestamp: freezed == lastUpdatedTimestamp
            ? _self.lastUpdatedTimestamp
            : lastUpdatedTimestamp // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        priceProvider: freezed == priceProvider
            ? _self.priceProvider
            : priceProvider // ignore: cast_nullable_to_non_nullable
                  as CexDataProvider?,
        change24h: freezed == change24h
            ? _self.change24h
            : change24h // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        change24hProvider: freezed == change24hProvider
            ? _self.change24hProvider
            : change24hProvider // ignore: cast_nullable_to_non_nullable
                  as CexDataProvider?,
        volume24h: freezed == volume24h
            ? _self.volume24h
            : volume24h // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        volumeProvider: freezed == volumeProvider
            ? _self.volumeProvider
            : volumeProvider // ignore: cast_nullable_to_non_nullable
                  as CexDataProvider?,
      ),
    );
  }
}
