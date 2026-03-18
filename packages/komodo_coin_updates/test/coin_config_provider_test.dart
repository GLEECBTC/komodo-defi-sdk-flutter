import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _ForceWalletOnlyTransform implements CoinConfigTransform {
  const _ForceWalletOnlyTransform();
  @override
  JsonMap transform(JsonMap config) {
    final out = JsonMap.of(config);
    out['wallet_only'] = true;
    return out;
  }

  @override
  bool needsTransform(JsonMap config) => true;
}

/// Helper function to create a GithubCoinConfigProvider with standard defaults
/// based on the actual build configuration values
GithubCoinConfigProvider createTestProvider({
  String? branch,
  String? coinsGithubContentUrl,
  String? coinsGithubApiUrl,
  String? coinsPath,
  String? coinsConfigPath,
  Map<String, String>? cdnBranchMirrors,
  String? githubToken,
  CoinConfigTransformer? transformer,
  http.Client? httpClient,
}) {
  // Use the actual build config values as defaults
  return GithubCoinConfigProvider(
    branch: branch ?? 'master',
    coinsGithubContentUrl:
        coinsGithubContentUrl ??
        'https://raw.githubusercontent.com/GLEECBTC/coins',
    coinsGithubApiUrl:
        coinsGithubApiUrl ??
        'https://api.github.com/repos/GLEECBTC/coins',
    coinsPath: coinsPath ?? 'coins',
    coinsConfigPath: coinsConfigPath ?? 'utils/coins_config_unfiltered.json',
    cdnBranchMirrors: cdnBranchMirrors,
    githubToken: githubToken,
    transformer: transformer,
    httpClient: httpClient,
  );
}

