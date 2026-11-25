// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trezor_initialization_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TrezorInitializationState {
  AuthenticationStatus get status;
  String? get message;
  TrezorDeviceInfo? get deviceInfo;
  String? get error;
  int? get taskId;

  /// Create a copy of TrezorInitializationState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $TrezorInitializationStateCopyWith<TrezorInitializationState> get copyWith =>
      _$TrezorInitializationStateCopyWithImpl<TrezorInitializationState>(
        this as TrezorInitializationState,
        _$identity,
      );

  @override
  bool operator ==(Object other) {
    final _this = this as TrezorInitializationState;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is TrezorInitializationState &&
            (identical(other.status, _this.status) ||
                other.status == _this.status) &&
            (identical(other.message, _this.message) ||
                other.message == _this.message) &&
            (identical(other.deviceInfo, _this.deviceInfo) ||
                other.deviceInfo == _this.deviceInfo) &&
            (identical(other.error, _this.error) ||
                other.error == _this.error) &&
            (identical(other.taskId, _this.taskId) ||
                other.taskId == _this.taskId));
  }

  @override
  int get hashCode {
    final _this = this as TrezorInitializationState;
    return Object.hash(
      runtimeType,
      _this.status,
      _this.message,
      _this.deviceInfo,
      _this.error,
      _this.taskId,
    );
  }

  @override
  String toString() {
    final _this = this as TrezorInitializationState;
    return 'TrezorInitializationState(status: ${_this.status}, message: ${_this.message}, deviceInfo: ${_this.deviceInfo}, error: ${_this.error}, taskId: ${_this.taskId})';
  }
}

/// @nodoc
abstract mixin class $TrezorInitializationStateCopyWith<$Res> {
  factory $TrezorInitializationStateCopyWith(
    TrezorInitializationState value,
    $Res Function(TrezorInitializationState) _then,
  ) = _$TrezorInitializationStateCopyWithImpl;
  @useResult
  $Res call({
    AuthenticationStatus status,
    String? message,
    TrezorDeviceInfo? deviceInfo,
    String? error,
    int? taskId,
  });

  $TrezorDeviceInfoCopyWith<$Res>? get deviceInfo;
}

