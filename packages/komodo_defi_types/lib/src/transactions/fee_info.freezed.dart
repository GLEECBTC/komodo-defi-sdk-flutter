// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fee_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FeeInfo {

/// Which coin pays the fee
 String get coin;
/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoCopyWith<FeeInfo> get copyWith => _$FeeInfoCopyWithImpl<FeeInfo>(this as FeeInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfo&&(identical(other.coin, coin) || other.coin == coin));
}


@override
int get hashCode => Object.hash(runtimeType,coin);

@override
String toString() {
  return 'FeeInfo(coin: $coin)';
}


}

/// @nodoc
abstract mixin class $FeeInfoCopyWith<$Res>  {
  factory $FeeInfoCopyWith(FeeInfo value, $Res Function(FeeInfo) _then) = _$FeeInfoCopyWithImpl;
@useResult
$Res call({
 String coin
});




}
/// @nodoc
class _$FeeInfoCopyWithImpl<$Res>
    implements $FeeInfoCopyWith<$Res> {
  _$FeeInfoCopyWithImpl(this._self, this._then);

  final FeeInfo _self;
  final $Res Function(FeeInfo) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? coin = null,}) {
  return _then(_self.copyWith(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FeeInfo].
extension FeeInfoPatterns on FeeInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FeeInfoUtxoFixed value)?  utxoFixed,TResult Function( FeeInfoUtxoPerKbyte value)?  utxoPerKbyte,TResult Function( FeeInfoEthGas value)?  ethGas,TResult Function( FeeInfoEthGasEip1559 value)?  ethGasEip1559,TResult Function( FeeInfoQrc20Gas value)?  qrc20Gas,TResult Function( FeeInfoCosmosGas value)?  cosmosGas,TResult Function( FeeInfoTendermint value)?  tendermint,TResult Function( FeeInfoSia value)?  sia,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FeeInfoUtxoFixed() when utxoFixed != null:
return utxoFixed(_that);case FeeInfoUtxoPerKbyte() when utxoPerKbyte != null:
return utxoPerKbyte(_that);case FeeInfoEthGas() when ethGas != null:
return ethGas(_that);case FeeInfoEthGasEip1559() when ethGasEip1559 != null:
return ethGasEip1559(_that);case FeeInfoQrc20Gas() when qrc20Gas != null:
return qrc20Gas(_that);case FeeInfoCosmosGas() when cosmosGas != null:
return cosmosGas(_that);case FeeInfoTendermint() when tendermint != null:
return tendermint(_that);case FeeInfoSia() when sia != null:
return sia(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FeeInfoUtxoFixed value)  utxoFixed,required TResult Function( FeeInfoUtxoPerKbyte value)  utxoPerKbyte,required TResult Function( FeeInfoEthGas value)  ethGas,required TResult Function( FeeInfoEthGasEip1559 value)  ethGasEip1559,required TResult Function( FeeInfoQrc20Gas value)  qrc20Gas,required TResult Function( FeeInfoCosmosGas value)  cosmosGas,required TResult Function( FeeInfoTendermint value)  tendermint,required TResult Function( FeeInfoSia value)  sia,}){
final _that = this;
switch (_that) {
case FeeInfoUtxoFixed():
return utxoFixed(_that);case FeeInfoUtxoPerKbyte():
return utxoPerKbyte(_that);case FeeInfoEthGas():
return ethGas(_that);case FeeInfoEthGasEip1559():
return ethGasEip1559(_that);case FeeInfoQrc20Gas():
return qrc20Gas(_that);case FeeInfoCosmosGas():
return cosmosGas(_that);case FeeInfoTendermint():
return tendermint(_that);case FeeInfoSia():
return sia(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FeeInfoUtxoFixed value)?  utxoFixed,TResult? Function( FeeInfoUtxoPerKbyte value)?  utxoPerKbyte,TResult? Function( FeeInfoEthGas value)?  ethGas,TResult? Function( FeeInfoEthGasEip1559 value)?  ethGasEip1559,TResult? Function( FeeInfoQrc20Gas value)?  qrc20Gas,TResult? Function( FeeInfoCosmosGas value)?  cosmosGas,TResult? Function( FeeInfoTendermint value)?  tendermint,TResult? Function( FeeInfoSia value)?  sia,}){
final _that = this;
switch (_that) {
case FeeInfoUtxoFixed() when utxoFixed != null:
return utxoFixed(_that);case FeeInfoUtxoPerKbyte() when utxoPerKbyte != null:
return utxoPerKbyte(_that);case FeeInfoEthGas() when ethGas != null:
return ethGas(_that);case FeeInfoEthGasEip1559() when ethGasEip1559 != null:
return ethGasEip1559(_that);case FeeInfoQrc20Gas() when qrc20Gas != null:
return qrc20Gas(_that);case FeeInfoCosmosGas() when cosmosGas != null:
return cosmosGas(_that);case FeeInfoTendermint() when tendermint != null:
return tendermint(_that);case FeeInfoSia() when sia != null:
return sia(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String coin,  Decimal amount)?  utxoFixed,TResult Function( String coin,  Decimal amount)?  utxoPerKbyte,TResult Function( String coin,  Decimal gasPrice,  int gas,  Decimal? totalGasFee)?  ethGas,TResult Function( String coin,  Decimal maxFeePerGas,  Decimal maxPriorityFeePerGas,  int gas,  Decimal? totalGasFee)?  ethGasEip1559,TResult Function( String coin,  Decimal gasPrice,  int gasLimit,  Decimal? totalGasFee)?  qrc20Gas,TResult Function( String coin,  Decimal gasPrice,  int gasLimit)?  cosmosGas,TResult Function( String coin,  Decimal amount,  int gasLimit)?  tendermint,TResult Function( String coin,  Decimal amount,  String policy)?  sia,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FeeInfoUtxoFixed() when utxoFixed != null:
return utxoFixed(_that.coin,_that.amount);case FeeInfoUtxoPerKbyte() when utxoPerKbyte != null:
return utxoPerKbyte(_that.coin,_that.amount);case FeeInfoEthGas() when ethGas != null:
return ethGas(_that.coin,_that.gasPrice,_that.gas,_that.totalGasFee);case FeeInfoEthGasEip1559() when ethGasEip1559 != null:
return ethGasEip1559(_that.coin,_that.maxFeePerGas,_that.maxPriorityFeePerGas,_that.gas,_that.totalGasFee);case FeeInfoQrc20Gas() when qrc20Gas != null:
return qrc20Gas(_that.coin,_that.gasPrice,_that.gasLimit,_that.totalGasFee);case FeeInfoCosmosGas() when cosmosGas != null:
return cosmosGas(_that.coin,_that.gasPrice,_that.gasLimit);case FeeInfoTendermint() when tendermint != null:
return tendermint(_that.coin,_that.amount,_that.gasLimit);case FeeInfoSia() when sia != null:
return sia(_that.coin,_that.amount,_that.policy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String coin,  Decimal amount)  utxoFixed,required TResult Function( String coin,  Decimal amount)  utxoPerKbyte,required TResult Function( String coin,  Decimal gasPrice,  int gas,  Decimal? totalGasFee)  ethGas,required TResult Function( String coin,  Decimal maxFeePerGas,  Decimal maxPriorityFeePerGas,  int gas,  Decimal? totalGasFee)  ethGasEip1559,required TResult Function( String coin,  Decimal gasPrice,  int gasLimit,  Decimal? totalGasFee)  qrc20Gas,required TResult Function( String coin,  Decimal gasPrice,  int gasLimit)  cosmosGas,required TResult Function( String coin,  Decimal amount,  int gasLimit)  tendermint,required TResult Function( String coin,  Decimal amount,  String policy)  sia,}) {final _that = this;
switch (_that) {
case FeeInfoUtxoFixed():
return utxoFixed(_that.coin,_that.amount);case FeeInfoUtxoPerKbyte():
return utxoPerKbyte(_that.coin,_that.amount);case FeeInfoEthGas():
return ethGas(_that.coin,_that.gasPrice,_that.gas,_that.totalGasFee);case FeeInfoEthGasEip1559():
return ethGasEip1559(_that.coin,_that.maxFeePerGas,_that.maxPriorityFeePerGas,_that.gas,_that.totalGasFee);case FeeInfoQrc20Gas():
return qrc20Gas(_that.coin,_that.gasPrice,_that.gasLimit,_that.totalGasFee);case FeeInfoCosmosGas():
return cosmosGas(_that.coin,_that.gasPrice,_that.gasLimit);case FeeInfoTendermint():
return tendermint(_that.coin,_that.amount,_that.gasLimit);case FeeInfoSia():
return sia(_that.coin,_that.amount,_that.policy);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String coin,  Decimal amount)?  utxoFixed,TResult? Function( String coin,  Decimal amount)?  utxoPerKbyte,TResult? Function( String coin,  Decimal gasPrice,  int gas,  Decimal? totalGasFee)?  ethGas,TResult? Function( String coin,  Decimal maxFeePerGas,  Decimal maxPriorityFeePerGas,  int gas,  Decimal? totalGasFee)?  ethGasEip1559,TResult? Function( String coin,  Decimal gasPrice,  int gasLimit,  Decimal? totalGasFee)?  qrc20Gas,TResult? Function( String coin,  Decimal gasPrice,  int gasLimit)?  cosmosGas,TResult? Function( String coin,  Decimal amount,  int gasLimit)?  tendermint,TResult? Function( String coin,  Decimal amount,  String policy)?  sia,}) {final _that = this;
switch (_that) {
case FeeInfoUtxoFixed() when utxoFixed != null:
return utxoFixed(_that.coin,_that.amount);case FeeInfoUtxoPerKbyte() when utxoPerKbyte != null:
return utxoPerKbyte(_that.coin,_that.amount);case FeeInfoEthGas() when ethGas != null:
return ethGas(_that.coin,_that.gasPrice,_that.gas,_that.totalGasFee);case FeeInfoEthGasEip1559() when ethGasEip1559 != null:
return ethGasEip1559(_that.coin,_that.maxFeePerGas,_that.maxPriorityFeePerGas,_that.gas,_that.totalGasFee);case FeeInfoQrc20Gas() when qrc20Gas != null:
return qrc20Gas(_that.coin,_that.gasPrice,_that.gasLimit,_that.totalGasFee);case FeeInfoCosmosGas() when cosmosGas != null:
return cosmosGas(_that.coin,_that.gasPrice,_that.gasLimit);case FeeInfoTendermint() when tendermint != null:
return tendermint(_that.coin,_that.amount,_that.gasLimit);case FeeInfoSia() when sia != null:
return sia(_that.coin,_that.amount,_that.policy);case _:
  return null;

}
}

}

