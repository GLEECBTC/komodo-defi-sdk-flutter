// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'build_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BuildConfig {
  ApiBuildUpdateConfig get api;
  AssetRuntimeUpdateConfig get coins;

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $BuildConfigCopyWith<BuildConfig> get copyWith =>
      _$BuildConfigCopyWithImpl<BuildConfig>(this as BuildConfig, _$identity);

  /// Serializes this BuildConfig to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as BuildConfig;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is BuildConfig &&
            (identical(other.api, _this.api) || other.api == _this.api) &&
            (identical(other.coins, _this.coins) ||
                other.coins == _this.coins));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as BuildConfig;
    return Object.hash(runtimeType, _this.api, _this.coins);
  }

  @override
  String toString() {
    final _this = this as BuildConfig;
    return 'BuildConfig(api: ${_this.api}, coins: ${_this.coins})';
  }
}

/// @nodoc
abstract mixin class $BuildConfigCopyWith<$Res> {
  factory $BuildConfigCopyWith(
    BuildConfig value,
    $Res Function(BuildConfig) _then,
  ) = _$BuildConfigCopyWithImpl;
  @useResult
  $Res call({ApiBuildUpdateConfig api, AssetRuntimeUpdateConfig coins});

  $ApiBuildUpdateConfigCopyWith<$Res> get api;
  $AssetRuntimeUpdateConfigCopyWith<$Res> get coins;
}

/// @nodoc
class _$BuildConfigCopyWithImpl<$Res> implements $BuildConfigCopyWith<$Res> {
  _$BuildConfigCopyWithImpl(this._self, this._then);

  final BuildConfig _self;
  final $Res Function(BuildConfig) _then;

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? api = null, Object? coins = null}) {
    return _then(
      BuildConfig(
        api: null == api
            ? _self.api
            : api // ignore: cast_nullable_to_non_nullable
                  as ApiBuildUpdateConfig,
        coins: null == coins
            ? _self.coins
            : coins // ignore: cast_nullable_to_non_nullable
                  as AssetRuntimeUpdateConfig,
      ),
    );
  }

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ApiBuildUpdateConfigCopyWith<$Res> get api {
    return $ApiBuildUpdateConfigCopyWith<$Res>(_self.api, (value) {
      return _then(_self.copyWith(api: value));
    });
  }

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $AssetRuntimeUpdateConfigCopyWith<$Res> get coins {
    return $AssetRuntimeUpdateConfigCopyWith<$Res>(_self.coins, (value) {
      return _then(_self.copyWith(coins: value));
    });
  }
}

/// Adds pattern-matching-related methods to [BuildConfig].
extension BuildConfigPatterns on BuildConfig {
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
    TResult Function(_BuildConfig value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _BuildConfig() when $default != null:
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
    TResult Function(_BuildConfig value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BuildConfig():
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
    TResult? Function(_BuildConfig value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BuildConfig() when $default != null:
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
    TResult Function(ApiBuildUpdateConfig api, AssetRuntimeUpdateConfig coins)?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _BuildConfig() when $default != null:
        return $default(_that.api, _that.coins);
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
    TResult Function(ApiBuildUpdateConfig api, AssetRuntimeUpdateConfig coins)
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BuildConfig():
        return $default(_that.api, _that.coins);
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
    TResult? Function(ApiBuildUpdateConfig api, AssetRuntimeUpdateConfig coins)?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BuildConfig() when $default != null:
        return $default(_that.api, _that.coins);
      case _:
        return null;
    }
  }
}

/// @nodoc

@JsonSerializable(explicitToJson: true, fieldRename: FieldRename.snake)
class _BuildConfig implements BuildConfig {
  const _BuildConfig({required this.api, required this.coins});
  factory _BuildConfig.fromJson(Map<String, dynamic> json) =>
      _$BuildConfigFromJson(json);

  @override
  final ApiBuildUpdateConfig api;
  @override
  final AssetRuntimeUpdateConfig coins;

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$BuildConfigCopyWith<_BuildConfig> get copyWith =>
      __$BuildConfigCopyWithImpl<_BuildConfig>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$BuildConfigToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _BuildConfig &&
            (identical(other.api, api) || other.api == api) &&
            (identical(other.coins, coins) || other.coins == coins));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, api, coins);
  }

  @override
  String toString() {
    return 'BuildConfig(api: $api, coins: $coins)';
  }
}

/// @nodoc
abstract mixin class _$BuildConfigCopyWith<$Res>
    implements $BuildConfigCopyWith<$Res> {
  factory _$BuildConfigCopyWith(
    _BuildConfig value,
    $Res Function(_BuildConfig) _then,
  ) = __$BuildConfigCopyWithImpl;
  @override
  @useResult
  $Res call({ApiBuildUpdateConfig api, AssetRuntimeUpdateConfig coins});

  @override
  $ApiBuildUpdateConfigCopyWith<$Res> get api;
  @override
  $AssetRuntimeUpdateConfigCopyWith<$Res> get coins;
}

/// @nodoc
class __$BuildConfigCopyWithImpl<$Res> implements _$BuildConfigCopyWith<$Res> {
  __$BuildConfigCopyWithImpl(this._self, this._then);

  final _BuildConfig _self;
  final $Res Function(_BuildConfig) _then;

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({Object? api = null, Object? coins = null}) {
    return _then(
      _BuildConfig(
        api: null == api
            ? _self.api
            : api // ignore: cast_nullable_to_non_nullable
                  as ApiBuildUpdateConfig,
        coins: null == coins
            ? _self.coins
            : coins // ignore: cast_nullable_to_non_nullable
                  as AssetRuntimeUpdateConfig,
      ),
    );
  }

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ApiBuildUpdateConfigCopyWith<$Res> get api {
    return $ApiBuildUpdateConfigCopyWith<$Res>(_self.api, (value) {
      return _then(_self.copyWith(api: value));
    });
  }

  /// Create a copy of BuildConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $AssetRuntimeUpdateConfigCopyWith<$Res> get coins {
    return $AssetRuntimeUpdateConfigCopyWith<$Res>(_self.coins, (value) {
      return _then(_self.copyWith(coins: value));
    });
  }
}
