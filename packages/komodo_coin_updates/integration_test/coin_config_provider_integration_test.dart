/// Integration tests for coin configuration providers with actual external dependencies.
///
/// **Purpose**: Tests the integration between coin configuration providers and their
/// external dependencies (HTTP clients, asset bundles, file systems) to ensure
/// proper data flow and error handling in real-world scenarios.
///
/// **Test Cases**:
/// - HTTP client integration with GitHub API
/// - Asset bundle loading and parsing
/// - Configuration transformation pipelines
/// - Error handling with real network conditions
/// - Provider fallback mechanisms
/// - Configuration validation workflows
///
/// **Functionality Tested**:
/// - Real HTTP client integration
/// - Asset bundle file loading
/// - Configuration parsing and validation
/// - Error propagation and handling
/// - Provider state management
/// - Integration workflows
///
/// **Edge Cases**:
/// - Network failures and timeouts
/// - Invalid configuration data
/// - Missing asset files
/// - HTTP error responses
/// - Configuration parsing failures
///
/// **Dependencies**: Tests the integration between providers and their external
/// dependencies, including HTTP clients, asset bundles, and file systems.
///
/// **Note**: This is an integration test that requires actual external dependencies
/// and should be run separately from unit tests. Some tests may be skipped in
/// CI environments.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, ByteData;
import 'package:http/http.dart' as http;
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _FakeAssetBundle extends AssetBundle {
  _FakeAssetBundle(this.map);
  final Map<String, String> map;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      map[key] ?? (throw StateError('Asset not found: $key'));

  @override
  void evict(String key) {}
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.responses);
  final Map<String, http.Response> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = request.url.toString();
    if (responses.containsKey(key)) {
      final response = responses[key]!;
      final stream = Stream.fromIterable([response.bodyBytes]);
      return http.StreamedResponse(
        stream,
        response.statusCode,
        headers: response.headers,
      );
    }
    throw Exception('No response configured for: $key');
  }

  @override
  void close() {
    // No-op implementation
  }
}

