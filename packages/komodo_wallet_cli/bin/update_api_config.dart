// ignore_for_file: unnecessary_string_escapes

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// CLI script to fetch the latest commit for a branch, fetch the URL and checksum for binaries,
/// and update the build config.
void main(List<String> arguments) async {
  final log = Logger('kdf-fetch-cli');

  // Setup logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stdout.writeln('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      stderr.writeln(record.error);
    }
    if (record.stackTrace != null) {
      stderr.writeln(record.stackTrace);
    }
  });

  // Parse arguments
  final parser = ArgParser()
    ..addOption(
      'branch',
      abbr: 'b',
      help: 'Branch to fetch commit from',
      defaultsTo: 'main',
    )
    ..addOption(
      'repo',
      help: 'GitHub repository in format owner/repo',
      defaultsTo: 'GLEECBTC/komodo-defi-framework',
    )
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to build config file',
      defaultsTo: 'build_config.json',
    )
    ..addOption(
      'output-dir',
      abbr: 'o',
      help: 'Output directory for temporary downloads',
      defaultsTo: 'temp_downloads',
    )
    ..addOption('token', abbr: 't', help: 'GitHub token for API access')
    ..addOption(
      'platform',
      abbr: 'p',
      help: 'Platform to update (e.g., web, macos, windows, linux)',
      defaultsTo: 'all',
    )
    ..addOption(
      'commit',
      abbr: 'm',
      help:
          'Commit hash to pin (short or full). Overrides latest commit lookup.',
    )
    ..addOption(
      'source',
      abbr: 's',
      help: 'Source to fetch from (github or mirror)',
      defaultsTo: 'github',
    )
    ..addOption(
      'mirror-url',
      help: 'Mirror URL if using mirror source',
      defaultsTo: 'https://sdk.devbuilds.komodo.earth',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose logging',
    )
    ..addFlag(
      'strict',
      negatable: true,
      defaultsTo: true,
      help:
          'Require exact commit-matching assets for all platforms; fail otherwise. Disable with --no-strict.',
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    log.severe('Error parsing arguments: $e');
    printUsage(parser);
    exit(1);
  }

  if (args['help'] as bool) {
    printUsage(parser);
    return;
  }

  if (args['verbose'] as bool) {
    Logger.root.level = Level.ALL;
    log.info('Verbose logging enabled');
  }

  final branch = args['branch'] as String;
  final repo = args['repo'] as String;
  final configPath = args['config'] as String;
  final outputDir = args['output-dir'] as String;
  final token =
      args['token'] as String? ??
      Platform.environment['GITHUB_API_PUBLIC_READONLY_TOKEN'];
  final platform = args['platform'] as String;
  final pinnedCommit = (args['commit'] as String?)?.trim();
  final source = args['source'] as String;
  final mirrorUrl = args['mirror-url'] as String;
  final verbose = args['verbose'] as bool;
  final strict = args['strict'] as bool;

  try {
    final fetcher = KdfFetcher(
      branch: branch,
      repo: repo,
      configPath: configPath,
      outputDir: outputDir,
      token: token,
      source: source,
      mirrorUrl: mirrorUrl,
      verbose: verbose,
      strict: strict,
    );

    await fetcher.loadBuildConfig();

    String commitHash;
    if (pinnedCommit != null && pinnedCommit.isNotEmpty) {
      commitHash = pinnedCommit;
      log.info('Using pinned commit: $commitHash');
    } else {
      log.info('Fetching latest commit for branch: $branch');
      commitHash = await fetcher.fetchLatestCommit();
      log.info('Latest commit: $commitHash');
    }

    // Ensure the build config is updated with a full 40-char commit SHA
    if (commitHash.length < 40) {
      try {
        final fullSha = await fetcher.resolveCommitSha(commitHash);
        log.info('Resolved short commit to full SHA: $fullSha');
        commitHash = fullSha;
      } catch (e) {
        log.warning(
          'Failed to resolve short commit to full SHA; proceeding with provided value: $commitHash',
        );
      }
    }

    if (platform == 'all') {
      final platforms = fetcher.getSupportedPlatforms();
      log.info('Updating config for all platforms: ${platforms.join(', ')}');

      for (final plat in platforms) {
        await fetcher.updatePlatformConfig(plat, commitHash);
      }
    } else {
      log.info('Updating config for platform: $platform');
      await fetcher.updatePlatformConfig(platform, commitHash);
    }

    await fetcher.updateBuildConfig(commitHash);
    log.info(
      'Build config updated successfully with commit hash and branch info',
    );

    // Clean up temporary directory
    final tempDir = Directory(outputDir);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
      log.info('Cleaned up temporary directory');
    }
  } catch (e, stackTrace) {
    log.severe('Error: $e', e, stackTrace);
    exit(1);
  }
}