/// @nodoc


class FeeInfoUtxoFixed extends FeeInfo {
  const FeeInfoUtxoFixed({required this.coin, required this.amount}): super._();
  

/// Which coin pays the fee
@override final  String coin;
/// The fee amount in coin units
 final  Decimal amount;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoUtxoFixedCopyWith<FeeInfoUtxoFixed> get copyWith => _$FeeInfoUtxoFixedCopyWithImpl<FeeInfoUtxoFixed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoUtxoFixed&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,coin,amount);

@override
String toString() {
  return 'FeeInfo.utxoFixed(coin: $coin, amount: $amount)';
}


}

/// @nodoc
abstract mixin class $FeeInfoUtxoFixedCopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoUtxoFixedCopyWith(FeeInfoUtxoFixed value, $Res Function(FeeInfoUtxoFixed) _then) = _$FeeInfoUtxoFixedCopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal amount
});




}
/// @nodoc
class _$FeeInfoUtxoFixedCopyWithImpl<$Res>
    implements $FeeInfoUtxoFixedCopyWith<$Res> {
  _$FeeInfoUtxoFixedCopyWithImpl(this._self, this._then);

  final FeeInfoUtxoFixed _self;
  final $Res Function(FeeInfoUtxoFixed) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? amount = null,}) {
  return _then(FeeInfoUtxoFixed(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as Decimal,
  ));
}


}

