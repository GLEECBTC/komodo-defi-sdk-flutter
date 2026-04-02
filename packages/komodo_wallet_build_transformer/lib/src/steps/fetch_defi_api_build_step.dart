import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:komodo_wallet_build_transformer/src/build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader_factory.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/macos_artefact_layout_normalizer.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/node_path.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_platform_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

class FetchDefiApiStep extends BuildStep {
  FetchDefiApiStep._({
    // required this.projectRoot,
    required this.apiCommitHash,
    required this.platformsConfig,
    required this.sourceUrls,
    required this.artefactDownloaders,
    required this.artifactOutputPath,
    required this.buildConfigFile,
    // ignore: unused_element, unused_element_parameter
    this.selectedPlatform,
    // ignore: unused_element, unused_element_parameter
    this.forceUpdate = false,
    this.enabled = true,
    this.concurrent = true,
  });

  factory FetchDefiApiStep.withBuildConfig(
    BuildConfig buildConfig,
    Directory artifactOutputPath,
    File buildConfigFile, {
    String? githubToken,
  }) {
    final artefactDownloaders = ArtefactDownloaderFactory.fromBuildConfig(
      buildConfig.apiConfig,
      githubToken: githubToken,
    );

    return FetchDefiApiStep._(
      apiCommitHash: buildConfig.apiConfig.apiCommitHash,
      platformsConfig: buildConfig.apiConfig.platforms,
      sourceUrls: buildConfig.apiConfig.sourceUrls,
      artefactDownloaders: artefactDownloaders,
      // TODO: Change type to Directory?
      artifactOutputPath: artifactOutputPath.path,
      enabled: buildConfig.apiConfig.fetchAtBuildEnabled,
      buildConfigFile: buildConfigFile,
      concurrent: buildConfig.coinCIConfig.concurrentDownloadsEnabled,
    );
  }
  @override
  final String id = idStatic;
  static const idStatic = 'fetch_defi_api';
  static const String _overrideEnvName = 'OVERRIDE_DEFI_API_DOWNLOAD';

  final _log = Logger('FetchDefiApiStep');

  // final String projectRoot;
  final String apiCommitHash;
  final Map<String, ApiBuildPlatformConfig> platformsConfig;
  final List<String> sourceUrls;
  final Map<String, ArtefactDownloader> artefactDownloaders;
  final String artifactOutputPath;
  final File buildConfigFile;
  String? selectedPlatform;
  bool forceUpdate;
  bool enabled;
  final bool concurrent;

  List<String> get platformsToUpdate =>
      selectedPlatform != null && platformsConfig.containsKey(selectedPlatform)
      ? [selectedPlatform!]
      : platformsConfig.keys.toList();

  @override
  Future<void> build() async {
    if (!enabled) {
      _log.info('API update is not enabled in the configuration.');
      return;
    }
    try {
      await updateAPI();
    } catch (e, s) {
      _log.severe('Error updating API', e, s);
      rethrow;
    }
  }

  @override
  Future<bool> canSkip() => Future.value(!enabled);

  @override
  Future<void> revert([Exception? e]) async {
    _log.warning('Reverting changes made by UpdateAPIStep...');
  }

  Future<void> updateAPI() async {
    if (!enabled) {
      _log.info('API update is not enabled in the configuration.');
      return;
    }

    _log.info('=====================');
    if (concurrent) {
      await Future.wait(platformsToUpdate.map(updatePlatformWithProgress));
    } else {
      await Future.forEach(platformsToUpdate, updatePlatformWithProgress);
    }
    _log.info('=====================');
    _updateDocumentationIfExists();
  }

  Future<void> updatePlatformWithProgress(String platform) async {
    if (_isTargetIphone() && platform != 'ios') {
      _log.info('Skipping build for $platform, since target is iOS');
      return;
    }

    final progressString =
        '${platformsToUpdate.indexOf(platform) + 1}/${platformsToUpdate.length}';
    _log.info('[$progressString] Updating $platform platform...');
    final platformConfig = platformsConfig[platform];
    if (platformConfig == null) {
      _log.severe('Platform $platform is not configured');
      return;
    }
    await _updatePlatform(platform, platformConfig);
  }

