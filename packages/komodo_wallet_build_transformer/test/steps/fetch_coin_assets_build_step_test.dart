import 'dart:convert';
import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/fetch_coin_assets_build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/coin_assets/coin_build_config.dart';
import 'package:test/test.dart';

void main() {
  group('FetchCoinAssetsBuildStep', () {
    late Directory tempDir;
    late File tempBuildConfigFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('test_');
      tempBuildConfigFile = File('${tempDir.path}/build_config.json');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('CDN Branch Mirrors Integration', () {
      test('should use CDN URL when branch has mirror configured', () {
        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: false,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {
            'main': 'https://cdn.example.com/main',
            'dev': 'https://cdn.example.com/dev',
          },
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final buildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          buildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // The build step config should preserve the original URL
        expect(
          buildStep.config.coinsRepoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );

        // But the downloader should receive the effective CDN URL
        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://cdn.example.com/main'),
        );
      });

      test('should use original GitHub URL when branch has no CDN mirror', () {
        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: false,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'feature-branch',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {
            'main': 'https://cdn.example.com/main',
            'dev': 'https://cdn.example.com/dev',
          },
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final buildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          buildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // The build step config should preserve the original URL
        expect(
          buildStep.config.coinsRepoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );

        // And the downloader should also receive the original URL (no CDN mirror)
        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );
      });

      test('should use original URL when no CDN mirrors are configured', () {
        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: false,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {},
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final buildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          buildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        expect(
          buildStep.config.coinsRepoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );

        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );
      });

      test('should handle master branch CDN mirror correctly', () {
        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: false,
          coinsRepoApiUrl: 'https://api.github.com/repos/GLEECBTC/coins',
          coinsRepoContentUrl:
              'https://raw.githubusercontent.com/GLEECBTC/coins',
          coinsRepoBranch: 'master',
          runtimeUpdatesEnabled: true,
          mappedFiles: {'config/coins.json': 'coins/coins.json'},
          mappedFolders: {'assets/coins': 'icons'},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {
            'master': 'https://gleecbtc.github.io/coins',
            'dev': 'https://gleecbtc.github.io/coins',
          },
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final buildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          buildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // Config should preserve original GitHub URL
        expect(
          buildStep.config.coinsRepoContentUrl,
          equals('https://raw.githubusercontent.com/GLEECBTC/coins'),
        );

        // But downloader should receive the CDN URL
        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://gleecbtc.github.io/coins'),
        );
      });

      test('should preserve original build config structure', () {
        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: false,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {'config/coins.json': 'coins/coins.json'},
          mappedFolders: {'assets/coins': 'icons'},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {'main': 'https://cdn.example.com/main'},
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final originalBuildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          originalBuildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // Verify that both the original and working configs preserve the original URL
        expect(buildStep.originalBuildConfig, equals(originalBuildConfig));
        expect(
          buildStep.originalBuildConfig!.coinCIConfig.coinsRepoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );
        expect(
          buildStep.config.coinsRepoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );

        // But the downloader should receive the CDN URL
        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://cdn.example.com/main'),
        );
      });

      test('should work with various CDN URL formats', () {
        final testCases = [
          {
            'branch': 'main',
            'cdnUrl': 'https://cdn.jsdelivr.net/gh/owner/repo@main',
            'description': 'jsDelivr CDN format',
          },
          {
            'branch': 'dev',
            'cdnUrl': 'https://cdn.statically.io/gh/owner/repo/dev',
            'description': 'Statically CDN format',
          },
          {
            'branch': 'staging',
            'cdnUrl': 'https://custom-cdn.example.com/repos/owner/repo/staging',
            'description': 'Custom CDN format',
          },
        ];

        for (final testCase in testCases) {
          final coinConfig = CoinBuildConfig(
            fetchAtBuildEnabled: true,
            bundledCoinsRepoCommit: 'abc123',
            updateCommitOnBuild: false,
            coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
            coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
            coinsRepoBranch: testCase['branch']! as String,
            runtimeUpdatesEnabled: true,
            mappedFiles: {},
            mappedFolders: {},
            concurrentDownloadsEnabled: true,
            cdnBranchMirrors: {
              testCase['branch']! as String: testCase['cdnUrl']! as String,
            },
          );

          final apiConfig = ApiBuildConfig(
            apiCommitHash: 'abc123',
            branch: 'main',
            fetchAtBuildEnabled: true,
            concurrentDownloadsEnabled: true,
            sourceUrls: ['https://example.com'],
            platforms: {},
          );

          final buildConfig = BuildConfig(
            apiConfig: apiConfig,
            coinCIConfig: coinConfig,
          );

          final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
            buildConfig,
            tempBuildConfigFile,
            artifactOutputDirectory: tempDir,
          );

          expect(
            buildStep.config.coinsRepoContentUrl,
            equals('https://raw.githubusercontent.com/owner/repo'),
            reason:
                'Config should preserve original URL for ${testCase['description']} with branch ${testCase['branch']}',
          );

          expect(
            buildStep.downloader.repoContentUrl,
            equals(testCase['cdnUrl']),
            reason:
                'Downloader should receive CDN URL for ${testCase['description']} with branch ${testCase['branch']}',
          );
        }
      });
    });

    group('GitHub File Downloader Integration', () {
      test('should pass effective content URL to downloader', () {
        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: false,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {'main': 'https://cdn.example.com/main'},
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final buildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          buildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // Verify that the config preserves the original URL
        expect(
          buildStep.config.coinsRepoContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );

        // But the downloader receives the CDN URL
        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://cdn.example.com/main'),
        );
      });

      test(
        'should pass original GitHub URL to downloader when no CDN mirror',
        () {
          final coinConfig = CoinBuildConfig(
            fetchAtBuildEnabled: true,
            bundledCoinsRepoCommit: 'abc123',
            updateCommitOnBuild: false,
            coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
            coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
            coinsRepoBranch: 'feature-branch',
            runtimeUpdatesEnabled: true,
            mappedFiles: {},
            mappedFolders: {},
            concurrentDownloadsEnabled: true,
            cdnBranchMirrors: {'main': 'https://cdn.example.com/main'},
          );

          final apiConfig = ApiBuildConfig(
            apiCommitHash: 'abc123',
            branch: 'main',
            fetchAtBuildEnabled: true,
            concurrentDownloadsEnabled: true,
            sourceUrls: ['https://example.com'],
            platforms: {},
          );

          final buildConfig = BuildConfig(
            apiConfig: apiConfig,
            coinCIConfig: coinConfig,
          );

          final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
            buildConfig,
            tempBuildConfigFile,
            artifactOutputDirectory: tempDir,
          );

          expect(
            buildStep.config.coinsRepoContentUrl,
            equals('https://raw.githubusercontent.com/owner/repo'),
          );

          expect(
            buildStep.downloader.repoContentUrl,
            equals('https://raw.githubusercontent.com/owner/repo'),
          );
        },
      );
    });

    group('Regression Tests', () {
      test('should not overwrite build config with hardcoded URLs anymore', () {
        // This test ensures that the original issue is fixed:
        // The build config should not be overwritten with hardcoded CDN URLs
        final originalContentUrl =
            'https://my-custom-cdn.example.com/custom-branch';

        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: false,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: originalContentUrl,
          coinsRepoBranch: 'custom-branch',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {
            'custom-branch': 'https://proper-cdn.example.com/custom-branch',
          },
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final originalBuildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          originalBuildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // Both the original and working configs should preserve the original URL
        expect(
          buildStep.originalBuildConfig!.coinCIConfig.coinsRepoContentUrl,
          equals(originalContentUrl),
        );

        expect(
          buildStep.config.coinsRepoContentUrl,
          equals(originalContentUrl),
        );

        // But the downloader should receive the CDN mirror URL
        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://proper-cdn.example.com/custom-branch'),
        );
      });

      test(
        'should handle the old hardcoded branch check behavior gracefully',
        () {
          // Test that both master and main branches work correctly
          final testBranches = ['master', 'main'];

          for (final branch in testBranches) {
            final coinConfig = CoinBuildConfig(
              fetchAtBuildEnabled: true,
              bundledCoinsRepoCommit: 'abc123',
              updateCommitOnBuild: false,
              coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
              coinsRepoContentUrl:
                  'https://raw.githubusercontent.com/owner/repo',
              coinsRepoBranch: branch,
              runtimeUpdatesEnabled: true,
              mappedFiles: {},
              mappedFolders: {},
              concurrentDownloadsEnabled: true,
              cdnBranchMirrors: {
                'master': 'https://cdn.example.com/master',
                'main': 'https://cdn.example.com/main',
              },
            );

            final apiConfig = ApiBuildConfig(
              apiCommitHash: 'abc123',
              branch: 'main',
              fetchAtBuildEnabled: true,
              concurrentDownloadsEnabled: true,
              sourceUrls: ['https://example.com'],
              platforms: {},
            );

            final buildConfig = BuildConfig(
              apiConfig: apiConfig,
              coinCIConfig: coinConfig,
            );

            final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
              buildConfig,
              tempBuildConfigFile,
              artifactOutputDirectory: tempDir,
            );

            expect(
              buildStep.config.coinsRepoContentUrl,
              equals('https://raw.githubusercontent.com/owner/repo'),
              reason: 'Config should preserve original URL for branch: $branch',
            );

            expect(
              buildStep.downloader.repoContentUrl,
              equals('https://cdn.example.com/$branch'),
              reason: 'Downloader should receive CDN URL for branch: $branch',
            );
          }
        },
      );
    });

    group('Integration Test - Original Issue Resolution', () {
      test('should completely resolve the original config overwrite issue', () async {
        // This test demonstrates that the original issue is completely fixed:
        // "After the transformer runs the `coins_repo_content_url` in build_config.json
        // is overwritten with an incorrect CDN branch mirror url instead of the existing value."

        // Setup: User has a custom content URL and CDN mirrors configured
        final userConfiguredUrl =
            'https://my-custom-github-mirror.example.com/GLEECBTC/coins';

        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true, // This triggers config save
          coinsRepoApiUrl: 'https://api.github.com/repos/GLEECBTC/coins',
          coinsRepoContentUrl: userConfiguredUrl, // User's custom URL
          coinsRepoBranch: 'master',
          runtimeUpdatesEnabled: true,
          mappedFiles: {'config/coins.json': 'coins/coins.json'},
          mappedFolders: {'assets/coins': 'icons'},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {
            'master': 'https://gleecbtc.github.io/coins',
            'dev': 'https://gleecbtc.github.io/coins',
          },
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final originalBuildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        // Create a temporary build config file to simulate the real scenario
        final tempBuildConfigFile = File('${tempDir.path}/build_config.json');
        await tempBuildConfigFile.writeAsString(
          '{}',
        ); // Start with empty config

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          originalBuildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // CRITICAL VERIFICATION: The working config should preserve the original URL
        expect(
          buildStep.config.coinsRepoContentUrl,
          equals(userConfiguredUrl),
          reason: 'Working config must preserve user-configured URL',
        );

        // CRITICAL VERIFICATION: The original config should be unchanged
        expect(
          buildStep.originalBuildConfig!.coinCIConfig.coinsRepoContentUrl,
          equals(userConfiguredUrl),
          reason: 'Original config must remain unchanged',
        );

        // CRITICAL VERIFICATION: The downloader should use the CDN mirror (effective URL)
        expect(
          buildStep.downloader.repoContentUrl,
          equals('https://gleecbtc.github.io/coins'),
          reason: 'Downloader should use CDN mirror for efficiency',
        );

        // CRITICAL VERIFICATION: The effective URL logic should work correctly
        expect(
          buildStep.config.effectiveContentUrl,
          equals('https://gleecbtc.github.io/coins'),
          reason: 'Effective URL should return CDN mirror when available',
        );

        // Simulate the config save operation that happens during the build
        await buildStep.config.save(
          assetPath: tempBuildConfigFile.path,
          originalBuildConfig: buildStep.originalBuildConfig,
        );

        // CRITICAL VERIFICATION: After saving, the config file should contain the original URL
        final savedConfigContent = await tempBuildConfigFile.readAsString();
        final savedConfigJson = jsonDecode(savedConfigContent);
        final savedCoinsConfig = savedConfigJson['coins'];

        expect(
          savedCoinsConfig['coins_repo_content_url'],
          equals(userConfiguredUrl),
          reason:
              'Saved config must preserve the original user-configured URL, not the CDN URL',
        );

        // ADDITIONAL VERIFICATION: CDN mirrors should be preserved in saved config
        expect(
          savedCoinsConfig['cdn_branch_mirrors'],
          equals({
            'master': 'https://gleecbtc.github.io/coins',
            'dev': 'https://gleecbtc.github.io/coins',
          }),
          reason:
              'CDN mirrors configuration should be preserved in saved config',
        );

        // SUCCESS: This proves the original issue is completely resolved:
        // 1. User's original coinsRepoContentUrl is preserved in the saved config
        // 2. CDN mirrors are used efficiently during the build process
        // 3. No hardcoded URL overwrites occur
        // 4. The config file maintains the user's original configuration
      });

      test('should handle the case where no CDN mirror is available', () async {
        // Test the scenario where user has a custom URL but no CDN mirror for the branch
        final userConfiguredUrl =
            'https://custom-mirror.example.com/repo/coins';

        final coinConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: userConfiguredUrl,
          coinsRepoBranch: 'feature-branch', // No CDN mirror for this branch
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {
            'master': 'https://cdn.example.com/master', // Only master has CDN
          },
        );

        final apiConfig = ApiBuildConfig(
          apiCommitHash: 'abc123',
          branch: 'main',
          fetchAtBuildEnabled: true,
          concurrentDownloadsEnabled: true,
          sourceUrls: ['https://example.com'],
          platforms: {},
        );

        final buildConfig = BuildConfig(
          apiConfig: apiConfig,
          coinCIConfig: coinConfig,
        );

        final tempBuildConfigFile = File('${tempDir.path}/build_config.json');
        await tempBuildConfigFile.writeAsString('{}');

        final buildStep = FetchCoinAssetsBuildStep.withBuildConfig(
          buildConfig,
          tempBuildConfigFile,
          artifactOutputDirectory: tempDir,
        );

        // Verify that without a CDN mirror, the original URL is used everywhere
        expect(
          buildStep.config.coinsRepoContentUrl,
          equals(userConfiguredUrl),
          reason: 'Config should preserve original URL',
        );

        expect(
          buildStep.downloader.repoContentUrl,
          equals(userConfiguredUrl),
          reason:
              'Downloader should use original URL when no CDN mirror available',
        );

        expect(
          buildStep.config.effectiveContentUrl,
          equals(userConfiguredUrl),
          reason:
              'Effective URL should fallback to original when no CDN mirror',
        );

        // Save and verify the config file preserves the original URL
        await buildStep.config.save(
          assetPath: tempBuildConfigFile.path,
          originalBuildConfig: buildStep.originalBuildConfig,
        );

        final savedConfigContent = await tempBuildConfigFile.readAsString();
        final savedConfigJson = jsonDecode(savedConfigContent);
        final savedCoinsConfig = savedConfigJson['coins'];

        expect(
          savedCoinsConfig['coins_repo_content_url'],
          equals(userConfiguredUrl),
          reason: 'Saved config must preserve original URL',
        );
      });
    });
  });
}
