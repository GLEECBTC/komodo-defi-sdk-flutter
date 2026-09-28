import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_coin_updates/src/coins_config/asset_parser.dart';
import 'package:komodo_coin_updates/src/coins_config/coin_config_provider.dart';
import 'package:komodo_coin_updates/src/coins_config/config_transform.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';

/// GitHub-backed implementation of [CoinConfigProvider].
///
/// Fetches the coins and coin configs from the Komodo `coins` repository
/// hosted on GitHub (or a configured CDN mirror).
class GithubCoinConfigProvider implements CoinConfigProvider {
  /// Creates a provider for fetching coins and coin configuration data
  /// from the Komodo `coins` repository.
  ///
  /// - [branch]: the branch or commit to read from (defaults to `master`).
  /// - [coinsGithubContentUrl]: base URL for fetching raw file contents.
  /// - [coinsGithubApiUrl]: base URL for GitHub API requests.
  /// - [coinsPath]: path to the coins directory in the repository.
  /// - [coinsConfigPath]: path to the JSON file containing coin configs.
  /// - [githubToken]: optional GitHub token for authenticated requests
  ///   (recommended to avoid rate limits).
  GithubCoinConfigProvider({
    required this.branch,
    required this.coinsGithubContentUrl,
    required this.coinsGithubApiUrl,
    required this.coinsPath,
    required this.coinsConfigPath,
    this.cdnBranchMirrors,
    this.githubToken,
    this.requestTimeout = const Duration(seconds: 10),
    CoinConfigTransformer? transformer,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client(),
       _transformer = transformer ?? const CoinConfigTransformer();

  /// Creates a provider from a runtime configuration.
  ///
  /// Derives provider settings from the given [config]. Optionally provide
  /// a [githubToken] for authenticated GitHub API requests.
  factory GithubCoinConfigProvider.fromConfig(
    AssetRuntimeUpdateConfig config, {
    String? githubToken,
    http.Client? httpClient,
    CoinConfigTransformer? transformer,
  }) {
    // Derive URLs and paths from build_config `coins` section.
    // We expect the following mapped files in the config:
    // - 'assets/config/coins_config.json' → path to unfiltered config JSON in repo
    // - 'assets/config/coins.json' → path to the coins folder in repo
    final coinsConfigPath =
        config.mappedFiles['assets/config/coins_config.json'] ??
        'utils/coins_config_unfiltered.json';
    final coinsPath = config.mappedFiles['assets/config/coins.json'] ?? 'coins';

    return GithubCoinConfigProvider(
      branch: config.coinsRepoBranch,
      coinsGithubContentUrl: config.coinsRepoContentUrl,
      coinsGithubApiUrl: config.coinsRepoApiUrl,
      coinsConfigPath: coinsConfigPath,
      coinsPath: coinsPath,
      cdnBranchMirrors: config.cdnBranchMirrors,
      githubToken: githubToken,
      transformer: transformer,
      httpClient: httpClient,
    );
  }
  static final Logger _log = Logger('GithubCoinConfigProvider');

  /// The branch or commit hash to read repository contents from.
  final String branch;

  /// Base URL used to fetch raw repository file contents (no API).
  final String coinsGithubContentUrl;

  /// Base URL used for GitHub REST API calls.
  final String coinsGithubApiUrl;

  /// Path to the directory containing coin JSON files.
  final String coinsPath;

  /// Path to the JSON file that contains the unfiltered coin configuration map.
  final String coinsConfigPath;

  /// Optional GitHub token used for authenticated requests to reduce
  /// the risk of rate limiting.
  final String? githubToken;

  /// Upper bound for an individual remote request.
  ///
  /// Startup refreshes rely on this to fall back to the last known coin list
  /// rather than delaying KDF indefinitely while offline.
  final Duration requestTimeout;

  /// Optional mapping of branch name to CDN base URL that directly hosts
  /// the repository contents for that branch (without an extra branch
  /// segment in the path). When present and the current [branch] is found
  /// in this mapping, requests will be made against that base URL without
  /// including the branch in the path.
  final Map<String, String>? cdnBranchMirrors;

  final http.Client _client;

  /// Optional transform pipeline applied to each raw coin config
  /// JSON before parsing.
  final CoinConfigTransformer _transformer;

  @override
  Future<List<Asset>> getAssetsForCommit(String commit) async {
    final url = _contentUri(coinsConfigPath, branchOrCommit: commit);
    final response = await _client.get(url).timeout(requestTimeout);
    if (response.statusCode != 200) {
      final body = response.body;
      final preview = body.length > 1024 ? '${body.substring(0, 1024)}…' : body;
      _log.warning(
        'Failed to fetch coin configs [status: ${response.statusCode}] '
        'url: $url, ref: $commit, body: $preview',
      );
      throw Exception(
        'Failed to fetch coin configs from $url at $commit '
        '[${response.statusCode}]: $preview',
      );
    }

    final items = jsonDecode(response.body) as Map<String, dynamic>;

    // Optionally transform each coin JSON before parsing
    final transformedItems = <String, Map<String, dynamic>>{
      for (final entry in items.entries)
        entry.key: _transformer.apply(
          Map<String, dynamic>.from(entry.value as Map<String, dynamic>),
        ),
    };

    // Use the standardized AssetParser to parse all assets
    const parser = AssetParser(loggerName: 'GithubCoinConfigProvider');
    return parser.parseAssetsFromConfig(
      transformedItems,
      shouldFilterCoin: (coinData) => const CoinFilter().shouldFilter(coinData),
      logContext: 'from GitHub at $commit',
    );
  }

  @override
  Future<List<Asset>> getAssets({String? branch}) async {
    return getAssetsForCommit(branch ?? this.branch);
  }

  @override
  Future<String> getLatestCommit({
    String? branch,
    String? apiBaseUrl,
    String? githubToken,
  }) async {
    final effectiveBranch = branch ?? this.branch;
    final effectiveApiBaseUrl = apiBaseUrl ?? coinsGithubApiUrl;
    final effectiveToken = githubToken ?? this.githubToken;

    final url = Uri.parse('$effectiveApiBaseUrl/branches/$effectiveBranch');
    final header = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'komodo-coin-updates',
    };

    if (effectiveToken != null) {
      header['Authorization'] = 'Bearer $effectiveToken';
      _log.fine('Using authentication for GitHub API request');
    }

    _log.fine('Fetching latest commit for branch $effectiveBranch');
    final response = await _client
        .get(url, headers: header)
        .timeout(requestTimeout);

    if (response.statusCode != 200) {
      _log.warning(
        'GitHub API request failed [${response.statusCode} '
        '${response.reasonPhrase}] for $effectiveBranch',
      );
      throw Exception(
        'Failed to retrieve latest commit hash: $effectiveBranch'
        ' [${response.statusCode}]: ${response.reasonPhrase}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final commit = json['commit'] as Map<String, dynamic>;
    final latestCommitHash = commit['sha'] as String;
    return latestCommitHash;
  }

  /// Helper to construct a content URI for a [path].
  Uri buildContentUri(String path, {String? branchOrCommit}) =>
      _contentUri(path, branchOrCommit: branchOrCommit);

  /// Helper to construct a content URI for a [path].
  ///
  /// If [branchOrCommit] is a branch name that matches a CDN mirror mapping,
  /// uses the CDN URL directly (CDN URLs always point to master/main).
  /// If [branchOrCommit] is a commit hash or non-CDN branch, uses GitHub raw URL.
  ///
  /// Uses the centralized URL building logic from [AssetRuntimeUpdateConfig.buildContentUrl].
  Uri _contentUri(String path, {String? branchOrCommit}) {
    branchOrCommit ??= branch;

    // Use the centralized helper for URL generation
    final uri = AssetRuntimeUpdateConfig.buildContentUrl(
      path: path,
      coinsRepoContentUrl: coinsGithubContentUrl,
      coinsRepoBranch: branchOrCommit,
      cdnBranchMirrors: cdnBranchMirrors ?? <String, String>{},
    );

    // Log the URL choice for debugging
    if (cdnBranchMirrors?.containsKey(branchOrCommit) ?? false) {
      _log.fine('Using CDN URL for branch $branchOrCommit: $uri');
    } else {
      _log.fine('Using GitHub raw URL for $branchOrCommit: $uri');
    }

    return uri;
  }

  /// Dispose HTTP resources if this provider owns the client.
  void dispose() {
    _client.close();
  }
}