  /// If set, the OVERRIDE_DEFI_API_DOWNLOAD environment variable will override
  /// any default behavior/configuration. e.g.
  // ignore: lines_longer_than_80_chars
  /// `flutter build web --release --dart-define=OVERRIDE_DEFI_API_DOWNLOAD=true`
  ///  or `OVERRIDE_DEFI_API_DOWNLOAD=true && flutter build web --release`
  ///
  /// If set to true/TRUE/True, the API will be fetched and downloaded on every
  /// build, even if it is already up-to-date with the configuration.
  ///
  /// If set to false/FALSE/False, the API fetching will be skipped, even if
  /// the existing API is not up-to-date with the configuration.
  ///
  /// If unset, the default behavior will be used.
  ///
  /// If both the system environment variable and the dart-defined environment
  /// variable are set, the dart-defined variable will take precedence.
  ///
  /// NB! Setting the value to false is not the same as it being unset.
  /// If the value is unset, the default behavior will be used.
  /// Bear this in mind when setting the value as a system environment variable.
  ///
  /// See `BUILD_CONFIG_README.md`  in `app_build/BUILD_CONFIG_README.md`.
  bool? get overrideDefiApiDownload =>
      const bool.hasEnvironment(_overrideEnvName)
      ? const bool.fromEnvironment(_overrideEnvName)
      : Platform.environment[_overrideEnvName] != null
      ? bool.tryParse(
          Platform.environment[_overrideEnvName]!,
          caseSensitive: false,
        )
      : null;

  Future<void> _updatePlatform(
    String platform,
    ApiBuildPlatformConfig config,
  ) async {
    final updateMessage = overrideDefiApiDownload != null
        ? '${overrideDefiApiDownload! ? 'FORCING' : 'SKIPPING'} update of '
              '$platform platform because OVERRIDE_DEFI_API_DOWNLOAD is set to '
              '$overrideDefiApiDownload'
        : null;

    if (updateMessage != null) {
      _log.info(updateMessage);
    }

    final destinationFolder = _getPlatformDestinationFolder(platform);
    final isOutdated = await _checkIfOutdated(
      platform,
      destinationFolder,
      config,
    );

    if (!_shouldUpdate(isOutdated)) {
      _log.info('$platform platform is up to date.');
      await _postUpdateActions(platform, destinationFolder);
      return;
    }

    String? zipFilePath;
    for (final sourceUrl in sourceUrls) {
      try {
        _log.fine('Attempting to download from $sourceUrl for $platform');

        final downloader = artefactDownloaders[sourceUrl];
        if (downloader == null) {
          throw ArgumentError.value(sourceUrl, '', 'No downloader found');
        }

        final zipFileUrl = await downloader.fetchDownloadUrl(
          config.matchingConfig,
          platform,
        );
        zipFilePath = await downloader.downloadArtefact(
          url: zipFileUrl,
          destinationPath: destinationFolder,
        );

        if (await _verifyChecksum(zipFilePath, platform)) {
          await _extractAndInstallArtefact(
            downloader: downloader,
            filePath: zipFilePath,
            destinationFolder: destinationFolder,
            platform: platform,
          );
          _updateLastUpdatedFile(platform, destinationFolder, zipFilePath);
          _log.info('$platform platform update completed.');
          break;
        } else {
          _log.warning('SHA256 Checksum verification failed for $zipFilePath');
          if (sourceUrl == sourceUrls.last) {
            throw Exception(
              'API fetch failed for all source URLs: $sourceUrls',
            );
          }
        }
      } catch (e) {
        _log.severe('Error updating from source $sourceUrl: $e');
        if (sourceUrl == sourceUrls.last) {
          rethrow;
        }
      } finally {
        if (zipFilePath != null) {
          try {
            File(zipFilePath).deleteSync();
            _log.info('Deleted zip file $zipFilePath');
          } catch (e) {
            _log.severe('Error deleting zip file', e);
          }
        }
      }
    }

    await _postUpdateActions(platform, destinationFolder);
  }

  bool _shouldUpdate(bool isOutdated) {
    return overrideDefiApiDownload ?? (forceUpdate || isOutdated);
  }

  Future<bool> _verifyChecksum(String filePath, String platform) async {
    final validChecksums = List<String>.from(
      platformsConfig[platform]!.validZipSha256Checksums,
    );

    _log.info('validChecksums: $validChecksums');

    final fileBytes = await File(filePath).readAsBytes();
    final fileSha256Checksum = sha256.convert(fileBytes).toString();

    if (validChecksums.contains(fileSha256Checksum)) {
      _log.info('Checksum validated for $filePath');
      return true;
    } else {
      _log.severe(
        'SHA256 Checksum mismatch for $filePath: expected any of '
        '$validChecksums, got $fileSha256Checksum',
      );
      return false;
    }
  }

