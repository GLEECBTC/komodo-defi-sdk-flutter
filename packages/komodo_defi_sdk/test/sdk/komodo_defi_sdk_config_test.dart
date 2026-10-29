import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

void main() {
  group('KomodoDefiSdkConfig.lifiProxyUrl', () {
    const url = 'https://swap.example.com/lifi';

    test('defaults to the public API', () {
      expect(const KomodoDefiSdkConfig().lifiProxyUrl, isNull);
    });

    test('survives an unrelated copy', () {
      const config = KomodoDefiSdkConfig(lifiProxyUrl: url);
      expect(config.copyWith(maxPreActivationAttempts: 1).lifiProxyUrl, url);
    });

    test('can be set by a copy', () {
      expect(
        const KomodoDefiSdkConfig().copyWith(lifiProxyUrl: url).lifiProxyUrl,
        url,
      );
    });
  });
}
