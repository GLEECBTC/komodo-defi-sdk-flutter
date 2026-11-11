import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/src/asset_management/loading_strategy.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements CoinConfigRepository {}

class _Provider extends Mock implements CoinConfigProvider {}

void main() {
  test(
    'candidate catalog never consults cached assets, including on fallback',
    () async {
      final repository = _Repository();
      final bundle = AssetBundleCoinConfigSource(provider: _Provider());
      final cache = StorageCoinConfigSource(repository: repository);
      const strategy = AssetBundleOnlyLoadingStrategy();

      for (final request in LoadingRequestType.values) {
        expect(
          await strategy.selectSources(
            requestType: request,
            availableSources: [cache, bundle],
          ),
          [bundle],
        );
      }
      verifyZeroInteractions(repository);
    },
  );

  test('missing immutable bundle does not unlock a stale catalog', () async {
    final repository = _Repository();
    expect(
      await const AssetBundleOnlyLoadingStrategy().selectSources(
        requestType: LoadingRequestType.fallbackLoad,
        availableSources: [StorageCoinConfigSource(repository: repository)],
      ),
      isEmpty,
    );
    verifyZeroInteractions(repository);
  });
}
