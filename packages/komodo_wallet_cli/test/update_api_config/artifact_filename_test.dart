import 'package:komodo_wallet_cli/src/update_api_config/artifact_filename.dart';
import 'package:test/test.dart';

void main() {
  const commit = 'bd413dcfea73c9de2e85903323946a378b180fa7';
  const pattern =
      r'^(?:kdf_[a-f0-9]{7,40}-wasm|mm2_[a-f0-9]{7,40}-wasm|mm2-[a-f0-9]{7,40}-wasm)\.zip$';

  group('apiArtifactFilenameFromUrl', () {
    test('uses the URL path basename without query parameters', () {
      expect(
        apiArtifactFilenameFromUrl(
          'https://builds.example/kdf_bd413dc-wasm.zip?token=secret',
        ),
        'kdf_bd413dc-wasm.zip',
      );
    });
  });

  group('matchesApiArtifactFilename', () {
    test('matches an exact commit token accepted by the platform pattern', () {
      expect(
        matchesApiArtifactFilename(
          'https://builds.example/kdf_bd413dc-wasm.zip?download=1',
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isTrue,
      );
    });

    test('rejects the expected commit embedded in a longer SHA token', () {
      expect(
        matchesApiArtifactFilename(
          'kdf_0bd413dc-wasm.zip',
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isFalse,
      );
    });

    test('applies an anchored platform pattern to the basename', () {
      expect(
        matchesApiArtifactFilename(
          'https://builds.example/prefix-kdf_bd413dc-wasm.zip',
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isFalse,
      );
    });
  });
}
