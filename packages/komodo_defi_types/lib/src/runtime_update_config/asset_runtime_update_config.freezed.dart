// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'asset_runtime_update_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AssetRuntimeUpdateConfig {

// Mirrors `coins` section in build_config.json
 bool get fetchAtBuildEnabled; bool get updateCommitOnBuild; String get bundledCoinsRepoCommit; String get coinsRepoApiUrl; String get coinsRepoContentUrl; String get coinsRepoBranch; bool get runtimeUpdatesEnabled; Map<String, String> get mappedFiles; Map<String, String> get mappedFolders; bool get concurrentDownloadsEnabled; Map<String, String> get cdnBranchMirrors;
/// Create a copy of AssetRuntimeUpdateConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssetRuntimeUpdateConfigCopyWith<AssetRuntimeUpdateConfig> get copyWith => _$AssetRuntimeUpdateConfigCopyWithImpl<AssetRuntimeUpdateConfig>(this as AssetRuntimeUpdateConfig, _$identity);

  /// Serializes this AssetRuntimeUpdateConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetRuntimeUpdateConfig&&(identical(other.fetchAtBuildEnabled, fetchAtBuildEnabled) || other.fetchAtBuildEnabled == fetchAtBuildEnabled)&&(identical(other.updateCommitOnBuild, updateCommitOnBuild) || other.updateCommitOnBuild == updateCommitOnBuild)&&(identical(other.bundledCoinsRepoCommit, bundledCoinsRepoCommit) || other.bundledCoinsRepoCommit == bundledCoinsRepoCommit)&&(identical(other.coinsRepoApiUrl, coinsRepoApiUrl) || other.coinsRepoApiUrl == coinsRepoApiUrl)&&(identical(other.coinsRepoContentUrl, coinsRepoContentUrl) || other.coinsRepoContentUrl == coinsRepoContentUrl)&&(identical(other.coinsRepoBranch, coinsRepoBranch) || other.coinsRepoBranch == coinsRepoBranch)&&(identical(other.runtimeUpdatesEnabled, runtimeUpdatesEnabled) || other.runtimeUpdatesEnabled == runtimeUpdatesEnabled)&&const DeepCollectionEquality().equals(other.mappedFiles, mappedFiles)&&const DeepCollectionEquality().equals(other.mappedFolders, mappedFolders)&&(identical(other.concurrentDownloadsEnabled, concurrentDownloadsEnabled) || other.concurrentDownloadsEnabled == concurrentDownloadsEnabled)&&const DeepCollectionEquality().equals(other.cdnBranchMirrors, cdnBranchMirrors));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,fetchAtBuildEnabled,updateCommitOnBuild,bundledCoinsRepoCommit,coinsRepoApiUrl,coinsRepoContentUrl,coinsRepoBranch,runtimeUpdatesEnabled,const DeepCollectionEquality().hash(mappedFiles),const DeepCollectionEquality().hash(mappedFolders),concurrentDownloadsEnabled,const DeepCollectionEquality().hash(cdnBranchMirrors));

@override
String toString() {
  return 'AssetRuntimeUpdateConfig(fetchAtBuildEnabled: $fetchAtBuildEnabled, updateCommitOnBuild: $updateCommitOnBuild, bundledCoinsRepoCommit: $bundledCoinsRepoCommit, coinsRepoApiUrl: $coinsRepoApiUrl, coinsRepoContentUrl: $coinsRepoContentUrl, coinsRepoBranch: $coinsRepoBranch, runtimeUpdatesEnabled: $runtimeUpdatesEnabled, mappedFiles: $mappedFiles, mappedFolders: $mappedFolders, concurrentDownloadsEnabled: $concurrentDownloadsEnabled, cdnBranchMirrors: $cdnBranchMirrors)';
}


}

