import 'dart:convert';
import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_platform_config.dart';
import 'package:test/test.dart';

void main() {
  const pinnedCommit = 'bd413dcfea73c9de2e85903323946a378b180fa7';
  const checksum =
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
  const pinnedChecksums = <String, String>{
    'web': '9242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c',
    'ios': '0cc494a8ff7b3f926cebc6956cda61c9928c7366624d592c71e29f080a3255bd',
    'macos': 'f1d8a52c7c34d9721761733586f7262177b5362f911d8a220b2550e1f9844bbe',
    'android-armv7':
        '929d57312908544c9e6ae94d660d8ae14c21fb84547821ba0e0aba26c4daf29a',
    'android-aarch64':
        '9953572e03956a751dcef365df76b6b84a3675800323220d50409dbd8175f037',
    'linux': 'ec5e2c801520e00ed1fd18c82c0edc0ade30716c6a4fb8aab453f265ce6afb33',
    'windows':
        '04062cf1a271888eab9a757fa1a19e41038beea15b19484a21e5731d4dfc05e0',
  };

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
    test('canonical GasFree manifest pins the complete platform build set', () {
      final manifest = File(
        '../komodo_defi_framework/app_build/build_config.json',
      );
      final json = jsonDecode(manifest.readAsStringSync());
      final apiJson = (json as Map<String, dynamic>)['api'];
      final parsed = ApiBuildConfig.fromJson(apiJson as Map<String, dynamic>);

      expect(parsed.apiCommitHash, pinnedCommit);
      expect(parsed.branch, 'feat/tron-gasfree');
      expect(parsed.requiredPlatforms, pinnedChecksums.keys);
      for (final entry in pinnedChecksums.entries) {
        final platform = parsed.platforms[entry.key];
        expect(platform, isNotNull, reason: '${entry.key} must be configured');
        expect(platform!.isReleaseBlocked, isFalse);
        expect(platform.validZipSha256Checksums, [entry.value]);
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
