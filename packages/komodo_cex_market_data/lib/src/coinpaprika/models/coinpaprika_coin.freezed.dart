// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'coinpaprika_coin.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CoinPaprikaCoin {
  /// Unique identifier for the coin (e.g., "btc-bitcoin")
  String get id;

  /// Full name of the coin (e.g., "Bitcoin")
  String get name;

  /// Symbol/ticker of the coin (e.g., "BTC")
  String get symbol;

  /// Market ranking of the coin
  int get rank;

  /// Whether this is a new coin (added within last 5 days)
  bool get isNew;

  /// Whether this coin is currently active
  bool get isActive;

  /// Type of cryptocurrency ("coin" or "token")
  String get type;

  /// Create a copy of CoinPaprikaCoin
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CoinPaprikaCoinCopyWith<CoinPaprikaCoin> get copyWith =>
      _$CoinPaprikaCoinCopyWithImpl<CoinPaprikaCoin>(
        this as CoinPaprikaCoin,
        _$identity,
      );

  /// Serializes this CoinPaprikaCoin to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as CoinPaprikaCoin;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CoinPaprikaCoin &&
            (identical(other.id, _this.id) || other.id == _this.id) &&
            (identical(other.name, _this.name) || other.name == _this.name) &&
            (identical(other.symbol, _this.symbol) ||
                other.symbol == _this.symbol) &&
            (identical(other.rank, _this.rank) || other.rank == _this.rank) &&
            (identical(other.isNew, _this.isNew) ||
                other.isNew == _this.isNew) &&
            (identical(other.isActive, _this.isActive) ||
                other.isActive == _this.isActive) &&
            (identical(other.type, _this.type) || other.type == _this.type));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as CoinPaprikaCoin;
    return Object.hash(
      runtimeType,
      _this.id,
      _this.name,
      _this.symbol,
      _this.rank,
      _this.isNew,
      _this.isActive,
      _this.type,
    );
  }

  @override
  String toString() {
    final _this = this as CoinPaprikaCoin;
    return 'CoinPaprikaCoin(id: ${_this.id}, name: ${_this.name}, symbol: ${_this.symbol}, rank: ${_this.rank}, isNew: ${_this.isNew}, isActive: ${_this.isActive}, type: ${_this.type})';
  }
}

/// @nodoc
abstract mixin class $CoinPaprikaCoinCopyWith<$Res> {
  factory $CoinPaprikaCoinCopyWith(
    CoinPaprikaCoin value,
    $Res Function(CoinPaprikaCoin) _then,
  ) = _$CoinPaprikaCoinCopyWithImpl;
  @useResult
  $Res call({
    String id,
    String name,
    String symbol,
    int rank,
    bool isNew,
    bool isActive,
    String type,
  });
}

