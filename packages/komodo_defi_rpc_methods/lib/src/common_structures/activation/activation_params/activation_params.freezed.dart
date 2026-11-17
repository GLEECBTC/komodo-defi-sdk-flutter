// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'activation_params.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;
PrivateKeyPolicy _$PrivateKeyPolicyFromJson(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'ContextPrivKey':
      return _ContextPrivKey.fromJson(json);
    case 'Trezor':
      return _Trezor.fromJson(json);
    case 'Metamask':
      return _Metamask.fromJson(json);
    case 'WalletConnect':
      return _WalletConnect.fromJson(json);

    default:
      throw CheckedFromJsonException(
        json,
        'type',
        'PrivateKeyPolicy',
        'Invalid union type "${json['type']}"!',
      );
  }
}

/// @nodoc
mixin _$PrivateKeyPolicy {
  /// Serializes this PrivateKeyPolicy to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is PrivateKeyPolicy);
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'PrivateKeyPolicy()';
  }
}

/// @nodoc
class $PrivateKeyPolicyCopyWith<$Res> {
  $PrivateKeyPolicyCopyWith(
    PrivateKeyPolicy _,
    $Res Function(PrivateKeyPolicy) __,
  );
}

/// Adds pattern-matching-related methods to [PrivateKeyPolicy].
extension PrivateKeyPolicyPatterns on PrivateKeyPolicy {
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
    TResult Function(_ContextPrivKey value)? contextPrivKey,
    TResult Function(_Trezor value)? trezor,
    TResult Function(_Metamask value)? metamask,
    TResult Function(_WalletConnect value)? walletConnect,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ContextPrivKey() when contextPrivKey != null:
        return contextPrivKey(_that);
      case _Trezor() when trezor != null:
        return trezor(_that);
      case _Metamask() when metamask != null:
        return metamask(_that);
      case _WalletConnect() when walletConnect != null:
        return walletConnect(_that);
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
    required TResult Function(_ContextPrivKey value) contextPrivKey,
    required TResult Function(_Trezor value) trezor,
    required TResult Function(_Metamask value) metamask,
    required TResult Function(_WalletConnect value) walletConnect,
  }) {
    final _that = this;
    switch (_that) {
      case _ContextPrivKey():
        return contextPrivKey(_that);
      case _Trezor():
        return trezor(_that);
      case _Metamask():
        return metamask(_that);
      case _WalletConnect():
        return walletConnect(_that);
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
    TResult? Function(_ContextPrivKey value)? contextPrivKey,
    TResult? Function(_Trezor value)? trezor,
    TResult? Function(_Metamask value)? metamask,
    TResult? Function(_WalletConnect value)? walletConnect,
  }) {
    final _that = this;
    switch (_that) {
      case _ContextPrivKey() when contextPrivKey != null:
        return contextPrivKey(_that);
      case _Trezor() when trezor != null:
        return trezor(_that);
      case _Metamask() when metamask != null:
        return metamask(_that);
      case _WalletConnect() when walletConnect != null:
        return walletConnect(_that);
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
    TResult Function()? contextPrivKey,
    TResult Function()? trezor,
    TResult Function()? metamask,
    TResult Function(String sessionTopic)? walletConnect,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ContextPrivKey() when contextPrivKey != null:
        return contextPrivKey();
      case _Trezor() when trezor != null:
        return trezor();
      case _Metamask() when metamask != null:
        return metamask();
      case _WalletConnect() when walletConnect != null:
        return walletConnect(_that.sessionTopic);
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
    required TResult Function() contextPrivKey,
    required TResult Function() trezor,
    required TResult Function() metamask,
    required TResult Function(String sessionTopic) walletConnect,
  }) {
    final _that = this;
    switch (_that) {
      case _ContextPrivKey():
        return contextPrivKey();
      case _Trezor():
        return trezor();
      case _Metamask():
        return metamask();
      case _WalletConnect():
        return walletConnect(_that.sessionTopic);
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
    TResult? Function()? contextPrivKey,
    TResult? Function()? trezor,
    TResult? Function()? metamask,
    TResult? Function(String sessionTopic)? walletConnect,
  }) {
    final _that = this;
    switch (_that) {
      case _ContextPrivKey() when contextPrivKey != null:
        return contextPrivKey();
      case _Trezor() when trezor != null:
        return trezor();
      case _Metamask() when metamask != null:
        return metamask();
      case _WalletConnect() when walletConnect != null:
        return walletConnect(_that.sessionTopic);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _ContextPrivKey extends PrivateKeyPolicy {
  const _ContextPrivKey({String? $type})
    : $type = $type ?? 'ContextPrivKey',
      super._();
  factory _ContextPrivKey.fromJson(Map<String, dynamic> json) =>
      _$ContextPrivKeyFromJson(json);

  @JsonKey(name: 'type')
  final String $type;

  @override
  Map<String, dynamic> toJson() {
    return _$ContextPrivKeyToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _ContextPrivKey);
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'PrivateKeyPolicy.contextPrivKey()';
  }
}

/// @nodoc
@JsonSerializable()
class _Trezor extends PrivateKeyPolicy {
  const _Trezor({String? $type}) : $type = $type ?? 'Trezor', super._();
  factory _Trezor.fromJson(Map<String, dynamic> json) => _$TrezorFromJson(json);

  @JsonKey(name: 'type')
  final String $type;

  @override
  Map<String, dynamic> toJson() {
    return _$TrezorToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _Trezor);
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'PrivateKeyPolicy.trezor()';
  }
}

