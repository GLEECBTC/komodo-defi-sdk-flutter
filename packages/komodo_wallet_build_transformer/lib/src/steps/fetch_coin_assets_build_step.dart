import 'dart:io';
import 'dart:isolate';

import 'package:komodo_wallet_build_transformer/src/build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/github/github_api_provider.dart';
import 'package:komodo_wallet_build_transformer/src/steps/github/github_file_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_progress_message.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/coin_assets/coin_build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/github/github_file.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/result.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// A build step that fetches coin assets from a GitHub repository.
class FetchCoinAssetsBuildStep extends BuildStep {
  FetchCoinAssetsBuildStep({
    required this.artifactOutputDirectory,
    required this.config,
    required this.downloader,
    required this.originalBuildConfig,
    required this.buildConfigOutput,
    required this.githubApiProvider,
    this.receivePort,
    this.enabled = true,
  }) {
    receivePort?.listen(
      (dynamic message) => onProgressData(message, receivePort),
      onError: onProgressError,
    );
  }

  factory FetchCoinAssetsBuildStep.withBuildConfig(
    BuildConfig buildConfig,
    File outputBuildConfigFile, {
    required Directory artifactOutputDirectory,
    ReceivePort? receivePort,
    String? githubToken,
  }) {
    // Use the original config unchanged to preserve user configuration
    final config = buildConfig.coinCIConfig;

    final provider = GithubApiProvider.withBaseUrl(
      baseUrl: config.coinsRepoApiUrl,
      branch: config.coinsRepoBranch,
      token: githubToken,
    );

    final downloader = GitHubFileDownloader(
      apiProvider: provider,
      // Branch mirrors serve mutable content and do not encode the commit.
      // Frozen builds must use the configured source at the pinned revision.
      repoContentUrl: config.updateCommitOnBuild
          ? config.effectiveContentUrl
          : config.coinsRepoContentUrl,
    );

    return FetchCoinAssetsBuildStep(
      artifactOutputDirectory: artifactOutputDirectory.path,
      config: config,
      downloader: downloader,
      originalBuildConfig: buildConfig,
      buildConfigOutput: outputBuildConfigFile,
      githubApiProvider: provider,
      receivePort: receivePort,
      enabled: config.fetchAtBuildEnabled,
    );
  }

  final File buildConfigOutput;
  final BuildConfig? originalBuildConfig;
  final String artifactOutputDirectory;
  final CoinBuildConfig config;
  final GitHubFileDownloader downloader;
  final ReceivePort? receivePort;
  final GithubApiProvider githubApiProvider;
  final _log = Logger('FetchCoinAssetsBuildStep');

  @override
  final String id = idStatic;
  static const idStatic = 'fetch_coin_assets';
  final bool enabled;