/// @nodoc
class _$CoinPaprikaCoinCopyWithImpl<$Res>
    implements $CoinPaprikaCoinCopyWith<$Res> {
  _$CoinPaprikaCoinCopyWithImpl(this._self, this._then);

  final CoinPaprikaCoin _self;
  final $Res Function(CoinPaprikaCoin) _then;

  /// Create a copy of CoinPaprikaCoin
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? symbol = null,
    Object? rank = null,
    Object? isNew = null,
    Object? isActive = null,
    Object? type = null,
  }) {
    return _then(
      CoinPaprikaCoin(
        id: null == id
            ? _self.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _self.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        rank: null == rank
            ? _self.rank
            : rank // ignore: cast_nullable_to_non_nullable
                  as int,
        isNew: null == isNew
            ? _self.isNew
            : isNew // ignore: cast_nullable_to_non_nullable
                  as bool,
        isActive: null == isActive
            ? _self.isActive
            : isActive // ignore: cast_nullable_to_non_nullable
                  as bool,
        type: null == type
            ? _self.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [CoinPaprikaCoin].
extension CoinPaprikaCoinPatterns on CoinPaprikaCoin {
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
    TResult Function(_CoinPaprikaCoin value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _CoinPaprikaCoin() when $default != null:
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
    TResult Function(_CoinPaprikaCoin value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _CoinPaprikaCoin():
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
    TResult? Function(_CoinPaprikaCoin value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _CoinPaprikaCoin() when $default != null:
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
      String id,
      String name,
      String symbol,
      int rank,
      bool isNew,
      bool isActive,
      String type,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _CoinPaprikaCoin() when $default != null:
        return $default(
          _that.id,
          _that.name,
          _that.symbol,
          _that.rank,
          _that.isNew,
          _that.isActive,
          _that.type,
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
      String id,
      String name,
      String symbol,
      int rank,
      bool isNew,
      bool isActive,
      String type,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _CoinPaprikaCoin():
        return $default(
          _that.id,
          _that.name,
          _that.symbol,
          _that.rank,
          _that.isNew,
          _that.isActive,
          _that.type,
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
      String id,
      String name,
      String symbol,
      int rank,
      bool isNew,
      bool isActive,
      String type,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _CoinPaprikaCoin() when $default != null:
        return $default(
          _that.id,
          _that.name,
          _that.symbol,
          _that.rank,
          _that.isNew,
          _that.isActive,
          _that.type,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _CoinPaprikaCoin implements CoinPaprikaCoin {
  const _CoinPaprikaCoin({
    required this.id,
    required this.name,
    required this.symbol,
    required this.rank,
    required this.isNew,
    required this.isActive,
    required this.type,
  });
  factory _CoinPaprikaCoin.fromJson(Map<String, dynamic> json) =>
      _$CoinPaprikaCoinFromJson(json);

  /// Unique identifier for the coin (e.g., "btc-bitcoin")
  @override
  final String id;

  /// Full name of the coin (e.g., "Bitcoin")
  @override
  final String name;

  /// Symbol/ticker of the coin (e.g., "BTC")
  @override
  final String symbol;

  /// Market ranking of the coin
  @override
  final int rank;

  /// Whether this is a new coin (added within last 5 days)
  @override
  final bool isNew;

  /// Whether this coin is currently active
  @override
  final bool isActive;

  /// Type of cryptocurrency ("coin" or "token")
  @override
  final String type;

  /// Create a copy of CoinPaprikaCoin
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$CoinPaprikaCoinCopyWith<_CoinPaprikaCoin> get copyWith =>
      __$CoinPaprikaCoinCopyWithImpl<_CoinPaprikaCoin>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$CoinPaprikaCoinToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _CoinPaprikaCoin &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.rank, rank) || other.rank == rank) &&
            (identical(other.isNew, isNew) || other.isNew == isNew) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.type, type) || other.type == type));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      id,
      name,
      symbol,
      rank,
      isNew,
      isActive,
      type,
    );
  }

  @override
  String toString() {
    return 'CoinPaprikaCoin(id: $id, name: $name, symbol: $symbol, rank: $rank, isNew: $isNew, isActive: $isActive, type: $type)';
  }
}

/// @nodoc
abstract mixin class _$CoinPaprikaCoinCopyWith<$Res>
    implements $CoinPaprikaCoinCopyWith<$Res> {
  factory _$CoinPaprikaCoinCopyWith(
    _CoinPaprikaCoin value,
    $Res Function(_CoinPaprikaCoin) _then,
  ) = __$CoinPaprikaCoinCopyWithImpl;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String symbol,
    int rank,
    bool isNew,
    bool isActive,
    String type,
  });
}

/// @nodoc
class __$CoinPaprikaCoinCopyWithImpl<$Res>
    implements _$CoinPaprikaCoinCopyWith<$Res> {
  __$CoinPaprikaCoinCopyWithImpl(this._self, this._then);

  final _CoinPaprikaCoin _self;
  final $Res Function(_CoinPaprikaCoin) _then;

  /// Create a copy of CoinPaprikaCoin
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? symbol = null,
    Object? rank = null,
    Object? isNew = null,
    Object? isActive = null,
    Object? type = null,
  }) {
    return _then(
      _CoinPaprikaCoin(
        id: null == id
            ? _self.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _self.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        symbol: null == symbol
            ? _self.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        rank: null == rank
            ? _self.rank
            : rank // ignore: cast_nullable_to_non_nullable
                  as int,
        isNew: null == isNew
            ? _self.isNew
            : isNew // ignore: cast_nullable_to_non_nullable
                  as bool,
        isActive: null == isActive
            ? _self.isActive
            : isActive // ignore: cast_nullable_to_non_nullable
                  as bool,
        type: null == type
            ? _self.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}
