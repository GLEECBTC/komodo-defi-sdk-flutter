import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show KdfDesktopDataDirectory;

void main() {
  group('KomodoDefiSdkConfig.desktopDataDirectory', () {
    final directory = KdfDesktopDataDirectory(
      windowsFolder: 'Gleec',
      linuxFolder: 'com.gleec.GleecDEX',
    );

    test('defaults to Documents/.kdf', () {
      expect(const KomodoDefiSdkConfig().desktopDataDirectory, isNull);
    });

    test('survives an unrelated copy', () {
      final config = KomodoDefiSdkConfig(desktopDataDirectory: directory);
      expect(
        config.copyWith(maxPreActivationAttempts: 1).desktopDataDirectory,
        directory,
      );
    });

    test('can be set by a copy', () {
      expect(
        const KomodoDefiSdkConfig()
            .copyWith(desktopDataDirectory: directory)
            .desktopDataDirectory,
        directory,
      );
    });
  });

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
