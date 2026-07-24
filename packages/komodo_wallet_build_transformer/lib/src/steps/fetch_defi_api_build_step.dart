import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:komodo_wallet_build_transformer/src/build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader_factory.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/node_path.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_artifact_provenance.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_platform_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// Determines whether an artifact must be downloaded without allowing an
/// explicit network opt-out to bypass stale provenance.
bool shouldUpdateApiArtifact({
  required bool isOutdated,
  required bool forceUpdate,
  required bool? overrideDownload,
  required String platform,
  required String apiCommitHash,
}) {
  if (overrideDownload == false && isOutdated) {
    throw StateError(
      'KDF artifact for $platform does not match pinned commit '
      '$apiCommitHash. OVERRIDE_DEFI_API_DOWNLOAD=false may disable network '
      'fetching, but it cannot bypass artifact provenance validation.',
    );
  }
  return overrideDownload ?? (forceUpdate || isOutdated);
}

const List<String> _webCoreWasmCandidates = [
  'kdflib_bg.wasm',
  'kdf_bg.wasm',
  'mm2_bg.wasm',
  'kdflib.wasm',
  'kdf.wasm',
  'mm2.wasm',
];
const String _webGlueFilename = 'kdflib.js';
const Set<String> _webRuntimeExtensions = {'.js', '.wasm'};

const Map<String, List<String>> _singleArtifactCandidates = {
  'ios': ['libkdf.a', 'libmm2.a'],
  'macos': ['kdf', 'mm2'],
  'android-armv7': ['libkdf.a', 'libmm2.a'],
  'android-aarch64': ['libkdf.a', 'libmm2.a'],
  'linux': ['kdf', 'mm2'],
  'windows': ['kdf.exe', 'mm2.exe'],
};

/// Selects only the artifacts relevant to the active build target.
List<String> apiPlatformsForTarget(
  Iterable<String> platforms, {
  required bool isTargetIphone,
}) => platforms
    .where((platform) => !isTargetIphone || platform == 'ios')
    .toList(growable: false);

/// Removes every recognized runtime candidate before extracting a new archive.
///
/// This prevents a verified archive that omits its runtime payload from
/// inheriting and certifying bytes left by an older extraction.
void clearExtractedApiArtifactCandidates({
  required String platform,
  required String destinationFolder,
}) {
  if (platform == 'web') {
    final destination = Directory(destinationFolder);
    if (!destination.existsSync()) return;

    for (final entity in destination.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (!_webRuntimeExtensions.contains(
        path.extension(entity.path).toLowerCase(),
      )) {
        continue;
      }
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        entity.deleteSync();
      }
    }
    return;
  }

  final candidates = _singleArtifactCandidates[platform];
  if (candidates == null) {
    throw UnsupportedError('No KDF artifact identity is defined for $platform');
  }

  for (final filename in candidates) {
    final artifact = File(path.join(destinationFolder, filename));
    if (artifact.existsSync()) {
      artifact.deleteSync();
    }
  }
}

/// Calculates the digest of the extracted KDF runtime used by [platform].
///
/// Candidate order is stable and supports both current `kdf` and legacy `mm2`
/// archive layouts. Web provenance is a deterministic aggregate over every
/// extracted JavaScript and WASM runtime output. Missing, ambiguous, linked, or
/// unknown artifacts fail closed.
Future<String> calculateExtractedApiArtifactSha256({
  required String platform,
  required String destinationFolder,
}) async {
  if (platform == 'web') {
    return _calculateExtractedWebRuntimeSha256(destinationFolder);
  }

  final candidates = _singleArtifactCandidates[platform];
  if (candidates == null) {
    throw UnsupportedError('No KDF artifact identity is defined for $platform');
  }

  final artifacts = <File>[];
  for (final filename in candidates) {
    final artifact = File(path.join(destinationFolder, filename));
    final type = FileSystemEntity.typeSync(artifact.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError(
        'Extracted KDF artifact must not be a link for $platform: '
        '${artifact.path}',
      );
    }
    if (type == FileSystemEntityType.file) {
      artifacts.add(artifact);
    }
  }
  if (artifacts.length == 1) {
    return (await sha256.bind(artifacts.single.openRead()).first).toString();
  }
  if (artifacts.length > 1) {
    throw StateError(
      'Extracted KDF artifact is ambiguous for $platform in '
      '$destinationFolder. Found: '
      '${artifacts.map((artifact) => path.basename(artifact.path)).join(', ')}',
    );
  }

  throw StateError(
    'Extracted KDF artifact is missing for $platform in $destinationFolder. '
    'Expected one of: ${candidates.join(', ')}',
  );
}

