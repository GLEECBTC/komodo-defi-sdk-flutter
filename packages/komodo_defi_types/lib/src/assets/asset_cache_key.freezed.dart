// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'asset_cache_key.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AssetCacheKey {
  String get assetConfigId;
  String get chainId;
  String get subClass;
  String get protocolKey;
  Map<String, Object?> get customFields;

  /// Create a copy of AssetCacheKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AssetCacheKeyCopyWith<AssetCacheKey> get copyWith =>
      _$AssetCacheKeyCopyWithImpl<AssetCacheKey>(
        this as AssetCacheKey,
        _$identity,
      );

  /// Serializes this AssetCacheKey to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as AssetCacheKey;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AssetCacheKey &&
            (identical(other.assetConfigId, _this.assetConfigId) ||
                other.assetConfigId == _this.assetConfigId) &&
            (identical(other.chainId, _this.chainId) ||
                other.chainId == _this.chainId) &&
            (identical(other.subClass, _this.subClass) ||
                other.subClass == _this.subClass) &&
            (identical(other.protocolKey, _this.protocolKey) ||
                other.protocolKey == _this.protocolKey) &&
            const DeepCollectionEquality().equals(
              other.customFields,
              _this.customFields,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as AssetCacheKey;
    return Object.hash(
      runtimeType,
      _this.assetConfigId,
      _this.chainId,
      _this.subClass,
      _this.protocolKey,
      const DeepCollectionEquality().hash(_this.customFields),
    );
  }

  @override
  String toString() {
    final _this = this as AssetCacheKey;
    return 'AssetCacheKey(assetConfigId: ${_this.assetConfigId}, chainId: ${_this.chainId}, subClass: ${_this.subClass}, protocolKey: ${_this.protocolKey}, customFields: ${_this.customFields})';
  }
}

/// @nodoc
abstract mixin class $AssetCacheKeyCopyWith<$Res> {
  factory $AssetCacheKeyCopyWith(
    AssetCacheKey value,
    $Res Function(AssetCacheKey) _then,
  ) = _$AssetCacheKeyCopyWithImpl;
  @useResult
  $Res call({
    String assetConfigId,
    String chainId,
    String subClass,
    String protocolKey,
    Map<String, Object?> customFields,
  });
}

