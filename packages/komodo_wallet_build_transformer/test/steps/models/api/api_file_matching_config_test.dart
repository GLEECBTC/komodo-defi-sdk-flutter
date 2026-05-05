import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';
import 'package:test/test.dart';

void main() {
  group('ApiFileMatchingConfig.choosePreferred', () {
    const macosArchivePattern =
        '^(?:kdf-macos-universal2-[a-f0-9]{7,40}|'
        'kdf_[a-f0-9]{7,40}-mac-universal|'
        r'libkdf-macos-universal2-[a-f0-9]{7,40})\.zip$';

    test('prefers GitHub macOS libkdf archives over executable archives', () {
      final config = ApiFileMatchingConfig(
        matchingPattern: macosArchivePattern,
        matchingPreference: const [
          'libkdf-macos-universal2',
          'kdf-macos-universal2',
          'kdf_',
          'universal2',
          'mac-arm64',
        ],
      );

      final preferred = config.choosePreferred(const [
        'kdf-macos-universal2-d56a7bc.zip',
        'libkdf-macos-universal2-d56a7bc.zip',
      ]);

      expect(preferred, equals('libkdf-macos-universal2-d56a7bc.zip'));
    });

    test(
      'falls back to the executable macOS archive when libkdf is absent',
      () {
        final config = ApiFileMatchingConfig(
          matchingPattern: macosArchivePattern,
          matchingPreference: const [
            'libkdf-macos-universal2',
            'kdf-macos-universal2',
            'kdf_',
            'universal2',
            'mac-arm64',
          ],
        );

        final preferred = config.choosePreferred(const [
          'kdf-macos-universal2-d56a7bc.zip',
        ]);

        expect(preferred, equals('kdf-macos-universal2-d56a7bc.zip'));
      },
    );

    test('keeps CI/mac-universal fallback deterministic', () {
      final config = ApiFileMatchingConfig(
        matchingPattern: macosArchivePattern,
        matchingPreference: const [
          'libkdf-macos-universal2',
          'kdf-macos-universal2',
          'kdf_',
          'universal2',
          'mac-arm64',
        ],
      );

      final preferred = config.choosePreferred(const [
        'kdf_d56a7bc-mac-universal.zip',
        'kdf_d56a7bc-mac-universal.zip.backup',
      ]);

      expect(preferred, equals('kdf_d56a7bc-mac-universal.zip'));
    });
  });
}
