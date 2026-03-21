// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/github/github_file_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:komodo_wallet_build_transformer/src/util/ide_json_formatter.dart';
import 'package:path/path.dart' as path;

/// Represents the build configuration for fetching coin assets.
class CoinBuildConfig {
  /// Creates a new instance of [CoinBuildConfig].
  CoinBuildConfig({
    required this.fetchAtBuildEnabled,
    required this.bundledCoinsRepoCommit,
    required this.updateCommitOnBuild,
    required this.coinsRepoApiUrl,
    required this.coinsRepoContentUrl,
    required this.coinsRepoBranch,
    required this.runtimeUpdatesEnabled,
    required this.mappedFiles,
    required this.mappedFolders,
    required this.concurrentDownloadsEnabled,
    this.cdnBranchMirrors = const {},
  });

  /// Creates a new instance of [CoinBuildConfig] from a JSON object.
  factory CoinBuildConfig.fromJson(Map<String, dynamic> json) {
    return CoinBuildConfig(
      fetchAtBuildEnabled: json['fetch_at_build_enabled'] as bool? ?? true,
      updateCommitOnBuild: json['update_commit_on_build'] as bool? ?? true,
      bundledCoinsRepoCommit: json['bundled_coins_repo_commit'] as String,
      coinsRepoApiUrl: json['coins_repo_api_url'] as String,
      coinsRepoContentUrl: json['coins_repo_content_url'] as String,
      coinsRepoBranch: json['coins_repo_branch'] as String,
      runtimeUpdatesEnabled: json['runtime_updates_enabled'] as bool? ?? true,
      concurrentDownloadsEnabled:
          json['concurrent_downloads_enabled'] as bool? ?? true,
      mappedFiles: Map<String, String>.from(
        json['mapped_files'] as Map<String, dynamic>? ?? {},
      ),
      mappedFolders: Map<String, String>.from(
        json['mapped_folders'] as Map<String, dynamic>? ?? {},
      ),
      cdnBranchMirrors: Map<String, String>.from(
        json['cdn_branch_mirrors'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  /// Gets the appropriate content URL for the current branch.
  /// If a CDN mirror is configured for the branch, it uses that.
  /// Otherwise, it falls back to the configured coinsRepoContentUrl.
  String get effectiveContentUrl =>
      cdnBranchMirrors[coinsRepoBranch] ?? coinsRepoContentUrl;

  /// Indicates whether fetching updates of the coins assets are enabled.
  final bool fetchAtBuildEnabled;

  /// The commit hash or branch coins repository to use when fetching coin
  /// assets.
  final String bundledCoinsRepoCommit;

  /// Indicates whether the commit hash should be updated on build. If `true`,
  /// the commit hash will be updated and saved to the build configuration file.
  /// If `false`, the commit hash will not be updated and the configured commit
  /// hash will be used.
  final bool updateCommitOnBuild;

  /// Indicates whether concurrent downloads of coin assets are enabled.
  /// If `true`, multiple coin assets will be downloaded concurrently.
  /// If `false`, coin assets will be downloaded sequentially.
  final bool concurrentDownloadsEnabled;

  /// The GitHub API of the coins repository used to fetch directory contents
  /// with SHA hashes from the GitHub API.
  final String coinsRepoApiUrl;

  /// The raw content GitHub URL of the coins repository used to fetch assets.
  final String coinsRepoContentUrl;

  /// The branch of the coins repository to use for fetching assets.
  final String coinsRepoBranch;

  /// Indicates whether runtime updates of the coins assets are enabled.
  ///
  /// NB: This does not affect the build process.
  final bool runtimeUpdatesEnabled;

  /// A map of mapped files to download.
  /// The keys represent the local paths where the files will be saved,
  /// and the values represent the relative paths of the files in the repository
  final Map<String, String> mappedFiles;

  /// A map of mapped folders to download. The keys represent the local paths
  /// where the folders will be saved, and the values represent the
  /// corresponding paths in the GitHub repository.
  final Map<String, String> mappedFolders;

  /// A map of branch names to CDN mirror URLs.
  /// When downloading assets, if the current branch has a CDN mirror
  /// configured, it will be used instead of the default content URL.
  /// This helps avoid rate limiting for commonly used branches.
  final Map<String, String> cdnBranchMirrors;

  CoinBuildConfig copyWith({
    String? bundledCoinsRepoCommit,
    bool? fetchAtBuildEnabled,
    bool? updateCommitOnBuild,
    String? coinsRepoApiUrl,
    String? coinsRepoContentUrl,
    String? coinsRepoBranch,
    bool? runtimeUpdatesEnabled,
    bool? concurrentDownloadsEnabled,
    Map<String, String>? mappedFiles,
    Map<String, String>? mappedFolders,
    Map<String, String>? cdnBranchMirrors,
  }) {
    return CoinBuildConfig(
      fetchAtBuildEnabled: fetchAtBuildEnabled ?? this.fetchAtBuildEnabled,
      updateCommitOnBuild: updateCommitOnBuild ?? this.updateCommitOnBuild,
      bundledCoinsRepoCommit:
          bundledCoinsRepoCommit ?? this.bundledCoinsRepoCommit,
      coinsRepoApiUrl: coinsRepoApiUrl ?? this.coinsRepoApiUrl,
      coinsRepoContentUrl: coinsRepoContentUrl ?? this.coinsRepoContentUrl,
      coinsRepoBranch: coinsRepoBranch ?? this.coinsRepoBranch,
      runtimeUpdatesEnabled:
          runtimeUpdatesEnabled ?? this.runtimeUpdatesEnabled,
      concurrentDownloadsEnabled:
          concurrentDownloadsEnabled ?? this.concurrentDownloadsEnabled,
      mappedFiles: mappedFiles ?? this.mappedFiles,
      mappedFolders: mappedFolders ?? this.mappedFolders,
      cdnBranchMirrors: cdnBranchMirrors ?? this.cdnBranchMirrors,
    );
  }

  /// Converts the [CoinBuildConfig] instance to a JSON object.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'fetch_at_build_enabled': fetchAtBuildEnabled,
    'update_commit_on_build': updateCommitOnBuild,
    'bundled_coins_repo_commit': bundledCoinsRepoCommit,
    'coins_repo_api_url': coinsRepoApiUrl,
    'coins_repo_content_url': coinsRepoContentUrl,
    'coins_repo_branch': coinsRepoBranch,
    'runtime_updates_enabled': runtimeUpdatesEnabled,
    'mapped_files': mappedFiles,
    'mapped_folders': mappedFolders,
    'concurrent_downloads_enabled': concurrentDownloadsEnabled,
    'cdn_branch_mirrors': cdnBranchMirrors,
  };

  /// Loads the coins runtime update configuration synchronously from the
  /// specified [path].
  ///
  /// Prints the path from which the configuration is being loaded.
  /// Reads the contents of the file at the specified path and decodes it as
  /// JSON.
  /// If the 'coins' key is not present in the decoded data, prints an error
  /// message and exits with code 1.
  /// Returns a [CoinBuildConfig] object created from the decoded 'coins' data.
  static CoinBuildConfig loadSync(String path) {
    print('Loading coins updates config from $path');

    try {
      final file = File(path);
      final contents = file.readAsStringSync();
      final data = jsonDecode(contents) as Map<String, dynamic>;

      return CoinBuildConfig.fromJson(
        data['coins'] as Map<String, dynamic>? ?? {},
      );
    } catch (e) {
      print('Error loading coins updates config: $e');
      throw Exception('Error loading coins update config');
    }
  }

  /// Saves the coins configuration to the specified asset path and optionally
  /// updates the build configuration file.
  ///
  /// The [assetPath] parameter specifies the path where the coins configuration
  /// will be saved.
  /// If [originalBuildConfig] is provided, the coins configuration will be
  /// merged with the original build configuration before saving.
  ///
  /// Throws an exception if any error occurs during the saving process.
  Future<void> save({
    required String assetPath,
    BuildConfig? originalBuildConfig,
  }) async {
    final foldersToCreate = <String>[path.dirname(assetPath)];
    createFolders(foldersToCreate);

    final mergedConfig = (originalBuildConfig?.toJson() ?? {})
      ..addAll({'coins': toJson()});

    print('Saving coin assets config to $assetPath');
    final data = formatJsonForIde(mergedConfig);
    await File(assetPath).writeAsString(data, flush: true);
  }
}