Future<String> _calculateExtractedWebRuntimeSha256(
  String destinationFolder,
) async {
  final destination = Directory(destinationFolder);
  if (!destination.existsSync()) {
    throw StateError(
      'Extracted KDF web runtime is missing in $destinationFolder',
    );
  }

  final glue = File(path.join(destinationFolder, _webGlueFilename));
  if (!FileSystemEntity.isFileSync(glue.path)) {
    throw StateError(
      'Extracted KDF web runtime is missing $_webGlueFilename in '
      '$destinationFolder',
    );
  }

  final coreWasmArtifacts = _webCoreWasmCandidates
      .map((filename) => File(path.join(destinationFolder, filename)))
      .where((artifact) => FileSystemEntity.isFileSync(artifact.path))
      .toList(growable: false);
  if (coreWasmArtifacts.length != 1) {
    throw StateError(
      'Extracted KDF web runtime must contain exactly one core WASM artifact '
      'in $destinationFolder. Found: '
      '${coreWasmArtifacts.map((file) => path.basename(file.path)).join(', ')}',
    );
  }

  final runtimeFiles = <File>[];
  for (final entity in destination.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (!_webRuntimeExtensions.contains(
      path.extension(entity.path).toLowerCase(),
    )) {
      continue;
    }
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError(
        'Extracted KDF web runtime must not contain linked output: '
        '${entity.path}',
      );
    }
    if (type == FileSystemEntityType.file) {
      runtimeFiles.add(File(entity.path));
    }
  }

  final manifestEntries = <List<String>>[];
  for (final runtimeFile in runtimeFiles) {
    final relativePath = path.posix.joinAll(
      path.split(path.relative(runtimeFile.path, from: destinationFolder)),
    );
    final digest = await sha256.bind(runtimeFile.openRead()).first;
    manifestEntries.add([relativePath, digest.toString()]);
  }
  manifestEntries.sort((left, right) => left.first.compareTo(right.first));

  return sha256.convert(utf8.encode(json.encode(manifestEntries))).toString();
}

