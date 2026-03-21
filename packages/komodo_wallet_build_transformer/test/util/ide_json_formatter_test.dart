import 'package:komodo_wallet_build_transformer/src/util/ide_json_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('formatJsonForIde', () {
    test('keeps short primitive arrays inline and wraps long arrays', () {
      const checksum =
          '6c09130fa7e4977dff617df5d5be385c1f2a57e6764a63e12e79797df52568f4';

      final formatted = formatJsonForIde({
        'api': {
          'platforms': {
            'macos': {
              'matching_preference': ['universal2', 'mac-arm64'],
              'valid_zip_sha256_checksums': [checksum],
            },
          },
        },
      });

      expect(
        formatted,
        equals('''
{
  "api": {
    "platforms": {
      "macos": {
        "matching_preference": ["universal2", "mac-arm64"],
        "valid_zip_sha256_checksums": [
          "$checksum"
        ]
      }
    }
  }
}
'''),
      );
    });
  });
}
