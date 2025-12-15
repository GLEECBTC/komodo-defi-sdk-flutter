// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'zcash_params_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ZcashParamFile {

/// The name of the parameter file.
 String get fileName;/// The expected SHA256 hash of the file for integrity verification.
 String get sha256Hash;/// The expected file size in bytes (optional, for progress reporting).
 int? get expectedSize;
/// Create a copy of ZcashParamFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZcashParamFileCopyWith<ZcashParamFile> get copyWith => _$ZcashParamFileCopyWithImpl<ZcashParamFile>(this as ZcashParamFile, _$identity);

  /// Serializes this ZcashParamFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZcashParamFile&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.sha256Hash, sha256Hash) || other.sha256Hash == sha256Hash)&&(identical(other.expectedSize, expectedSize) || other.expectedSize == expectedSize));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,fileName,sha256Hash,expectedSize);

@override
String toString() {
  return 'ZcashParamFile(fileName: $fileName, sha256Hash: $sha256Hash, expectedSize: $expectedSize)';
}


}

/// @nodoc
abstract mixin class $ZcashParamFileCopyWith<$Res>  {
  factory $ZcashParamFileCopyWith(ZcashParamFile value, $Res Function(ZcashParamFile) _then) = _$ZcashParamFileCopyWithImpl;
@useResult
$Res call({
 String fileName, String sha256Hash, int? expectedSize
});




}
/// @nodoc
class _$ZcashParamFileCopyWithImpl<$Res>
    implements $ZcashParamFileCopyWith<$Res> {
  _$ZcashParamFileCopyWithImpl(this._self, this._then);

  final ZcashParamFile _self;
  final $Res Function(ZcashParamFile) _then;

/// Create a copy of ZcashParamFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fileName = null,Object? sha256Hash = null,Object? expectedSize = freezed,}) {
  return _then(_self.copyWith(
fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,sha256Hash: null == sha256Hash ? _self.sha256Hash : sha256Hash // ignore: cast_nullable_to_non_nullable
as String,expectedSize: freezed == expectedSize ? _self.expectedSize : expectedSize // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ZcashParamFile].
extension ZcashParamFilePatterns on ZcashParamFile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ZcashParamFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ZcashParamFile() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ZcashParamFile value)  $default,){
final _that = this;
switch (_that) {
case _ZcashParamFile():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ZcashParamFile value)?  $default,){
final _that = this;
switch (_that) {
case _ZcashParamFile() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String fileName,  String sha256Hash,  int? expectedSize)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ZcashParamFile() when $default != null:
return $default(_that.fileName,_that.sha256Hash,_that.expectedSize);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String fileName,  String sha256Hash,  int? expectedSize)  $default,) {final _that = this;
switch (_that) {
case _ZcashParamFile():
return $default(_that.fileName,_that.sha256Hash,_that.expectedSize);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String fileName,  String sha256Hash,  int? expectedSize)?  $default,) {final _that = this;
switch (_that) {
case _ZcashParamFile() when $default != null:
return $default(_that.fileName,_that.sha256Hash,_that.expectedSize);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _ZcashParamFile extends ZcashParamFile {
  const _ZcashParamFile({required this.fileName, required this.sha256Hash, this.expectedSize}): super._();
  factory _ZcashParamFile.fromJson(Map<String, dynamic> json) => _$ZcashParamFileFromJson(json);

/// The name of the parameter file.
@override final  String fileName;
/// The expected SHA256 hash of the file for integrity verification.
@override final  String sha256Hash;
/// The expected file size in bytes (optional, for progress reporting).
@override final  int? expectedSize;

/// Create a copy of ZcashParamFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ZcashParamFileCopyWith<_ZcashParamFile> get copyWith => __$ZcashParamFileCopyWithImpl<_ZcashParamFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ZcashParamFileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ZcashParamFile&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.sha256Hash, sha256Hash) || other.sha256Hash == sha256Hash)&&(identical(other.expectedSize, expectedSize) || other.expectedSize == expectedSize));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,fileName,sha256Hash,expectedSize);

@override
String toString() {
  return 'ZcashParamFile(fileName: $fileName, sha256Hash: $sha256Hash, expectedSize: $expectedSize)';
}


}

/// @nodoc
abstract mixin class _$ZcashParamFileCopyWith<$Res> implements $ZcashParamFileCopyWith<$Res> {
  factory _$ZcashParamFileCopyWith(_ZcashParamFile value, $Res Function(_ZcashParamFile) _then) = __$ZcashParamFileCopyWithImpl;
@override @useResult
$Res call({
 String fileName, String sha256Hash, int? expectedSize
});




}
/// @nodoc
class __$ZcashParamFileCopyWithImpl<$Res>
    implements _$ZcashParamFileCopyWith<$Res> {
  __$ZcashParamFileCopyWithImpl(this._self, this._then);

  final _ZcashParamFile _self;
  final $Res Function(_ZcashParamFile) _then;

/// Create a copy of ZcashParamFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fileName = null,Object? sha256Hash = null,Object? expectedSize = freezed,}) {
  return _then(_ZcashParamFile(
fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,sha256Hash: null == sha256Hash ? _self.sha256Hash : sha256Hash // ignore: cast_nullable_to_non_nullable
as String,expectedSize: freezed == expectedSize ? _self.expectedSize : expectedSize // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$ZcashParamsConfig {

/// List of ZCash parameter files to download.
 List<ZcashParamFile> get paramFiles;/// Primary download URL for ZCash parameters.
 String get primaryUrl;/// Backup download URL for ZCash parameters.
 String get backupUrl;/// Timeout duration for HTTP downloads in seconds.
 int get downloadTimeoutSeconds;// 30 minutes
/// Maximum number of retry attempts for failed downloads.
 int get maxRetries;/// Delay between retry attempts in seconds.
 int get retryDelaySeconds;/// Buffer size for file downloads in bytes (1MB).
 int get downloadBufferSize;
/// Create a copy of ZcashParamsConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZcashParamsConfigCopyWith<ZcashParamsConfig> get copyWith => _$ZcashParamsConfigCopyWithImpl<ZcashParamsConfig>(this as ZcashParamsConfig, _$identity);

  /// Serializes this ZcashParamsConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZcashParamsConfig&&const DeepCollectionEquality().equals(other.paramFiles, paramFiles)&&(identical(other.primaryUrl, primaryUrl) || other.primaryUrl == primaryUrl)&&(identical(other.backupUrl, backupUrl) || other.backupUrl == backupUrl)&&(identical(other.downloadTimeoutSeconds, downloadTimeoutSeconds) || other.downloadTimeoutSeconds == downloadTimeoutSeconds)&&(identical(other.maxRetries, maxRetries) || other.maxRetries == maxRetries)&&(identical(other.retryDelaySeconds, retryDelaySeconds) || other.retryDelaySeconds == retryDelaySeconds)&&(identical(other.downloadBufferSize, downloadBufferSize) || other.downloadBufferSize == downloadBufferSize));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(paramFiles),primaryUrl,backupUrl,downloadTimeoutSeconds,maxRetries,retryDelaySeconds,downloadBufferSize);

@override
String toString() {
  return 'ZcashParamsConfig(paramFiles: $paramFiles, primaryUrl: $primaryUrl, backupUrl: $backupUrl, downloadTimeoutSeconds: $downloadTimeoutSeconds, maxRetries: $maxRetries, retryDelaySeconds: $retryDelaySeconds, downloadBufferSize: $downloadBufferSize)';
}


}

/// @nodoc
abstract mixin class $ZcashParamsConfigCopyWith<$Res>  {
  factory $ZcashParamsConfigCopyWith(ZcashParamsConfig value, $Res Function(ZcashParamsConfig) _then) = _$ZcashParamsConfigCopyWithImpl;
@useResult
$Res call({
 List<ZcashParamFile> paramFiles, String primaryUrl, String backupUrl, int downloadTimeoutSeconds, int maxRetries, int retryDelaySeconds, int downloadBufferSize
});




}
/// @nodoc
class _$ZcashParamsConfigCopyWithImpl<$Res>
    implements $ZcashParamsConfigCopyWith<$Res> {
  _$ZcashParamsConfigCopyWithImpl(this._self, this._then);

  final ZcashParamsConfig _self;
  final $Res Function(ZcashParamsConfig) _then;

/// Create a copy of ZcashParamsConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? paramFiles = null,Object? primaryUrl = null,Object? backupUrl = null,Object? downloadTimeoutSeconds = null,Object? maxRetries = null,Object? retryDelaySeconds = null,Object? downloadBufferSize = null,}) {
  return _then(_self.copyWith(
paramFiles: null == paramFiles ? _self.paramFiles : paramFiles // ignore: cast_nullable_to_non_nullable
as List<ZcashParamFile>,primaryUrl: null == primaryUrl ? _self.primaryUrl : primaryUrl // ignore: cast_nullable_to_non_nullable
as String,backupUrl: null == backupUrl ? _self.backupUrl : backupUrl // ignore: cast_nullable_to_non_nullable
as String,downloadTimeoutSeconds: null == downloadTimeoutSeconds ? _self.downloadTimeoutSeconds : downloadTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,maxRetries: null == maxRetries ? _self.maxRetries : maxRetries // ignore: cast_nullable_to_non_nullable
as int,retryDelaySeconds: null == retryDelaySeconds ? _self.retryDelaySeconds : retryDelaySeconds // ignore: cast_nullable_to_non_nullable
as int,downloadBufferSize: null == downloadBufferSize ? _self.downloadBufferSize : downloadBufferSize // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ZcashParamsConfig].
extension ZcashParamsConfigPatterns on ZcashParamsConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ZcashParamsConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ZcashParamsConfig() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ZcashParamsConfig value)  $default,){
final _that = this;
switch (_that) {
case _ZcashParamsConfig():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ZcashParamsConfig value)?  $default,){
final _that = this;
switch (_that) {
case _ZcashParamsConfig() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ZcashParamFile> paramFiles,  String primaryUrl,  String backupUrl,  int downloadTimeoutSeconds,  int maxRetries,  int retryDelaySeconds,  int downloadBufferSize)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ZcashParamsConfig() when $default != null:
return $default(_that.paramFiles,_that.primaryUrl,_that.backupUrl,_that.downloadTimeoutSeconds,_that.maxRetries,_that.retryDelaySeconds,_that.downloadBufferSize);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ZcashParamFile> paramFiles,  String primaryUrl,  String backupUrl,  int downloadTimeoutSeconds,  int maxRetries,  int retryDelaySeconds,  int downloadBufferSize)  $default,) {final _that = this;
switch (_that) {
case _ZcashParamsConfig():
return $default(_that.paramFiles,_that.primaryUrl,_that.backupUrl,_that.downloadTimeoutSeconds,_that.maxRetries,_that.retryDelaySeconds,_that.downloadBufferSize);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ZcashParamFile> paramFiles,  String primaryUrl,  String backupUrl,  int downloadTimeoutSeconds,  int maxRetries,  int retryDelaySeconds,  int downloadBufferSize)?  $default,) {final _that = this;
switch (_that) {
case _ZcashParamsConfig() when $default != null:
return $default(_that.paramFiles,_that.primaryUrl,_that.backupUrl,_that.downloadTimeoutSeconds,_that.maxRetries,_that.retryDelaySeconds,_that.downloadBufferSize);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _ZcashParamsConfig extends ZcashParamsConfig {
  const _ZcashParamsConfig({required final  List<ZcashParamFile> paramFiles, this.primaryUrl = 'https://z.cash/downloads/', this.backupUrl = 'https://komodoplatform.com/downloads/', this.downloadTimeoutSeconds = 1800, this.maxRetries = 3, this.retryDelaySeconds = 5, this.downloadBufferSize = 1048576}): _paramFiles = paramFiles,super._();
  factory _ZcashParamsConfig.fromJson(Map<String, dynamic> json) => _$ZcashParamsConfigFromJson(json);

/// List of ZCash parameter files to download.
 final  List<ZcashParamFile> _paramFiles;
/// List of ZCash parameter files to download.
@override List<ZcashParamFile> get paramFiles {
  if (_paramFiles is EqualUnmodifiableListView) return _paramFiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_paramFiles);
}

/// Primary download URL for ZCash parameters.
@override@JsonKey() final  String primaryUrl;
/// Backup download URL for ZCash parameters.
@override@JsonKey() final  String backupUrl;
/// Timeout duration for HTTP downloads in seconds.
@override@JsonKey() final  int downloadTimeoutSeconds;
// 30 minutes
/// Maximum number of retry attempts for failed downloads.
@override@JsonKey() final  int maxRetries;
/// Delay between retry attempts in seconds.
@override@JsonKey() final  int retryDelaySeconds;
/// Buffer size for file downloads in bytes (1MB).
@override@JsonKey() final  int downloadBufferSize;

/// Create a copy of ZcashParamsConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ZcashParamsConfigCopyWith<_ZcashParamsConfig> get copyWith => __$ZcashParamsConfigCopyWithImpl<_ZcashParamsConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ZcashParamsConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ZcashParamsConfig&&const DeepCollectionEquality().equals(other._paramFiles, _paramFiles)&&(identical(other.primaryUrl, primaryUrl) || other.primaryUrl == primaryUrl)&&(identical(other.backupUrl, backupUrl) || other.backupUrl == backupUrl)&&(identical(other.downloadTimeoutSeconds, downloadTimeoutSeconds) || other.downloadTimeoutSeconds == downloadTimeoutSeconds)&&(identical(other.maxRetries, maxRetries) || other.maxRetries == maxRetries)&&(identical(other.retryDelaySeconds, retryDelaySeconds) || other.retryDelaySeconds == retryDelaySeconds)&&(identical(other.downloadBufferSize, downloadBufferSize) || other.downloadBufferSize == downloadBufferSize));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_paramFiles),primaryUrl,backupUrl,downloadTimeoutSeconds,maxRetries,retryDelaySeconds,downloadBufferSize);

@override
String toString() {
  return 'ZcashParamsConfig(paramFiles: $paramFiles, primaryUrl: $primaryUrl, backupUrl: $backupUrl, downloadTimeoutSeconds: $downloadTimeoutSeconds, maxRetries: $maxRetries, retryDelaySeconds: $retryDelaySeconds, downloadBufferSize: $downloadBufferSize)';
}


}

/// @nodoc
abstract mixin class _$ZcashParamsConfigCopyWith<$Res> implements $ZcashParamsConfigCopyWith<$Res> {
  factory _$ZcashParamsConfigCopyWith(_ZcashParamsConfig value, $Res Function(_ZcashParamsConfig) _then) = __$ZcashParamsConfigCopyWithImpl;
@override @useResult
$Res call({
 List<ZcashParamFile> paramFiles, String primaryUrl, String backupUrl, int downloadTimeoutSeconds, int maxRetries, int retryDelaySeconds, int downloadBufferSize
});




}
/// @nodoc
class __$ZcashParamsConfigCopyWithImpl<$Res>
    implements _$ZcashParamsConfigCopyWith<$Res> {
  __$ZcashParamsConfigCopyWithImpl(this._self, this._then);

  final _ZcashParamsConfig _self;
  final $Res Function(_ZcashParamsConfig) _then;

/// Create a copy of ZcashParamsConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? paramFiles = null,Object? primaryUrl = null,Object? backupUrl = null,Object? downloadTimeoutSeconds = null,Object? maxRetries = null,Object? retryDelaySeconds = null,Object? downloadBufferSize = null,}) {
  return _then(_ZcashParamsConfig(
paramFiles: null == paramFiles ? _self._paramFiles : paramFiles // ignore: cast_nullable_to_non_nullable
as List<ZcashParamFile>,primaryUrl: null == primaryUrl ? _self.primaryUrl : primaryUrl // ignore: cast_nullable_to_non_nullable
as String,backupUrl: null == backupUrl ? _self.backupUrl : backupUrl // ignore: cast_nullable_to_non_nullable
as String,downloadTimeoutSeconds: null == downloadTimeoutSeconds ? _self.downloadTimeoutSeconds : downloadTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,maxRetries: null == maxRetries ? _self.maxRetries : maxRetries // ignore: cast_nullable_to_non_nullable
as int,retryDelaySeconds: null == retryDelaySeconds ? _self.retryDelaySeconds : retryDelaySeconds // ignore: cast_nullable_to_non_nullable
as int,downloadBufferSize: null == downloadBufferSize ? _self.downloadBufferSize : downloadBufferSize // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