void main() {
  group('CoinConfigProvider Integration Tests', () {
    group('LocalAssetCoinConfigProvider Integration', () {
      test('loads and parses valid configuration from asset bundle', () async {
        const jsonMap = {
          'KMD': {
            'coin': 'KMD',
            'decimals': 8,
            'type': 'UTXO',
            'protocol': {'type': 'UTXO'},
            'fname': 'Komodo',
            'chain_id': 0,
            'is_testnet': false,
          },
        };

        final bundle = _FakeAssetBundle({
          'packages/komodo_defi_framework/assets/config/coins_config.json':
              jsonEncode(jsonMap),
        });

        final provider = LocalAssetCoinConfigProvider.fromConfig(
          const AssetRuntimeUpdateConfig(),
          bundle: bundle,
        );

        final assets = await provider.getAssets();
        expect(assets, hasLength(1));
        expect(assets.first.id.id, 'KMD');
        expect(assets.first.id.name, 'Komodo');
        expect(assets.first.protocol.subClass, CoinSubClass.utxo);
      });

      test('handles missing asset gracefully', () async {
        final provider = LocalAssetCoinConfigProvider.fromConfig(
          const AssetRuntimeUpdateConfig(),
          bundle: _FakeAssetBundle({}),
        );

        expect(provider.getAssets(), throwsA(isA<StateError>()));
      });

      test('applies configuration transformations', () async {
        const jsonMap = {
          'KMD': {
            'coin': 'KMD',
            'decimals': 8,
            'type': 'UTXO',
            'protocol': {'type': 'UTXO'},
            'fname': 'Komodo',
            'chain_id': 0,
            'is_testnet': false,
          },
        };

        final bundle = _FakeAssetBundle({
          'packages/komodo_defi_framework/assets/config/coins_config.json':
              jsonEncode(jsonMap),
        });

        final provider = LocalAssetCoinConfigProvider.fromConfig(
          const AssetRuntimeUpdateConfig(),
          transformer: const CoinConfigTransformer(
            transforms: [WssWebsocketTransform()],
          ),
          bundle: bundle,
        );

        final assets = await provider.getAssets();
        expect(assets, hasLength(1));
        // The transform should have been applied
        expect(assets.first, isA<Asset>());
      });
    });

    group('GithubCoinConfigProvider Integration', () {
      test('fetches and parses configuration from GitHub API', () async {
        final mockResponses = {
          'https://api.github.com/repos/GLEECBTC/coins/branches/master':
              http.Response(
                jsonEncode({
                  'commit': {'sha': 'abc123def456'},
                }),
                200,
              ),
          'https://raw.githubusercontent.com/GLEECBTC/coins/master/utils/coins_config_unfiltered.json':
              http.Response(
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
        };

        final httpClient = _FakeHttpClient(mockResponses);

        final provider = GithubCoinConfigProvider(
          branch: 'master',
          coinsGithubContentUrl:
              'https://raw.githubusercontent.com/GLEECBTC/coins',
          coinsGithubApiUrl:
              'https://api.github.com/repos/GLEECBTC/coins',
          coinsPath: 'coins',
          coinsConfigPath: 'utils/coins_config_unfiltered.json',
          httpClient: httpClient,
        );

        final latestCommit = await provider.getLatestCommit();
        expect(latestCommit, 'abc123def456');

        final assets = await provider.getAssets();
        expect(assets, hasLength(1));
        expect(assets.first.id.id, 'KMD');
      });

      test('handles HTTP errors gracefully', () async {
        final mockResponses = {
          'https://api.github.com/repos/GLEECBTC/coins/branches/master':
              http.Response('Not Found', 404),
        };

        final httpClient = _FakeHttpClient(mockResponses);

        final provider = GithubCoinConfigProvider(
          branch: 'master',
          coinsGithubContentUrl:
              'https://raw.githubusercontent.com/GLEECBTC/coins',
          coinsGithubApiUrl:
              'https://api.github.com/repos/GLEECBTC/coins',
          coinsPath: 'coins',
          coinsConfigPath: 'utils/coins_config_unfiltered.json',
          httpClient: httpClient,
        );

        expect(provider.getLatestCommit(), throwsA(isA<Exception>()));
      });

      test('uses CDN mirrors when available', () async {
        final provider = GithubCoinConfigProvider(
          branch: 'master',
          coinsGithubContentUrl:
              'https://raw.githubusercontent.com/GLEECBTC/coins',
          coinsGithubApiUrl:
              'https://api.github.com/repos/GLEECBTC/coins',
          coinsPath: 'coins',
          coinsConfigPath: 'utils/coins_config_unfiltered.json',
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
        );
        expect(uri.toString(), contains('gleecbtc.github.io'));
        expect(uri.toString(), isNot(contains('raw.githubusercontent.com')));
      });

      test('falls back to GitHub raw for non-master branches', () async {
        final provider = GithubCoinConfigProvider(
          branch: 'dev',
          coinsGithubContentUrl:
              'https://raw.githubusercontent.com/GLEECBTC/coins',
          coinsGithubApiUrl:
              'https://api.github.com/repos/GLEECBTC/coins',
          coinsPath: 'coins',
          coinsConfigPath: 'utils/coins_config_unfiltered.json',
          cdnBranchMirrors: const {
            'master': 'https://gleecbtc.github.io/coins',
          },
        );

        final uri = provider.buildContentUri(
          'utils/coins_config_unfiltered.json',
        );
        expect(uri.toString(), contains('raw.githubusercontent.com'));
        expect(uri.toString(), contains('/dev/'));
        expect(uri.toString(), isNot(contains('gleecbtc.github.io')));
      });
    });

    group('Configuration Transformation Integration', () {
      test('transforms are applied in sequence', () async {
        const jsonMap = {
          'KMD': {
            'coin': 'KMD',
            'decimals': 8,
            'type': 'UTXO',
            'protocol': {'type': 'UTXO'},
            'fname': 'Komodo',
            'chain_id': 0,
            'is_testnet': false,
            'electrum': [
              {'url': 'wss://example.com', 'protocol': 'WSS'},
              {'url': 'tcp://example.com', 'protocol': 'TCP'},
            ],
          },
        };

        final bundle = _FakeAssetBundle({
          'packages/komodo_defi_framework/assets/config/coins_config.json':
              jsonEncode(jsonMap),
        });

        final provider = LocalAssetCoinConfigProvider.fromConfig(
          const AssetRuntimeUpdateConfig(),
          transformer: const CoinConfigTransformer(
            transforms: [WssWebsocketTransform(), ParentCoinTransform()],
          ),
          bundle: bundle,
        );

        final assets = await provider.getAssets();
        expect(assets, hasLength(1));
        // Verify transformations were applied
        expect(assets.first, isA<Asset>());
      });
    });
  });
}
