import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/github/github_api_provider.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

class GithubArtefactDownloader implements ArtefactDownloader {
  GithubArtefactDownloader({
    required this.apiBranch,
    required this.apiCommitHash,
    required this.sourceUrl,
    required this.githubApiProvider,
  });

  final _log = Logger('GithubArtefactDownloader');

  final GithubApiProvider githubApiProvider;

  @override
  final String apiBranch;

  @override
  final String apiCommitHash;

  @override
  final String sourceUrl;

  @override
  Future<String> fetchDownloadUrl(
    ApiFileMatchingConfig matchingConfig,
    String platform,
  ) async {
    final releases = await githubApiProvider.getReleases();
    final fullHash = apiCommitHash;
    final shortHash = apiCommitHash.substring(0, 7);

    _log.info('Looking for release files with hash $fullHash or $shortHash');

    // TODO! Try to find exact version release first
    // if (version != null && version!.isNotEmpty) {
    //   _log.info('Searching for exact version match: $version');
    //   for (final release in releases) {
    //     if (release.tagName == version) {
    //       _log.info('Found matching release: ${release.tagName}');
    //       for (final asset in release.assets) {
    //         final fileName = path.basename(asset.browserDownloadUrl);
    //         _log.fine('Checking file $fileName for $platform');

    //         if (matchingConfig.matches(fileName)) {
    //           _log.info('Found matching file $fileName in version $version');
    //           return asset.browserDownloadUrl;
    //         }
    //       }
    //       _log.warning('No matching assets found in version $version. '
    //           'Available assets:\n${release.assets.map((a) => '  - ${a.name}').join('\n')}');
    //     }
    //   }
    //   _log.warning('No exact version match found for $version');
    // }

    // If no exact version match found, try matching by commit hash
    _log.info('Searching for commit hash match');
    final candidates = <String, String>{}; // fileName -> url
    for (final release in releases) {
      for (final asset in release.assets) {
        final fileName = path.basename(asset.browserDownloadUrl);

        if (matchingConfig.matches(fileName)) {
          if (fileName.contains(fullHash) || fileName.contains(shortHash)) {
            final commitHash = await githubApiProvider.getLatestCommitHash(
              branch: release.tagName,
            );
            if (commitHash == apiCommitHash) {
              candidates[fileName] = asset.browserDownloadUrl;
            }
          }
        }
      }
    }

    if (candidates.isNotEmpty) {
      final preferred = matchingConfig.choosePreferred(candidates.keys);
      final url = candidates[preferred] ?? candidates.values.first;
      _log.info('Selected file: $preferred');
      return url;
    }

    // Log available assets to help diagnose issues
    final releaseAssets = releases
        .expand((r) => r.assets)
        .map((a) => '  - ${a.name}')
        .join('\n');
    _log.fine(
      'No files found matching criteria:\n'
      'Platform: $platform\n'
      'Version: \$version\n'
      'Hash: $fullHash or $shortHash\n'
      'Pattern: ${matchingConfig.matchingPattern}\n'
      'Available assets:\n$releaseAssets',
    );

    throw Exception(
      'Zip file not found for platform $platform in GitHub releases. '
      'Searched for version: \$version, commit: $apiCommitHash',
    );
  }

  @override
  Future<String> downloadArtefact({
    required String url,
    required String destinationPath,
  }) async {
    _log.info('Downloading $url...');
    final response = await http.get(Uri.parse(url));
    response.throwIfNotSuccessResponse();

    final zipFileName = path.basename(url);
    final zipFilePath = path.join(destinationPath, zipFileName);

    final directory = Directory(destinationPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final zipFile = File(zipFilePath);
    try {
      await zipFile.writeAsBytes(response.bodyBytes);
    } catch (e) {
      _log.info('Error writing file', e);
      rethrow;
    }

    _log.info('Downloaded $zipFileName');
    return zipFilePath;
  }

  @override
  Future<void> extractArtefact({
    required String filePath,
    required String destinationFolder,
  }) async {
    try {
      // Determine the platform to use the appropriate extraction command
      if (Platform.isMacOS || Platform.isLinux) {
        // For macOS and Linux, use the `unzip` command with overwrite option
        final result = await Process.run('unzip', [
          '-o',
          filePath,
          '-d',
          destinationFolder,
        ]);
        if (result.exitCode != 0) {
          throw Exception('Error extracting zip file: ${result.stderr}');
        }
      } else if (Platform.isWindows) {
        // For Windows, use PowerShell's Expand-Archive command
        final result = await Process.run('powershell', [
          '-Command',
          'Expand-Archive -Path "$filePath" -DestinationPath "$destinationFolder" -Force',
        ]);
        if (result.exitCode != 0) {
          throw Exception('Error extracting zip file: ${result.stderr}');
        }
      } else {
        _log.severe('Unsupported platform: ${Platform.operatingSystem}');
        throw UnsupportedError('Unsupported platform');
      }
      _log.info('Extraction completed.');
    } catch (e) {
      _log.shout('Failed to extract zip file: $e');
      rethrow;
    }
  }
}
