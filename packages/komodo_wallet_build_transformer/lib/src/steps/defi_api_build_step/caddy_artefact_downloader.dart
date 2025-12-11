import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// A file entry returned by Caddy's JSON directory listing API.
class CaddyFileEntry {
  CaddyFileEntry({
    required this.name,
    required this.size,
    required this.url,
    required this.modTime,
    required this.isDir,
    required this.isSymlink,
  });

  factory CaddyFileEntry.fromJson(Map<String, dynamic> json) {
    return CaddyFileEntry(
      name: json['name'] as String,
      size: json['size'] as int,
      url: json['url'] as String,
      modTime: DateTime.parse(json['mod_time'] as String),
      isDir: json['is_dir'] as bool,
      isSymlink: json['is_symlink'] as bool,
    );
  }

  final String name;
  final int size;
  final String url;
  final DateTime modTime;
  final bool isDir;
  final bool isSymlink;
}

/// Artefact downloader for Caddy file servers using the JSON directory API.
///
/// Caddy provides a JSON directory listing when the `Accept: application/json`
/// header is included. This is more reliable than HTML scraping.
class CaddyArtefactDownloader implements ArtefactDownloader {
  CaddyArtefactDownloader({
    required this.apiBranch,
    required this.apiCommitHash,
    required this.sourceUrl,
  });

  final _log = Logger('CaddyArtefactDownloader');

  @override
  final String apiBranch;

  @override
  final String apiCommitHash;

  @override
  final String sourceUrl;

  /// Fetches directory listing from Caddy using JSON API.
  Future<List<CaddyFileEntry>> _fetchDirectoryListing(Uri uri) async {
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
    response.throwIfNotSuccessResponse();

    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .map((e) => CaddyFileEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Recursively searches for matching files in the directory tree.
  Future<Map<String, String>> _searchForFiles({
    required Uri baseUri,
    required ApiFileMatchingConfig matchingConfig,
    required String fullHash,
    required String shortHash,
    int maxDepth = 3,
    int currentDepth = 0,
  }) async {
    if (currentDepth >= maxDepth) {
      return {};
    }

    final candidates = <String, String>{};

    try {
      final entries = await _fetchDirectoryListing(baseUri);

      for (final entry in entries) {
        if (entry.isDir) {
          // Recursively search subdirectories
          final subUri = baseUri.resolve(entry.url);
          final subCandidates = await _searchForFiles(
            baseUri: subUri,
            matchingConfig: matchingConfig,
            fullHash: fullHash,
            shortHash: shortHash,
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
          );
          candidates.addAll(subCandidates);
        } else {
          // Check if file matches criteria
          final fileName = entry.name;

          // Skip non-zip files
          if (!fileName.endsWith('.zip')) continue;

          // Skip wallet archives
          if (fileName.contains('wallet')) continue;

          // Check pattern match
          if (!matchingConfig.matches(fileName)) continue;

          // Check hash match
          final containsHash =
              fileName.contains(fullHash) || fileName.contains(shortHash);
          if (!containsHash) continue;

          // Build absolute URL
          final resolvedUrl = baseUri.resolve(entry.url).toString();
          candidates[fileName] = resolvedUrl;
          _log.fine('Found candidate: $fileName at $resolvedUrl');
        }
      }
    } catch (e) {
      _log.fine('Failed to fetch directory listing from $baseUri: $e');
    }

    return candidates;
  }

  @override
  Future<String> fetchDownloadUrl(
    ApiFileMatchingConfig matchingConfig,
    String platform,
  ) async {
    final normalizedSource = sourceUrl.endsWith('/')
        ? sourceUrl
        : '$sourceUrl/';
    final baseUri = Uri.parse(normalizedSource);

    final fullHash = apiCommitHash;
    final shortHash = apiCommitHash.substring(0, 7);
    _log.info('Looking for files with hash $fullHash or $shortHash');

    // Try branch-scoped directory first, then fall back to base
    final candidateListingUrls = <Uri>{
      if (apiBranch.isNotEmpty) baseUri.resolve('$apiBranch/'),
      baseUri,
    };

    for (final listingUrl in candidateListingUrls) {
      _log.info('Searching in $listingUrl');

      final candidates = await _searchForFiles(
        baseUri: listingUrl,
        matchingConfig: matchingConfig,
        fullHash: fullHash,
        shortHash: shortHash,
      );

      if (candidates.isNotEmpty) {
        final preferred = matchingConfig.choosePreferred(candidates.keys);
        final url = candidates[preferred] ?? candidates.values.first;
        _log.info('Selected file: $preferred from $listingUrl');
        return url;
      }

      _log.fine('No matching files found in $listingUrl');
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
      if (Platform.isMacOS || Platform.isLinux) {
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
