import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_platform_config.dart';

class ApiBuildConfig {
  ApiBuildConfig({
    required this.apiCommitHash,
    required this.branch,
    required this.fetchAtBuildEnabled,
    required this.concurrentDownloadsEnabled,
    required this.sourceUrls,
    required this.platforms,
    this.requireFullCommitHash = false,
    this.requiredPlatforms = const <String>[],
  });

  factory ApiBuildConfig.fromJson(Map<String, dynamic> json) {
    try {
      final apiCommitHash = _parseString(json, 'api_commit_hash');
      final requireFullCommitHash =
          json['require_full_commit_hash'] as bool? ?? false;
      _validateCommitHash(apiCommitHash);

      final platforms = _parsePlatforms(json);
      final requiredPlatforms = json.containsKey('required_platforms')
          ? _parseStringList(json, 'required_platforms')
          : const <String>[];
      final missingPlatforms = requiredPlatforms
          .where((platform) => !platforms.containsKey(platform))
          .toList();
      if (missingPlatforms.isNotEmpty) {
        throw FormatException(
          'Required API platforms are not configured: '
          '${missingPlatforms.join(', ')}',
        );
      }

      return ApiBuildConfig(
        apiCommitHash: apiCommitHash,
        branch: _parseString(json, 'branch'),
        fetchAtBuildEnabled: _parseBool(json, 'fetch_at_build_enabled'),
        concurrentDownloadsEnabled:
            json['concurrent_downloads_enabled'] as bool? ?? true,
        requireFullCommitHash: requireFullCommitHash,
        requiredPlatforms: requiredPlatforms,
        sourceUrls: _parseStringList(json, 'source_urls'),
        platforms: platforms,
      );
    } catch (e) {
      throw FormatException('Invalid JSON format for ApiBuildConfig: $e');
    }
  }

  String apiCommitHash;
  String branch;
  bool fetchAtBuildEnabled;
  final bool concurrentDownloadsEnabled;
  final bool requireFullCommitHash;
  final List<String> requiredPlatforms;
  List<String> sourceUrls;
  Map<String, ApiBuildPlatformConfig> platforms;

  static String _parseString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException(
        'Expected a string for "$key", but got ${value.runtimeType}',
      );
    }
    return value;
  }

  static bool _parseBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException(
        'Expected a boolean for "$key", but got ${value.runtimeType}',
      );
    }
    return value;
  }

  static List<String> _parseStringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) {
      throw FormatException(
        'Expected a list for "$key", but got ${value.runtimeType}',
      );
    }
    return List<String>.from(
      value.map((e) {
        if (e is! String) {
          throw FormatException(
            'Expected string elements in "$key" list, but found '
            '${e.runtimeType}',
          );
        }
        return e;
      }),
    );
  }

  static Map<String, ApiBuildPlatformConfig> _parsePlatforms(
    Map<String, dynamic> json,
  ) {
    final platforms = json['platforms'];
    if (platforms is! Map<String, dynamic>) {
      throw FormatException(
        'Expected a map for "platforms", but got ${platforms.runtimeType}',
      );
    }
    return Map<String, ApiBuildPlatformConfig>.from(
      platforms.map((key, value) {
        if (value is! Map<String, dynamic>) {
          throw FormatException(
            'Expected a map for platform "$key", but got '
            '${value.runtimeType}',
          );
        }
        return MapEntry(key, ApiBuildPlatformConfig.fromJson(value));
      }),
    );
  }

  static void _validateCommitHash(String value) {
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(value)) {
      throw const FormatException(
        'api_commit_hash must be a full 40-character lowercase hash because '
        'artifact provenance markers require an immutable commit identity',
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'api_commit_hash': apiCommitHash,
      'branch': branch,
      'fetch_at_build_enabled': fetchAtBuildEnabled,
      'concurrent_downloads_enabled': concurrentDownloadsEnabled,
      'require_full_commit_hash': requireFullCommitHash,
      if (requiredPlatforms.isNotEmpty) 'required_platforms': requiredPlatforms,
      'source_urls': sourceUrls,
      'platforms': platforms.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  ApiBuildConfig copyWith({
    String? apiCommitHash,
    String? branch,
    bool? fetchAtBuildEnabled,
    bool? concurrentDownloadsEnabled,
    bool? requireFullCommitHash,
    List<String>? requiredPlatforms,
    List<String>? sourceUrls,
    Map<String, ApiBuildPlatformConfig>? platforms,
  }) {
    return ApiBuildConfig(
      apiCommitHash: apiCommitHash ?? this.apiCommitHash,
      branch: branch ?? this.branch,
      fetchAtBuildEnabled: fetchAtBuildEnabled ?? this.fetchAtBuildEnabled,
      concurrentDownloadsEnabled:
          concurrentDownloadsEnabled ?? this.concurrentDownloadsEnabled,
      requireFullCommitHash:
          requireFullCommitHash ?? this.requireFullCommitHash,
      requiredPlatforms: requiredPlatforms ?? this.requiredPlatforms,
      sourceUrls: sourceUrls ?? this.sourceUrls,
      platforms: platforms ?? this.platforms,
    );
  }
}
