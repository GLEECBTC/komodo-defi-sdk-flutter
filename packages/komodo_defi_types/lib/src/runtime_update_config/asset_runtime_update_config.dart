import 'package:freezed_annotation/freezed_annotation.dart';

part 'asset_runtime_update_config.freezed.dart';
part 'asset_runtime_update_config.g.dart';

/// Configuration for the runtime update process.
///
/// Mirrors the `coins` section in build_config.json.
@freezed
abstract class AssetRuntimeUpdateConfig with _$AssetRuntimeUpdateConfig {
  /// Configuration for the runtime update process.
  ///
  /// Mirrors the `coins` section in build_config.json.
  @JsonSerializable(explicitToJson: true, fieldRename: FieldRename.snake)
  const factory AssetRuntimeUpdateConfig({
    // Mirrors `coins` section in build_config.json
    @Default(true) bool fetchAtBuildEnabled,
    @Default(true) bool updateCommitOnBuild,
    @Default('master') String bundledCoinsRepoCommit,
    @Default('https://api.github.com/repos/GLEECBTC/coins')
    String coinsRepoApiUrl,
    @Default('https://raw.githubusercontent.com/GLEECBTC/coins')
    String coinsRepoContentUrl,
    @Default('master') String coinsRepoBranch,
    @Default(true) bool runtimeUpdatesEnabled,
    @Default(<String, String>{
      'assets/config/coins_config.json': 'utils/coins_config_unfiltered.json',
      'assets/config/coins.json': 'coins',
      'assets/config/seed_nodes.json': 'seed-nodes.json',
    })
    Map<String, String> mappedFiles,
    @Default(<String, String>{'assets/coin_icons/png/': 'icons'})
    Map<String, String> mappedFolders,
    @Default(false) bool concurrentDownloadsEnabled,
    @Default(<String, String>{
      'master': 'https://gleecbtc.github.io/coins',
      'main': 'https://gleecbtc.github.io/coins',
    })
    Map<String, String> cdnBranchMirrors,
  }) = _AssetRuntimeUpdateConfig;

  /// Creates a [AssetRuntimeUpdateConfig] from a JSON map.
  factory AssetRuntimeUpdateConfig.fromJson(Map<String, dynamic> json) =>
      _$AssetRuntimeUpdateConfigFromJson(json);

  /// Builds a content URL for fetching repository content, preferring CDN mirrors when available.
  ///
  /// This method implements the standard logic for choosing between CDN mirrors and
  /// raw GitHub URLs based on the branch/commit and available CDN mirrors.
  ///
  /// Logic:
  /// 1. If [branchOrCommit] looks like a commit hash (40 hex chars), always use raw GitHub URL
  /// 2. If [branchOrCommit] is a branch name found in [cdnBranchMirrors], use CDN URL
  /// 3. Otherwise, fall back to raw GitHub URL
  ///
  /// [path] - The path to the resource in the repository (e.g., 'seed-nodes.json')
  /// [branchOrCommit] - The branch name or commit hash (defaults to [coinsRepoBranch])
  static Uri buildContentUrl({
    required String path,
    required String coinsRepoContentUrl,
    required String coinsRepoBranch,
    required Map<String, String> cdnBranchMirrors,
    String? branchOrCommit,
  }) {
    branchOrCommit ??= coinsRepoBranch;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;

    final String? cdnBase = cdnBranchMirrors[branchOrCommit];
    if (cdnBase != null && cdnBase.isNotEmpty) {
      final baseWithSlash = cdnBase.endsWith('/') ? cdnBase : '$cdnBase/';
      final baseUri = Uri.parse(baseWithSlash);
      return baseUri.resolve(normalizedPath);
    }

    // Use GitHub raw URL with branch or commit hash
    final contentBaseWithSlash = coinsRepoContentUrl.endsWith('/')
        ? coinsRepoContentUrl
        : '$coinsRepoContentUrl/';
    final contentBase = Uri.parse(
      contentBaseWithSlash,
    ).resolve('$branchOrCommit/');
    return contentBase.resolve(normalizedPath);
  }
}
