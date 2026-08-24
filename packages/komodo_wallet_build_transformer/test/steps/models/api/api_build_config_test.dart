import 'dart:convert';
import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_platform_config.dart';
import 'package:test/test.dart';

void main() {
  const pinnedCommit = 'bd413dcfea73c9de2e85903323946a378b180fa7';
  const checksum =
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';

  /// Every platform the shipped manifest must pin, whatever it is pinned to.
  ///
  /// This used to also carry each platform's expected checksum and the commit
  /// itself, which made a routine KDF roll fail a *policy* test: the values
  /// went stale the moment the pin moved off `bd413dc` and stayed red through
  /// three subsequent rolls. The commit and the checksums belong to the
  /// manifest; what this test guards is the shape - a full 40-character hash,
  /// all seven platforms present, none release-blocked, exactly one checksum
  /// each. Assert that, and a roll stays a one-file change.
  const requiredPlatforms = <String>[
    'web',
    'ios',
    'macos',
    'android-armv7',
    'android-aarch64',
    'linux',
    'windows',
  ];

  Map<String, dynamic> platform() => {
    'matching_pattern': r'^kdf_[a-f0-9]{7,40}-android-aarch64\.zip$',
    'valid_zip_sha256_checksums': [checksum],
    'path': 'android/libs/arm64-v8a',
  };

  Map<String, dynamic> config() => {
    'api_commit_hash': pinnedCommit,
    'branch': 'feat/tron-gasfree',
    'fetch_at_build_enabled': true,
    'concurrent_downloads_enabled': true,
    'require_full_commit_hash': true,
    'required_platforms': ['android-aarch64'],
    'source_urls': ['https://builds.example.com'],
    'platforms': {'android-aarch64': platform()},
  };

  group('ApiBuildConfig artifact policy', () {
    test('the shipped manifest pins the complete platform build set', () {
      final manifest = File(
        '../komodo_defi_framework/app_build/build_config.json',
      );
      final json = jsonDecode(manifest.readAsStringSync());
      final apiJson = (json as Map<String, dynamic>)['api'];
      final parsed = ApiBuildConfig.fromJson(apiJson as Map<String, dynamic>);

      expect(
        parsed.apiCommitHash,
        matches(RegExp(r'^[0-9a-f]{40}$')),
        reason: 'the manifest must pin an immutable, full-length commit',
      );
      expect(parsed.branch, isNotEmpty);
      expect(parsed.requiredPlatforms, requiredPlatforms);
      for (final name in requiredPlatforms) {
        final platform = parsed.platforms[name];
        expect(platform, isNotNull, reason: '$name must be configured');
        expect(platform!.isReleaseBlocked, isFalse);
        expect(
          platform.validZipSha256Checksums,
          hasLength(1),
          reason:
              '$name must pin exactly one artefact; more than one means a '
              'previous roll left a stale checksum behind',
        );
        expect(
          platform.validZipSha256Checksums.single,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: '$name checksum must be a full sha256',
        );
      }
    });

    test('accepts a full immutable commit and all required platforms', () {
      final parsed = ApiBuildConfig.fromJson(config());

      expect(parsed.requireFullCommitHash, isTrue);
      expect(parsed.requiredPlatforms, ['android-aarch64']);
    });

    test('rejects a short commit when full hashes are required', () {
      final json = config()..['api_commit_hash'] = 'bd413dc';

      expect(() => ApiBuildConfig.fromJson(json), throwsFormatException);
    });

    test('rejects a short commit even when the legacy flag is disabled', () {
      final json = config()
        ..['api_commit_hash'] = 'bd413dc'
        ..['require_full_commit_hash'] = false;

      expect(() => ApiBuildConfig.fromJson(json), throwsFormatException);
    });

    test('rejects a missing required platform', () {
      final json = config()..['platforms'] = <String, dynamic>{};

      expect(() => ApiBuildConfig.fromJson(json), throwsFormatException);
    });
  });

  group('ApiBuildPlatformConfig artifact policy', () {
    test('recognizes the all-zero release blocker', () {
      final json = platform()
        ..['valid_zip_sha256_checksums'] = [
          ApiBuildPlatformConfig.releaseBlockerChecksum,
        ];

      expect(ApiBuildPlatformConfig.fromJson(json).isReleaseBlocked, isTrue);
    });

    test('rejects malformed checksums', () {
      final json = platform()
        ..['valid_zip_sha256_checksums'] = ['not-a-checksum'];

      expect(
        () => ApiBuildPlatformConfig.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects mixing a blocker with accepted checksums', () {
      final json = platform()
        ..['valid_zip_sha256_checksums'] = [
          ApiBuildPlatformConfig.releaseBlockerChecksum,
          checksum,
        ];

      expect(
        () => ApiBuildPlatformConfig.fromJson(json),
        throwsFormatException,
      );
    });
  });
}
