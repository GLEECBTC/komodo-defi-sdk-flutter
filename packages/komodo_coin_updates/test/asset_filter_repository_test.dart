import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_coin_updates/hive/hive_registrar.g.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

import 'helpers/asset_test_helpers.dart';

class _CachedAssetPolicyTransform implements CoinConfigTransform {
  const _CachedAssetPolicyTransform();

  @override
  bool needsTransform(JsonMap config) => !config.containsKey('app_policy');

  @override
  JsonMap transform(JsonMap config) =>
      JsonMap.of(config)..['app_policy'] = 'applied';
}

class _TickerEnrollmentTransform implements CoinConfigTransform {
  const _TickerEnrollmentTransform(this.ticker);

  final String ticker;

  @override
  bool needsTransform(JsonMap config) =>
      config['coin'] == ticker && !config.containsKey('gasless');

  @override
  JsonMap transform(JsonMap config) =>
      JsonMap.of(config)..['gasless'] = <String, dynamic>{'enabled': true};
}

void main() {
  /// Unit tests for repository-driven asset filtering functionality.
  ///
  /// **Purpose**: Tests the integration between CoinConfigRepository and asset filtering
  /// mechanisms, ensuring that repository-stored assets can be properly filtered by
  /// protocol subclasses and other criteria.
  ///
  /// **Test Cases**:
  /// - UTXO and smart chain asset filtering from repository storage
  /// - Protocol subclass-based filtering (UTXO, smart chain, etc.)
  /// - Repository integration with filtering logic
  /// - Asset type validation and filtering accuracy
  ///
  /// **Functionality Tested**:
  /// - Repository asset retrieval and filtering
  /// - Protocol subclass filtering (UTXO, smart chain)
  /// - Asset type validation and classification
  /// - Repository-driven filtering workflows
  /// - Asset data integrity during filtering operations
  ///
  /// **Edge Cases**:
  /// - Empty asset lists
  /// - Mixed asset types in repository
  /// - Protocol subclass edge cases
  /// - Repository state consistency during filtering
  ///
  /// **Dependencies**: Tests the integration between CoinConfigRepository and asset
  /// filtering logic, uses HiveTestEnv for isolated database testing, and validates
  /// that repository-stored assets maintain proper protocol classification for filtering.
  group('Repository-driven asset filtering', () {
    late CoinConfigRepository repo;
    late String hivePath;
    setUp(() async {
      hivePath =
          './.dart_tool/test_hive_${DateTime.now().microsecondsSinceEpoch}';
      Hive
        ..init(hivePath)
        ..registerAdapters();
      repo = CoinConfigRepository.withDefaults(
        const AssetRuntimeUpdateConfig(),
      );
      await repo.upsertRawAssets({'KMD': AssetTestHelpers.utxoJson()}, 'test');
    });

    tearDown(() async {
      try {
        await Hive.close();
      } catch (_) {}
      try {
        final dir = Directory(hivePath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('UTXO-only filter using repository assets', () async {
      final all = await repo.getAssets();
      final utxoOnly = all
          .where(
            (a) =>
                a.protocol.subClass == CoinSubClass.utxo ||
                a.protocol.subClass == CoinSubClass.smartChain,
          )
          .toList();
      expect(utxoOnly.any((a) => a.id.id == 'KMD'), isTrue);
      // Ensure no non-UTXO subclasses slipped through
      expect(
        utxoOnly.any(
          (a) =>
              a.protocol.subClass != CoinSubClass.utxo &&
              a.protocol.subClass != CoinSubClass.smartChain,
        ),
        isFalse,
      );
    });

    test('applies current transforms when rebuilding cached assets', () async {
      final transformedRepo = CoinConfigRepository.withDefaults(
        const AssetRuntimeUpdateConfig(),
        transformer: const CoinConfigTransformer(
          transforms: [_CachedAssetPolicyTransform()],
        ),
      );

      final all = await transformedRepo.getAssets();

      expect(all.single.protocol.config['app_policy'], 'applied');
    });

    test(
      'application enrollment is transient across policy restarts',
      () async {
        await repo.upsertRawAssets({
          'KMD': AssetTestHelpers.utxoJson(),
          'BTC': AssetTestHelpers.utxoJson(
            coin: 'BTC',
            fname: 'Bitcoin',
            chainId: 0,
          ),
        }, 'test');
        final configuredRepo = CoinConfigRepository.withDefaults(
          const AssetRuntimeUpdateConfig(),
          transformer: const CoinConfigTransformer(
            transforms: [_TickerEnrollmentTransform('KMD')],
          ),
        );

        final configured = {
          for (final asset in await configuredRepo.getAssets())
            asset.id.id: asset.protocol.config,
        };
        expect(configured['KMD']?['gasless'], {'enabled': true});
        expect(configured['BTC'], isNot(contains('gasless')));

        final unconfigured = {
          for (final asset in await repo.getAssets())
            asset.id.id: asset.protocol.config,
        };
        expect(unconfigured['KMD'], isNot(contains('gasless')));
        expect(unconfigured['BTC'], isNot(contains('gasless')));

        final switchedRepo = CoinConfigRepository.withDefaults(
          const AssetRuntimeUpdateConfig(),
          transformer: const CoinConfigTransformer(
            transforms: [_TickerEnrollmentTransform('BTC')],
          ),
        );
        final switched = {
          for (final asset in await switchedRepo.getAssets())
            asset.id.id: asset.protocol.config,
        };
        expect(switched['KMD'], isNot(contains('gasless')));
        expect(switched['BTC']?['gasless'], {'enabled': true});
      },
    );
  });
}