void printUsage(ArgParser parser) {
  stdout.writeln('''
KDF Fetch CLI Tool

This script fetches the latest commit for a specified branch, locates available binaries,
calculates their checksums, and updates the build config with this information including
the branch name and commit hash. It does not extract or set up the files - that is the 
responsibility of the build step.

It supports both GitHub releases and the internal mirror site at:
https://sdk.devbuilds.komodo.earth/

Usage:
  dart run komodo_wallet_cli:update_api_config [options]

If you've activated the package globally, you can also use:
  komodo_wallet_cli update_api_config --branch dev --source mirror --config path/to/build_config.json

Options:
${parser.usage}

Examples:
  # Basic command to update the config for all platforms with the latest dev branch from mirror
  dart run komodo_wallet_cli:update_api_config \
    --branch dev \
    --source mirror \
    --config packages/komodo_defi_framework/app_build/build_config.json \
    --output-dir packages/komodo_defi_framework/app_build/temp_downloads \
    --verbose \
    --strict

  # Update only the web platform
  dart run komodo_wallet_cli:update_api_config \
    --branch dev \
    --source mirror \
    --platform web \
    --config packages/komodo_defi_framework/app_build/build_config.json \
    --output-dir packages/komodo_defi_framework/app_build/temp_downloads \
    --no-strict

  # Update using GitHub as the source
  dart run komodo_wallet_cli:update_api_config \
    --branch main \
    --source github \
    --config packages/komodo_defi_framework/app_build/build_config.json \
    --output-dir packages/komodo_defi_framework/app_build/temp_downloads

  # Using a custom mirror URL
  dart run komodo_wallet_cli:update_api_config \
    --branch dev \
    --source mirror \
    --mirror-url https://custom-mirror.example.com \
    --config packages/komodo_defi_framework/app_build/build_config.json \
    --output-dir packages/komodo_defi_framework/app_build/temp_downloads
''');
}

/// Main class for handling the KDF fetch operations
class KdfFetcher {
  KdfFetcher({
    required this.branch,
    required this.repo,
    required this.configPath,
    required this.outputDir,
    required this.verbose,
    this.strict = true,
    this.token,
    this.source = 'github',
    this.mirrorUrl = 'https://sdk.devbuilds.komodo.earth',
  }) {
    final parts = repo.split('/');
    if (parts.length != 2) {
      throw ArgumentError('Repository should be in format owner/repo');
    }
    owner = parts[0];
    repository = parts[1];

    // Create output directory if it doesn't exist
    final outputDirObj = Directory(outputDir);
    if (!outputDirObj.existsSync()) {
      outputDirObj.createSync(recursive: true);
    }

    if (source != 'github' && source != 'mirror') {
      throw ArgumentError('Source must be either "github" or "mirror"');
    }
  }

  final String branch;
  final String repo;
  final String configPath;
  final String outputDir;
  final String? token;
  final String source;
  final String mirrorUrl;
  late final String owner;
  late final String repository;
  final bool verbose;
  final bool strict;
  final log = Logger('KdfFetcher');
  // Preference helper used by URL selectors
  String _choosePreferred(Iterable<String> candidates, List<String> prefs) {
    final list = candidates.toList();
    if (list.isEmpty) return '';
    if (prefs.isEmpty) return list.first;
    for (final pref in prefs) {
      final found = list.firstWhere((c) => c.contains(pref), orElse: () => '');
      if (found.isNotEmpty) return found;
    }
    return list.first;
  }

  Map<String, dynamic>? _configData;

  /// Headers to use for GitHub API requests
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  /// Get the GitHub API URL for this repo
  String get _apiBaseUrl => 'https://api.github.com/repos/$owner/$repository';

  /// Fetches the latest commit hash for the specified branch
  Future<String> fetchLatestCommit() async {
    final url = '$_apiBaseUrl/commits/$branch';
    log.fine('Fetching latest commit from: $url');

    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch latest commit: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['sha'] as String;
  }

  /// Resolves a short or full commit into a full 40-char SHA via GitHub API
  Future<String> resolveCommitSha(String shaOrShort) async {
    final url = '$_apiBaseUrl/commits/$shaOrShort';
    log.fine('Resolving commit SHA from: $url');

    final response = await http.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to resolve commit: ${response.statusCode} ${response.reasonPhrase}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sha = data['sha'] as String?;
    if (sha == null || sha.length != 40) {
      throw Exception('Resolved commit SHA is invalid: $sha');
    }
    return sha;
  }