/// @nodoc


class FeeInfoUtxoPerKbyte extends FeeInfo {
  const FeeInfoUtxoPerKbyte({required this.coin, required this.amount}): super._();
  

@override final  String coin;
 final  Decimal amount;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoUtxoPerKbyteCopyWith<FeeInfoUtxoPerKbyte> get copyWith => _$FeeInfoUtxoPerKbyteCopyWithImpl<FeeInfoUtxoPerKbyte>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoUtxoPerKbyte&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,coin,amount);

@override
String toString() {
  return 'FeeInfo.utxoPerKbyte(coin: $coin, amount: $amount)';
}


}

/// @nodoc
abstract mixin class $FeeInfoUtxoPerKbyteCopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoUtxoPerKbyteCopyWith(FeeInfoUtxoPerKbyte value, $Res Function(FeeInfoUtxoPerKbyte) _then) = _$FeeInfoUtxoPerKbyteCopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal amount
});




}
/// @nodoc
class _$FeeInfoUtxoPerKbyteCopyWithImpl<$Res>
    implements $FeeInfoUtxoPerKbyteCopyWith<$Res> {
  _$FeeInfoUtxoPerKbyteCopyWithImpl(this._self, this._then);

  final FeeInfoUtxoPerKbyte _self;
  final $Res Function(FeeInfoUtxoPerKbyte) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? amount = null,}) {
  return _then(FeeInfoUtxoPerKbyte(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as Decimal,
  ));
}


}

