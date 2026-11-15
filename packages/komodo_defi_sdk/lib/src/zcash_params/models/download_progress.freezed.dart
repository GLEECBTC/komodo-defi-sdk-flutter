// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DownloadProgress {
  /// The name of the file being downloaded.
  String get fileName;

  /// The number of bytes downloaded so far.
  int get downloaded;

  /// The total number of bytes to download.
  int get total;

  /// Create a copy of DownloadProgress
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DownloadProgressCopyWith<DownloadProgress> get copyWith =>
      _$DownloadProgressCopyWithImpl<DownloadProgress>(
        this as DownloadProgress,
        _$identity,
      );

  /// Serializes this DownloadProgress to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as DownloadProgress;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DownloadProgress &&
            (identical(other.fileName, _this.fileName) ||
                other.fileName == _this.fileName) &&
            (identical(other.downloaded, _this.downloaded) ||
                other.downloaded == _this.downloaded) &&
            (identical(other.total, _this.total) ||
                other.total == _this.total));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as DownloadProgress;
    return Object.hash(
      runtimeType,
      _this.fileName,
      _this.downloaded,
      _this.total,
    );
  }

  @override
  String toString() {
    final _this = this as DownloadProgress;
    return 'DownloadProgress(fileName: ${_this.fileName}, downloaded: ${_this.downloaded}, total: ${_this.total})';
  }
}

/// @nodoc
abstract mixin class $DownloadProgressCopyWith<$Res> {
  factory $DownloadProgressCopyWith(
    DownloadProgress value,
    $Res Function(DownloadProgress) _then,
  ) = _$DownloadProgressCopyWithImpl;
  @useResult
  $Res call({String fileName, int downloaded, int total});
}

/// @nodoc
class _$DownloadProgressCopyWithImpl<$Res>
    implements $DownloadProgressCopyWith<$Res> {
  _$DownloadProgressCopyWithImpl(this._self, this._then);

  final DownloadProgress _self;
  final $Res Function(DownloadProgress) _then;

  /// Create a copy of DownloadProgress
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fileName = null,
    Object? downloaded = null,
    Object? total = null,
  }) {
    return _then(
      DownloadProgress(
        fileName: null == fileName
            ? _self.fileName
            : fileName // ignore: cast_nullable_to_non_nullable
                  as String,
        downloaded: null == downloaded
            ? _self.downloaded
            : downloaded // ignore: cast_nullable_to_non_nullable
                  as int,
        total: null == total
            ? _self.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [DownloadProgress].
extension DownloadProgressPatterns on DownloadProgress {
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
    TResult Function(_DownloadProgress value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DownloadProgress() when $default != null:
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
    TResult Function(_DownloadProgress value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DownloadProgress():
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
    TResult? Function(_DownloadProgress value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DownloadProgress() when $default != null:
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
    TResult Function(String fileName, int downloaded, int total)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DownloadProgress() when $default != null:
        return $default(_that.fileName, _that.downloaded, _that.total);
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
    TResult Function(String fileName, int downloaded, int total) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DownloadProgress():
        return $default(_that.fileName, _that.downloaded, _that.total);
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
    TResult? Function(String fileName, int downloaded, int total)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DownloadProgress() when $default != null:
        return $default(_that.fileName, _that.downloaded, _that.total);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _DownloadProgress extends DownloadProgress {
  const _DownloadProgress({
    required this.fileName,
    required this.downloaded,
    required this.total,
  }) : super._();
  factory _DownloadProgress.fromJson(Map<String, dynamic> json) =>
      _$DownloadProgressFromJson(json);

  /// The name of the file being downloaded.
  @override
  final String fileName;

  /// The number of bytes downloaded so far.
  @override
  final int downloaded;

  /// The total number of bytes to download.
  @override
  final int total;

  /// Create a copy of DownloadProgress
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DownloadProgressCopyWith<_DownloadProgress> get copyWith =>
      __$DownloadProgressCopyWithImpl<_DownloadProgress>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$DownloadProgressToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DownloadProgress &&
            (identical(other.fileName, fileName) ||
                other.fileName == fileName) &&
            (identical(other.downloaded, downloaded) ||
                other.downloaded == downloaded) &&
            (identical(other.total, total) || other.total == total));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, fileName, downloaded, total);
  }

  @override
  String toString() {
    return 'DownloadProgress(fileName: $fileName, downloaded: $downloaded, total: $total)';
  }
}

/// @nodoc
abstract mixin class _$DownloadProgressCopyWith<$Res>
    implements $DownloadProgressCopyWith<$Res> {
  factory _$DownloadProgressCopyWith(
    _DownloadProgress value,
    $Res Function(_DownloadProgress) _then,
  ) = __$DownloadProgressCopyWithImpl;
  @override
  @useResult
  $Res call({String fileName, int downloaded, int total});
}

/// @nodoc
class __$DownloadProgressCopyWithImpl<$Res>
    implements _$DownloadProgressCopyWith<$Res> {
  __$DownloadProgressCopyWithImpl(this._self, this._then);

  final _DownloadProgress _self;
  final $Res Function(_DownloadProgress) _then;

  /// Create a copy of DownloadProgress
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? fileName = null,
    Object? downloaded = null,
    Object? total = null,
  }) {
    return _then(
      _DownloadProgress(
        fileName: null == fileName
            ? _self.fileName
            : fileName // ignore: cast_nullable_to_non_nullable
                  as String,
        downloaded: null == downloaded
            ? _self.downloaded
            : downloaded // ignore: cast_nullable_to_non_nullable
                  as int,
        total: null == total
            ? _self.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}