/// @nodoc
class _$AssetCacheKeyCopyWithImpl<$Res>
    implements $AssetCacheKeyCopyWith<$Res> {
  _$AssetCacheKeyCopyWithImpl(this._self, this._then);

  final AssetCacheKey _self;
  final $Res Function(AssetCacheKey) _then;

  /// Create a copy of AssetCacheKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? assetConfigId = null,
    Object? chainId = null,
    Object? subClass = null,
    Object? protocolKey = null,
    Object? customFields = null,
  }) {
    return _then(
      AssetCacheKey(
        assetConfigId: null == assetConfigId
            ? _self.assetConfigId
            : assetConfigId // ignore: cast_nullable_to_non_nullable
                  as String,
        chainId: null == chainId
            ? _self.chainId
            : chainId // ignore: cast_nullable_to_non_nullable
                  as String,
        subClass: null == subClass
            ? _self.subClass
            : subClass // ignore: cast_nullable_to_non_nullable
                  as String,
        protocolKey: null == protocolKey
            ? _self.protocolKey
            : protocolKey // ignore: cast_nullable_to_non_nullable
                  as String,
        customFields: null == customFields
            ? _self.customFields
            : customFields // ignore: cast_nullable_to_non_nullable
                  as Map<String, Object?>,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [AssetCacheKey].
extension AssetCacheKeyPatterns on AssetCacheKey {
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
    TResult Function(_AssetCacheKey value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AssetCacheKey() when $default != null:
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
    TResult Function(_AssetCacheKey value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetCacheKey():
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
    TResult? Function(_AssetCacheKey value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetCacheKey() when $default != null:
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
      String assetConfigId,
      String chainId,
      String subClass,
      String protocolKey,
      Map<String, Object?> customFields,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AssetCacheKey() when $default != null:
        return $default(
          _that.assetConfigId,
          _that.chainId,
          _that.subClass,
          _that.protocolKey,
          _that.customFields,
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
      String assetConfigId,
      String chainId,
      String subClass,
      String protocolKey,
      Map<String, Object?> customFields,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetCacheKey():
        return $default(
          _that.assetConfigId,
          _that.chainId,
          _that.subClass,
          _that.protocolKey,
          _that.customFields,
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
      String assetConfigId,
      String chainId,
      String subClass,
      String protocolKey,
      Map<String, Object?> customFields,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AssetCacheKey() when $default != null:
        return $default(
          _that.assetConfigId,
          _that.chainId,
          _that.subClass,
          _that.protocolKey,
          _that.customFields,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _AssetCacheKey implements AssetCacheKey {
  const _AssetCacheKey({
    required this.assetConfigId,
    required this.chainId,
    required this.subClass,
    required this.protocolKey,
    Map<String, Object?> customFields = const <String, Object?>{},
  }) : _customFields = customFields;
  factory _AssetCacheKey.fromJson(Map<String, dynamic> json) =>
      _$AssetCacheKeyFromJson(json);

  @override
  final String assetConfigId;
  @override
  final String chainId;
  @override
  final String subClass;
  @override
  final String protocolKey;
  final Map<String, Object?> _customFields;
  @override
  @JsonKey()
  Map<String, Object?> get customFields {
    if (_customFields is EqualUnmodifiableMapView) return _customFields;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_customFields);
  }

  /// Create a copy of AssetCacheKey
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AssetCacheKeyCopyWith<_AssetCacheKey> get copyWith =>
      __$AssetCacheKeyCopyWithImpl<_AssetCacheKey>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AssetCacheKeyToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AssetCacheKey &&
            (identical(other.assetConfigId, assetConfigId) ||
                other.assetConfigId == assetConfigId) &&
            (identical(other.chainId, chainId) || other.chainId == chainId) &&
            (identical(other.subClass, subClass) ||
                other.subClass == subClass) &&
            (identical(other.protocolKey, protocolKey) ||
                other.protocolKey == protocolKey) &&
            const DeepCollectionEquality().equals(
              other.customFields,
              _customFields,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      assetConfigId,
      chainId,
      subClass,
      protocolKey,
      const DeepCollectionEquality().hash(_customFields),
    );
  }

  @override
  String toString() {
    return 'AssetCacheKey(assetConfigId: $assetConfigId, chainId: $chainId, subClass: $subClass, protocolKey: $protocolKey, customFields: $customFields)';
  }
}

/// @nodoc
abstract mixin class _$AssetCacheKeyCopyWith<$Res>
    implements $AssetCacheKeyCopyWith<$Res> {
  factory _$AssetCacheKeyCopyWith(
    _AssetCacheKey value,
    $Res Function(_AssetCacheKey) _then,
  ) = __$AssetCacheKeyCopyWithImpl;
  @override
  @useResult
  $Res call({
    String assetConfigId,
    String chainId,
    String subClass,
    String protocolKey,
    Map<String, Object?> customFields,
  });
}

/// @nodoc
class __$AssetCacheKeyCopyWithImpl<$Res>
    implements _$AssetCacheKeyCopyWith<$Res> {
  __$AssetCacheKeyCopyWithImpl(this._self, this._then);

  final _AssetCacheKey _self;
  final $Res Function(_AssetCacheKey) _then;

  /// Create a copy of AssetCacheKey
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? assetConfigId = null,
    Object? chainId = null,
    Object? subClass = null,
    Object? protocolKey = null,
    Object? customFields = null,
  }) {
    return _then(
      _AssetCacheKey(
        assetConfigId: null == assetConfigId
            ? _self.assetConfigId
            : assetConfigId // ignore: cast_nullable_to_non_nullable
                  as String,
        chainId: null == chainId
            ? _self.chainId
            : chainId // ignore: cast_nullable_to_non_nullable
                  as String,
        subClass: null == subClass
            ? _self.subClass
            : subClass // ignore: cast_nullable_to_non_nullable
                  as String,
        protocolKey: null == protocolKey
            ? _self.protocolKey
            : protocolKey // ignore: cast_nullable_to_non_nullable
                  as String,
        customFields: null == customFields
            ? _self._customFields
            : customFields // ignore: cast_nullable_to_non_nullable
                  as Map<String, Object?>,
      ),
    );
  }
}