/// @nodoc
abstract mixin class $AssetRuntimeUpdateConfigCopyWith<$Res>  {
  factory $AssetRuntimeUpdateConfigCopyWith(AssetRuntimeUpdateConfig value, $Res Function(AssetRuntimeUpdateConfig) _then) = _$AssetRuntimeUpdateConfigCopyWithImpl;
@useResult
$Res call({
 bool fetchAtBuildEnabled, bool updateCommitOnBuild, String bundledCoinsRepoCommit, String coinsRepoApiUrl, String coinsRepoContentUrl, String coinsRepoBranch, bool runtimeUpdatesEnabled, Map<String, String> mappedFiles, Map<String, String> mappedFolders, bool concurrentDownloadsEnabled, Map<String, String> cdnBranchMirrors
});




}
/// @nodoc
class _$AssetRuntimeUpdateConfigCopyWithImpl<$Res>
    implements $AssetRuntimeUpdateConfigCopyWith<$Res> {
  _$AssetRuntimeUpdateConfigCopyWithImpl(this._self, this._then);

  final AssetRuntimeUpdateConfig _self;
  final $Res Function(AssetRuntimeUpdateConfig) _then;

/// Create a copy of AssetRuntimeUpdateConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fetchAtBuildEnabled = null,Object? updateCommitOnBuild = null,Object? bundledCoinsRepoCommit = null,Object? coinsRepoApiUrl = null,Object? coinsRepoContentUrl = null,Object? coinsRepoBranch = null,Object? runtimeUpdatesEnabled = null,Object? mappedFiles = null,Object? mappedFolders = null,Object? concurrentDownloadsEnabled = null,Object? cdnBranchMirrors = null,}) {
  return _then(_self.copyWith(
fetchAtBuildEnabled: null == fetchAtBuildEnabled ? _self.fetchAtBuildEnabled : fetchAtBuildEnabled // ignore: cast_nullable_to_non_nullable
as bool,updateCommitOnBuild: null == updateCommitOnBuild ? _self.updateCommitOnBuild : updateCommitOnBuild // ignore: cast_nullable_to_non_nullable
as bool,bundledCoinsRepoCommit: null == bundledCoinsRepoCommit ? _self.bundledCoinsRepoCommit : bundledCoinsRepoCommit // ignore: cast_nullable_to_non_nullable
as String,coinsRepoApiUrl: null == coinsRepoApiUrl ? _self.coinsRepoApiUrl : coinsRepoApiUrl // ignore: cast_nullable_to_non_nullable
as String,coinsRepoContentUrl: null == coinsRepoContentUrl ? _self.coinsRepoContentUrl : coinsRepoContentUrl // ignore: cast_nullable_to_non_nullable
as String,coinsRepoBranch: null == coinsRepoBranch ? _self.coinsRepoBranch : coinsRepoBranch // ignore: cast_nullable_to_non_nullable
as String,runtimeUpdatesEnabled: null == runtimeUpdatesEnabled ? _self.runtimeUpdatesEnabled : runtimeUpdatesEnabled // ignore: cast_nullable_to_non_nullable
as bool,mappedFiles: null == mappedFiles ? _self.mappedFiles : mappedFiles // ignore: cast_nullable_to_non_nullable
as Map<String, String>,mappedFolders: null == mappedFolders ? _self.mappedFolders : mappedFolders // ignore: cast_nullable_to_non_nullable
as Map<String, String>,concurrentDownloadsEnabled: null == concurrentDownloadsEnabled ? _self.concurrentDownloadsEnabled : concurrentDownloadsEnabled // ignore: cast_nullable_to_non_nullable
as bool,cdnBranchMirrors: null == cdnBranchMirrors ? _self.cdnBranchMirrors : cdnBranchMirrors // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [AssetRuntimeUpdateConfig].
extension AssetRuntimeUpdateConfigPatterns on AssetRuntimeUpdateConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssetRuntimeUpdateConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssetRuntimeUpdateConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssetRuntimeUpdateConfig value)  $default,){
final _that = this;
switch (_that) {
case _AssetRuntimeUpdateConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssetRuntimeUpdateConfig value)?  $default,){
final _that = this;
switch (_that) {
case _AssetRuntimeUpdateConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool fetchAtBuildEnabled,  bool updateCommitOnBuild,  String bundledCoinsRepoCommit,  String coinsRepoApiUrl,  String coinsRepoContentUrl,  String coinsRepoBranch,  bool runtimeUpdatesEnabled,  Map<String, String> mappedFiles,  Map<String, String> mappedFolders,  bool concurrentDownloadsEnabled,  Map<String, String> cdnBranchMirrors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssetRuntimeUpdateConfig() when $default != null:
return $default(_that.fetchAtBuildEnabled,_that.updateCommitOnBuild,_that.bundledCoinsRepoCommit,_that.coinsRepoApiUrl,_that.coinsRepoContentUrl,_that.coinsRepoBranch,_that.runtimeUpdatesEnabled,_that.mappedFiles,_that.mappedFolders,_that.concurrentDownloadsEnabled,_that.cdnBranchMirrors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool fetchAtBuildEnabled,  bool updateCommitOnBuild,  String bundledCoinsRepoCommit,  String coinsRepoApiUrl,  String coinsRepoContentUrl,  String coinsRepoBranch,  bool runtimeUpdatesEnabled,  Map<String, String> mappedFiles,  Map<String, String> mappedFolders,  bool concurrentDownloadsEnabled,  Map<String, String> cdnBranchMirrors)  $default,) {final _that = this;
switch (_that) {
case _AssetRuntimeUpdateConfig():
return $default(_that.fetchAtBuildEnabled,_that.updateCommitOnBuild,_that.bundledCoinsRepoCommit,_that.coinsRepoApiUrl,_that.coinsRepoContentUrl,_that.coinsRepoBranch,_that.runtimeUpdatesEnabled,_that.mappedFiles,_that.mappedFolders,_that.concurrentDownloadsEnabled,_that.cdnBranchMirrors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool fetchAtBuildEnabled,  bool updateCommitOnBuild,  String bundledCoinsRepoCommit,  String coinsRepoApiUrl,  String coinsRepoContentUrl,  String coinsRepoBranch,  bool runtimeUpdatesEnabled,  Map<String, String> mappedFiles,  Map<String, String> mappedFolders,  bool concurrentDownloadsEnabled,  Map<String, String> cdnBranchMirrors)?  $default,) {final _that = this;
switch (_that) {
case _AssetRuntimeUpdateConfig() when $default != null:
return $default(_that.fetchAtBuildEnabled,_that.updateCommitOnBuild,_that.bundledCoinsRepoCommit,_that.coinsRepoApiUrl,_that.coinsRepoContentUrl,_that.coinsRepoBranch,_that.runtimeUpdatesEnabled,_that.mappedFiles,_that.mappedFolders,_that.concurrentDownloadsEnabled,_that.cdnBranchMirrors);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true, fieldRename: FieldRename.snake)
class _AssetRuntimeUpdateConfig implements AssetRuntimeUpdateConfig {
  const _AssetRuntimeUpdateConfig({this.fetchAtBuildEnabled = true, this.updateCommitOnBuild = true, this.bundledCoinsRepoCommit = 'master', this.coinsRepoApiUrl = 'https://api.github.com/repos/GLEECBTC/coins', this.coinsRepoContentUrl = 'https://raw.githubusercontent.com/GLEECBTC/coins', this.coinsRepoBranch = 'master', this.runtimeUpdatesEnabled = true, final  Map<String, String> mappedFiles = const <String, String>{'assets/config/coins_config.json' : 'utils/coins_config_unfiltered.json', 'assets/config/coins.json' : 'coins', 'assets/config/seed_nodes.json' : 'seed-nodes.json'}, final  Map<String, String> mappedFolders = const <String, String>{'assets/coin_icons/png/' : 'icons'}, this.concurrentDownloadsEnabled = false, final  Map<String, String> cdnBranchMirrors = const <String, String>{'master' : 'https://gleecbtc.github.io/coins', 'main' : 'https://gleecbtc.github.io/coins'}}): _mappedFiles = mappedFiles,_mappedFolders = mappedFolders,_cdnBranchMirrors = cdnBranchMirrors;
  factory _AssetRuntimeUpdateConfig.fromJson(Map<String, dynamic> json) => _$AssetRuntimeUpdateConfigFromJson(json);

// Mirrors `coins` section in build_config.json
@override@JsonKey() final  bool fetchAtBuildEnabled;
@override@JsonKey() final  bool updateCommitOnBuild;
@override@JsonKey() final  String bundledCoinsRepoCommit;
@override@JsonKey() final  String coinsRepoApiUrl;
@override@JsonKey() final  String coinsRepoContentUrl;
@override@JsonKey() final  String coinsRepoBranch;
@override@JsonKey() final  bool runtimeUpdatesEnabled;
 final  Map<String, String> _mappedFiles;
@override@JsonKey() Map<String, String> get mappedFiles {
  if (_mappedFiles is EqualUnmodifiableMapView) return _mappedFiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_mappedFiles);
}

 final  Map<String, String> _mappedFolders;
@override@JsonKey() Map<String, String> get mappedFolders {
  if (_mappedFolders is EqualUnmodifiableMapView) return _mappedFolders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_mappedFolders);
}

@override@JsonKey() final  bool concurrentDownloadsEnabled;
 final  Map<String, String> _cdnBranchMirrors;
@override@JsonKey() Map<String, String> get cdnBranchMirrors {
  if (_cdnBranchMirrors is EqualUnmodifiableMapView) return _cdnBranchMirrors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_cdnBranchMirrors);
}


/// Create a copy of AssetRuntimeUpdateConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssetRuntimeUpdateConfigCopyWith<_AssetRuntimeUpdateConfig> get copyWith => __$AssetRuntimeUpdateConfigCopyWithImpl<_AssetRuntimeUpdateConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AssetRuntimeUpdateConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssetRuntimeUpdateConfig&&(identical(other.fetchAtBuildEnabled, fetchAtBuildEnabled) || other.fetchAtBuildEnabled == fetchAtBuildEnabled)&&(identical(other.updateCommitOnBuild, updateCommitOnBuild) || other.updateCommitOnBuild == updateCommitOnBuild)&&(identical(other.bundledCoinsRepoCommit, bundledCoinsRepoCommit) || other.bundledCoinsRepoCommit == bundledCoinsRepoCommit)&&(identical(other.coinsRepoApiUrl, coinsRepoApiUrl) || other.coinsRepoApiUrl == coinsRepoApiUrl)&&(identical(other.coinsRepoContentUrl, coinsRepoContentUrl) || other.coinsRepoContentUrl == coinsRepoContentUrl)&&(identical(other.coinsRepoBranch, coinsRepoBranch) || other.coinsRepoBranch == coinsRepoBranch)&&(identical(other.runtimeUpdatesEnabled, runtimeUpdatesEnabled) || other.runtimeUpdatesEnabled == runtimeUpdatesEnabled)&&const DeepCollectionEquality().equals(other._mappedFiles, _mappedFiles)&&const DeepCollectionEquality().equals(other._mappedFolders, _mappedFolders)&&(identical(other.concurrentDownloadsEnabled, concurrentDownloadsEnabled) || other.concurrentDownloadsEnabled == concurrentDownloadsEnabled)&&const DeepCollectionEquality().equals(other._cdnBranchMirrors, _cdnBranchMirrors));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,fetchAtBuildEnabled,updateCommitOnBuild,bundledCoinsRepoCommit,coinsRepoApiUrl,coinsRepoContentUrl,coinsRepoBranch,runtimeUpdatesEnabled,const DeepCollectionEquality().hash(_mappedFiles),const DeepCollectionEquality().hash(_mappedFolders),concurrentDownloadsEnabled,const DeepCollectionEquality().hash(_cdnBranchMirrors));

@override
String toString() {
  return 'AssetRuntimeUpdateConfig(fetchAtBuildEnabled: $fetchAtBuildEnabled, updateCommitOnBuild: $updateCommitOnBuild, bundledCoinsRepoCommit: $bundledCoinsRepoCommit, coinsRepoApiUrl: $coinsRepoApiUrl, coinsRepoContentUrl: $coinsRepoContentUrl, coinsRepoBranch: $coinsRepoBranch, runtimeUpdatesEnabled: $runtimeUpdatesEnabled, mappedFiles: $mappedFiles, mappedFolders: $mappedFolders, concurrentDownloadsEnabled: $concurrentDownloadsEnabled, cdnBranchMirrors: $cdnBranchMirrors)';
}


}

/// @nodoc
abstract mixin class _$AssetRuntimeUpdateConfigCopyWith<$Res> implements $AssetRuntimeUpdateConfigCopyWith<$Res> {
  factory _$AssetRuntimeUpdateConfigCopyWith(_AssetRuntimeUpdateConfig value, $Res Function(_AssetRuntimeUpdateConfig) _then) = __$AssetRuntimeUpdateConfigCopyWithImpl;
@override @useResult
$Res call({
 bool fetchAtBuildEnabled, bool updateCommitOnBuild, String bundledCoinsRepoCommit, String coinsRepoApiUrl, String coinsRepoContentUrl, String coinsRepoBranch, bool runtimeUpdatesEnabled, Map<String, String> mappedFiles, Map<String, String> mappedFolders, bool concurrentDownloadsEnabled, Map<String, String> cdnBranchMirrors
});




}
/// @nodoc
class __$AssetRuntimeUpdateConfigCopyWithImpl<$Res>
    implements _$AssetRuntimeUpdateConfigCopyWith<$Res> {
  __$AssetRuntimeUpdateConfigCopyWithImpl(this._self, this._then);

  final _AssetRuntimeUpdateConfig _self;
  final $Res Function(_AssetRuntimeUpdateConfig) _then;

/// Create a copy of AssetRuntimeUpdateConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fetchAtBuildEnabled = null,Object? updateCommitOnBuild = null,Object? bundledCoinsRepoCommit = null,Object? coinsRepoApiUrl = null,Object? coinsRepoContentUrl = null,Object? coinsRepoBranch = null,Object? runtimeUpdatesEnabled = null,Object? mappedFiles = null,Object? mappedFolders = null,Object? concurrentDownloadsEnabled = null,Object? cdnBranchMirrors = null,}) {
  return _then(_AssetRuntimeUpdateConfig(
fetchAtBuildEnabled: null == fetchAtBuildEnabled ? _self.fetchAtBuildEnabled : fetchAtBuildEnabled // ignore: cast_nullable_to_non_nullable
as bool,updateCommitOnBuild: null == updateCommitOnBuild ? _self.updateCommitOnBuild : updateCommitOnBuild // ignore: cast_nullable_to_non_nullable
as bool,bundledCoinsRepoCommit: null == bundledCoinsRepoCommit ? _self.bundledCoinsRepoCommit : bundledCoinsRepoCommit // ignore: cast_nullable_to_non_nullable
as String,coinsRepoApiUrl: null == coinsRepoApiUrl ? _self.coinsRepoApiUrl : coinsRepoApiUrl // ignore: cast_nullable_to_non_nullable
as String,coinsRepoContentUrl: null == coinsRepoContentUrl ? _self.coinsRepoContentUrl : coinsRepoContentUrl // ignore: cast_nullable_to_non_nullable
as String,coinsRepoBranch: null == coinsRepoBranch ? _self.coinsRepoBranch : coinsRepoBranch // ignore: cast_nullable_to_non_nullable
as String,runtimeUpdatesEnabled: null == runtimeUpdatesEnabled ? _self.runtimeUpdatesEnabled : runtimeUpdatesEnabled // ignore: cast_nullable_to_non_nullable
as bool,mappedFiles: null == mappedFiles ? _self._mappedFiles : mappedFiles // ignore: cast_nullable_to_non_nullable
as Map<String, String>,mappedFolders: null == mappedFolders ? _self._mappedFolders : mappedFolders // ignore: cast_nullable_to_non_nullable
as Map<String, String>,concurrentDownloadsEnabled: null == concurrentDownloadsEnabled ? _self.concurrentDownloadsEnabled : concurrentDownloadsEnabled // ignore: cast_nullable_to_non_nullable
as bool,cdnBranchMirrors: null == cdnBranchMirrors ? _self._cdnBranchMirrors : cdnBranchMirrors // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

// dart format on
