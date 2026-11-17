// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'address_path.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AddressPath {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is AddressPath);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'AddressPath()';
  }
}

/// @nodoc
class $AddressPathCopyWith<$Res> {
  $AddressPathCopyWith(AddressPath _, $Res Function(AddressPath) __);
}

/// Adds pattern-matching-related methods to [AddressPath].
extension AddressPathPatterns on AddressPath {
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
    TResult Function(_DerivationPath value)? derivationPath,
    TResult Function(_ComponentsPath value)? components,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DerivationPath() when derivationPath != null:
        return derivationPath(_that);
      case _ComponentsPath() when components != null:
        return components(_that);
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
    required TResult Function(_DerivationPath value) derivationPath,
    required TResult Function(_ComponentsPath value) components,
  }) {
    final _that = this;
    switch (_that) {
      case _DerivationPath():
        return derivationPath(_that);
      case _ComponentsPath():
        return components(_that);
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
    TResult? Function(_DerivationPath value)? derivationPath,
    TResult? Function(_ComponentsPath value)? components,
  }) {
    final _that = this;
    switch (_that) {
      case _DerivationPath() when derivationPath != null:
        return derivationPath(_that);
      case _ComponentsPath() when components != null:
        return components(_that);
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
    TResult Function(String path)? derivationPath,
    TResult Function(int accountId, String chain, int addressId)? components,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DerivationPath() when derivationPath != null:
        return derivationPath(_that.path);
      case _ComponentsPath() when components != null:
        return components(_that.accountId, _that.chain, _that.addressId);
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
    required TResult Function(String path) derivationPath,
    required TResult Function(int accountId, String chain, int addressId)
    components,
  }) {
    final _that = this;
    switch (_that) {
      case _DerivationPath():
        return derivationPath(_that.path);
      case _ComponentsPath():
        return components(_that.accountId, _that.chain, _that.addressId);
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
    TResult? Function(String path)? derivationPath,
    TResult? Function(int accountId, String chain, int addressId)? components,
  }) {
    final _that = this;
    switch (_that) {
      case _DerivationPath() when derivationPath != null:
        return derivationPath(_that.path);
      case _ComponentsPath() when components != null:
        return components(_that.accountId, _that.chain, _that.addressId);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _DerivationPath extends AddressPath {
  const _DerivationPath(this.path) : super._();

  final String path;

  /// Create a copy of AddressPath
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DerivationPathCopyWith<_DerivationPath> get copyWith =>
      __$DerivationPathCopyWithImpl<_DerivationPath>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DerivationPath &&
            (identical(other.path, path) || other.path == path));
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, path);
  }

  @override
  String toString() {
    return 'AddressPath.derivationPath(path: $path)';
  }
}

/// @nodoc
abstract mixin class _$DerivationPathCopyWith<$Res>
    implements $AddressPathCopyWith<$Res> {
  factory _$DerivationPathCopyWith(
    _DerivationPath value,
    $Res Function(_DerivationPath) _then,
  ) = __$DerivationPathCopyWithImpl;
  @useResult
  $Res call({String path});
}

/// @nodoc
class __$DerivationPathCopyWithImpl<$Res>
    implements _$DerivationPathCopyWith<$Res> {
  __$DerivationPathCopyWithImpl(this._self, this._then);

  final _DerivationPath _self;
  final $Res Function(_DerivationPath) _then;

  /// Create a copy of AddressPath
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({Object? path = null}) {
    return _then(
      _DerivationPath(
        null == path
            ? _self.path
            : path // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _ComponentsPath extends AddressPath {
  const _ComponentsPath({
    required this.accountId,
    required this.chain,
    required this.addressId,
  }) : super._();

  final int accountId;
  final String chain;
  final int addressId;

  /// Create a copy of AddressPath
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ComponentsPathCopyWith<_ComponentsPath> get copyWith =>
      __$ComponentsPathCopyWithImpl<_ComponentsPath>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ComponentsPath &&
            (identical(other.accountId, accountId) ||
                other.accountId == accountId) &&
            (identical(other.chain, chain) || other.chain == chain) &&
            (identical(other.addressId, addressId) ||
                other.addressId == addressId));
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, accountId, chain, addressId);
  }

  @override
  String toString() {
    return 'AddressPath.components(accountId: $accountId, chain: $chain, addressId: $addressId)';
  }
}

/// @nodoc
abstract mixin class _$ComponentsPathCopyWith<$Res>
    implements $AddressPathCopyWith<$Res> {
  factory _$ComponentsPathCopyWith(
    _ComponentsPath value,
    $Res Function(_ComponentsPath) _then,
  ) = __$ComponentsPathCopyWithImpl;
  @useResult
  $Res call({int accountId, String chain, int addressId});
}

/// @nodoc
class __$ComponentsPathCopyWithImpl<$Res>
    implements _$ComponentsPathCopyWith<$Res> {
  __$ComponentsPathCopyWithImpl(this._self, this._then);

  final _ComponentsPath _self;
  final $Res Function(_ComponentsPath) _then;

  /// Create a copy of AddressPath
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? accountId = null,
    Object? chain = null,
    Object? addressId = null,
  }) {
    return _then(
      _ComponentsPath(
        accountId: null == accountId
            ? _self.accountId
            : accountId // ignore: cast_nullable_to_non_nullable
                  as int,
        chain: null == chain
            ? _self.chain
            : chain // ignore: cast_nullable_to_non_nullable
                  as String,
        addressId: null == addressId
            ? _self.addressId
            : addressId // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}