/// @nodoc


class FeeInfoEthGas extends FeeInfo {
  const FeeInfoEthGas({required this.coin, required this.gasPrice, required this.gas, this.totalGasFee}): super._();
  

@override final  String coin;
/// Gas price in ETH. e.g. "0.000000003" => 3 Gwei
 final  Decimal gasPrice;
/// Gas limit (number of gas units)
 final  int gas;
/// Optional total fee override. If provided, this value will be used directly
/// instead of calculating from gasPrice * gas.
 final  Decimal? totalGasFee;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoEthGasCopyWith<FeeInfoEthGas> get copyWith => _$FeeInfoEthGasCopyWithImpl<FeeInfoEthGas>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoEthGas&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.gasPrice, gasPrice) || other.gasPrice == gasPrice)&&(identical(other.gas, gas) || other.gas == gas)&&(identical(other.totalGasFee, totalGasFee) || other.totalGasFee == totalGasFee));
}


@override
int get hashCode => Object.hash(runtimeType,coin,gasPrice,gas,totalGasFee);

@override
String toString() {
  return 'FeeInfo.ethGas(coin: $coin, gasPrice: $gasPrice, gas: $gas, totalGasFee: $totalGasFee)';
}


}

/// @nodoc
abstract mixin class $FeeInfoEthGasCopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoEthGasCopyWith(FeeInfoEthGas value, $Res Function(FeeInfoEthGas) _then) = _$FeeInfoEthGasCopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal gasPrice, int gas, Decimal? totalGasFee
});




}
/// @nodoc
class _$FeeInfoEthGasCopyWithImpl<$Res>
    implements $FeeInfoEthGasCopyWith<$Res> {
  _$FeeInfoEthGasCopyWithImpl(this._self, this._then);

  final FeeInfoEthGas _self;
  final $Res Function(FeeInfoEthGas) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? gasPrice = null,Object? gas = null,Object? totalGasFee = freezed,}) {
  return _then(FeeInfoEthGas(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,gasPrice: null == gasPrice ? _self.gasPrice : gasPrice // ignore: cast_nullable_to_non_nullable
as Decimal,gas: null == gas ? _self.gas : gas // ignore: cast_nullable_to_non_nullable
as int,totalGasFee: freezed == totalGasFee ? _self.totalGasFee : totalGasFee // ignore: cast_nullable_to_non_nullable
as Decimal?,
  ));
}


}

