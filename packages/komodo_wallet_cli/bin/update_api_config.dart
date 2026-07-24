// ignore_for_file: unnecessary_string_escapes

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/komodo_wallet_build_transformer.dart';
import 'package:komodo_wallet_cli/src/update_api_config/artifact_filename.dart';
import 'package:komodo_wallet_cli/src/update_api_config/commit_hash_resolver.dart';
import 'package:komodo_wallet_cli/src/update_api_config/mirror_asset_matcher.dart';
import 'package:komodo_wallet_cli/src/update_api_config/platform_update_scope.dart';
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
          'Commit hash to pin. Short SHAs are resolved remotely; the manifest '
          'always stores a full 40-character lowercase SHA. Overrides latest '
          'commit lookup.',
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
      defaultsTo: 'https://devbuilds.gleec.com',
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

    final requestedCommitHash = commitHash;
    commitHash = await resolveCommitHashForUpdate(
      commitHash,
      strict: strict,
      requireFullCommitHash: true,
      resolveShortCommit: fetcher.resolveCommitSha,
    );
    if (commitHash != requestedCommitHash) {
      log.info('Resolved short commit to full SHA: $commitHash');
    }

    final supportedPlatforms = fetcher.getSupportedPlatforms();
    final platforms = resolveRequestedApiPlatforms(
      requestedPlatform: platform,
      supportedPlatforms: supportedPlatforms,
    );
    validateApiCommitUpdateScope(
      previousCommitHash: fetcher.currentApiCommitHash,
      nextCommitHash: commitHash,
      updatedPlatforms: platforms,
      requiredPlatforms: fetcher.requiredPlatforms,
      supportedPlatforms: supportedPlatforms,
      strict: strict,
      requireFullCommitHash: fetcher.requiresFullCommitHash,
    );

    if (platform == 'all') {
      log.info('Updating config for all platforms: ${platforms.join(', ')}');
    } else {
      log.info('Updating config for platform: $platform');
    }
    for (final plat in platforms) {
      await fetcher.updatePlatformConfig(plat, commitHash);
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
https://devbuilds.gleec.com/

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
    this.mirrorUrl = 'https://devbuilds.gleec.com',
  }) {
    final parts = repo.split('/');
    if (parts.length != 2) {
      throw ArgumentError('Repository should be in format owner/repo');
    }
    owner = parts[0];
    repository = parts[1];

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
  final Map<String, String> _updatedPlatformCommits = <String, String>{};

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

  /// Whether the loaded manifest requires an immutable full commit SHA.
  bool get requiresFullCommitHash {
    final apiConfig = _configData?['api'] as Map<String, dynamic>?;
    if (apiConfig == null) {
      throw StateError('Build config not loaded or missing api section');
    }
    final value = apiConfig['require_full_commit_hash'];
    if (value == null) return false;
    if (value is! bool) {
      throw StateError('require_full_commit_hash must be a boolean');
    }
    return value;
  }

  /// Whether artifact selection must match the requested commit exactly.
  bool get requiresExactArtifactCommit => strict || requiresFullCommitHash;

  /// The commit currently stored in the loaded global API manifest.
  String get currentApiCommitHash {
    final apiConfig = _configData?['api'] as Map<String, dynamic>?;
    if (apiConfig == null) {
      throw StateError('Build config not loaded or missing api section');
    }
    final value = apiConfig['api_commit_hash'];
    if (value is! String) {
      throw StateError('api_commit_hash must be a string');
    }
    return value;
  }

  /// Platforms that must move together when the global commit changes.
  List<String> get requiredPlatforms {
    final apiConfig = _configData?['api'] as Map<String, dynamic>?;
    if (apiConfig == null) {
      throw StateError('Build config not loaded or missing api section');
    }
    final value = apiConfig['required_platforms'];
    if (value == null) return const <String>[];
    if (value is! List || value.any((platform) => platform is! String)) {
      throw StateError('required_platforms must be a list of strings');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  /// Locates and verifies download URL for a platform
  Future<void> updatePlatformConfig(String platform, String commitHash) async {
    final config = await loadBuildConfig();
    validateResolvedCommitHashForUpdate(
      commitHash,
      strict: strict,
      requireFullCommitHash: true,
    );
    log.info(
      'Updating config for platform: $platform with commit: $commitHash',
    );

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
      _updatedPlatformCommits[platform] = commitHash;
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

    final candidates = <String, String>{};
    for (final release in releases) {
      final assets = release['assets'] as List<dynamic>;

      for (final asset in assets) {
        final fileName = apiArtifactFilenameFromUrl(asset['name'] as String);

        var matches = false;
        try {
          matches = matchesApiArtifactFilename(
            fileName,
            matchingPattern: matchingPattern,
            matchingKeyword: matchingKeyword,
            commitHash: commitHash,
          );
        } on FormatException {
          log.warning('Invalid regex pattern: $matchingPattern');
        }

        if (matches) {
          candidates[fileName] = asset['browser_download_url'] as String;
        }
      }
    }

    if (candidates.isNotEmpty) {
      final preferred = _choosePreferred(candidates.keys, matchingPreference);
      return candidates[preferred] ?? candidates.values.first;
    }

    // In strict mode do not fallback – require exact commit match
    if (!requiresExactArtifactCommit) {
      // If we couldn't find an exact match, try just matching the platform pattern
      final candidates = <String, String>{};
      for (final release in releases) {
        final assets = release['assets'] as List<dynamic>;

        for (final asset in assets) {
          final fileName = apiArtifactFilenameFromUrl(asset['name'] as String);

          var matches = false;
          try {
            matches = matchesApiArtifactFilename(
              fileName,
              matchingPattern: matchingPattern,
              matchingKeyword: matchingKeyword,
            );
          } on FormatException {
            log.warning('Invalid regex pattern: $matchingPattern');
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
    // Try raw and sanitized branch-scoped listings before falling back to the base index.
    final normalizedMirror = mirrorUrl.endsWith('/')
        ? mirrorUrl
        : '$mirrorUrl/';
    final mirrorUri = Uri.parse(normalizedMirror);
    final sanitizedBranch = branch.replaceAll('/', '-');
    final listingUrls = <Uri>{
      if (branch.isNotEmpty) mirrorUri.resolve('$branch/'),
      if (branch.isNotEmpty && sanitizedBranch != branch)
        mirrorUri.resolve('$sanitizedBranch/'),
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

          final hrefPath = Uri.tryParse(href)?.path ?? href;
          var matches = false;
          try {
            matches = matchesMirrorArchiveHref(
              href,
              extensions: extensions,
              matchingPattern: matchingPattern,
              matchingKeyword: matchingKeyword,
              commitHash: commitHash,
            );
          } on FormatException {
            log.warning('Invalid regex pattern: $matchingPattern');
          }

          if (matches) {
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
        if (!requiresExactArtifactCommit) {
          final candidates = <String, String>{};
          for (final element in document.querySelectorAll('a')) {
            final href = element.attributes['href'];
            if (href == null) continue;
            final hrefPath = Uri.tryParse(href)?.path ?? href;

            var matches = false;
            try {
              matches = matchesMirrorArchiveHref(
                href,
                extensions: extensions,
                matchingPattern: matchingPattern,
                matchingKeyword: matchingKeyword,
              );
            } on FormatException {
              log.warning('Invalid regex pattern: $matchingPattern');
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

    final fileName = apiArtifactFilenameFromUrl(url);
    final filePath = path.join(outputDir, fileName);

    await Directory(outputDir).create(recursive: true);
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
    validateResolvedCommitHashForUpdate(
      commitHash,
      strict: strict,
      requireFullCommitHash: true,
    );
    final apiConfig = config['api'] as Map<String, dynamic>;
    final supportedPlatforms = getSupportedPlatforms();
    validateApiCommitUpdateScope(
      previousCommitHash: currentApiCommitHash,
      nextCommitHash: commitHash,
      updatedPlatforms: apiPlatformsUpdatedForCommit(
        _updatedPlatformCommits,
        commitHash,
      ),
      requiredPlatforms: requiredPlatforms,
      supportedPlatforms: supportedPlatforms,
      strict: strict,
      requireFullCommitHash: requiresFullCommitHash,
    );

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
    try {
      await configFile.writeAsString(formatJsonForIde(config));
    } finally {
      _updatedPlatformCommits.clear();
    }

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