  /// Loads the build config file
  Future<Map<String, dynamic>> loadBuildConfig() async {
    if (_configData != null) {
      return _configData!;
    }

    final configFile = File(configPath);
    if (!configFile.existsSync()) {
      throw FileSystemException('Build config file not found', configPath);
    }

    final configContent = await configFile.readAsString();
    _configData = jsonDecode(configContent) as Map<String, dynamic>;

    if (verbose) {
      log.info('Loaded build config: $_configData');
    }

    return _configData!;
  }

  /// Gets the list of supported platforms from the build config
  List<String> getSupportedPlatforms() {
    final config = _configData?['api'] as Map<String, dynamic>?;
    if (config == null) {
      throw StateError('Build config not loaded or missing api section');
    }

    final platforms = config['platforms'] as Map<String, dynamic>?;
    if (platforms == null) {
      throw StateError('Build config missing platforms section');
    }

    return platforms.keys.toList();
  }

  /// Locates and verifies download URL for a platform
  Future<void> updatePlatformConfig(String platform, String commitHash) async {
    log.info(
      'Updating config for platform: $platform with commit: $commitHash',
    );

    final config = await loadBuildConfig();
    final apiConfig = config['api'] as Map<String, dynamic>;

    final platforms = apiConfig['platforms'] as Map<String, dynamic>;
    if (!platforms.containsKey(platform)) {
      throw ArgumentError('Platform $platform not found in config');
    }

    final platformConfig = platforms[platform] as Map<String, dynamic>;

    try {
      // Get download URL
      final downloadUrl = await fetchDownloadUrl(platform, commitHash);
      log.info('Located binary at: $downloadUrl');

      // Download binary to calculate checksum
      final zipFilePath = await downloadBinary(downloadUrl, platform);

      // Calculate checksum
      final checksum = await calculateChecksum(zipFilePath);
      log.info('Calculated checksum: $checksum');

      // Replace existing checksums when the commit changes; otherwise, accumulate
      final previousCommit = (apiConfig['api_commit_hash'] as String?);
      final isCommitChanged =
          previousCommit == null || previousCommit != commitHash;

      if (isCommitChanged) {
        platformConfig['valid_zip_sha256_checksums'] = <String>[checksum];
        log.info(
          'API commit changed from ${previousCommit ?? 'undefined'} to $commitHash; '
          'replaced existing checksums for platform $platform',
        );
      } else {
        // Update platform config with new checksum (accumulate unique)
        final checksums =
            (platformConfig['valid_zip_sha256_checksums'] as List<dynamic>)
                .map((e) => e.toString())
                .toSet();
        if (!checksums.contains(checksum)) {
          checksums.add(checksum);
          platformConfig['valid_zip_sha256_checksums'] = checksums.toList();
          log.info('Added new checksum to platform config: $checksum');
        } else {
          log.info('Checksum already exists in platform config');
        }
      }
    } catch (e) {
      log.severe('Error updating platform config for $platform: $e');
      throw Exception('Failed to update platform $platform: $e');
    }
  }

  /// Fetches the download URL for a release asset matching the given platform
  Future<String> fetchDownloadUrl(String platform, String commitHash) async {
    final config = await loadBuildConfig();
    final apiConfig = config['api'] as Map<String, dynamic>;
    final platformConfig =
        (apiConfig['platforms'] as Map<String, dynamic>)[platform]
            as Map<String, dynamic>;

    // Get the matching pattern/keyword and preference
    final matchingPattern = platformConfig['matching_pattern'] as String?;
    final matchingKeyword = platformConfig['matching_keyword'] as String?;
    final matchingPreference = (platformConfig['matching_preference'] is List)
        ? (platformConfig['matching_preference'] as List)
              .whereType<String>()
              .toList()
        : <String>[];

    if (matchingPattern == null && matchingKeyword == null) {
      throw StateError(
        'Platform config missing matching_pattern or matching_keyword',
      );
    }

    if (source == 'github') {
      return _fetchGithubDownloadUrl(
        platform,
        commitHash,
        matchingPattern,
        matchingKeyword,
        matchingPreference,
      );
    } else {
      return _fetchMirrorDownloadUrl(
        platform,
        commitHash,
        matchingPattern,
        matchingKeyword,
        matchingPreference,
      );
    }
  }