  @override
  Future<void> build() async {
    // Check if the coin assets already exist in the artifact directory
    final alreadyHadCoinAssets = File(
      '$artifactOutputDirectory/assets/config/coins.json',
    ).existsSync();

    final isDebugBuild =
        (Platform.environment['FLUTTER_BUILD_MODE'] ?? '').toLowerCase() ==
        'debug';
    var configWithUpdatedCommit = config;

    if (config.updateCommitOnBuild) {
      final latestCommitHash = await githubApiProvider.getLatestCommitHash(
        branch: config.coinsRepoBranch,
      );
      _log.info('Updating commit hash in build config');
      configWithUpdatedCommit = config.copyWith(
        bundledCoinsRepoCommit: latestCommitHash,
      );
      await configWithUpdatedCommit.save(
        assetPath: buildConfigOutput.path,
        originalBuildConfig: originalBuildConfig,
      );
    }

    final downloadMethod = config.concurrentDownloadsEnabled
        ? downloader.download
        : downloader.downloadSync;
    final frozenAssetsWereCurrent =
        config.updateCommitOnBuild ||
        (await _canSkipMappedFiles(
              config.mappedFiles,
              config.bundledCoinsRepoCommit,
            ) &&
            await _canSkipMappedFolders(
              config.mappedFolders,
              config.bundledCoinsRepoCommit,
            ));
    await downloadMethod(
      configWithUpdatedCommit.bundledCoinsRepoCommit,
      _adjustPaths(configWithUpdatedCommit.mappedFiles),
      _adjustPaths(configWithUpdatedCommit.mappedFolders),
    );

    if (!config.updateCommitOnBuild &&
        (!await _canSkipMappedFiles(
              config.mappedFiles,
              config.bundledCoinsRepoCommit,
            ) ||
            !await _canSkipMappedFolders(
              config.mappedFolders,
              config.bundledCoinsRepoCommit,
            ))) {
      throw StateError('Downloaded coin assets do not match the pinned commit');
    }

    final wasCommitHashUpdated =
        config.bundledCoinsRepoCommit !=
        configWithUpdatedCommit.bundledCoinsRepoCommit;

    if (wasCommitHashUpdated ||
        !alreadyHadCoinAssets ||
        !frozenAssetsWereCurrent) {
      final errorMessage =
          '''
        \n
        ${'=-' * 20}
        BUILD FAILED

        What: Coin assets were updated.

        How to fix: Re-run the build process for the changes to take effect.

        Why: This is due to a limitation in Flutter's build system. We're
        working on a fix to Flutter, but it will depend on Flutter team
        considering the PR.

        How to avoid: If you absolutely need to avoid this double build, you
        can manually run `flutter clean && flutter build bundle` but this is
        not recommended since the double build will be fixed in the future.

        For more details, follow the GLEECBTC Flutter fork:
        https://github.com/GLEECBTC/flutter
        ${'=-' * 20}
        \n
      ''';

      // If it's not a debug build and the commit hash was updated, throw an
      // exception to indicate that the build process should be re-run. We can
      // skip this check for debug builds if we already had coin assets.
      if (!isDebugBuild || !alreadyHadCoinAssets) {
        _log.shout(errorMessage);
        receivePort?.close();
        throw BuildStepWithoutRevertException(errorMessage);
      }

      _log.warning('$errorMessage\n');
    }

    receivePort?.close();
    _log.info('Coin assets fetched successfully. Build step completed.');
  }

  @override
  Future<bool> canSkip() async {
    if (!enabled) {
      return true;
    }

    if (config.updateCommitOnBuild) {
      final latestCommitHash = await githubApiProvider.getLatestCommitHash(
        branch: config.coinsRepoBranch,
      );
      if (latestCommitHash != config.bundledCoinsRepoCommit) return false;
    }

    if (!await _canSkipMappedFiles(
      config.mappedFiles,
      config.bundledCoinsRepoCommit,
    )) {
      _log.fine('Cannot skip build step: mapped files check failed');
      return false;
    }

    if (!await _canSkipMappedFolders(
      config.mappedFolders,
      config.bundledCoinsRepoCommit,
    )) {
      _log.fine('Cannot skip build step: mapped folders check failed');
      return false;
    }

    return true;
  }

  @override
  Future<void> revert([Exception? e]) async {
    if (e is BuildStepWithoutRevertException) {
      _log.warning(
        'Step not reverted because the build process was completed with '
        'changes',
      );

      return;
    }

    _log.info(
      'Reverting fetch coin assets build step. '
      'Reverting or deleting downloaded files.',
    );

    // Try `git checkout` to revert changes instead of deleting all files
    // because there may be mapped files/folders that are tracked by git
    final mappedFilePaths = config.mappedFiles.keys.toList();
    final mappedFolderPaths = config.mappedFolders.keys.toList();

    final mappedFolderFilePaths = mappedFolderPaths.map(_getFilesInFolder);

    final allFiles =
        mappedFilePaths +
        mappedFolderFilePaths.expand((List<String> x) => x).toList();

    await GitHubFileDownloader.revertOrDeleteGitFiles(allFiles);
  }

  Future<bool> _canSkipMappedFiles(
    Map<String, String> files,
    String repoCommit,
  ) async {
    for (final mappedFile in files.entries) {
      final remoteFile = await githubApiProvider.getFileMetadata(
        mappedFile.value,
        ref: repoCommit,
      );
      final canSkipFile = await _canSkipFile(
        path.join(artifactOutputDirectory, mappedFile.key),
        remoteFile,
      );
      if (!canSkipFile.success) {
        _log.info('Cannot skip build step: ${canSkipFile.error}');
        return false;
      }
    }

    return true;
  }

