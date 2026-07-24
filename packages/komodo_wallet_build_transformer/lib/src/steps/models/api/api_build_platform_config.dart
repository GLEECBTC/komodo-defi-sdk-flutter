import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';

/// Configuration for a specific platform's API build settings.
///
/// This class contains the configuration needed to download and verify API
/// binaries for a specific platform (e.g., 'web', 'macos', 'windows', etc.).
class ApiBuildPlatformConfig {
  /// Creates a new [ApiBuildPlatformConfig] with required parameters.
  ///
  /// The [matchingConfig] specifies how to identify the correct API file.
  /// [validZipSha256Checksums] contains the list of valid SHA256 checksums for
  /// verification.
  /// [path] specifies where the API files should be stored.
  ApiBuildPlatformConfig({
    required this.matchingConfig,
    required this.validZipSha256Checksums,
    required this.path,
  }) : assert(
         validZipSha256Checksums.isNotEmpty,
         'At least one valid checksum must be provided',
       );

  /// Creates a [ApiBuildPlatformConfig] from a JSON map.
  ///
  /// The JSON must contain either 'matching_keyword' or 'matching_pattern',
  /// 'valid_zip_sha256_checksums' as a non-empty list, and a 'path' string.
  /// Throws a [FormatException] if the JSON is invalid.
  factory ApiBuildPlatformConfig.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('valid_zip_sha256_checksums')) {
      throw FormatException(
        'Missing required field: valid_zip_sha256_checksums',
        json.toString(),
      );
    }

    if (!json.containsKey('path')) {
      throw FormatException('Missing required field: path', json.toString());
    }

    if (!json.containsKey('matching_keyword') &&
        !json.containsKey('matching_pattern')) {
      throw FormatException(
        'Either matching_keyword or matching_pattern must be provided',
        json.toString(),
      );
    }

    final checksums = json['valid_zip_sha256_checksums'];
    if (checksums is! List || checksums.isEmpty) {
      throw FormatException(
        'valid_zip_sha256_checksums must be a non-empty list',
        json.toString(),
      );
    }

    final parsedChecksums = checksums.whereType<String>().toList();
    if (parsedChecksums.length != checksums.length ||
        parsedChecksums.any(
          (checksum) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum),
        )) {
      throw FormatException(
        'valid_zip_sha256_checksums must contain lowercase SHA-256 values',
        json.toString(),
      );
    }
    if (parsedChecksums.contains(releaseBlockerChecksum) &&
        parsedChecksums.length != 1) {
      throw FormatException(
        'The all-zero release blocker must be the only checksum',
        json.toString(),
      );
    }

    final matchingConfig = ApiFileMatchingConfig(
      matchingKeyword: json['matching_keyword'] as String?,
      matchingPattern: json['matching_pattern'] as String?,
      matchingPreference: (json['matching_preference'] is List)
          ? List<String>.from(json['matching_preference'] as List)
          : const <String>[],
    );

    return ApiBuildPlatformConfig(
      matchingConfig: matchingConfig,
      validZipSha256Checksums: parsedChecksums,
      path: json['path'] as String,
    );
  }

  static const releaseBlockerChecksum =
      '0000000000000000000000000000000000000000000000000000000000000000';

  /// Configuration for matching the correct API file
  final ApiFileMatchingConfig matchingConfig;

  /// List of valid SHA256 checksums for the API zip file
  ///
  /// Multiple checksums can be valid at the same time to support different
  /// versions or variations of the API.
  final List<String> validZipSha256Checksums;

  /// Path where the API files should be stored
  ///
  /// This path is relative to the project's artifact output directory.
  final String path;

  /// Whether this platform is declared but intentionally blocked from release.
  bool get isReleaseBlocked =>
      validZipSha256Checksums.length == 1 &&
      validZipSha256Checksums.single == releaseBlockerChecksum;

  /// Converts the configuration to a JSON map.
  Map<String, dynamic> toJson() => {
    ...matchingConfig.toJson(),
    'valid_zip_sha256_checksums': validZipSha256Checksums,
    'path': path,
  };
}