/// Promotes a validated extraction without exposing a partial archive.
///
/// Existing files affected by the archive, stale runtime candidates, and the
/// provenance marker are moved to a sibling backup first. Any install or
/// finalization failure restores those files before the error is rethrown.
Future<void> replaceExtractedApiArtifactAtomically({
  required String platform,
  required String stagingFolder,
  required String destinationFolder,
  required Future<void> Function() finalizeInstall,
}) async {
  final staging = Directory(stagingFolder);
  if (!staging.existsSync()) {
    throw StateError(
      'KDF artifact staging directory is missing: $stagingFolder',
    );
  }

  final stagedFiles = <String, File>{};
  for (final entity in staging.listSync(recursive: true, followLinks: false)) {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError(
        'Extracted KDF archive must not contain links: ${entity.path}',
      );
    }
    if (type != FileSystemEntityType.file) continue;

    final relativePath = path.normalize(
      path.relative(entity.path, from: stagingFolder),
    );
    if (relativePath == '.' ||
        relativePath == '..' ||
        relativePath.startsWith('..${path.separator}')) {
      throw StateError(
        'Extracted KDF archive contains an unsafe path: ${entity.path}',
      );
    }
    if (path.basename(relativePath).startsWith('.api_last_updated_')) {
      throw StateError(
        'Extracted KDF archive must not provide provenance markers: '
        '$relativePath',
      );
    }
    stagedFiles[relativePath] = File(entity.path);
  }
  if (stagedFiles.isEmpty) {
    throw StateError('Extracted KDF archive contains no files');
  }

  final destination = Directory(destinationFolder)..createSync(recursive: true);
  final targetPaths = <String>{
    ...stagedFiles.keys,
    ..._existingRuntimeRelativePaths(platform, destinationFolder),
    '.api_last_updated_$platform',
  };
  for (final relativePath in targetPaths) {
    final targetPath = path.join(destinationFolder, relativePath);
    if (FileSystemEntity.typeSync(targetPath, followLinks: false) ==
        FileSystemEntityType.directory) {
      throw StateError(
        'Cannot replace KDF artifact file with a directory: $targetPath',
      );
    }
  }

  final backup = Directory(
    path.dirname(destination.path),
  ).createTempSync('.${path.basename(destination.path)}.kdf-backup-');
  final backedUpTypes = <String, FileSystemEntityType>{};
  final installedPaths = <String>[];
  var finalizationStarted = false;
  var committed = false;
  var rolledBack = false;

  try {
    for (final relativePath in targetPaths.toList()..sort()) {
      final targetPath = path.join(destinationFolder, relativePath);
      final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.link) {
        continue;
      }

      final backupPath = path.join(backup.path, relativePath);
      Directory(path.dirname(backupPath)).createSync(recursive: true);
      _renameFileSystemEntity(targetPath, backupPath, type);
      backedUpTypes[relativePath] = type;
    }

    final stagedEntries = stagedFiles.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in stagedEntries) {
      final targetPath = path.join(destinationFolder, entry.key);
      Directory(path.dirname(targetPath)).createSync(recursive: true);
      entry.value.renameSync(targetPath);
      installedPaths.add(entry.key);
    }

    finalizationStarted = true;
    await finalizeInstall();
    committed = true;
  } catch (error, stackTrace) {
    for (final relativePath in installedPaths.reversed) {
      _deleteFileSystemEntityIfPresent(
        path.join(destinationFolder, relativePath),
      );
    }
    if (finalizationStarted) {
      _deleteFileSystemEntityIfPresent(
        path.join(destinationFolder, '.api_last_updated_$platform'),
      );
    }
    for (final entry in backedUpTypes.entries) {
      final targetPath = path.join(destinationFolder, entry.key);
      _deleteFileSystemEntityIfPresent(targetPath);
      Directory(path.dirname(targetPath)).createSync(recursive: true);
      _renameFileSystemEntity(
        path.join(backup.path, entry.key),
        targetPath,
        entry.value,
      );
    }
    rolledBack = true;
    Error.throwWithStackTrace(error, stackTrace);
  } finally {
    _deleteDirectoryIfPresent(staging);
    if (committed || rolledBack || backedUpTypes.isEmpty) {
      _deleteDirectoryIfPresent(backup);
    }
  }

  _deleteDirectoryIfPresent(backup);
}

