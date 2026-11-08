import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  test('all default catalog boxes use the candidate namespace', () {
    const namespace = String.fromEnvironment('KDF_COINS_STORAGE_NAMESPACE');
    String expected(String name) =>
        namespace.isEmpty ? name : '${namespace}_$name';
    final repository = CoinConfigRepository.withDefaults(
      const AssetRuntimeUpdateConfig(),
    );
    final directRepository = CoinConfigRepository(
      coinConfigProvider: repository.coinConfigProvider,
    );
    for (final value in [repository, directRepository]) {
      expect(value.assetsBoxName, expected('assets'));
      expect(value.settingsBoxName, expected('coins_settings'));
    }
    expect(CustomTokenStorage().customTokensBoxName, expected('custom_tokens'));
    if (namespace.isNotEmpty) {
      expect(repository.assetsBoxName, isNot('assets'));
      expect(repository.settingsBoxName, isNot('coins_settings'));
      expect(CustomTokenStorage().customTokensBoxName, isNot('custom_tokens'));
    }
  });

  test('different immutable catalogs cannot share a database name', () {
    for (final name in ['assets', 'coins_settings', 'custom_tokens']) {
      expect(
        KomodoCoinUpdater.storageBoxName(name, namespace: 'solana-preview-aaa'),
        isNot(
          KomodoCoinUpdater.storageBoxName(
            name,
            namespace: 'solana-preview-bbb',
          ),
        ),
      );
    }
  });
}