/// @nodoc


class FeeInfoEthGasEip1559 extends FeeInfo {
  const FeeInfoEthGasEip1559({required this.coin, required this.maxFeePerGas, required this.maxPriorityFeePerGas, required this.gas, this.totalGasFee}): super._();
  

@override final  String coin;
/// Maximum fee per gas in ETH. e.g. "0.000000003" => 3 Gwei
 final  Decimal maxFeePerGas;
/// Maximum priority fee per gas in ETH. e.g. "0.000000001" => 1 Gwei
 final  Decimal maxPriorityFeePerGas;
/// Gas limit (number of gas units)
 final  int gas;
/// Optional total fee override. If provided, this value will be used directly
/// instead of calculating from maxFeePerGas * gas.
 final  Decimal? totalGasFee;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoEthGasEip1559CopyWith<FeeInfoEthGasEip1559> get copyWith => _$FeeInfoEthGasEip1559CopyWithImpl<FeeInfoEthGasEip1559>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoEthGasEip1559&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.maxFeePerGas, maxFeePerGas) || other.maxFeePerGas == maxFeePerGas)&&(identical(other.maxPriorityFeePerGas, maxPriorityFeePerGas) || other.maxPriorityFeePerGas == maxPriorityFeePerGas)&&(identical(other.gas, gas) || other.gas == gas)&&(identical(other.totalGasFee, totalGasFee) || other.totalGasFee == totalGasFee));
}


@override
int get hashCode => Object.hash(runtimeType,coin,maxFeePerGas,maxPriorityFeePerGas,gas,totalGasFee);

@override
String toString() {
  return 'FeeInfo.ethGasEip1559(coin: $coin, maxFeePerGas: $maxFeePerGas, maxPriorityFeePerGas: $maxPriorityFeePerGas, gas: $gas, totalGasFee: $totalGasFee)';
}


}

/// @nodoc
abstract mixin class $FeeInfoEthGasEip1559CopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoEthGasEip1559CopyWith(FeeInfoEthGasEip1559 value, $Res Function(FeeInfoEthGasEip1559) _then) = _$FeeInfoEthGasEip1559CopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal maxFeePerGas, Decimal maxPriorityFeePerGas, int gas, Decimal? totalGasFee
});




}
/// @nodoc
class _$FeeInfoEthGasEip1559CopyWithImpl<$Res>
    implements $FeeInfoEthGasEip1559CopyWith<$Res> {
  _$FeeInfoEthGasEip1559CopyWithImpl(this._self, this._then);

  final FeeInfoEthGasEip1559 _self;
  final $Res Function(FeeInfoEthGasEip1559) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? maxFeePerGas = null,Object? maxPriorityFeePerGas = null,Object? gas = null,Object? totalGasFee = freezed,}) {
  return _then(FeeInfoEthGasEip1559(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,maxFeePerGas: null == maxFeePerGas ? _self.maxFeePerGas : maxFeePerGas // ignore: cast_nullable_to_non_nullable
as Decimal,maxPriorityFeePerGas: null == maxPriorityFeePerGas ? _self.maxPriorityFeePerGas : maxPriorityFeePerGas // ignore: cast_nullable_to_non_nullable
as Decimal,gas: null == gas ? _self.gas : gas // ignore: cast_nullable_to_non_nullable
as int,totalGasFee: freezed == totalGasFee ? _self.totalGasFee : totalGasFee // ignore: cast_nullable_to_non_nullable
as Decimal?,
  ));
}


}

