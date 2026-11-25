// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'new_address_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NewAddressState {
  NewAddressStatus get status;
  String? get message;
  int? get taskId;
  NewAddressInfo? get address;
  String? get expectedAddress;
  String? get error;

  /// Create a copy of NewAddressState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NewAddressStateCopyWith<NewAddressState> get copyWith =>
      _$NewAddressStateCopyWithImpl<NewAddressState>(
        this as NewAddressState,
        _$identity,
      );

  /// Serializes this NewAddressState to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    final _this = this as NewAddressState;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NewAddressState &&
            (identical(other.status, _this.status) ||
                other.status == _this.status) &&
            (identical(other.message, _this.message) ||
                other.message == _this.message) &&
            (identical(other.taskId, _this.taskId) ||
                other.taskId == _this.taskId) &&
            (identical(other.address, _this.address) ||
                other.address == _this.address) &&
            (identical(other.expectedAddress, _this.expectedAddress) ||
                other.expectedAddress == _this.expectedAddress) &&
            (identical(other.error, _this.error) ||
                other.error == _this.error));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    final _this = this as NewAddressState;
    return Object.hash(
      runtimeType,
      _this.status,
      _this.message,
      _this.taskId,
      _this.address,
      _this.expectedAddress,
      _this.error,
    );
  }

  @override
  String toString() {
    final _this = this as NewAddressState;
    return 'NewAddressState(status: ${_this.status}, message: ${_this.message}, taskId: ${_this.taskId}, address: ${_this.address}, expectedAddress: ${_this.expectedAddress}, error: ${_this.error})';
  }
}

/// @nodoc
abstract mixin class $NewAddressStateCopyWith<$Res> {
  factory $NewAddressStateCopyWith(
    NewAddressState value,
    $Res Function(NewAddressState) _then,
  ) = _$NewAddressStateCopyWithImpl;
  @useResult
  $Res call({
    NewAddressStatus status,
    String? message,
    int? taskId,
    NewAddressInfo? address,
    String? expectedAddress,
    String? error,
  });
}

/// @nodoc
class _$NewAddressStateCopyWithImpl<$Res>
    implements $NewAddressStateCopyWith<$Res> {
  _$NewAddressStateCopyWithImpl(this._self, this._then);

  final NewAddressState _self;
  final $Res Function(NewAddressState) _then;

  /// Create a copy of NewAddressState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? message = freezed,
    Object? taskId = freezed,
    Object? address = freezed,
    Object? expectedAddress = freezed,
    Object? error = freezed,
  }) {
    return _then(
      NewAddressState(
        status: null == status
            ? _self.status
            : status // ignore: cast_nullable_to_non_nullable
                  as NewAddressStatus,
        message: freezed == message
            ? _self.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        taskId: freezed == taskId
            ? _self.taskId
            : taskId // ignore: cast_nullable_to_non_nullable
                  as int?,
        address: freezed == address
            ? _self.address
            : address // ignore: cast_nullable_to_non_nullable
                  as NewAddressInfo?,
        expectedAddress: freezed == expectedAddress
            ? _self.expectedAddress
            : expectedAddress // ignore: cast_nullable_to_non_nullable
                  as String?,
        error: freezed == error
            ? _self.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// Adds pattern-matching-related methods to [NewAddressState].
extension NewAddressStatePatterns on NewAddressState {
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
    TResult Function(_NewAddressState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NewAddressState() when $default != null:
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
    TResult Function(_NewAddressState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NewAddressState():
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
    TResult? Function(_NewAddressState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NewAddressState() when $default != null:
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
      NewAddressStatus status,
      String? message,
      int? taskId,
      NewAddressInfo? address,
      String? expectedAddress,
      String? error,
    )?
    $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NewAddressState() when $default != null:
        return $default(
          _that.status,
          _that.message,
          _that.taskId,
          _that.address,
          _that.expectedAddress,
          _that.error,
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
      NewAddressStatus status,
      String? message,
      int? taskId,
      NewAddressInfo? address,
      String? expectedAddress,
      String? error,
    )
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NewAddressState():
        return $default(
          _that.status,
          _that.message,
          _that.taskId,
          _that.address,
          _that.expectedAddress,
          _that.error,
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
      NewAddressStatus status,
      String? message,
      int? taskId,
      NewAddressInfo? address,
      String? expectedAddress,
      String? error,
    )?
    $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NewAddressState() when $default != null:
        return $default(
          _that.status,
          _that.message,
          _that.taskId,
          _that.address,
          _that.expectedAddress,
          _that.error,
        );
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _NewAddressState extends NewAddressState {
  const _NewAddressState({
    required this.status,
    this.message,
    this.taskId,
    this.address,
    this.expectedAddress,
    this.error,
  }) : super._();
  factory _NewAddressState.fromJson(Map<String, dynamic> json) =>
      _$NewAddressStateFromJson(json);

  @override
  final NewAddressStatus status;
  @override
  final String? message;
  @override
  final int? taskId;
  @override
  final NewAddressInfo? address;
  @override
  final String? expectedAddress;
  @override
  final String? error;

  /// Create a copy of NewAddressState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NewAddressStateCopyWith<_NewAddressState> get copyWith =>
      __$NewAddressStateCopyWithImpl<_NewAddressState>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$NewAddressStateToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NewAddressState &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.taskId, taskId) || other.taskId == taskId) &&
            (identical(other.address, address) || other.address == address) &&
            (identical(other.expectedAddress, expectedAddress) ||
                other.expectedAddress == expectedAddress) &&
            (identical(other.error, error) || other.error == error));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(
      runtimeType,
      status,
      message,
      taskId,
      address,
      expectedAddress,
      error,
    );
  }

  @override
  String toString() {
    return 'NewAddressState(status: $status, message: $message, taskId: $taskId, address: $address, expectedAddress: $expectedAddress, error: $error)';
  }
}

/// @nodoc
abstract mixin class _$NewAddressStateCopyWith<$Res>
    implements $NewAddressStateCopyWith<$Res> {
  factory _$NewAddressStateCopyWith(
    _NewAddressState value,
    $Res Function(_NewAddressState) _then,
  ) = __$NewAddressStateCopyWithImpl;
  @override
  @useResult
  $Res call({
    NewAddressStatus status,
    String? message,
    int? taskId,
    NewAddressInfo? address,
    String? expectedAddress,
    String? error,
  });
}

/// @nodoc
class __$NewAddressStateCopyWithImpl<$Res>
    implements _$NewAddressStateCopyWith<$Res> {
  __$NewAddressStateCopyWithImpl(this._self, this._then);

  final _NewAddressState _self;
  final $Res Function(_NewAddressState) _then;

  /// Create a copy of NewAddressState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? status = null,
    Object? message = freezed,
    Object? taskId = freezed,
    Object? address = freezed,
    Object? expectedAddress = freezed,
    Object? error = freezed,
  }) {
    return _then(
      _NewAddressState(
        status: null == status
            ? _self.status
            : status // ignore: cast_nullable_to_non_nullable
                  as NewAddressStatus,
        message: freezed == message
            ? _self.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        taskId: freezed == taskId
            ? _self.taskId
            : taskId // ignore: cast_nullable_to_non_nullable
                  as int?,
        address: freezed == address
            ? _self.address
            : address // ignore: cast_nullable_to_non_nullable
                  as NewAddressInfo?,
        expectedAddress: freezed == expectedAddress
            ? _self.expectedAddress
            : expectedAddress // ignore: cast_nullable_to_non_nullable
                  as String?,
        error: freezed == error
            ? _self.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}