/// @nodoc
@JsonSerializable()
class _Metamask extends PrivateKeyPolicy {
  const _Metamask({String? $type}) : $type = $type ?? 'Metamask', super._();
  factory _Metamask.fromJson(Map<String, dynamic> json) =>
      _$MetamaskFromJson(json);

  @JsonKey(name: 'type')
  final String $type;

  @override
  Map<String, dynamic> toJson() {
    return _$MetamaskToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _Metamask);
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'PrivateKeyPolicy.metamask()';
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _WalletConnect extends PrivateKeyPolicy {
  const _WalletConnect(this.sessionTopic, {String? $type})
    : $type = $type ?? 'WalletConnect',
      super._();
  factory _WalletConnect.fromJson(Map<String, dynamic> json) =>
      _$WalletConnectFromJson(json);

  final String sessionTopic;

  @JsonKey(name: 'type')
  final String $type;

  /// Create a copy of PrivateKeyPolicy
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$WalletConnectCopyWith<_WalletConnect> get copyWith =>
      __$WalletConnectCopyWithImpl<_WalletConnect>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$WalletConnectToJson(this);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _WalletConnect &&
            (identical(other.sessionTopic, sessionTopic) ||
                other.sessionTopic == sessionTopic));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode {
    return Object.hash(runtimeType, sessionTopic);
  }

  @override
  String toString() {
    return 'PrivateKeyPolicy.walletConnect(sessionTopic: $sessionTopic)';
  }
}

/// @nodoc
abstract mixin class _$WalletConnectCopyWith<$Res>
    implements $PrivateKeyPolicyCopyWith<$Res> {
  factory _$WalletConnectCopyWith(
    _WalletConnect value,
    $Res Function(_WalletConnect) _then,
  ) = __$WalletConnectCopyWithImpl;
  @useResult
  $Res call({String sessionTopic});
}

/// @nodoc
class __$WalletConnectCopyWithImpl<$Res>
    implements _$WalletConnectCopyWith<$Res> {
  __$WalletConnectCopyWithImpl(this._self, this._then);

  final _WalletConnect _self;
  final $Res Function(_WalletConnect) _then;

  /// Create a copy of PrivateKeyPolicy
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({Object? sessionTopic = null}) {
    return _then(
      _WalletConnect(
        null == sessionTopic
            ? _self.sessionTopic
            : sessionTopic // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}
