// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api_build_update_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ApiPlatformConfig {
  String get matchingPattern;
  String get path;
  List<String> get validZipSha256Checksums;

  /// Create a copy of ApiPlatformConfig
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ApiPlatformConfigCopyWith<ApiPlatformConfig> get copyWith =>
      _$ApiPlatformConfigCopyWithImpl<ApiPlatformConfig>(
        this as ApiPlatformConfig,
        _$identity,
      );

  /// Serializes this ApiPlatformConfig to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as ApiPlatformConfig;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ApiPlatformConfig &&
            (identical(other.matchingPattern, _this.matchingPattern) ||
                other.matchingPattern == _this.matchingPattern) &&
            (identical(other.path, _this.path) || other.path == _this.path) &&
            const DeepCollectionEquality().equals(
              other.validZipSha256Checksums,
              _this.validZipSha256Checksums,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as ApiPlatformConfig;
    return Object.hash(
      runtimeType,
      _this.matchingPattern,
      _this.path,
      const DeepCollectionEquality().hash(_this.validZipSha256Checksums),
    );
  }

  @override
  String toString() {
    final _this = this as ApiPlatformConfig;
    return 'ApiPlatformConfig(matchingPattern: ${_this.matchingPattern}, path: ${_this.path}, validZipSha256Checksums: ${_this.validZipSha256Checksums})';
  }
}

/// @nodoc
abstract mixin class $ApiPlatformConfigCopyWith<$Res> {
  factory $ApiPlatformConfigCopyWith(
    ApiPlatformConfig value,
    $Res Function(ApiPlatformConfig) _then,
  ) = _$ApiPlatformConfigCopyWithImpl;
  @useResult
  $Res call({
    String matchingPattern,
    String path,
    List<String> validZipSha256Checksums,
  });
}