  void _updateLastUpdatedFile(
    String platform,
    String destinationFolder,
    String zipFilePath,
  ) {
    final lastUpdatedFile = File(
      path.join(destinationFolder, '.api_last_updated_$platform'),
    );
    lastUpdatedFile.parent.createSync(recursive: true);
    final currentTimestamp = DateTime.now().toIso8601String();
    final targetChecksums = List<String>.from(
      platformsConfig[platform]!.validZipSha256Checksums,
    );
    lastUpdatedFile.writeAsStringSync(
      json.encode({
        'api_commit_hash': apiCommitHash,
        'timestamp': currentTimestamp,
        'checksums': targetChecksums,
      }),
    );
    _log.info('Updated last updated file for $platform.');
  }

  Future<bool> _checkIfOutdated(
    String platform,
    String destinationFolder,
    ApiBuildPlatformConfig config,
  ) async {
    final lastUpdatedFilePath = path.join(
      destinationFolder,
      '.api_last_updated_$platform',
    );
    final lastUpdatedFile = File(lastUpdatedFilePath);

    if (!lastUpdatedFile.existsSync()) {
      return true;
    }

    try {
      final lastUpdatedData =
          json.decode(lastUpdatedFile.readAsStringSync())
              as Map<String, dynamic>? ??
          {};
      if (lastUpdatedData['api_commit_hash'] == apiCommitHash) {
        final storedChecksums = List<String>.from(
          lastUpdatedData['checksums'] as List? ?? [],
        );
        final targetChecksums = List<String>.from(
          config.validZipSha256Checksums,
        );

        // Consider up-to-date only if the stored set exactly matches the
        // target set.
        final storedSet = storedChecksums.toSet();
        final targetSet = targetChecksums.toSet();
        if (storedSet.length == targetSet.length &&
            storedSet.containsAll(targetSet)) {
          _log.info(
            'version: $apiCommitHash and checksum set matches exactly.',
          );
          return false;
        }
      }
    } catch (e, s) {
      _log.severe('Error reading or parsing .api_last_updated_$platform', e, s);
      lastUpdatedFile.deleteSync();
      rethrow;
    }

    return true;
  }

  Future<void> _updateWebPackages() async {
    // First check for a `package.json` file in the root of the project
    final packageJsonFile = File(path.join(artifactOutputPath, 'package.json'));
    if (!packageJsonFile.existsSync()) {
      _log.info('No package.json file found in $artifactOutputPath');
      return;
    }

    _log
      ..info('Updating Web platform...')
      ..fine('Running npm install in $artifactOutputPath');
    final npmPath = findNode();
    final installResult = await Process.run(npmPath, [
      'install',
    ], workingDirectory: artifactOutputPath);
    if (installResult.exitCode != 0) {
      throw Exception('npm install failed: ${installResult.stderr}');
    }

    _log.fine('Running npm run build in $artifactOutputPath');
    final buildResult = await Process.run(npmPath, [
      'run',
      'build',
    ], workingDirectory: artifactOutputPath);
    if (buildResult.exitCode != 0) {
      throw Exception('npm run build failed: ${buildResult.stderr}');
    }

    _log.info('Web platform updated successfully.');
  }

  void setFilePermissions(File file) {
    if (Platform.isWindows) {
      Process.runSync('attrib', ['+x', file.path]);
    } else {
      Process.runSync('chmod', ['+x', file.path]);
    }
  }

  void _setExecutablePermissions(String destinationFolder) {
    _log.info('Setting executable permissions for $destinationFolder...');
    // Update the file permissions to make it executable. As part of the
    // transition from mm2 naming to kdf, update whichever file is present.
    // ignore: unused_local_variable
    final binaryNames = ['mm2', 'kdf']
        .map((e) => File(path.join(destinationFolder, e)))
        .where((filePath) => filePath.existsSync());

    if (!Platform.isWindows) {
      for (final filePath in binaryNames) {
        Process.run('chmod', ['+x', filePath.path]);
      }
    }
  }

  String _getPlatformDestinationFolder(String platform) {
    if (platformsConfig.containsKey(platform)) {
      return path.join(artifactOutputPath, platformsConfig[platform]!.path);
    } else {
      throw ArgumentError('Invalid platform: $platform');
    }
  }

  // TODO: Dynamically determine if the platform is using an executable file
  // or static/dynamic library.
  bool _isBinaryExecutable(String platform) {
    return platform == 'linux' || platform == 'macos' || platform == 'windows';
  }

