import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/src/coins_config/config_transform.dart';
import 'package:komodo_coin_updates/src/coins_config/local_asset_coin_config_provider.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetRuntimeUpdateConfig;

class _FakeBundle extends AssetBundle {
  _FakeBundle(this.map);
  final Map<String, String> map;
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      map[key] ?? (throw StateError('Asset not found: $key'));
  @override
  void evict(String key) {}
}

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

/// Unit tests for the LocalAssetCoinConfigProvider class.
///
/// **Purpose**: Tests the provider that loads coin configurations from local Flutter
/// assets, including configuration transformation, filtering, and error handling
/// for bundled coin configurations.
///
/// **Test Cases**:
/// - Missing asset error handling and propagation
/// - Configuration transformation application
/// - Excluded coin filtering and removal
/// - Asset bundle integration and loading
/// - Configuration processing pipeline
///
/// **Functionality Tested**:
/// - Local asset loading from Flutter bundles
/// - Configuration transformation and modification
/// - Coin exclusion and filtering mechanisms
/// - Error handling for missing assets
/// - Configuration processing workflows
/// - Asset bundle integration
///
/// **Edge Cases**:
/// - Missing asset files
/// - Configuration transformation failures
/// - Excluded coin handling
/// - Asset bundle loading errors
/// - Configuration validation edge cases
///
/// **Dependencies**: Tests the local asset loading mechanism that provides coin
/// configurations from bundled Flutter assets, including transformation pipelines
/// and filtering mechanisms for runtime configuration.
void main() {
  group('LocalAssetCoinConfigProvider', () {
    test('throws when asset is missing', () async {
      final provider = LocalAssetCoinConfigProvider.fromConfig(
        const AssetRuntimeUpdateConfig(),
        bundle: _FakeBundle({}),
      );
      expect(provider.getAssets(), throwsA(isA<StateError>()));
    });

    test('applies transform and filters excluded coins', () async {
      // Test verifies that coins marked with 'excluded: true' are filtered out
      // This makes the exclusion behavior explicit and future-proof
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
        'SLP': {
          'coin': 'SLP',
          'decimals': 8,
          'type': 'SLP',
          'protocol': {'type': 'SLP'},
          'fname': 'SLP Token',
          'chain_id': 0,
          'is_testnet': false,
          'excluded': true,
        },
      };
      final bundle = _FakeBundle({
        'packages/komodo_defi_framework/assets/config/coins_config.json':
            jsonEncode(jsonMap),
      });

      final provider = LocalAssetCoinConfigProvider.fromConfig(
        const AssetRuntimeUpdateConfig(),
        transformer: const CoinConfigTransformer(
          transforms: [_ForceWalletOnlyTransform()],
        ),
        bundle: bundle,
      );

      final assets = await provider.getAssets();
      expect(assets.any((a) => a.id.id == 'KMD'), isTrue);
      expect(assets.any((a) => a.id.id == 'SLP'), isFalse);
      final kmd = assets.firstWhere((a) => a.id.id == 'KMD');
      expect(kmd.isWalletOnly, isTrue);
    });

    test('filters invalid EVM configs before parsing', () async {
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
        'BROKENETH': {
          'coin': 'BROKENETH',
          'type': 'ETH',
          'protocol': {
            'type': 'ETH',
            'protocol_data': {'chain_id': 1},
          },
          'chain_id': 1,
          'nodes': [],
          'swap_contract_address': '0x61EEC68Cf64d1b31e41EA713356De2563fB6D3F1',
        },
      };
      final bundle = _FakeBundle({
        'packages/komodo_defi_framework/assets/config/coins_config.json':
            jsonEncode(jsonMap),
      });

      final provider = LocalAssetCoinConfigProvider.fromConfig(
        const AssetRuntimeUpdateConfig(),
        bundle: bundle,
      );

      final assets = await provider.getAssets();
      expect(assets.any((a) => a.id.id == 'KMD'), isTrue);
      expect(assets.any((a) => a.id.id == 'BROKENETH'), isFalse);
    });
  });
}
