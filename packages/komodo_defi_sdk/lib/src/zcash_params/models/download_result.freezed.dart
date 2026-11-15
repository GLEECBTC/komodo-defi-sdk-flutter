// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;
DownloadResult _$DownloadResultFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'success':
      return DownloadResultSuccess.fromJson(json);
    case 'failure':
      return DownloadResultFailure.fromJson(json);

    default:
      throw CheckedFromJsonException(
        json,
        'runtimeType',
        'DownloadResult',
        'Invalid union type "${json['runtimeType']}"!',
      );
  }
}

/// @nodoc
mixin _$DownloadResult {
  /// Serializes this DownloadResult to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is DownloadResult);
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'DownloadResult()';
  }
}

/// @nodoc
class $DownloadResultCopyWith<$Res> {
  $DownloadResultCopyWith(DownloadResult _, $Res Function(DownloadResult) __);
}

/// Adds pattern-matching-related methods to [DownloadResult].
extension DownloadResultPatterns on DownloadResult {
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
    TResult Function(DownloadResultSuccess value)? success,
    TResult Function(DownloadResultFailure value)? failure,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case DownloadResultSuccess() when success != null:
        return success(_that);
      case DownloadResultFailure() when failure != null:
        return failure(_that);
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
    required TResult Function(DownloadResultSuccess value) success,
    required TResult Function(DownloadResultFailure value) failure,
  }) {
    final _that = this;
    switch (_that) {
      case DownloadResultSuccess():
        return success(_that);
      case DownloadResultFailure():
        return failure(_that);
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
    TResult? Function(DownloadResultSuccess value)? success,
    TResult? Function(DownloadResultFailure value)? failure,
  }) {
    final _that = this;
    switch (_that) {
      case DownloadResultSuccess() when success != null:
        return success(_that);
      case DownloadResultFailure() when failure != null:
        return failure(_that);
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
    TResult Function(String paramsPath)? success,
    TResult Function(String error)? failure,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case DownloadResultSuccess() when success != null:
        return success(_that.paramsPath);
      case DownloadResultFailure() when failure != null:
        return failure(_that.error);
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
    required TResult Function(String paramsPath) success,
    required TResult Function(String error) failure,
  }) {
    final _that = this;
    switch (_that) {
      case DownloadResultSuccess():
        return success(_that.paramsPath);
      case DownloadResultFailure():
        return failure(_that.error);
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
    TResult? Function(String paramsPath)? success,
    TResult? Function(String error)? failure,
  }) {
    final _that = this;
    switch (_that) {
      case DownloadResultSuccess() when success != null:
        return success(_that.paramsPath);
      case DownloadResultFailure() when failure != null:
        return failure(_that.error);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class DownloadResultSuccess implements DownloadResult {
  const DownloadResultSuccess({required this.paramsPath, String? $type})
    : $type = $type ?? 'success';
  factory DownloadResultSuccess.fromJson(Map<String, dynamic> json) =>
      _$DownloadResultSuccessFromJson(json);

  /// The path to the downloaded ZCash parameters directory.
  final String paramsPath;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of DownloadResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DownloadResultSuccessCopyWith<DownloadResultSuccess> get copyWith =>
      _$DownloadResultSuccessCopyWithImpl<DownloadResultSuccess>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$DownloadResultSuccessToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DownloadResultSuccess &&
            (identical(other.paramsPath, paramsPath) ||
                other.paramsPath == paramsPath));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, paramsPath);
  }

  @override
  String toString() {
    return 'DownloadResult.success(paramsPath: $paramsPath)';
  }
}

/// @nodoc
abstract mixin class $DownloadResultSuccessCopyWith<$Res>
    implements $DownloadResultCopyWith<$Res> {
  factory $DownloadResultSuccessCopyWith(
    DownloadResultSuccess value,
    $Res Function(DownloadResultSuccess) _then,
  ) = _$DownloadResultSuccessCopyWithImpl;
  @useResult
  $Res call({String paramsPath});
}

/// @nodoc
class _$DownloadResultSuccessCopyWithImpl<$Res>
    implements $DownloadResultSuccessCopyWith<$Res> {
  _$DownloadResultSuccessCopyWithImpl(this._self, this._then);

  final DownloadResultSuccess _self;
  final $Res Function(DownloadResultSuccess) _then;

  /// Create a copy of DownloadResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({Object? paramsPath = null}) {
    return _then(
      DownloadResultSuccess(
        paramsPath: null == paramsPath
            ? _self.paramsPath
            : paramsPath // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class DownloadResultFailure implements DownloadResult {
  const DownloadResultFailure({required this.error, String? $type})
    : $type = $type ?? 'failure';
  factory DownloadResultFailure.fromJson(Map<String, dynamic> json) =>
      _$DownloadResultFailureFromJson(json);

  /// Error message if the download failed.
  final String error;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of DownloadResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DownloadResultFailureCopyWith<DownloadResultFailure> get copyWith =>
      _$DownloadResultFailureCopyWithImpl<DownloadResultFailure>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$DownloadResultFailureToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DownloadResultFailure &&
            (identical(other.error, error) || other.error == error));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, error);
  }

  @override
  String toString() {
    return 'DownloadResult.failure(error: $error)';
  }
}

/// @nodoc
abstract mixin class $DownloadResultFailureCopyWith<$Res>
    implements $DownloadResultCopyWith<$Res> {
  factory $DownloadResultFailureCopyWith(
    DownloadResultFailure value,
    $Res Function(DownloadResultFailure) _then,
  ) = _$DownloadResultFailureCopyWithImpl;
  @useResult
  $Res call({String error});
}

/// @nodoc
class _$DownloadResultFailureCopyWithImpl<$Res>
    implements $DownloadResultFailureCopyWith<$Res> {
  _$DownloadResultFailureCopyWithImpl(this._self, this._then);

  final DownloadResultFailure _self;
  final $Res Function(DownloadResultFailure) _then;

  /// Create a copy of DownloadResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({Object? error = null}) {
    return _then(
      DownloadResultFailure(
        error: null == error
            ? _self.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}