/// @nodoc
class _$ApiPlatformConfigCopyWithImpl<$Res>
    implements $ApiPlatformConfigCopyWith<$Res> {
  _$ApiPlatformConfigCopyWithImpl(this._self, this._then);

  final ApiPlatformConfig _self;
  final $Res Function(ApiPlatformConfig) _then;

  /// Create a copy of ApiPlatformConfig
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? matchingPattern = null,
    Object? path = null,
    Object? validZipSha256Checksums = null,
  }) {
    return _then(
      ApiPlatformConfig(
        matchingPattern: null == matchingPattern
            ? _self.matchingPattern
            : matchingPattern // ignore: cast_nullable_to_non_nullable
                  as String,
        path: null == path
            ? _self.path
            : path // ignore: cast_nullable_to_non_nullable
                  as String,
        validZipSha256Checksums: null == validZipSha256Checksums
            ? _self.validZipSha256Checksums
            : validZipSha256Checksums // ignore: cast_nullable_to_non_nullable
                  as List<String>,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [ApiPlatformConfig].
extension ApiPlatformConfigPatterns on ApiPlatformConfig {
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
    TResult Function(_ApiPlatformConfig value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ApiPlatformConfig() when $default != null:
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
    TResult Function(_ApiPlatformConfig value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiPlatformConfig():
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
    TResult? Function(_ApiPlatformConfig value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiPlatformConfig() when $default != null:
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
      String matchingPattern,
      String path,
      List<String> validZipSha256Checksums,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ApiPlatformConfig() when $default != null:
        return $default(
          _that.matchingPattern,
          _that.path,
          _that.validZipSha256Checksums,
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
      String matchingPattern,
      String path,
      List<String> validZipSha256Checksums,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiPlatformConfig():
        return $default(
          _that.matchingPattern,
          _that.path,
          _that.validZipSha256Checksums,
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
      String matchingPattern,
      String path,
      List<String> validZipSha256Checksums,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiPlatformConfig() when $default != null:
        return $default(
          _that.matchingPattern,
          _that.path,
          _that.validZipSha256Checksums,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc

@JsonSerializable(explicitToJson: true, fieldRename: FieldRename.snake)
class _ApiPlatformConfig implements ApiPlatformConfig {
  const _ApiPlatformConfig({
    required this.matchingPattern,
    required this.path,
    List<String> validZipSha256Checksums = const <String>[],
  }) : _validZipSha256Checksums = validZipSha256Checksums;
  factory _ApiPlatformConfig.fromJson(Map<String, dynamic> json) =>
      _$ApiPlatformConfigFromJson(json);

  @override
  final String matchingPattern;
  @override
  final String path;
  final List<String> _validZipSha256Checksums;
  @override
  @JsonKey()
  List<String> get validZipSha256Checksums {
    if (_validZipSha256Checksums is EqualUnmodifiableListView)
      return _validZipSha256Checksums;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_validZipSha256Checksums);
  }

  /// Create a copy of ApiPlatformConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ApiPlatformConfigCopyWith<_ApiPlatformConfig> get copyWith =>
      __$ApiPlatformConfigCopyWithImpl<_ApiPlatformConfig>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ApiPlatformConfigToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ApiPlatformConfig &&
            (identical(other.matchingPattern, matchingPattern) ||
                other.matchingPattern == matchingPattern) &&
            (identical(other.path, path) || other.path == path) &&
            const DeepCollectionEquality().equals(
              other.validZipSha256Checksums,
              _validZipSha256Checksums,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      matchingPattern,
      path,
      const DeepCollectionEquality().hash(_validZipSha256Checksums),
    );
  }

  @override
  String toString() {
    return 'ApiPlatformConfig(matchingPattern: $matchingPattern, path: $path, validZipSha256Checksums: $validZipSha256Checksums)';
  }
}

/// @nodoc
abstract mixin class _$ApiPlatformConfigCopyWith<$Res>
    implements $ApiPlatformConfigCopyWith<$Res> {
  factory _$ApiPlatformConfigCopyWith(
    _ApiPlatformConfig value,
    $Res Function(_ApiPlatformConfig) _then,
  ) = __$ApiPlatformConfigCopyWithImpl;
  @override
  @useResult
  $Res call({
    String matchingPattern,
    String path,
    List<String> validZipSha256Checksums,
  });
}

/// @nodoc
class __$ApiPlatformConfigCopyWithImpl<$Res>
    implements _$ApiPlatformConfigCopyWith<$Res> {
  __$ApiPlatformConfigCopyWithImpl(this._self, this._then);

  final _ApiPlatformConfig _self;
  final $Res Function(_ApiPlatformConfig) _then;

  /// Create a copy of ApiPlatformConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? matchingPattern = null,
    Object? path = null,
    Object? validZipSha256Checksums = null,
  }) {
    return _then(
      _ApiPlatformConfig(
        matchingPattern: null == matchingPattern
            ? _self.matchingPattern
            : matchingPattern // ignore: cast_nullable_to_non_nullable
                  as String,
        path: null == path
            ? _self.path
            : path // ignore: cast_nullable_to_non_nullable
                  as String,
        validZipSha256Checksums: null == validZipSha256Checksums
            ? _self._validZipSha256Checksums
            : validZipSha256Checksums // ignore: cast_nullable_to_non_nullable
                  as List<String>,
      ),
    );
  }
}

/// @nodoc
mixin _$ApiBuildUpdateConfig {
  String get apiCommitHash;
  String get branch;
  bool get fetchAtBuildEnabled;
  bool get concurrentDownloadsEnabled;
  List<String> get sourceUrls;
  Map<String, ApiPlatformConfig> get platforms;

  /// Create a copy of ApiBuildUpdateConfig
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ApiBuildUpdateConfigCopyWith<ApiBuildUpdateConfig> get copyWith =>
      _$ApiBuildUpdateConfigCopyWithImpl<ApiBuildUpdateConfig>(
        this as ApiBuildUpdateConfig,
        _$identity,
      );

  /// Serializes this ApiBuildUpdateConfig to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as ApiBuildUpdateConfig;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ApiBuildUpdateConfig &&
            (identical(other.apiCommitHash, _this.apiCommitHash) ||
                other.apiCommitHash == _this.apiCommitHash) &&
            (identical(other.branch, _this.branch) ||
                other.branch == _this.branch) &&
            (identical(other.fetchAtBuildEnabled, _this.fetchAtBuildEnabled) ||
                other.fetchAtBuildEnabled == _this.fetchAtBuildEnabled) &&
            (identical(
                  other.concurrentDownloadsEnabled,
                  _this.concurrentDownloadsEnabled,
                ) ||
                other.concurrentDownloadsEnabled ==
                    _this.concurrentDownloadsEnabled) &&
            const DeepCollectionEquality().equals(
              other.sourceUrls,
              _this.sourceUrls,
            ) &&
            const DeepCollectionEquality().equals(
              other.platforms,
              _this.platforms,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as ApiBuildUpdateConfig;
    return Object.hash(
      runtimeType,
      _this.apiCommitHash,
      _this.branch,
      _this.fetchAtBuildEnabled,
      _this.concurrentDownloadsEnabled,
      const DeepCollectionEquality().hash(_this.sourceUrls),
      const DeepCollectionEquality().hash(_this.platforms),
    );
  }

  @override
  String toString() {
    final _this = this as ApiBuildUpdateConfig;
    return 'ApiBuildUpdateConfig(apiCommitHash: ${_this.apiCommitHash}, branch: ${_this.branch}, fetchAtBuildEnabled: ${_this.fetchAtBuildEnabled}, concurrentDownloadsEnabled: ${_this.concurrentDownloadsEnabled}, sourceUrls: ${_this.sourceUrls}, platforms: ${_this.platforms})';
  }
}

/// @nodoc
abstract mixin class $ApiBuildUpdateConfigCopyWith<$Res> {
  factory $ApiBuildUpdateConfigCopyWith(
    ApiBuildUpdateConfig value,
    $Res Function(ApiBuildUpdateConfig) _then,
  ) = _$ApiBuildUpdateConfigCopyWithImpl;
  @useResult
  $Res call({
    String apiCommitHash,
    String branch,
    bool fetchAtBuildEnabled,
    bool concurrentDownloadsEnabled,
    List<String> sourceUrls,
    Map<String, ApiPlatformConfig> platforms,
  });
}

/// @nodoc
class _$ApiBuildUpdateConfigCopyWithImpl<$Res>
    implements $ApiBuildUpdateConfigCopyWith<$Res> {
  _$ApiBuildUpdateConfigCopyWithImpl(this._self, this._then);

  final ApiBuildUpdateConfig _self;
  final $Res Function(ApiBuildUpdateConfig) _then;

  /// Create a copy of ApiBuildUpdateConfig
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? apiCommitHash = null,
    Object? branch = null,
    Object? fetchAtBuildEnabled = null,
    Object? concurrentDownloadsEnabled = null,
    Object? sourceUrls = null,
    Object? platforms = null,
  }) {
    return _then(
      ApiBuildUpdateConfig(
        apiCommitHash: null == apiCommitHash
            ? _self.apiCommitHash
            : apiCommitHash // ignore: cast_nullable_to_non_nullable
                  as String,
        branch: null == branch
            ? _self.branch
            : branch // ignore: cast_nullable_to_non_nullable
                  as String,
        fetchAtBuildEnabled: null == fetchAtBuildEnabled
            ? _self.fetchAtBuildEnabled
            : fetchAtBuildEnabled // ignore: cast_nullable_to_non_nullable
                  as bool,
        concurrentDownloadsEnabled: null == concurrentDownloadsEnabled
            ? _self.concurrentDownloadsEnabled
            : concurrentDownloadsEnabled // ignore: cast_nullable_to_non_nullable
                  as bool,
        sourceUrls: null == sourceUrls
            ? _self.sourceUrls
            : sourceUrls // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        platforms: null == platforms
            ? _self.platforms
            : platforms // ignore: cast_nullable_to_non_nullable
                  as Map<String, ApiPlatformConfig>,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [ApiBuildUpdateConfig].
extension ApiBuildUpdateConfigPatterns on ApiBuildUpdateConfig {
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
    TResult Function(_ApiBuildUpdateConfig value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ApiBuildUpdateConfig() when $default != null:
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
    TResult Function(_ApiBuildUpdateConfig value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiBuildUpdateConfig():
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
    TResult? Function(_ApiBuildUpdateConfig value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiBuildUpdateConfig() when $default != null:
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
      String apiCommitHash,
      String branch,
      bool fetchAtBuildEnabled,
      bool concurrentDownloadsEnabled,
      List<String> sourceUrls,
      Map<String, ApiPlatformConfig> platforms,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ApiBuildUpdateConfig() when $default != null:
        return $default(
          _that.apiCommitHash,
          _that.branch,
          _that.fetchAtBuildEnabled,
          _that.concurrentDownloadsEnabled,
          _that.sourceUrls,
          _that.platforms,
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
      String apiCommitHash,
      String branch,
      bool fetchAtBuildEnabled,
      bool concurrentDownloadsEnabled,
      List<String> sourceUrls,
      Map<String, ApiPlatformConfig> platforms,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiBuildUpdateConfig():
        return $default(
          _that.apiCommitHash,
          _that.branch,
          _that.fetchAtBuildEnabled,
          _that.concurrentDownloadsEnabled,
          _that.sourceUrls,
          _that.platforms,
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
      String apiCommitHash,
      String branch,
      bool fetchAtBuildEnabled,
      bool concurrentDownloadsEnabled,
      List<String> sourceUrls,
      Map<String, ApiPlatformConfig> platforms,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ApiBuildUpdateConfig() when $default != null:
        return $default(
          _that.apiCommitHash,
          _that.branch,
          _that.fetchAtBuildEnabled,
          _that.concurrentDownloadsEnabled,
          _that.sourceUrls,
          _that.platforms,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc

@JsonSerializable(explicitToJson: true, fieldRename: FieldRename.snake)
class _ApiBuildUpdateConfig implements ApiBuildUpdateConfig {
  const _ApiBuildUpdateConfig({
    required this.apiCommitHash,
    required this.branch,
    this.fetchAtBuildEnabled = true,
    this.concurrentDownloadsEnabled = false,
    List<String> sourceUrls = const <String>[],
    Map<String, ApiPlatformConfig> platforms =
        const <String, ApiPlatformConfig>{},
  }) : _sourceUrls = sourceUrls,
       _platforms = platforms;
  factory _ApiBuildUpdateConfig.fromJson(Map<String, dynamic> json) =>
      _$ApiBuildUpdateConfigFromJson(json);

  @override
  final String apiCommitHash;
  @override
  final String branch;
  @override
  @JsonKey()
  final bool fetchAtBuildEnabled;
  @override
  @JsonKey()
  final bool concurrentDownloadsEnabled;
  final List<String> _sourceUrls;
  @override
  @JsonKey()
  List<String> get sourceUrls {
    if (_sourceUrls is EqualUnmodifiableListView) return _sourceUrls;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sourceUrls);
  }

  final Map<String, ApiPlatformConfig> _platforms;
  @override
  @JsonKey()
  Map<String, ApiPlatformConfig> get platforms {
    if (_platforms is EqualUnmodifiableMapView) return _platforms;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_platforms);
  }

  /// Create a copy of ApiBuildUpdateConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ApiBuildUpdateConfigCopyWith<_ApiBuildUpdateConfig> get copyWith =>
      __$ApiBuildUpdateConfigCopyWithImpl<_ApiBuildUpdateConfig>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$ApiBuildUpdateConfigToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ApiBuildUpdateConfig &&
            (identical(other.apiCommitHash, apiCommitHash) ||
                other.apiCommitHash == apiCommitHash) &&
            (identical(other.branch, branch) || other.branch == branch) &&
            (identical(other.fetchAtBuildEnabled, fetchAtBuildEnabled) ||
                other.fetchAtBuildEnabled == fetchAtBuildEnabled) &&
            (identical(
                  other.concurrentDownloadsEnabled,
                  concurrentDownloadsEnabled,
                ) ||
                other.concurrentDownloadsEnabled ==
                    concurrentDownloadsEnabled) &&
            const DeepCollectionEquality().equals(
              other.sourceUrls,
              _sourceUrls,
            ) &&
            const DeepCollectionEquality().equals(other.platforms, _platforms));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      apiCommitHash,
      branch,
      fetchAtBuildEnabled,
      concurrentDownloadsEnabled,
      const DeepCollectionEquality().hash(_sourceUrls),
      const DeepCollectionEquality().hash(_platforms),
    );
  }

  @override
  String toString() {
    return 'ApiBuildUpdateConfig(apiCommitHash: $apiCommitHash, branch: $branch, fetchAtBuildEnabled: $fetchAtBuildEnabled, concurrentDownloadsEnabled: $concurrentDownloadsEnabled, sourceUrls: $sourceUrls, platforms: $platforms)';
  }
}

/// @nodoc
abstract mixin class _$ApiBuildUpdateConfigCopyWith<$Res>
    implements $ApiBuildUpdateConfigCopyWith<$Res> {
  factory _$ApiBuildUpdateConfigCopyWith(
    _ApiBuildUpdateConfig value,
    $Res Function(_ApiBuildUpdateConfig) _then,
  ) = __$ApiBuildUpdateConfigCopyWithImpl;
  @override
  @useResult
  $Res call({
    String apiCommitHash,
    String branch,
    bool fetchAtBuildEnabled,
    bool concurrentDownloadsEnabled,
    List<String> sourceUrls,
    Map<String, ApiPlatformConfig> platforms,
  });
}

/// @nodoc
class __$ApiBuildUpdateConfigCopyWithImpl<$Res>
    implements _$ApiBuildUpdateConfigCopyWith<$Res> {
  __$ApiBuildUpdateConfigCopyWithImpl(this._self, this._then);

  final _ApiBuildUpdateConfig _self;
  final $Res Function(_ApiBuildUpdateConfig) _then;

  /// Create a copy of ApiBuildUpdateConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? apiCommitHash = null,
    Object? branch = null,
    Object? fetchAtBuildEnabled = null,
    Object? concurrentDownloadsEnabled = null,
    Object? sourceUrls = null,
    Object? platforms = null,
  }) {
    return _then(
      _ApiBuildUpdateConfig(
        apiCommitHash: null == apiCommitHash
            ? _self.apiCommitHash
            : apiCommitHash // ignore: cast_nullable_to_non_nullable
                  as String,
        branch: null == branch
            ? _self.branch
            : branch // ignore: cast_nullable_to_non_nullable
                  as String,
        fetchAtBuildEnabled: null == fetchAtBuildEnabled
            ? _self.fetchAtBuildEnabled
            : fetchAtBuildEnabled // ignore: cast_nullable_to_non_nullable
                  as bool,
        concurrentDownloadsEnabled: null == concurrentDownloadsEnabled
            ? _self.concurrentDownloadsEnabled
            : concurrentDownloadsEnabled // ignore: cast_nullable_to_non_nullable
                  as bool,
        sourceUrls: null == sourceUrls
            ? _self._sourceUrls
            : sourceUrls // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        platforms: null == platforms
            ? _self._platforms
            : platforms // ignore: cast_nullable_to_non_nullable
                  as Map<String, ApiPlatformConfig>,
      ),
    );
  }
}