Set<String> _existingRuntimeRelativePaths(
  String platform,
  String destinationFolder,
) {
  if (platform == 'web') {
    final destination = Directory(destinationFolder);
    if (!destination.existsSync()) return const <String>{};

    return destination
        .listSync(recursive: true, followLinks: false)
        .where(
          (entity) => _webRuntimeExtensions.contains(
            path.extension(entity.path).toLowerCase(),
          ),
        )
        .map(
          (entity) => path.normalize(
            path.relative(entity.path, from: destinationFolder),
          ),
        )
        .toSet();
  }

  final candidates = _singleArtifactCandidates[platform];
  if (candidates == null) {
    throw UnsupportedError('No KDF artifact identity is defined for $platform');
  }
  return candidates
      .where(
        (filename) =>
            FileSystemEntity.typeSync(
              path.join(destinationFolder, filename),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound,
      )
      .toSet();
}

void _renameFileSystemEntity(
  String sourcePath,
  String destinationPath,
  FileSystemEntityType type,
) {
  if (type == FileSystemEntityType.file) {
    File(sourcePath).renameSync(destinationPath);
    return;
  }
  if (type == FileSystemEntityType.link) {
    Link(sourcePath).renameSync(destinationPath);
    return;
  }
  throw StateError(
    'Unsupported KDF artifact entity type at $sourcePath: $type',
  );
}

void _deleteFileSystemEntityIfPresent(String entityPath) {
  final type = FileSystemEntity.typeSync(entityPath, followLinks: false);
  if (type == FileSystemEntityType.file) {
    File(entityPath).deleteSync();
  } else if (type == FileSystemEntityType.link) {
    Link(entityPath).deleteSync();
  }
}

void _deleteDirectoryIfPresent(Directory directory) {
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
}

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
    validateApiArtifactProvenanceCommitHash(
      buildConfig.apiConfig.apiCommitHash,
    );
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
      concurrent: buildConfig.apiConfig.concurrentDownloadsEnabled,
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

    final targetPlatforms = apiPlatformsForTarget(
      platformsToUpdate,
      isTargetIphone: _isTargetIphone(),
    );
    final releaseBlockedPlatforms = targetPlatforms
        .where(
          (platform) => platformsConfig[platform]?.isReleaseBlocked ?? false,
        )
        .toList();
    if (releaseBlockedPlatforms.isNotEmpty) {
      throw StateError(
        'KDF artifact release is blocked for '
        '${releaseBlockedPlatforms.join(', ')} at $apiCommitHash. Build and '
        'publish each exact pinned-commit archive, calculate its SHA-256, and '
        'replace the all-zero manifest checksum.',
      );
    }

    _log.info('=====================');
    if (concurrent) {
      await Future.wait(targetPlatforms.map(updatePlatformWithProgress));
    } else {
      await Future.forEach(targetPlatforms, updatePlatformWithProgress);
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
    if (config.isReleaseBlocked) {
      throw StateError(
        'KDF artifact release is blocked for $platform at $apiCommitHash. '
        'Build and publish the exact pinned-commit archive, calculate its '
        'SHA-256, and replace the all-zero manifest checksum.',
      );
    }

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

    if (!_shouldUpdate(isOutdated, platform)) {
      _log.info('$platform platform is up to date.');
      await _postUpdateActions(platform, destinationFolder);
      return;
    }

    String? zipFilePath;
    String? acceptedArchiveFilename;
    String? acceptedArchiveSha256;
    Directory? acceptedStagingDirectory;
    for (final sourceUrl in sourceUrls) {
      Directory? attemptStagingDirectory;
      zipFilePath = null;
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

        final archiveSha256 = await _verifyChecksum(zipFilePath, platform);
        if (archiveSha256 != null) {
          attemptStagingDirectory = _createArtifactStagingDirectory(
            destinationFolder,
          );
          await downloader.extractArtefact(
            filePath: zipFilePath,
            destinationFolder: attemptStagingDirectory.path,
          );
          _normalizeStagedArtifact(platform, attemptStagingDirectory.path);
          await calculateExtractedApiArtifactSha256(
            platform: platform,
            destinationFolder: attemptStagingDirectory.path,
          );
          acceptedArchiveFilename = path.basename(zipFilePath);
          acceptedArchiveSha256 = archiveSha256;
          acceptedStagingDirectory = attemptStagingDirectory;
          attemptStagingDirectory = null;
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
        if (attemptStagingDirectory != null) {
          _deleteDirectoryIfPresent(attemptStagingDirectory);
        }
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

    if (acceptedArchiveFilename == null ||
        acceptedArchiveSha256 == null ||
        acceptedStagingDirectory == null) {
      throw StateError('No verified KDF archive was extracted for $platform');
    }
    await replaceExtractedApiArtifactAtomically(
      platform: platform,
      stagingFolder: acceptedStagingDirectory.path,
      destinationFolder: destinationFolder,
      finalizeInstall: () async {
        await _postUpdateActions(platform, destinationFolder);
        await _updateLastUpdatedFile(
          platform,
          destinationFolder,
          acceptedArchiveFilename!,
          acceptedArchiveSha256!,
        );
      },
    );
    _log.info('$platform platform update completed.');
  }

  Directory _createArtifactStagingDirectory(String destinationFolder) {
    final parent = Directory(path.dirname(destinationFolder))
      ..createSync(recursive: true);
    return parent.createTempSync(
      '.${path.basename(destinationFolder)}.kdf-staging-',
    );
  }

  void _normalizeStagedArtifact(String platform, String stagingFolder) {
    if (platform == 'web') return;
    if (_isBinaryExecutable(platform)) {
      _tryRenameExecutable(platform, stagingFolder);
    } else {
      _tryRenameLibrary(platform, stagingFolder);
    }
  }

  bool _shouldUpdate(bool isOutdated, String platform) {
    return shouldUpdateApiArtifact(
      isOutdated: isOutdated,
      forceUpdate: forceUpdate,
      overrideDownload: overrideDefiApiDownload,
      platform: platform,
      apiCommitHash: apiCommitHash,
    );
  }

  Future<String?> _verifyChecksum(String filePath, String platform) async {
    final validChecksums = List<String>.from(
      platformsConfig[platform]!.validZipSha256Checksums,
    );

    _log.info('validChecksums: $validChecksums');

    final fileBytes = await File(filePath).readAsBytes();
    final fileSha256Checksum = sha256.convert(fileBytes).toString();

    if (validChecksums.contains(fileSha256Checksum)) {
      _log.info('Checksum validated for $filePath');
      return fileSha256Checksum;
    } else {
      _log.severe(
        'SHA256 Checksum mismatch for $filePath: expected any of '
        '$validChecksums, got $fileSha256Checksum',
      );
      return null;
    }
  }

  Future<void> _updateLastUpdatedFile(
    String platform,
    String destinationFolder,
    String archiveFilename,
    String archiveSha256,
  ) async {
    final lastUpdatedFile = File(
      path.join(destinationFolder, '.api_last_updated_$platform'),
    );
    final currentTimestamp = DateTime.now().toIso8601String();
    final targetChecksums = List<String>.from(
      platformsConfig[platform]!.validZipSha256Checksums,
    );
    final artifactSha256 = await calculateExtractedApiArtifactSha256(
      platform: platform,
      destinationFolder: destinationFolder,
    );
    final provenance = <String, dynamic>{
      'api_commit_hash': apiCommitHash,
      'checksums': targetChecksums,
      'archive_filename': path.basename(archiveFilename),
      'archive_sha256': archiveSha256,
      'artifact_sha256': artifactSha256,
    };
    ApiArtifactProvenance.fromJson(provenance);
    lastUpdatedFile.writeAsStringSync(
      json.encode({...provenance, 'timestamp': currentTimestamp}),
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
      final lastUpdatedData = json.decode(lastUpdatedFile.readAsStringSync());
      if (lastUpdatedData is! Map<String, dynamic>) {
        throw const FormatException('Artifact marker must be a JSON object');
      }
      final provenance = ApiArtifactProvenance.fromJson(lastUpdatedData);
      if (!config.matchingConfig.matches(provenance.archiveFilename)) {
        _log.warning(
          'Artifact marker archive ${provenance.archiveFilename} does not '
          'match the configured $platform archive pattern.',
        );
        return true;
      }
      final observedArtifactSha256 = await calculateExtractedApiArtifactSha256(
        platform: platform,
        destinationFolder: destinationFolder,
      );
      if (provenance.matches(
        expectedCommitHash: apiCommitHash,
        expectedChecksums: config.validZipSha256Checksums,
        observedArtifactSha256: observedArtifactSha256,
      )) {
        _log.info('version: $apiCommitHash and checksum set matches exactly.');
        return false;
      }
    } catch (e, s) {
      _log.severe('Error reading or parsing .api_last_updated_$platform', e, s);
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
    if (_isBinaryExecutable(platform)) {
      _tryRenameExecutable(platform, destinationFolder);
      _setExecutablePermissions(destinationFolder);
    } else {
      _tryRenameLibrary(platform, destinationFolder);
    }

    return Future.value();
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
        final existingTarget = File(newExecutablePath);
        if (existingTarget.existsSync()) {
          existingTarget.deleteSync();
        }
        File(filePath).renameSync(newExecutablePath);
        _log.info('Renamed kdf from $filePath to $newExecutableName');
      } catch (e) {
        _log.severe('Failed to rename kdf: $e');
        rethrow;
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