  Future<bool> _canSkipMappedFolders(
    Map<String, String> folders,
    String repoCommit,
  ) async {
    for (final mappedFolder in folders.entries) {
      final remoteFolderContents = await githubApiProvider.getDirectoryContents(
        mappedFolder.value,
        repoCommit,
      );
      final canSkipFolder = await _canSkipDirectory(
        path.join(artifactOutputDirectory, mappedFolder.key),
        remoteFolderContents,
      );

      if (!canSkipFolder.success) {
        _log.info('Cannot skip build step: ${canSkipFolder.error}');
        return false;
      }
    }
    return true;
  }

  Future<Result> _canSkipFile(
    String localFilePath,
    GitHubFile remoteFile,
  ) async {
    final localFile = File(localFilePath);

    if (!localFile.existsSync()) {
      return Result.error('$localFilePath does not exist');
    }

    final localFileSize = await localFile.length();
    if (remoteFile.size != localFileSize) {
      return Result.error(
        '$localFilePath size mismatch: '
        'remote: ${remoteFile.size}, local: $localFileSize',
      );
    }

    final localFileSha = calculateGithubSha1(localFilePath);
    if (localFileSha != remoteFile.sha) {
      return Result.error(
        '$localFilePath sha mismatch: '
        'remote: ${remoteFile.sha}, local: $localFileSha',
      );
    }

    return Result.success();
  }

  Future<Result> _canSkipDirectory(
    String directory,
    List<GitHubFile> remoteDirectoryContents,
  ) async {
    final localFolder = Directory(directory);

    if (!localFolder.existsSync()) {
      return Result.error('$directory does not exist');
    }

    if (!config.updateCommitOnBuild) {
      final expectedNames = remoteDirectoryContents
          .map((file) => file.name)
          .toSet();
      for (final entry in localFolder.listSync()) {
        final name = path.basename(entry.path);
        // The SDK tracks an empty placeholder for the generated directory.
        if (name == '.gitkeep' && entry is File && entry.lengthSync() == 0) {
          continue;
        }
        if (!expectedNames.contains(name)) {
          return Result.error(
            'Unexpected cached coin asset ${entry.path}; '
            'remove the generated asset folder and rebuild',
          );
        }
      }
    }

    for (final remoteFile in remoteDirectoryContents) {
      final localFilePath = path.join(directory, remoteFile.name);
      final canSkipFile = await _canSkipFile(localFilePath, remoteFile);
      if (!canSkipFile.success) {
        return Result.error('Cannot skip build step: ${canSkipFile.error}');
      }
    }

    return Result.success();
  }

  List<String> _getFilesInFolder(String folderPath) {
    final localFolder = Directory(folderPath);
    if (!localFolder.existsSync()) {
      return <String>[];
    }
    final localFolderContents = localFolder.listSync(recursive: true);
    return localFolderContents
        .map((FileSystemEntity file) => file.path)
        .toList();
  }

  Map<String, String> _adjustPaths(Map<String, String> paths) {
    return paths.map(
      (key, value) => MapEntry(path.join(artifactOutputDirectory, key), value),
    );
  }

  void onProgressError(dynamic error) {
    _log.severe('\nError: $error');

    // throw Exception('An error occurred during the coin fetch build step');
  }

  void onProgressData(dynamic message, ReceivePort? recevePort) {
    if (message is BuildProgressMessage) {
      _log.info(
        '\r${message.message} - Progress: '
        '${message.progress.toStringAsFixed(2)}% \x1b[K',
      );

      if (message.progress == 100 && message.finished) {
        _log.info('Progress: 100% - Done. Closing receive port');
        recevePort?.close();
      }
    } else {
      _log.warning('Received unknown message: $message');
    }
  }
}

class BuildStepWithoutRevertException implements Exception {
  BuildStepWithoutRevertException(this.message);

  final String message;

  @override
  String toString() => message;
}
