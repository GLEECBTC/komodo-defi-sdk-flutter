import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/src/steps/models/github/github_file.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/github/release.dart';
import 'package:logging/logging.dart';

/// A provider for interacting with the GitHub API.
class GithubApiProvider {
  /// Creates a new instance of [GithubApiProvider]. The [owner] parameter is
  /// the owner of the repository. The [repo] parameter is the name of the
  /// repository.
  /// The [branch] parameter is the branch name to use for API requests.
  /// The [token] parameter is an optional token to use for authentication.
  GithubApiProvider({
    required String owner,
    required String repo,
    required String branch,
    String? token,
  }) : _branch = branch,
       _baseUrl = 'https://api.github.com/repos/$owner/$repo' {
    if (token != null) {
      _log.finer('Using authentication token for GitHub API requests.');
      _headers['Authorization'] = 'Bearer $token';
    }
  }

  /// Creates a new instance of [GithubApiProvider] with a custom base URL.
  /// The [baseUrl] parameter is the base URL of the GitHub API.
  /// The [branch] parameter is the branch name to use for API requests.
  GithubApiProvider.withBaseUrl({
    required String baseUrl,
    required String branch,
    String? token,
  }) : _branch = branch,
       _baseUrl = baseUrl {
    final repoMatch = RegExp(
      r'^https://api\.github\.com/repos/([^/]+)/([^/]+)',
    ).firstMatch(baseUrl);
    assert(repoMatch != null, 'Invalid GitHub repository URL: $baseUrl');

    if (token != null) {
      _log.finer('Using authentication token for GitHub API requests.');
      _headers['Authorization'] = 'Bearer $token';
    }
  }

  final String _baseUrl;
  final String _branch;
  final Map<String, String> _headers = {
    'Accept': 'application/vnd.github.v3+json',
  };
  final _log = Logger('GithubApiProvider');

  bool get hasToken => _headers.containsKey('Authorization');

  /// Retrieves the contents of a file from the repository API. The [filePath]
  /// parameter specifies the path of the file within the repository.
  Future<GitHubFile> getFileMetadata(String filePath, {String? ref}) async {
    final fileMetadataUrl =
        '$_baseUrl/contents/$filePath?ref=${ref ?? _branch}';
    _log.finest('Fetching file metadata from $fileMetadataUrl');

    final fileContentResponse = await http.get(
      Uri.parse(fileMetadataUrl),
      headers: _headers,
    );
    if (fileContentResponse.statusCode != 200) {
      throw Exception(
        'Failed to fetch remote file metadata at $fileMetadataUrl: '
        '${fileContentResponse.statusCode} ${fileContentResponse.reasonPhrase}',
      );
    }

    final fileContent = GitHubFile.fromJson(
      jsonDecode(fileContentResponse.body) as Map<String, dynamic>,
    );

    return fileContent;
  }

  /// Retrieves the latest commit hash for a given branch from the repository
  /// API.
  ///
  /// The [branch] parameter specifies the branch name for which to retrieve the
  ///  latest commit hash.
  /// By default, it is set to 'master'.
  ///
  /// Returns a [Future] that completes with a [String] representing the latest
  ///  commit hash.
  Future<String> getLatestCommitHash({String branch = 'master'}) async {
    final apiUrl = '$_baseUrl/commits/$branch';
    _log
      ..finest('Fetching latest commit hash from $apiUrl')
      ..finest('Using authentication: ${hasToken ? 'yes' : 'no'}');

    final response = await http.get(Uri.parse(apiUrl), headers: _headers);
    if (response.statusCode != 200) {
      _log
        ..severe(
          'GitHub API request failed: '
          '${response.statusCode} ${response.reasonPhrase}',
        )
        ..severe('Response body: ${response.body}')
        ..severe('Request headers: $_headers');
      throw Exception(
        'Failed to retrieve latest commit hash: $branch'
        '[${response.statusCode}]: ${response.reasonPhrase}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['sha'] as String;
  }

  /// Retrieves the contents of a GitHub directory for a given repository and
  /// commit.
  ///
  /// The [repoPath] parameter specifies the path of the directory within the
  /// repository.
  /// The [repoCommit] parameter specifies the commit hash or branch name.
  ///
  /// Returns a [Future] that completes with a list of [GitHubFile] objects
  /// representing the files in the directory.
  Future<List<GitHubFile>> getDirectoryContents(
    String repoPath,
    String repoCommit,
  ) async {
    final apiUrl = '$_baseUrl/contents/$repoPath?ref=$repoCommit';
    _log.finest('Fetching directory contents from $apiUrl');
    final response = await http.get(Uri.parse(apiUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to retrieve directory contents: $repoPath'
        '[${response.statusCode}]: ${response.reasonPhrase}',
      );
    }

    final respString = response.body;
    final data = jsonDecode(respString) as List<dynamic>;
    final files = data
        .where(
          (dynamic item) => (item as Map<String, dynamic>)['type'] == 'file',
        )
        .map(
          (dynamic file) => GitHubFile.fromJson(file as Map<String, dynamic>),
        )
        .toList();

    _log
      ..fine('Directory $repoPath contains ${data.length} items')
      ..fine('\t of which ${files.length} are files');

    return files;
  }

  Future<String> getLatestReleaseTag() async {
    final apiUrl = '$_baseUrl/releases/latest';
    _log.finest('Fetching latest release tag from $apiUrl');

    final response = await http.get(Uri.parse(apiUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to retrieve latest release tag: '
        '[${response.statusCode}]: ${response.reasonPhrase}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['tag_name'] as String;
  }

  Future<List<Release>> getReleases() async {
    final apiUrl = '$_baseUrl/releases';
    _log.finest('Fetching releases from $apiUrl');

    final response = await http.get(Uri.parse(apiUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to retrieve releases: '
        '[${response.statusCode}]: ${response.reasonPhrase}',
      );
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => Release.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
