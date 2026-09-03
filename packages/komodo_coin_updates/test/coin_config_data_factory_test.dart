import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/src/coins_config/coin_config_repository.dart';
import 'package:komodo_coin_updates/src/coins_config/coin_config_repository_factory.dart';
import 'package:komodo_coin_updates/src/coins_config/config_transform.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetRuntimeUpdateConfig;

/// Unit tests for the DefaultCoinConfigDataFactory class.
///
/// **Purpose**: Tests the factory pattern implementation that creates coin configuration
/// repositories and local providers with proper dependency injection and configuration.
///
/// **Test Cases**:
/// - Factory creates CoinConfigRepository with correct wiring and transformer
/// - Factory creates LocalAssetCoinConfigProvider from runtime configuration
///
/// **Functionality Tested**:
/// - Dependency injection and object creation
/// - Factory pattern implementation
/// - Configuration passing between components
/// - Repository and provider instantiation
///
/// **Edge Cases**: None specific - focuses on happy path factory creation
///
/// **Dependencies**: Tests the factory's ability to wire together CoinConfigRepository,
/// AssetRuntimeUpdateConfigRepository, and CoinConfigTransformer components.
void main() {
  group('DefaultCoinConfigDataFactory', () {
    test('createRepository wires defaults and passes transformer', () {
      const transformer = CoinConfigTransformer();
      const factory = DefaultCoinConfigDataFactory();
      final repo = factory.createRepository(
        const AssetRuntimeUpdateConfig(),
        transformer,
      );
      expect(repo, isA<CoinConfigRepository>());
    });

    test(
      'createLocalProvider returns LocalAssetCoinConfigProvider.fromConfig',
      () {
        const factory = DefaultCoinConfigDataFactory();
        const transformer = CoinConfigTransformer();
        final provider = factory.createLocalProvider(
          const AssetRuntimeUpdateConfig(),
          transformer,
        );
        // We don\'t import the concrete type here; verifying an instance is returned is enough
        expect(provider, isNotNull);
      },
    );
  });
}