/// @nodoc
class _$TrezorInitializationStateCopyWithImpl<$Res>
    implements $TrezorInitializationStateCopyWith<$Res> {
  _$TrezorInitializationStateCopyWithImpl(this._self, this._then);

  final TrezorInitializationState _self;
  final $Res Function(TrezorInitializationState) _then;

  /// Create a copy of TrezorInitializationState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? message = freezed,
    Object? deviceInfo = freezed,
    Object? error = freezed,
    Object? taskId = freezed,
  }) {
    return _then(
      TrezorInitializationState(
        status: null == status
            ? _self.status
            : status // ignore: cast_nullable_to_non_nullable
                  as AuthenticationStatus,
        message: freezed == message
            ? _self.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        deviceInfo: freezed == deviceInfo
            ? _self.deviceInfo
            : deviceInfo // ignore: cast_nullable_to_non_nullable
                  as TrezorDeviceInfo?,
        error: freezed == error
            ? _self.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
        taskId: freezed == taskId
            ? _self.taskId
            : taskId // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }

  /// Create a copy of TrezorInitializationState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $TrezorDeviceInfoCopyWith<$Res>? get deviceInfo {
    if (_self.deviceInfo == null) {
      return null;
    }

    return $TrezorDeviceInfoCopyWith<$Res>(_self.deviceInfo!, (value) {
      return _then(_self.copyWith(deviceInfo: value));
    });
  }
}

/// Adds pattern-matching-related methods to [TrezorInitializationState].
extension TrezorInitializationStatePatterns on TrezorInitializationState {
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
    TResult Function(_TrezorInitializationState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _TrezorInitializationState() when $default != null:
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
    TResult Function(_TrezorInitializationState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _TrezorInitializationState():
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
    TResult? Function(_TrezorInitializationState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _TrezorInitializationState() when $default != null:
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
      AuthenticationStatus status,
      String? message,
      TrezorDeviceInfo? deviceInfo,
      String? error,
      int? taskId,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _TrezorInitializationState() when $default != null:
        return $default(
          _that.status,
          _that.message,
          _that.deviceInfo,
          _that.error,
          _that.taskId,
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
      AuthenticationStatus status,
      String? message,
      TrezorDeviceInfo? deviceInfo,
      String? error,
      int? taskId,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _TrezorInitializationState():
        return $default(
          _that.status,
          _that.message,
          _that.deviceInfo,
          _that.error,
          _that.taskId,
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
      AuthenticationStatus status,
      String? message,
      TrezorDeviceInfo? deviceInfo,
      String? error,
      int? taskId,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _TrezorInitializationState() when $default != null:
        return $default(
          _that.status,
          _that.message,
          _that.deviceInfo,
          _that.error,
          _that.taskId,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc

class _TrezorInitializationState extends TrezorInitializationState {
  const _TrezorInitializationState({
    required this.status,
    this.message,
    this.deviceInfo,
    this.error,
    this.taskId,
  }) : super._();

  @override
  final AuthenticationStatus status;
  @override
  final String? message;
  @override
  final TrezorDeviceInfo? deviceInfo;
  @override
  final String? error;
  @override
  final int? taskId;

  /// Create a copy of TrezorInitializationState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$TrezorInitializationStateCopyWith<_TrezorInitializationState>
  get copyWith =>
      __$TrezorInitializationStateCopyWithImpl<_TrezorInitializationState>(
        this,
        _$identity,
      );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _TrezorInitializationState &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.deviceInfo, deviceInfo) ||
                other.deviceInfo == deviceInfo) &&
            (identical(other.error, error) || other.error == error) &&
            (identical(other.taskId, taskId) || other.taskId == taskId));
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, status, message, deviceInfo, error, taskId);
  }

  @override
  String toString() {
    return 'TrezorInitializationState(status: $status, message: $message, deviceInfo: $deviceInfo, error: $error, taskId: $taskId)';
  }
}

/// @nodoc
abstract mixin class _$TrezorInitializationStateCopyWith<$Res>
    implements $TrezorInitializationStateCopyWith<$Res> {
  factory _$TrezorInitializationStateCopyWith(
    _TrezorInitializationState value,
    $Res Function(_TrezorInitializationState) _then,
  ) = __$TrezorInitializationStateCopyWithImpl;
  @override
  @useResult
  $Res call({
    AuthenticationStatus status,
    String? message,
    TrezorDeviceInfo? deviceInfo,
    String? error,
    int? taskId,
  });

  @override
  $TrezorDeviceInfoCopyWith<$Res>? get deviceInfo;
}

/// @nodoc
class __$TrezorInitializationStateCopyWithImpl<$Res>
    implements _$TrezorInitializationStateCopyWith<$Res> {
  __$TrezorInitializationStateCopyWithImpl(this._self, this._then);

  final _TrezorInitializationState _self;
  final $Res Function(_TrezorInitializationState) _then;

  /// Create a copy of TrezorInitializationState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? status = null,
    Object? message = freezed,
    Object? deviceInfo = freezed,
    Object? error = freezed,
    Object? taskId = freezed,
  }) {
    return _then(
      _TrezorInitializationState(
        status: null == status
            ? _self.status
            : status // ignore: cast_nullable_to_non_nullable
                  as AuthenticationStatus,
        message: freezed == message
            ? _self.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        deviceInfo: freezed == deviceInfo
            ? _self.deviceInfo
            : deviceInfo // ignore: cast_nullable_to_non_nullable
                  as TrezorDeviceInfo?,
        error: freezed == error
            ? _self.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
        taskId: freezed == taskId
            ? _self.taskId
            : taskId // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }

  /// Create a copy of TrezorInitializationState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $TrezorDeviceInfoCopyWith<$Res>? get deviceInfo {
    if (_self.deviceInfo == null) {
      return null;
    }

    return $TrezorDeviceInfoCopyWith<$Res>(_self.deviceInfo!, (value) {
      return _then(_self.copyWith(deviceInfo: value));
    });
  }
}
