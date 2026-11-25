// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quote_currency.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;
QuoteCurrency _$QuoteCurrencyFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'fiat':
      return FiatQuoteCurrency.fromJson(json);
    case 'stablecoin':
      return StablecoinQuoteCurrency.fromJson(json);
    case 'crypto':
      return CryptocurrencyQuoteCurrency.fromJson(json);
    case 'commodity':
      return CommodityQuoteCurrency.fromJson(json);

    default:
      throw CheckedFromJsonException(
        json,
        'runtimeType',
        'QuoteCurrency',
        'Invalid union type "${json['runtimeType']}"!',
      );
  }
}

/// @nodoc
mixin _$QuoteCurrency {
  String get symbol;
  String get displayName;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $QuoteCurrencyCopyWith<QuoteCurrency> get copyWith =>
      _$QuoteCurrencyCopyWithImpl<QuoteCurrency>(
        this as QuoteCurrency,
        _$identity,
      );

  /// Serializes this QuoteCurrency to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as QuoteCurrency;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is QuoteCurrency &&
            (identical(other.symbol, _this.symbol) ||
                other.symbol == _this.symbol) &&
            (identical(other.displayName, _this.displayName) ||
                other.displayName == _this.displayName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as QuoteCurrency;
    return Object.hash(runtimeType, _this.symbol, _this.displayName);
  }
}

/// @nodoc
abstract mixin class $QuoteCurrencyCopyWith<$Res> {
  factory $QuoteCurrencyCopyWith(
    QuoteCurrency value,
    $Res Function(QuoteCurrency) _then,
  ) = _$QuoteCurrencyCopyWithImpl;
  @useResult
  $Res call({String symbol, String displayName});
}