  Future<void> _postUpdateActions(String platform, String destinationFolder) {
    if (platform == 'web') {
      return _updateWebPackages();
      // TODO: Consider adding npm if it makes a significant difference to
      // file build size or if it is required for cache-busting.
    }
    if (platform == 'macos') {
      // macOS artefacts are normalized into their final layout during install.
      return Future.value();
    }
    if (_isBinaryExecutable(platform)) {
      _tryRenameExecutable(platform, destinationFolder);
      _setExecutablePermissions(destinationFolder);
    } else {
      _tryRenameLibrary(platform, destinationFolder);
    }

    return Future.value();
  }

  Future<void> _extractAndInstallArtefact({
    required ArtefactDownloader downloader,
    required String filePath,
    required String destinationFolder,
    required String platform,
  }) async {
    if (platform != 'macos') {
      await downloader.extractArtefact(
        filePath: filePath,
        destinationFolder: destinationFolder,
      );
      return;
    }

    final extractedDirectory = await Directory.systemTemp.createTemp(
      'kdf_macos_extract_',
    );
    try {
      await downloader.extractArtefact(
        filePath: filePath,
        destinationFolder: extractedDirectory.path,
      );

      final destinationRoot = Directory(path.dirname(destinationFolder));
      final normalizer = MacosArtefactLayoutNormalizer(log: _log);
      final result = await normalizer.installFromExtractedDirectory(
        extractedDirectory: extractedDirectory,
        destinationRoot: destinationRoot,
      );

      _log.info(
        'Installed macOS artefacts: '
        'executable=${result.hasExecutable}, '
        'dynamicLibrary=${result.hasDynamicLibrary}, '
        'staticLibrary=${result.hasStaticLibrary}',
      );
    } finally {
      if (extractedDirectory.existsSync()) {
        await extractedDirectory.delete(recursive: true);
      }
    }
  }

  /// if executable is named "mm2" or "mm2.exe", then rename to "kdf"
  void _tryRenameExecutable(String platform, String destinationFolder) {
    final executableName = platform == 'windows' ? 'mm2.exe' : 'mm2';
    final executablePath = path.join(destinationFolder, executableName);

    _tryRenameFile(
      filePath: executablePath,
      destinationFolder: destinationFolder,
    );
  }

  /// if library is named "libmm2.a" or "libmm2.dylib", then rename to
  /// "libkdf.a" or "libkdf.dylib"
  void _tryRenameLibrary(String platform, String destinationFolder) {
    const libraryName = 'libmm2.a';
    final libraryPath = path.join(destinationFolder, libraryName);

    _tryRenameFile(filePath: libraryPath, destinationFolder: destinationFolder);
  }

  void _tryRenameFile({
    required String filePath,
    required String destinationFolder,
  }) {
    _log.fine('Looking for KDF at: $filePath');
    final newExecutableName = path.basename(filePath).replaceAll('mm2', 'kdf');
    final newExecutablePath = path.join(destinationFolder, newExecutableName);
    if (FileSystemEntity.isFileSync(filePath)) {
      try {
        File(filePath).renameSync(newExecutablePath);
        _log.info('Renamed kdf from $filePath to $newExecutableName');
      } catch (e) {
        _log.severe('Failed to rename kdf: $e');
      }
    } else {
      // If it's already renamed, there's no need to log a warning.
      if (!FileSystemEntity.isFileSync(newExecutablePath)) {
        _log.warning('KDF not found at: $filePath');
      }
    }
  }

  void _updateDocumentationIfExists() {
    // TODO: re-implement?
    //   final documentationFile = File('$projectRoot/docs/UPDATE_API_MODULE.md');
    //   if (!documentationFile.existsSync()) {
    //     return;
    //   }

    //   final content = documentationFile.readAsStringSync().replaceAllMapped(
    //         RegExp(r'(Current api module version is) `([^`]+)`'),
    //         (match) => '${match[1]} `$apiCommitHash`',
    //       );
    //   documentationFile.writeAsStringSync(content);
    //   _logMessage('Updated API version in documentation.');
    // }
  }

  bool _isTargetIphone() {
    return Platform.environment['TARGET_DEVICE_PLATFORM_NAME'] == 'iphoneos' ||
        Platform.environment['TARGET_DEVICE_PLATFORM_NAME'] ==
            'iphonesimulator' ||
        Platform.environment['SWIFT_PLATFORM_TARGET_PREFIX'] == 'ios';
  }
}
