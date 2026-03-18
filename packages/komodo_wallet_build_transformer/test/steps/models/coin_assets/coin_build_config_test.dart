import 'dart:convert';
import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/models/coin_assets/coin_build_config.dart';
import 'package:test/test.dart';

void main() {
  group('CoinBuildConfig', () {
    group('cdnBranchMirrors', () {
      test('should default to empty map when not provided', () {
        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
        );

        expect(config.cdnBranchMirrors, equals(<String, String>{}));
      });

      test('should accept cdnBranchMirrors in constructor', () {
        final mirrors = {
          'main': 'https://cdn.example.com/main',
          'dev': 'https://cdn.example.com/dev',
        };

        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: mirrors,
        );

        expect(config.cdnBranchMirrors, equals(mirrors));
      });
    });

    group('effectiveContentUrl', () {
      test(
        'should return CDN mirror URL when branch has mirror configured',
        () {
          final config = CoinBuildConfig(
            fetchAtBuildEnabled: true,
            bundledCoinsRepoCommit: 'abc123',
            updateCommitOnBuild: true,
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

          expect(
            config.effectiveContentUrl,
            equals('https://cdn.example.com/main'),
          );
        },
      );

      test('should return original content URL when branch has no mirror', () {
        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
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

        expect(
          config.effectiveContentUrl,
          equals('https://raw.githubusercontent.com/owner/repo'),
        );
      });

      test(
        'should return original content URL when no mirrors are configured',
        () {
          final config = CoinBuildConfig(
            fetchAtBuildEnabled: true,
            bundledCoinsRepoCommit: 'abc123',
            updateCommitOnBuild: true,
            coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
            coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
            coinsRepoBranch: 'main',
            runtimeUpdatesEnabled: true,
            mappedFiles: {},
            mappedFolders: {},
            concurrentDownloadsEnabled: true,
          );

          expect(
            config.effectiveContentUrl,
            equals('https://raw.githubusercontent.com/owner/repo'),
          );
        },
      );

      test('should handle master branch correctly', () {
        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'master',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {'master': 'https://cdn.example.com/master'},
        );

        expect(
          config.effectiveContentUrl,
          equals('https://cdn.example.com/master'),
        );
      });
    });

    group('fromJson', () {
      test('should parse cdnBranchMirrors from JSON', () {
        final json = {
          'fetch_at_build_enabled': true,
          'update_commit_on_build': true,
          'bundled_coins_repo_commit': 'abc123',
          'coins_repo_api_url': 'https://api.github.com/repos/owner/repo',
          'coins_repo_content_url':
              'https://raw.githubusercontent.com/owner/repo',
          'coins_repo_branch': 'main',
          'runtime_updates_enabled': true,
          'concurrent_downloads_enabled': true,
          'mapped_files': <String, String>{},
          'mapped_folders': <String, String>{},
          'cdn_branch_mirrors': {
            'main': 'https://cdn.example.com/main',
            'dev': 'https://cdn.example.com/dev',
          },
        };

        final config = CoinBuildConfig.fromJson(json);

        expect(
          config.cdnBranchMirrors,
          equals({
            'main': 'https://cdn.example.com/main',
            'dev': 'https://cdn.example.com/dev',
          }),
        );
      });

      test(
        'should default to empty map when cdn_branch_mirrors is not in JSON',
        () {
          final json = {
            'fetch_at_build_enabled': true,
            'update_commit_on_build': true,
            'bundled_coins_repo_commit': 'abc123',
            'coins_repo_api_url': 'https://api.github.com/repos/owner/repo',
            'coins_repo_content_url':
                'https://raw.githubusercontent.com/owner/repo',
            'coins_repo_branch': 'main',
            'runtime_updates_enabled': true,
            'concurrent_downloads_enabled': true,
            'mapped_files': <String, String>{},
            'mapped_folders': <String, String>{},
          };

          final config = CoinBuildConfig.fromJson(json);

          expect(config.cdnBranchMirrors, equals(<String, String>{}));
        },
      );

      test('should handle null cdn_branch_mirrors in JSON', () {
        final json = {
          'fetch_at_build_enabled': true,
          'update_commit_on_build': true,
          'bundled_coins_repo_commit': 'abc123',
          'coins_repo_api_url': 'https://api.github.com/repos/owner/repo',
          'coins_repo_content_url':
              'https://raw.githubusercontent.com/owner/repo',
          'coins_repo_branch': 'main',
          'runtime_updates_enabled': true,
          'concurrent_downloads_enabled': true,
          'mapped_files': <String, String>{},
          'mapped_folders': <String, String>{},
          'cdn_branch_mirrors': null,
        };

        final config = CoinBuildConfig.fromJson(json);

        expect(config.cdnBranchMirrors, equals(<String, String>{}));
      });
    });

    group('toJson', () {
      test('should include cdnBranchMirrors in JSON output', () {
        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
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

        final json = config.toJson();

        expect(
          json['cdn_branch_mirrors'],
          equals({
            'main': 'https://cdn.example.com/main',
            'dev': 'https://cdn.example.com/dev',
          }),
        );
      });

      test(
        'should include empty map for cdnBranchMirrors when none configured',
        () {
          final config = CoinBuildConfig(
            fetchAtBuildEnabled: true,
            bundledCoinsRepoCommit: 'abc123',
            updateCommitOnBuild: true,
            coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
            coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
            coinsRepoBranch: 'main',
            runtimeUpdatesEnabled: true,
            mappedFiles: {},
            mappedFolders: {},
            concurrentDownloadsEnabled: true,
          );

          final json = config.toJson();

          expect(json['cdn_branch_mirrors'], equals(<String, String>{}));
        },
      );
    });

    group('copyWith', () {
      test('should copy cdnBranchMirrors when provided', () {
        final originalConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {'main': 'https://cdn.example.com/main'},
        );

        final newMirrors = {
          'main': 'https://new-cdn.example.com/main',
          'dev': 'https://new-cdn.example.com/dev',
        };

        final copiedConfig = originalConfig.copyWith(
          cdnBranchMirrors: newMirrors,
        );

        expect(copiedConfig.cdnBranchMirrors, equals(newMirrors));
        expect(
          originalConfig.cdnBranchMirrors,
          equals({'main': 'https://cdn.example.com/main'}),
        );
      });

      test('should preserve cdnBranchMirrors when not provided', () {
        final originalMirrors = {
          'main': 'https://cdn.example.com/main',
          'dev': 'https://cdn.example.com/dev',
        };

        final originalConfig = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
          coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
          coinsRepoBranch: 'main',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: originalMirrors,
        );

        final copiedConfig = originalConfig.copyWith(coinsRepoBranch: 'dev');

        expect(copiedConfig.cdnBranchMirrors, equals(originalMirrors));
        expect(copiedConfig.coinsRepoBranch, equals('dev'));
      });
    });

    group('serialization round-trip', () {
      test(
        'should preserve all data including cdnBranchMirrors through JSON round-trip',
        () {
          final originalConfig = CoinBuildConfig(
            fetchAtBuildEnabled: true,
            bundledCoinsRepoCommit: 'abc123',
            updateCommitOnBuild: true,
            coinsRepoApiUrl: 'https://api.github.com/repos/owner/repo',
            coinsRepoContentUrl: 'https://raw.githubusercontent.com/owner/repo',
            coinsRepoBranch: 'main',
            runtimeUpdatesEnabled: true,
            mappedFiles: {'config/coins.json': 'coins/coins.json'},
            mappedFolders: {'assets': 'icons'},
            concurrentDownloadsEnabled: true,
            cdnBranchMirrors: {
              'main': 'https://cdn.example.com/main',
              'dev': 'https://cdn.example.com/dev',
              'staging': 'https://staging-cdn.example.com/staging',
            },
          );

          final json = originalConfig.toJson();
          final reconstructedConfig = CoinBuildConfig.fromJson(json);

          expect(
            reconstructedConfig.fetchAtBuildEnabled,
            equals(originalConfig.fetchAtBuildEnabled),
          );
          expect(
            reconstructedConfig.bundledCoinsRepoCommit,
            equals(originalConfig.bundledCoinsRepoCommit),
          );
          expect(
            reconstructedConfig.updateCommitOnBuild,
            equals(originalConfig.updateCommitOnBuild),
          );
          expect(
            reconstructedConfig.coinsRepoApiUrl,
            equals(originalConfig.coinsRepoApiUrl),
          );
          expect(
            reconstructedConfig.coinsRepoContentUrl,
            equals(originalConfig.coinsRepoContentUrl),
          );
          expect(
            reconstructedConfig.coinsRepoBranch,
            equals(originalConfig.coinsRepoBranch),
          );
          expect(
            reconstructedConfig.runtimeUpdatesEnabled,
            equals(originalConfig.runtimeUpdatesEnabled),
          );
          expect(
            reconstructedConfig.mappedFiles,
            equals(originalConfig.mappedFiles),
          );
          expect(
            reconstructedConfig.mappedFolders,
            equals(originalConfig.mappedFolders),
          );
          expect(
            reconstructedConfig.concurrentDownloadsEnabled,
            equals(originalConfig.concurrentDownloadsEnabled),
          );
          expect(
            reconstructedConfig.cdnBranchMirrors,
            equals(originalConfig.cdnBranchMirrors),
          );
          expect(
            reconstructedConfig.effectiveContentUrl,
            equals(originalConfig.effectiveContentUrl),
          );
        },
      );
    });

    group('integration scenarios', () {
      test('should prefer CDN for main branch in typical configuration', () {
        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'latest',
          updateCommitOnBuild: true,
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

        expect(
          config.effectiveContentUrl,
          equals('https://gleecbtc.github.io/coins'),
        );
      });

      test('should fallback to GitHub raw for feature branches', () {
        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/GLEECBTC/coins',
          coinsRepoContentUrl:
              'https://raw.githubusercontent.com/GLEECBTC/coins',
          coinsRepoBranch: 'feature/new-coin-support',
          runtimeUpdatesEnabled: true,
          mappedFiles: {'config/coins.json': 'coins/coins.json'},
          mappedFolders: {'assets/coins': 'icons'},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {
            'master': 'https://gleecbtc.github.io/coins',
            'dev': 'https://gleecbtc.github.io/coins',
          },
        );

        expect(
          config.effectiveContentUrl,
          equals('https://raw.githubusercontent.com/GLEECBTC/coins'),
        );
      });

      test('should work with empty CDN mirrors configuration', () {
        final config = CoinBuildConfig(
          fetchAtBuildEnabled: true,
          bundledCoinsRepoCommit: 'abc123',
          updateCommitOnBuild: true,
          coinsRepoApiUrl: 'https://api.github.com/repos/GLEECBTC/coins',
          coinsRepoContentUrl:
              'https://raw.githubusercontent.com/GLEECBTC/coins',
          coinsRepoBranch: 'master',
          runtimeUpdatesEnabled: true,
          mappedFiles: {},
          mappedFolders: {},
          concurrentDownloadsEnabled: true,
          cdnBranchMirrors: {},
        );

        expect(
          config.effectiveContentUrl,
          equals('https://raw.githubusercontent.com/GLEECBTC/coins'),
        );
      });
    });
  });
}