/// @nodoc


class FeeInfoQrc20Gas extends FeeInfo {
  const FeeInfoQrc20Gas({required this.coin, required this.gasPrice, required this.gasLimit, this.totalGasFee}): super._();
  

@override final  String coin;
/// Gas price in coin units. e.g. "0.000000004"
 final  Decimal gasPrice;
/// Gas limit
 final  int gasLimit;
/// Optional total gas fee in coin units. If not provided, it will be calculated
/// as `gasPrice * gasLimit`.
 final  Decimal? totalGasFee;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoQrc20GasCopyWith<FeeInfoQrc20Gas> get copyWith => _$FeeInfoQrc20GasCopyWithImpl<FeeInfoQrc20Gas>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoQrc20Gas&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.gasPrice, gasPrice) || other.gasPrice == gasPrice)&&(identical(other.gasLimit, gasLimit) || other.gasLimit == gasLimit)&&(identical(other.totalGasFee, totalGasFee) || other.totalGasFee == totalGasFee));
}


@override
int get hashCode => Object.hash(runtimeType,coin,gasPrice,gasLimit,totalGasFee);

@override
String toString() {
  return 'FeeInfo.qrc20Gas(coin: $coin, gasPrice: $gasPrice, gasLimit: $gasLimit, totalGasFee: $totalGasFee)';
}


}

/// @nodoc
abstract mixin class $FeeInfoQrc20GasCopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoQrc20GasCopyWith(FeeInfoQrc20Gas value, $Res Function(FeeInfoQrc20Gas) _then) = _$FeeInfoQrc20GasCopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal gasPrice, int gasLimit, Decimal? totalGasFee
});




}
/// @nodoc
class _$FeeInfoQrc20GasCopyWithImpl<$Res>
    implements $FeeInfoQrc20GasCopyWith<$Res> {
  _$FeeInfoQrc20GasCopyWithImpl(this._self, this._then);

  final FeeInfoQrc20Gas _self;
  final $Res Function(FeeInfoQrc20Gas) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? gasPrice = null,Object? gasLimit = null,Object? totalGasFee = freezed,}) {
  return _then(FeeInfoQrc20Gas(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,gasPrice: null == gasPrice ? _self.gasPrice : gasPrice // ignore: cast_nullable_to_non_nullable
as Decimal,gasLimit: null == gasLimit ? _self.gasLimit : gasLimit // ignore: cast_nullable_to_non_nullable
as int,totalGasFee: freezed == totalGasFee ? _self.totalGasFee : totalGasFee // ignore: cast_nullable_to_non_nullable
as Decimal?,
  ));
}


}

/// @nodoc


class FeeInfoCosmosGas extends FeeInfo {
  const FeeInfoCosmosGas({required this.coin, required this.gasPrice, required this.gasLimit}): super._();
  

@override final  String coin;
/// Gas price in coin units. e.g. "0.05"
 final  Decimal gasPrice;
/// Gas limit
 final  int gasLimit;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoCosmosGasCopyWith<FeeInfoCosmosGas> get copyWith => _$FeeInfoCosmosGasCopyWithImpl<FeeInfoCosmosGas>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoCosmosGas&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.gasPrice, gasPrice) || other.gasPrice == gasPrice)&&(identical(other.gasLimit, gasLimit) || other.gasLimit == gasLimit));
}


@override
int get hashCode => Object.hash(runtimeType,coin,gasPrice,gasLimit);

@override
String toString() {
  return 'FeeInfo.cosmosGas(coin: $coin, gasPrice: $gasPrice, gasLimit: $gasLimit)';
}


}

