// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AuthenticationState {
  AuthenticationStatus get status;
  String? get message;
  int? get taskId;
  String? get error;
  KdfUser? get user;

  /// Create a copy of AuthenticationState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AuthenticationStateCopyWith<AuthenticationState> get copyWith =>
      _$AuthenticationStateCopyWithImpl<AuthenticationState>(
        this as AuthenticationState,
        _$identity,
      );

  @override
  bool operator ==(Object other) {
    final _this = this as AuthenticationState;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AuthenticationState &&
            (identical(other.status, _this.status) ||
                other.status == _this.status) &&
            (identical(other.message, _this.message) ||
                other.message == _this.message) &&
            (identical(other.taskId, _this.taskId) ||
                other.taskId == _this.taskId) &&
            (identical(other.error, _this.error) ||
                other.error == _this.error) &&
            (identical(other.user, _this.user) || other.user == _this.user));
  }

  @override
  int get hashCode {
    final _this = this as AuthenticationState;
    return Object.hash(
      runtimeType,
      _this.status,
      _this.message,
      _this.taskId,
      _this.error,
      _this.user,
    );
  }

  @override
  String toString() {
    final _this = this as AuthenticationState;
    return 'AuthenticationState(status: ${_this.status}, message: ${_this.message}, taskId: ${_this.taskId}, error: ${_this.error}, user: ${_this.user})';
  }
}

/// @nodoc
abstract mixin class $AuthenticationStateCopyWith<$Res> {
  factory $AuthenticationStateCopyWith(
    AuthenticationState value,
    $Res Function(AuthenticationState) _then,
  ) = _$AuthenticationStateCopyWithImpl;
  @useResult
  $Res call({
    AuthenticationStatus status,
    String? message,
    int? taskId,
    String? error,
    KdfUser? user,
  });
}

/// @nodoc
class _$AuthenticationStateCopyWithImpl<$Res>
    implements $AuthenticationStateCopyWith<$Res> {
  _$AuthenticationStateCopyWithImpl(this._self, this._then);

  final AuthenticationState _self;
  final $Res Function(AuthenticationState) _then;

  /// Create a copy of AuthenticationState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? message = freezed,
    Object? taskId = freezed,
    Object? error = freezed,
    Object? user = freezed,
  }) {
    return _then(
      AuthenticationState(
        status: null == status
            ? _self.status
            : status // ignore: cast_nullable_to_non_nullable
                  as AuthenticationStatus,
        message: freezed == message
            ? _self.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        taskId: freezed == taskId
            ? _self.taskId
            : taskId // ignore: cast_nullable_to_non_nullable
                  as int?,
        error: freezed == error
            ? _self.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
        user: freezed == user
            ? _self.user
            : user // ignore: cast_nullable_to_non_nullable
                  as KdfUser?,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [AuthenticationState].
extension AuthenticationStatePatterns on AuthenticationState {
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
    TResult Function(_AuthenticationState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AuthenticationState() when $default != null:
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
    TResult Function(_AuthenticationState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AuthenticationState():
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
    TResult? Function(_AuthenticationState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AuthenticationState() when $default != null:
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
      int? taskId,
      String? error,
      KdfUser? user,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AuthenticationState() when $default != null:
        return $default(
          _that.status,
          _that.message,
          _that.taskId,
          _that.error,
          _that.user,
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
      int? taskId,
      String? error,
      KdfUser? user,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AuthenticationState():
        return $default(
          _that.status,
          _that.message,
          _that.taskId,
          _that.error,
          _that.user,
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
      int? taskId,
      String? error,
      KdfUser? user,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AuthenticationState() when $default != null:
        return $default(
          _that.status,
          _that.message,
          _that.taskId,
          _that.error,
          _that.user,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc

class _AuthenticationState implements AuthenticationState {
  const _AuthenticationState({
    required this.status,
    this.message,
    this.taskId,
    this.error,
    this.user,
  });

  @override
  final AuthenticationStatus status;
  @override
  final String? message;
  @override
  final int? taskId;
  @override
  final String? error;
  @override
  final KdfUser? user;

  /// Create a copy of AuthenticationState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AuthenticationStateCopyWith<_AuthenticationState> get copyWith =>
      __$AuthenticationStateCopyWithImpl<_AuthenticationState>(
        this,
        _$identity,
      );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AuthenticationState &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.taskId, taskId) || other.taskId == taskId) &&
            (identical(other.error, error) || other.error == error) &&
            (identical(other.user, user) || other.user == user));
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, status, message, taskId, error, user);
  }

  @override
  String toString() {
    return 'AuthenticationState(status: $status, message: $message, taskId: $taskId, error: $error, user: $user)';
  }
}

/// @nodoc
abstract mixin class _$AuthenticationStateCopyWith<$Res>
    implements $AuthenticationStateCopyWith<$Res> {
  factory _$AuthenticationStateCopyWith(
    _AuthenticationState value,
    $Res Function(_AuthenticationState) _then,
  ) = __$AuthenticationStateCopyWithImpl;
  @override
  @useResult
  $Res call({
    AuthenticationStatus status,
    String? message,
    int? taskId,
    String? error,
    KdfUser? user,
  });
}

/// @nodoc
class __$AuthenticationStateCopyWithImpl<$Res>
    implements _$AuthenticationStateCopyWith<$Res> {
  __$AuthenticationStateCopyWithImpl(this._self, this._then);

  final _AuthenticationState _self;
  final $Res Function(_AuthenticationState) _then;

  /// Create a copy of AuthenticationState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? status = null,
    Object? message = freezed,
    Object? taskId = freezed,
    Object? error = freezed,
    Object? user = freezed,
  }) {
    return _then(
      _AuthenticationState(
        status: null == status
            ? _self.status
            : status // ignore: cast_nullable_to_non_nullable
                  as AuthenticationStatus,
        message: freezed == message
            ? _self.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        taskId: freezed == taskId
            ? _self.taskId
            : taskId // ignore: cast_nullable_to_non_nullable
                  as int?,
        error: freezed == error
            ? _self.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
        user: freezed == user
            ? _self.user
            : user // ignore: cast_nullable_to_non_nullable
                  as KdfUser?,
      ),
    );
  }
}