  /// Fetches download URL from GitHub releases
  Future<String> _fetchGithubDownloadUrl(
    String platform,
    String commitHash,
    String? matchingPattern,
    String? matchingKeyword,
    List<String> matchingPreference,
  ) async {
    // Get releases
    final releasesUrl = '$_apiBaseUrl/releases';
    log.fine('Fetching releases from: $releasesUrl');

    final response = await http.get(Uri.parse(releasesUrl), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch releases: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final releases = jsonDecode(response.body) as List<dynamic>;

    // Look for the asset with the matching pattern/keyword and commit hash
    final shortHash = commitHash.substring(0, 7);

    final candidates = <String, String>{};
    for (final release in releases) {
      final assets = release['assets'] as List<dynamic>;

      for (final asset in assets) {
        final fileName = asset['name'] as String;

        var matches = false;
        if (matchingPattern != null) {
          try {
            final regex = RegExp(matchingPattern);
            matches = regex.hasMatch(fileName);
          } catch (e) {
            log.warning('Invalid regex pattern: $matchingPattern');
          }
        } else if (matchingKeyword != null) {
          matches = fileName.contains(matchingKeyword);
        }

        if (matches &&
            (fileName.contains(commitHash) || fileName.contains(shortHash))) {
          candidates[fileName] = asset['browser_download_url'] as String;
        }
      }
    }

    if (candidates.isNotEmpty) {
      final preferred = _choosePreferred(candidates.keys, matchingPreference);
      return candidates[preferred] ?? candidates.values.first;
    }

    // In strict mode do not fallback – require exact commit match
    if (!strict) {
      // If we couldn't find an exact match, try just matching the platform pattern
      final candidates = <String, String>{};
      for (final release in releases) {
        final assets = release['assets'] as List<dynamic>;

        for (final asset in assets) {
          final fileName = asset['name'] as String;

          var matches = false;
          if (matchingPattern != null) {
            try {
              final regex = RegExp(matchingPattern);
              matches = regex.hasMatch(fileName);
            } catch (e) {
              log.warning('Invalid regex pattern: $matchingPattern');
            }
          } else if (matchingKeyword != null) {
            matches = fileName.contains(matchingKeyword);
          }

          if (matches) {
            candidates[fileName] = asset['browser_download_url'] as String;
          }
        }
      }
      if (candidates.isNotEmpty) {
        final preferred = _choosePreferred(candidates.keys, matchingPreference);
        final url = candidates[preferred] ?? candidates.values.first;
        log.warning(
          'Could not find exact commit match. Using latest matching asset: $url',
        );
        return url;
      }
    }

    throw Exception(
      'No matching asset found for platform $platform and commit $commitHash',
    );
  }

  /// Fetches download URL from mirror site
  Future<String> _fetchMirrorDownloadUrl(
    String platform,
    String commitHash,
    String? matchingPattern,
    String? matchingKeyword,
    List<String> matchingPreference,
  ) async {
    // Try both branch-scoped and base listings; mirrors now expose branch paths
    final normalizedMirror = mirrorUrl.endsWith('/')
        ? mirrorUrl
        : '$mirrorUrl/';
    final mirrorUri = Uri.parse(normalizedMirror);
    final listingUrls = <Uri>{
      if (branch.isNotEmpty) mirrorUri.resolve('$branch/'),
      mirrorUri,
    };

    final extensions = ['.zip'];
    final fullHash = commitHash;
    final shortHash = commitHash.substring(0, 7);
    log.info('Looking for files with hash $fullHash or $shortHash');

    for (final baseUrl in listingUrls) {
      log.fine('Fetching files from mirror: $baseUrl');
      try {
        final response = await http.get(baseUrl);
        if (response.statusCode != 200) {
          log.fine(
            'Mirror listing failed at $baseUrl: ${response.statusCode} ${response.reasonPhrase}',
          );
          continue;
        }

        final document = parser.parse(response.body);
        final attemptedFiles = <String>[];

        // First pass: require short/full hash match; collect all candidates
        final hashCandidates = <String, String>{};
        for (final element in document.querySelectorAll('a')) {
          final href = element.attributes['href'];
          if (href == null) continue;
          attemptedFiles.add(href);

          // Prefer checking the path portion for extensions to ignore query params
          final hrefPath = Uri.tryParse(href)?.path ?? href;
          if (!extensions.any(hrefPath.endsWith)) continue;
          if (href.contains('wallet')) continue; // Ignore wallet builds

          var matches = false;
          if (matchingPattern != null) {
            try {
              final regex = RegExp(matchingPattern);
              matches = regex.hasMatch(hrefPath);
            } catch (e) {
              log.warning('Invalid regex pattern: $matchingPattern');
            }
          } else if (matchingKeyword != null) {
            matches = hrefPath.contains(matchingKeyword);
          }

          if (matches &&
              (hrefPath.contains(fullHash) || hrefPath.contains(shortHash))) {
            final fileName = path.basename(hrefPath);
            final resolved = href.startsWith('http')
                ? href
                : baseUrl.resolve(href).toString();
            hashCandidates[fileName] = resolved;
          }
        }
        if (hashCandidates.isNotEmpty) {
          final preferred = _choosePreferred(
            hashCandidates.keys,
            matchingPreference,
          );
          final resolved =
              hashCandidates[preferred] ?? hashCandidates.values.first;
          log.info('Found matching files for commit; selected: $resolved');
          return resolved;
        }

        // Second pass: latest matching asset without commit constraint (only when not strict)
        if (!strict) {
          final candidates = <String, String>{};
          for (final element in document.querySelectorAll('a')) {
            final href = element.attributes['href'];
            if (href == null) continue;
            final hrefPath = Uri.tryParse(href)?.path ?? href;
            if (!extensions.any(hrefPath.endsWith)) continue;
            if (href.contains('wallet')) continue;

            var matches = false;
            if (matchingPattern != null) {
              try {
                final regex = RegExp(matchingPattern);
                matches = regex.hasMatch(hrefPath);
              } catch (e) {
                log.warning('Invalid regex pattern: $matchingPattern');
              }
            } else if (matchingKeyword != null) {
              matches = hrefPath.contains(matchingKeyword);
            }

            if (matches) {
              final fileName = path.basename(hrefPath);
              final resolved = href.startsWith('http')
                  ? href
                  : baseUrl.resolve(href).toString();
              candidates[fileName] = resolved;
            }
          }
          if (candidates.isNotEmpty) {
            final preferred = _choosePreferred(
              candidates.keys,
              matchingPreference,
            );
            final resolved = candidates[preferred] ?? candidates.values.first;
            log.warning(
              'Could not find exact commit match. Using latest matching asset: $resolved',
            );
            return resolved;
          }
        }

        log.fine(
          'No matching files found in $baseUrl. '
          '\nPattern: $matchingPattern, '
          '\nKeyword: $matchingKeyword, '
          '\nHashes tried: [$fullHash, $shortHash]'
          '\nAvailable assets: ${attemptedFiles.join('\n')}',
        );
      } catch (e) {
        log.fine('Error querying mirror listing $baseUrl: $e');
      }
    }

    throw Exception(
      'No matching asset found for platform $platform and commit $commitHash',
    );
  }

  /// Downloads a binary from the given URL
  Future<String> downloadBinary(String url, String platform) async {
    log.info('Downloading from: $url');

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download binary: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final fileName = path.basename(url);
    final filePath = path.join(outputDir, fileName);

    await File(filePath).writeAsBytes(response.bodyBytes);
    log.info('Downloaded to: $filePath');

    return filePath;
  }

  /// Calculates the SHA-256 checksum of a file
  Future<String> calculateChecksum(String filePath) async {
    final file = File(filePath);

    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }

    final bytes = await file.readAsBytes();
    final checksum = sha256.convert(bytes).toString();

    log.info('Calculated checksum: $checksum for $filePath');

    return checksum;
  }

  /// Updates the build config with the new commit hash and branch name, then writes it back to disk
  Future<void> updateBuildConfig(String commitHash) async {
    final config = await loadBuildConfig();
    final apiConfig = config['api'] as Map<String, dynamic>;

    // Update commit hash
    apiConfig['api_commit_hash'] = commitHash;

    // Update branch name
    final currentBranch = apiConfig['branch'] as String?;
    if (currentBranch != branch) {
      log.info(
        'Updating branch from ${currentBranch ?? 'undefined'} to $branch',
      );
      apiConfig['branch'] = branch;
    }

    // Write config back to disk
    final configFile = File(configPath);
    const encoder = JsonEncoder.withIndent('    ');
    await configFile.writeAsString(encoder.convert(config));

    log.info(
      'Updated build config with commit hash: $commitHash${currentBranch != branch ? ' and branch: $branch' : ''}',
    );
  }
}

// ================ Credit to Flutter team: ================
// https://api.flutter.dev/flutter/foundation/listEquals.html
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) {
    return b == null;
  }
  if (b == null || a.length != b.length) {
    return false;
  }
  if (identical(a, b)) {
    return true;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

// =========================================
