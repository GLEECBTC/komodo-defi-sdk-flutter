import 'dart:io';

import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

class DevBuildsArtefactDownloader implements ArtefactDownloader {
  DevBuildsArtefactDownloader({
    required this.apiBranch,
    required this.apiCommitHash,
    required this.sourceUrl,
  });

  final _log = Logger('DevBuildsArtefactDownloader');

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
    // Try both branch-scoped and base-scoped listings to support different mirrors
    final normalizedSource = sourceUrl.endsWith('/')
        ? sourceUrl
        : '$sourceUrl/';
    final baseUri = Uri.parse(normalizedSource);
    final candidateListingUrls = <Uri>{
      if (apiBranch.isNotEmpty) baseUri.resolve('$apiBranch/'),
      baseUri,
    };

    final extensions = ['.zip'];
    final fullHash = apiCommitHash;
    final shortHash = apiCommitHash.substring(0, 7);
    _log.info('Looking for files with hash $fullHash or $shortHash');

    for (final listingUrl in candidateListingUrls) {
      try {
        final response = await http.get(listingUrl);
        response.throwIfNotSuccessResponse();
        final document = parser.parse(response.body);

        final attemptedFiles = <String>[];
        final resolvedCandidates =
            <String, String>{}; // fileName -> resolvedUrl
        for (final element in document.querySelectorAll('a')) {
          final href = element.attributes['href'];
          if (href == null) continue;
          attemptedFiles.add(href);

          // Normalize href for directory indexes that include absolute paths
          final hrefPath = Uri.tryParse(href)?.path ?? href;
          final fileName = path.basename(hrefPath);

          // Ignore wallet archives on Nebula index
          if (fileName.contains('wallet')) {
            continue;
          }

          final matches =
              matchingConfig.matches(fileName) &&
              extensions.any(hrefPath.endsWith);
          if (matches) {
            final containsHash =
                hrefPath.contains(fullHash) || hrefPath.contains(shortHash);
            if (containsHash) {
              // Build absolute URL respecting whether href is absolute or relative
              final resolvedUrl = href.startsWith('http')
                  ? href
                  : listingUrl.resolve(href).toString();
              resolvedCandidates[fileName] = resolvedUrl;
            }
          }
        }

        if (resolvedCandidates.isNotEmpty) {
          final preferred = matchingConfig.choosePreferred(
            resolvedCandidates.keys,
          );
          final url =
              resolvedCandidates[preferred] ?? resolvedCandidates.values.first;
          _log.info('Selected file: $preferred at $listingUrl');
          return url;
        }

        _log.fine(
          'No matching files found in $listingUrl. '
          '\nPattern: ${matchingConfig.matchingPattern}, '
          '\nHashes tried: [$fullHash, $shortHash]'
          '\nAvailable assets: ${attemptedFiles.join('\n')}',
        );
      } catch (e) {
        _log.fine('Failed to query listing $listingUrl: $e');
      }
    }

    throw Exception(
      'Zip file not found for platform $platform from $sourceUrl',
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