/// @nodoc
class _$QuoteCurrencyCopyWithImpl<$Res>
    implements $QuoteCurrencyCopyWith<$Res> {
  _$QuoteCurrencyCopyWithImpl(this._self, this._then);

  final QuoteCurrency _self;
  final $Res Function(QuoteCurrency) _then;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? symbol = null, Object? displayName = null}) {
    return _then(
      _self.copyWith(
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        displayName: null == displayName
            ? _self.displayName
            : displayName // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [QuoteCurrency].
extension QuoteCurrencyPatterns on QuoteCurrency {
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
    TResult Function(FiatQuoteCurrency value)? fiat,
    TResult Function(StablecoinQuoteCurrency value)? stablecoin,
    TResult Function(CryptocurrencyQuoteCurrency value)? crypto,
    TResult Function(CommodityQuoteCurrency value)? commodity,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case FiatQuoteCurrency() when fiat != null:
        return fiat(_that);
      case StablecoinQuoteCurrency() when stablecoin != null:
        return stablecoin(_that);
      case CryptocurrencyQuoteCurrency() when crypto != null:
        return crypto(_that);
      case CommodityQuoteCurrency() when commodity != null:
        return commodity(_that);
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
    required TResult Function(FiatQuoteCurrency value) fiat,
    required TResult Function(StablecoinQuoteCurrency value) stablecoin,
    required TResult Function(CryptocurrencyQuoteCurrency value) crypto,
    required TResult Function(CommodityQuoteCurrency value) commodity,
  }) {
    final _that = this;
    switch (_that) {
      case FiatQuoteCurrency():
        return fiat(_that);
      case StablecoinQuoteCurrency():
        return stablecoin(_that);
      case CryptocurrencyQuoteCurrency():
        return crypto(_that);
      case CommodityQuoteCurrency():
        return commodity(_that);
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
    TResult? Function(FiatQuoteCurrency value)? fiat,
    TResult? Function(StablecoinQuoteCurrency value)? stablecoin,
    TResult? Function(CryptocurrencyQuoteCurrency value)? crypto,
    TResult? Function(CommodityQuoteCurrency value)? commodity,
  }) {
    final _that = this;
    switch (_that) {
      case FiatQuoteCurrency() when fiat != null:
        return fiat(_that);
      case StablecoinQuoteCurrency() when stablecoin != null:
        return stablecoin(_that);
      case CryptocurrencyQuoteCurrency() when crypto != null:
        return crypto(_that);
      case CommodityQuoteCurrency() when commodity != null:
        return commodity(_that);
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
    TResult Function(String symbol, String displayName)? fiat,
    TResult Function(
      String symbol,
      String displayName,
      FiatQuoteCurrency underlyingFiat,
    )?
    stablecoin,
    TResult Function(String symbol, String displayName)? crypto,
    TResult Function(String symbol, String displayName)? commodity,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case FiatQuoteCurrency() when fiat != null:
        return fiat(_that.symbol, _that.displayName);
      case StablecoinQuoteCurrency() when stablecoin != null:
        return stablecoin(
          _that.symbol,
          _that.displayName,
          _that.underlyingFiat,
        );
      case CryptocurrencyQuoteCurrency() when crypto != null:
        return crypto(_that.symbol, _that.displayName);
      case CommodityQuoteCurrency() when commodity != null:
        return commodity(_that.symbol, _that.displayName);
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
    required TResult Function(String symbol, String displayName) fiat,
    required TResult Function(
      String symbol,
      String displayName,
      FiatQuoteCurrency underlyingFiat,
    )
    stablecoin,
    required TResult Function(String symbol, String displayName) crypto,
    required TResult Function(String symbol, String displayName) commodity,
  }) {
    final _that = this;
    switch (_that) {
      case FiatQuoteCurrency():
        return fiat(_that.symbol, _that.displayName);
      case StablecoinQuoteCurrency():
        return stablecoin(
          _that.symbol,
          _that.displayName,
          _that.underlyingFiat,
        );
      case CryptocurrencyQuoteCurrency():
        return crypto(_that.symbol, _that.displayName);
      case CommodityQuoteCurrency():
        return commodity(_that.symbol, _that.displayName);
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
    TResult? Function(String symbol, String displayName)? fiat,
    TResult? Function(
      String symbol,
      String displayName,
      FiatQuoteCurrency underlyingFiat,
    )?
    stablecoin,
    TResult? Function(String symbol, String displayName)? crypto,
    TResult? Function(String symbol, String displayName)? commodity,
  }) {
    final _that = this;
    switch (_that) {
      case FiatQuoteCurrency() when fiat != null:
        return fiat(_that.symbol, _that.displayName);
      case StablecoinQuoteCurrency() when stablecoin != null:
        return stablecoin(
          _that.symbol,
          _that.displayName,
          _that.underlyingFiat,
        );
      case CryptocurrencyQuoteCurrency() when crypto != null:
        return crypto(_that.symbol, _that.displayName);
      case CommodityQuoteCurrency() when commodity != null:
        return commodity(_that.symbol, _that.displayName);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class FiatQuoteCurrency extends QuoteCurrency {
  const FiatQuoteCurrency({
    required this.symbol,
    required this.displayName,
    String? $type,
  }) : $type = $type ?? 'fiat',
       super._();
  factory FiatQuoteCurrency.fromJson(Map<String, dynamic> json) =>
      _$FiatQuoteCurrencyFromJson(json);

  @override
  final String symbol;
  @override
  final String displayName;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $FiatQuoteCurrencyCopyWith<FiatQuoteCurrency> get copyWith =>
      _$FiatQuoteCurrencyCopyWithImpl<FiatQuoteCurrency>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$FiatQuoteCurrencyToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is FiatQuoteCurrency &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, symbol, displayName);
  }
}

/// @nodoc
abstract mixin class $FiatQuoteCurrencyCopyWith<$Res>
    implements $QuoteCurrencyCopyWith<$Res> {
  factory $FiatQuoteCurrencyCopyWith(
    FiatQuoteCurrency value,
    $Res Function(FiatQuoteCurrency) _then,
  ) = _$FiatQuoteCurrencyCopyWithImpl;
  @override
  @useResult
  $Res call({String symbol, String displayName});
}

/// @nodoc
class _$FiatQuoteCurrencyCopyWithImpl<$Res>
    implements $FiatQuoteCurrencyCopyWith<$Res> {
  _$FiatQuoteCurrencyCopyWithImpl(this._self, this._then);

  final FiatQuoteCurrency _self;
  final $Res Function(FiatQuoteCurrency) _then;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({Object? symbol = null, Object? displayName = null}) {
    return _then(
      FiatQuoteCurrency(
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        displayName: null == displayName
            ? _self.displayName
            : displayName // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class StablecoinQuoteCurrency extends QuoteCurrency {
  const StablecoinQuoteCurrency({
    required this.symbol,
    required this.displayName,
    required this.underlyingFiat,
    String? $type,
  }) : $type = $type ?? 'stablecoin',
       super._();
  factory StablecoinQuoteCurrency.fromJson(Map<String, dynamic> json) =>
      _$StablecoinQuoteCurrencyFromJson(json);

  @override
  final String symbol;
  @override
  final String displayName;
  final FiatQuoteCurrency underlyingFiat;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $StablecoinQuoteCurrencyCopyWith<StablecoinQuoteCurrency> get copyWith =>
      _$StablecoinQuoteCurrencyCopyWithImpl<StablecoinQuoteCurrency>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$StablecoinQuoteCurrencyToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is StablecoinQuoteCurrency &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            const DeepCollectionEquality().equals(
              other.underlyingFiat,
              underlyingFiat,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      symbol,
      displayName,
      const DeepCollectionEquality().hash(underlyingFiat),
    );
  }
}

/// @nodoc
abstract mixin class $StablecoinQuoteCurrencyCopyWith<$Res>
    implements $QuoteCurrencyCopyWith<$Res> {
  factory $StablecoinQuoteCurrencyCopyWith(
    StablecoinQuoteCurrency value,
    $Res Function(StablecoinQuoteCurrency) _then,
  ) = _$StablecoinQuoteCurrencyCopyWithImpl;
  @override
  @useResult
  $Res call({
    String symbol,
    String displayName,
    FiatQuoteCurrency underlyingFiat,
  });
}

/// @nodoc
class _$StablecoinQuoteCurrencyCopyWithImpl<$Res>
    implements $StablecoinQuoteCurrencyCopyWith<$Res> {
  _$StablecoinQuoteCurrencyCopyWithImpl(this._self, this._then);

  final StablecoinQuoteCurrency _self;
  final $Res Function(StablecoinQuoteCurrency) _then;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? symbol = null,
    Object? displayName = null,
    Object? underlyingFiat = freezed,
  }) {
    return _then(
      StablecoinQuoteCurrency(
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        displayName: null == displayName
            ? _self.displayName
            : displayName // ignore: cast_nullable_to_non_nullable
                  as String,
        underlyingFiat: freezed == underlyingFiat
            ? _self.underlyingFiat
            : underlyingFiat // ignore: cast_nullable_to_non_nullable
                  as FiatQuoteCurrency,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class CryptocurrencyQuoteCurrency extends QuoteCurrency {
  const CryptocurrencyQuoteCurrency({
    required this.symbol,
    required this.displayName,
    String? $type,
  }) : $type = $type ?? 'crypto',
       super._();
  factory CryptocurrencyQuoteCurrency.fromJson(Map<String, dynamic> json) =>
      _$CryptocurrencyQuoteCurrencyFromJson(json);

  @override
  final String symbol;
  @override
  final String displayName;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CryptocurrencyQuoteCurrencyCopyWith<CryptocurrencyQuoteCurrency>
  get copyWith =>
      _$CryptocurrencyQuoteCurrencyCopyWithImpl<CryptocurrencyQuoteCurrency>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$CryptocurrencyQuoteCurrencyToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CryptocurrencyQuoteCurrency &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, symbol, displayName);
  }
}

/// @nodoc
abstract mixin class $CryptocurrencyQuoteCurrencyCopyWith<$Res>
    implements $QuoteCurrencyCopyWith<$Res> {
  factory $CryptocurrencyQuoteCurrencyCopyWith(
    CryptocurrencyQuoteCurrency value,
    $Res Function(CryptocurrencyQuoteCurrency) _then,
  ) = _$CryptocurrencyQuoteCurrencyCopyWithImpl;
  @override
  @useResult
  $Res call({String symbol, String displayName});
}

/// @nodoc
class _$CryptocurrencyQuoteCurrencyCopyWithImpl<$Res>
    implements $CryptocurrencyQuoteCurrencyCopyWith<$Res> {
  _$CryptocurrencyQuoteCurrencyCopyWithImpl(this._self, this._then);

  final CryptocurrencyQuoteCurrency _self;
  final $Res Function(CryptocurrencyQuoteCurrency) _then;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({Object? symbol = null, Object? displayName = null}) {
    return _then(
      CryptocurrencyQuoteCurrency(
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        displayName: null == displayName
            ? _self.displayName
            : displayName // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class CommodityQuoteCurrency extends QuoteCurrency {
  const CommodityQuoteCurrency({
    required this.symbol,
    required this.displayName,
    String? $type,
  }) : $type = $type ?? 'commodity',
       super._();
  factory CommodityQuoteCurrency.fromJson(Map<String, dynamic> json) =>
      _$CommodityQuoteCurrencyFromJson(json);

  @override
  final String symbol;
  @override
  final String displayName;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CommodityQuoteCurrencyCopyWith<CommodityQuoteCurrency> get copyWith =>
      _$CommodityQuoteCurrencyCopyWithImpl<CommodityQuoteCurrency>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$CommodityQuoteCurrencyToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CommodityQuoteCurrency &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, symbol, displayName);
  }
}

/// @nodoc
abstract mixin class $CommodityQuoteCurrencyCopyWith<$Res>
    implements $QuoteCurrencyCopyWith<$Res> {
  factory $CommodityQuoteCurrencyCopyWith(
    CommodityQuoteCurrency value,
    $Res Function(CommodityQuoteCurrency) _then,
  ) = _$CommodityQuoteCurrencyCopyWithImpl;
  @override
  @useResult
  $Res call({String symbol, String displayName});
}

/// @nodoc
class _$CommodityQuoteCurrencyCopyWithImpl<$Res>
    implements $CommodityQuoteCurrencyCopyWith<$Res> {
  _$CommodityQuoteCurrencyCopyWithImpl(this._self, this._then);

  final CommodityQuoteCurrency _self;
  final $Res Function(CommodityQuoteCurrency) _then;

  /// Create a copy of QuoteCurrency
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({Object? symbol = null, Object? displayName = null}) {
    return _then(
      CommodityQuoteCurrency(
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        displayName: null == displayName
            ? _self.displayName
            : displayName // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}