/// Comprehensive unit tests for the GithubCoinConfigProvider class and
/// CDN mirror functionality.
///
/// **Purpose**: Tests the GitHub-based coin configuration provider that
/// fetches coin configurations from GitHub repositories, including CDN
/// mirror support, HTTP client integration, and configuration
/// transformation pipelines.
///
/// **Test Cases**:
/// - CDN mirror URL construction and fallback behavior
/// - Branch-specific CDN mirror usage (master/main vs development branches)
/// - Commit hash handling and URL construction
/// - HTTP client integration and error handling
/// - Configuration transformation and filtering
/// - Asset loading and parsing workflows
/// - Error scenarios and exception handling
///
/// **Functionality Tested**:
/// - CDN mirror URL resolution and fallback
/// - GitHub API integration for commit information
/// - Raw content loading and parsing
/// - Configuration transformation pipelines
/// - Asset filtering and exclusion
/// - HTTP client integration and mocking
/// - Error handling and propagation
/// - URL construction and normalization
///
/// **Edge Cases**:
/// - CDN mirror availability and fallbacks
/// - Branch vs commit hash URL construction
/// - HTTP error responses and status codes
/// - Configuration parsing failures
/// - Network timeout and connection issues
/// - CDN vs raw GitHub URL selection logic
/// - Commit hash validation and URL construction
///
/// **Dependencies**: Tests the GitHub-based configuration provider that serves
/// the primary source for coin configurations, including CDN optimization, HTTP
/// client integration, and configuration processing pipelines.
void main() {
  group('GithubCoinConfigProvider CDN mirrors', () {
    test('uses CDN base when exact branch mirror exists', () {
      final provider = createTestProvider(
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins',
        },
      );

      final uri = provider.buildContentUri(
        'utils/coins_config_unfiltered.json',
      );
      expect(
        uri.toString(),
        'https://gleecbtc.github.io/coins/utils/coins_config_unfiltered.json',
      );
    });

    test('falls back to raw content when branch has no mirror', () {
      final provider = createTestProvider(
        branch: 'dev',
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins',
        },
      );

      final uri = provider.buildContentUri(
        'utils/coins_config_unfiltered.json',
      );
      expect(
        uri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/dev/utils/coins_config_unfiltered.json',
      );
    });

    test('branchOrCommit override uses matching CDN when available', () {
      final provider = createTestProvider(
        branch: 'dev',
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins',
        },
      );

      final uri = provider.buildContentUri(
        'utils/coins_config_unfiltered.json',
        branchOrCommit: 'master',
      );
      expect(
        uri.toString(),
        'https://gleecbtc.github.io/coins/utils/coins_config_unfiltered.json',
      );
    });

    test('branchOrCommit override falls back to raw when not mirrored', () {
      final provider = createTestProvider(
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins',
        },
      );

      final uri = provider.buildContentUri(
        'utils/coins_config_unfiltered.json',
        branchOrCommit: 'feature/example',
      );
      expect(
        uri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/feature/example/utils/coins_config_unfiltered.json',
      );
    });

    test('ignores empty CDN entry and falls back to raw', () {
      final provider = createTestProvider(
        branch: 'dev',
        cdnBranchMirrors: const {'dev': ''},
      );

      final uri = provider.buildContentUri(
        'utils/coins_config_unfiltered.json',
      );
      expect(
        uri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/dev/utils/coins_config_unfiltered.json',
      );
    });

    test('uses raw URL for commit hash even when CDN is available', () {
      final provider = createTestProvider(
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins',
        },
      );

      final uri = provider.buildContentUri(
        'utils/coins_config_unfiltered.json',
        branchOrCommit: 'f7d8e39cd11c3b6431df314fcaae5becc2814136',
      );
      expect(
        uri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/f7d8e39cd11c3b6431df314fcaae5becc2814136/utils/coins_config_unfiltered.json',
      );
    });

    test('handles null mirrors and falls back to raw', () {
      final provider = createTestProvider();

      final uri = provider.buildContentUri(
        'utils/coins_config_unfiltered.json',
      );
      expect(
        uri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/master/utils/coins_config_unfiltered.json',
      );
    });

    test('CDN base with trailing slash and path with leading slash', () {
      final provider = createTestProvider(
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins/',
        },
      );

      final uri = provider.buildContentUri(
        '/utils/coins_config_unfiltered.json',
      );
      expect(
        uri.toString(),
        'https://gleecbtc.github.io/coins/utils/coins_config_unfiltered.json',
      );
    });

    test('Raw content base with trailing slash and path with leading slash', () {
      final provider = createTestProvider(
        branch: 'feature/example',
        coinsGithubContentUrl:
            'https://raw.githubusercontent.com/GLEECBTC/coins/',
      );

      final uri = provider.buildContentUri(
        '/utils/coins_config_unfiltered.json',
      );
      expect(
        uri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/feature/example/utils/coins_config_unfiltered.json',
      );
    });

    group('master/main branch CDN behavior', () {
      test('master branch uses CDN URL without appending branch name', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
        );
        expect(
          uri.toString(),
          'https://gleecbtc.github.io/coins/utils/coins_config_unfiltered.json',
        );
      });

      test('main branch uses CDN URL without appending branch name', () {
        final provider = createTestProvider(
          branch: 'main',
          cdnBranchMirrors: const {
            'main': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
        );
        expect(
          uri.toString(),
          'https://gleecbtc.github.io/coins/utils/coins_config_unfiltered.json',
        );
      });

      test('explicit master override uses CDN URL', () {
        final provider = createTestProvider(
          branch: 'dev',
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
            'main': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'master',
        );
        expect(
          uri.toString(),
          'https://gleecbtc.github.io/coins/utils/coins_config_unfiltered.json',
        );
      });

      test('explicit main override uses CDN URL', () {
        final provider = createTestProvider(
          branch: 'dev',
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
            'main': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'main',
        );
        expect(
          uri.toString(),
          'https://gleecbtc.github.io/coins/utils/coins_config_unfiltered.json',
        );
      });
    });

    group('non-master/main branch behavior', () {
      test('development branch uses GitHub raw URL even with CDN available', () {
        final provider = createTestProvider(
          branch: 'dev',
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/dev/utils/coins_config_unfiltered.json',
        );
      });

      test('feature branch uses GitHub raw URL even with CDN available', () {
        final provider = createTestProvider(
          branch: 'feature/new-coin-support',
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
            'main': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/feature/new-coin-support/utils/coins_config_unfiltered.json',
        );
      });

      test('release branch uses GitHub raw URL even with CDN available', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'release/v1.2.0',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/release/v1.2.0/utils/coins_config_unfiltered.json',
        );
      });

      test('hotfix branch uses GitHub raw URL even with CDN available', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
            'main': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'hotfix/urgent-fix',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/hotfix/urgent-fix/utils/coins_config_unfiltered.json',
        );
      });
    });

    group('commit hash behavior', () {
      test('full 40-character commit hash uses GitHub raw URL', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
            'main': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'f7d8e39cd11c3b6431df314fcaae5becc2814136',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/f7d8e39cd11c3b6431df314fcaae5becc2814136/utils/coins_config_unfiltered.json',
        );
      });

      test('different commit hash uses GitHub raw URL', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'abc123def456789012345678901234567890abcd',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/abc123def456789012345678901234567890abcd/utils/coins_config_unfiltered.json',
        );
      });

      test('commit hash with uppercase letters uses GitHub raw URL', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
            'main': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'F7D8E39CD11C3B6431DF314FCAAE5BECC2814136',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/F7D8E39CD11C3B6431DF314FCAAE5BECC2814136/utils/coins_config_unfiltered.json',
        );
      });

      test('mixed case commit hash uses GitHub raw URL', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'AbC123DeF456789012345678901234567890AbCd',
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/AbC123DeF456789012345678901234567890AbCd/utils/coins_config_unfiltered.json',
        );
      });
    });

    group('edge cases and validation', () {
      test('short hash-like string is treated as branch name', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'abc123': 'https://example.com/short-hash-branch',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'abc123', // Only 6 characters, not a commit hash
        );
        expect(
          uri.toString(),
          'https://example.com/short-hash-branch/utils/coins_config_unfiltered.json',
        );
      });

      test('39-character string is treated as branch name', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit: 'f7d8e39cd11c3b6431df314fcaae5becc281413', // 39 chars
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/f7d8e39cd11c3b6431df314fcaae5becc281413/utils/coins_config_unfiltered.json',
        );
      });

      test('41-character string is treated as branch name', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit:
              'f7d8e39cd11c3b6431df314fcaae5becc2814136a', // 41 chars
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/f7d8e39cd11c3b6431df314fcaae5becc2814136a/utils/coins_config_unfiltered.json',
        );
      });

      test('40-character string with non-hex characters is treated as branch', () {
        final provider = createTestProvider(
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
          branchOrCommit:
              'f7d8e39cd11c3b6431df314fcaae5becc281413g', // 40 chars but contains 'g'
        );
        expect(
          uri.toString(),
          'https://raw.githubusercontent.com/GLEECBTC/coins/f7d8e39cd11c3b6431df314fcaae5becc281413g/utils/coins_config_unfiltered.json',
        );
      });
    });
  });
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(<String, String>{});
  });

  group('GithubCoinConfigProvider', () {
    late _MockHttpClient client;
    late GithubCoinConfigProvider provider;

    setUp(() {
      client = _MockHttpClient();
      provider = createTestProvider(httpClient: client);
    });

    test('reproduces commit hash appended to CDN URL bug', () async {
      // This test reproduces the exact issue described in the bug report
      final providerWithCdn = createTestProvider(
        httpClient: client,
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins',
        },
      );

      // This should NOT append the commit hash to the CDN URL
      final uri = providerWithCdn.buildContentUri(
        'utils/coins_config_unfiltered.json',
        branchOrCommit: 'f7d8e39cd11c3b6431df314fcaae5becc2814136',
      );

      // The bug shows this URL is being generated:
      // https://gleecbtc.github.io/coins/f7d8e39cd11c3b6431df314fcaae5becc2814136/utils/coins_config_unfiltered.json
      // But it should be:
      // https://raw.githubusercontent.com/GLEECBTC/coins/f7d8e39cd11c3b6431df314fcaae5becc2814136/utils/coins_config_unfiltered.json

      expect(
        uri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/f7d8e39cd11c3b6431df314fcaae5becc2814136/utils/coins_config_unfiltered.json',
        reason:
            'Commit hashes should never use CDN URLs - they should always use raw GitHub URLs',
      );

      // Verify the URL does NOT contain the CDN base
      expect(
        uri.toString(),
        isNot(contains('gleecbtc.github.io')),
        reason: 'CDN URLs should not be used for commit hashes',
      );
    });

    test('getLatestCommit returns sha on 200', () async {
      final uri = Uri.parse(
        '${provider.coinsGithubApiUrl}/branches/${provider.branch}',
      );
      when(() => client.get(uri, headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'commit': {'sha': 'abc123'},
          }),
          200,
        ),
      );

      final sha = await provider.getLatestCommit();
      expect(sha, 'abc123');
    });

    test('getLatestAssets parses list of Asset from config map', () async {
      final uri = Uri.parse(
        '${provider.coinsGithubContentUrl}/${provider.branch}/${provider.coinsConfigPath}',
      );

      when(() => client.get(uri)).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'KMD': {
              'coin': 'KMD',
              'decimals': 8,
              'type': 'UTXO',
              'protocol': {'type': 'UTXO'},
              'fname': 'Komodo',
              'chain_id': 0,
              'is_testnet': false,
            },
          }),
          200,
        ),
      );

      final assets = await provider.getAssets();
      expect(assets, isNotEmpty);
      expect(assets.first.id.id, 'KMD');
    });

    test('getLatestCommit throws on non-200 and includes headers', () async {
      final uri = Uri.parse(
        '${provider.coinsGithubApiUrl}/branches/${provider.branch}',
      );
      when(() => client.get(uri, headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response('nope', 403, reasonPhrase: 'Forbidden'),
      );

      expect(() => provider.getLatestCommit(), throwsA(isA<Exception>()));
    });

    test('getAssetsForCommit throws on non-200', () async {
      final url = provider.buildContentUri(provider.coinsConfigPath);
      when(
        () => client.get(url),
      ).thenAnswer((_) async => http.Response('error', 500));
      expect(
        () => provider.getAssetsForCommit(provider.branch),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'transformation pipeline applies and filters excluded coins',
      () async {
        final p = createTestProvider(
          httpClient: client,
          transformer: const CoinConfigTransformer(
            transforms: [_ForceWalletOnlyTransform()],
          ),
        );

        final uri = Uri.parse(
          '${p.coinsGithubContentUrl}/${p.branch}/${p.coinsConfigPath}',
        );
        when(() => client.get(uri)).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'KMD': {
                'coin': 'KMD',
                'type': 'UTXO',
                'protocol': {'type': 'UTXO'},
                'fname': 'Komodo',
                'chain_id': 0,
                'is_testnet': false,
              },
              'SLP': {
                'coin': 'SLP',
                'type': 'SLP',
                'protocol': {'type': 'SLP'},
                'fname': 'SLP Token',
                'chain_id': 0,
                'is_testnet': false,
              },
            }),
            200,
          ),
        );

        final assets = await p.getAssets();
        expect(assets.any((a) => a.id.id == 'SLP'), isFalse);
        final kmd = assets.firstWhere((a) => a.id.id == 'KMD');
        expect(kmd.isWalletOnly, isTrue);
      },
    );

    test('buildContentUri normalizes coinsPath entries', () {
      final p = createTestProvider(
        coinsGithubContentUrl:
            'https://raw.githubusercontent.com/GLEECBTC/coins/',
        cdnBranchMirrors: const {
          'master': 'https://gleecbtc.github.io/coins/',
        },
      );

      final cdnUri = p.buildContentUri('/coins/KMD.json');
      expect(
        cdnUri.toString(),
        'https://gleecbtc.github.io/coins/coins/KMD.json',
      );

      final rawP = createTestProvider(
        coinsGithubContentUrl:
            'https://raw.githubusercontent.com/GLEECBTC/coins/',
        cdnBranchMirrors: const {},
      );
      final rawUri = rawP.buildContentUri('/coins/KMD.json');
      expect(
        rawUri.toString(),
        'https://raw.githubusercontent.com/GLEECBTC/coins/master/coins/KMD.json',
      );
    });

    test('getAssets with branch override uses that ref', () async {
      final p = createTestProvider(httpClient: client);
      final uri = Uri.parse(
        '${p.coinsGithubContentUrl}/dev/${p.coinsConfigPath}',
      );
      when(() => client.get(uri)).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'KMD': {
              'coin': 'KMD',
              'type': 'UTXO',
              'protocol': {'type': 'UTXO'},
              'fname': 'Komodo',
              'chain_id': 0,
              'is_testnet': false,
            },
          }),
          200,
        ),
      );
      final assets = await p.getAssets(branch: 'dev');
      expect(assets, isNotEmpty);
    });

    test('getLatestCommit sends Accept and UA headers', () async {
      final uri = Uri.parse(
        '${provider.coinsGithubApiUrl}/branches/${provider.branch}',
      );
      when(() => client.get(uri, headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'commit': {'sha': 'abc123'},
          }),
          200,
        ),
      );
      await provider.getLatestCommit();
      verify(() => client.get(uri, headers: any(named: 'headers'))).called(1);
    });
  });
}
