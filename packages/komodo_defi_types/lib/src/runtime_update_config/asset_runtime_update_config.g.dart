// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset_runtime_update_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AssetRuntimeUpdateConfig _$AssetRuntimeUpdateConfigFromJson(
  Map<String, dynamic> json,
) => _AssetRuntimeUpdateConfig(
  fetchAtBuildEnabled: json['fetch_at_build_enabled'] as bool? ?? true,
  updateCommitOnBuild: json['update_commit_on_build'] as bool? ?? true,
  bundledCoinsRepoCommit:
      json['bundled_coins_repo_commit'] as String? ?? 'master',
  coinsRepoApiUrl:
      json['coins_repo_api_url'] as String? ??
      'https://api.github.com/repos/GLEECBTC/coins',
  coinsRepoContentUrl:
      json['coins_repo_content_url'] as String? ??
      'https://raw.githubusercontent.com/GLEECBTC/coins',
  coinsRepoBranch: json['coins_repo_branch'] as String? ?? 'master',
  runtimeUpdatesEnabled: json['runtime_updates_enabled'] as bool? ?? true,
  mappedFiles:
      (json['mapped_files'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const <String, String>{
        'assets/config/coins_config.json': 'utils/coins_config_unfiltered.json',
        'assets/config/coins.json': 'coins',
        'assets/config/seed_nodes.json': 'seed-nodes.json',
      },
  mappedFolders:
      (json['mapped_folders'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const <String, String>{'assets/coin_icons/png/': 'icons'},
  concurrentDownloadsEnabled:
      json['concurrent_downloads_enabled'] as bool? ?? false,
  cdnBranchMirrors:
      (json['cdn_branch_mirrors'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const <String, String>{
        'master': 'https://gleecbtc.github.io/coins',
        'main': 'https://gleecbtc.github.io/coins',
      },
);

Map<String, dynamic> _$AssetRuntimeUpdateConfigToJson(
  _AssetRuntimeUpdateConfig instance,
) => <String, dynamic>{
  'fetch_at_build_enabled': instance.fetchAtBuildEnabled,
  'update_commit_on_build': instance.updateCommitOnBuild,
  'bundled_coins_repo_commit': instance.bundledCoinsRepoCommit,
  'coins_repo_api_url': instance.coinsRepoApiUrl,
  'coins_repo_content_url': instance.coinsRepoContentUrl,
  'coins_repo_branch': instance.coinsRepoBranch,
  'runtime_updates_enabled': instance.runtimeUpdatesEnabled,
  'mapped_files': instance.mappedFiles,
  'mapped_folders': instance.mappedFolders,
  'concurrent_downloads_enabled': instance.concurrentDownloadsEnabled,
  'cdn_branch_mirrors': instance.cdnBranchMirrors,
};