/// @nodoc
abstract mixin class $FeeInfoCosmosGasCopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoCosmosGasCopyWith(FeeInfoCosmosGas value, $Res Function(FeeInfoCosmosGas) _then) = _$FeeInfoCosmosGasCopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal gasPrice, int gasLimit
});




}
/// @nodoc
class _$FeeInfoCosmosGasCopyWithImpl<$Res>
    implements $FeeInfoCosmosGasCopyWith<$Res> {
  _$FeeInfoCosmosGasCopyWithImpl(this._self, this._then);

  final FeeInfoCosmosGas _self;
  final $Res Function(FeeInfoCosmosGas) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? gasPrice = null,Object? gasLimit = null,}) {
  return _then(FeeInfoCosmosGas(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,gasPrice: null == gasPrice ? _self.gasPrice : gasPrice // ignore: cast_nullable_to_non_nullable
as Decimal,gasLimit: null == gasLimit ? _self.gasLimit : gasLimit // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FeeInfoTendermint extends FeeInfo {
  const FeeInfoTendermint({required this.coin, required this.amount, required this.gasLimit}): super._();
  

@override final  String coin;
/// The fee amount in coin units
 final  Decimal amount;
/// Gas limit
 final  int gasLimit;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoTendermintCopyWith<FeeInfoTendermint> get copyWith => _$FeeInfoTendermintCopyWithImpl<FeeInfoTendermint>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoTendermint&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.gasLimit, gasLimit) || other.gasLimit == gasLimit));
}


@override
int get hashCode => Object.hash(runtimeType,coin,amount,gasLimit);

@override
String toString() {
  return 'FeeInfo.tendermint(coin: $coin, amount: $amount, gasLimit: $gasLimit)';
}


}

/// @nodoc
abstract mixin class $FeeInfoTendermintCopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoTendermintCopyWith(FeeInfoTendermint value, $Res Function(FeeInfoTendermint) _then) = _$FeeInfoTendermintCopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal amount, int gasLimit
});




}
/// @nodoc
class _$FeeInfoTendermintCopyWithImpl<$Res>
    implements $FeeInfoTendermintCopyWith<$Res> {
  _$FeeInfoTendermintCopyWithImpl(this._self, this._then);

  final FeeInfoTendermint _self;
  final $Res Function(FeeInfoTendermint) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? amount = null,Object? gasLimit = null,}) {
  return _then(FeeInfoTendermint(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as Decimal,gasLimit: null == gasLimit ? _self.gasLimit : gasLimit // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FeeInfoSia extends FeeInfo {
  const FeeInfoSia({required this.coin, required this.amount, required this.policy}): super._();
  

@override final  String coin;
/// The fee amount in coin units
 final  Decimal amount;
/// The fee policy (e.g., "Fixed")
 final  String policy;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FeeInfoSiaCopyWith<FeeInfoSia> get copyWith => _$FeeInfoSiaCopyWithImpl<FeeInfoSia>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FeeInfoSia&&(identical(other.coin, coin) || other.coin == coin)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.policy, policy) || other.policy == policy));
}


@override
int get hashCode => Object.hash(runtimeType,coin,amount,policy);

@override
String toString() {
  return 'FeeInfo.sia(coin: $coin, amount: $amount, policy: $policy)';
}


}

/// @nodoc
abstract mixin class $FeeInfoSiaCopyWith<$Res> implements $FeeInfoCopyWith<$Res> {
  factory $FeeInfoSiaCopyWith(FeeInfoSia value, $Res Function(FeeInfoSia) _then) = _$FeeInfoSiaCopyWithImpl;
@override @useResult
$Res call({
 String coin, Decimal amount, String policy
});




}
/// @nodoc
class _$FeeInfoSiaCopyWithImpl<$Res>
    implements $FeeInfoSiaCopyWith<$Res> {
  _$FeeInfoSiaCopyWithImpl(this._self, this._then);

  final FeeInfoSia _self;
  final $Res Function(FeeInfoSia) _then;

/// Create a copy of FeeInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? coin = null,Object? amount = null,Object? policy = null,}) {
  return _then(FeeInfoSia(
coin: null == coin ? _self.coin : coin // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as Decimal,policy: null == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
