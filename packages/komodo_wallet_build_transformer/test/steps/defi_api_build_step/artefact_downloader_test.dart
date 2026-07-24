import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:test/test.dart';

void main() {
  const commit = 'bd413dcfea73c9de2e85903323946a378b180fa7';

  group('apiArtifactFilenameFromUrl', () {
    test('uses the URL path basename without query parameters', () {
      expect(
        apiArtifactFilenameFromUrl(
          'https://builds.example/kdf_bd413dc-wasm.zip?token=secret',
        ),
        'kdf_bd413dc-wasm.zip',
      );
    });

    test('accepts Caddy dot-relative artifact links', () {
      expect(
        apiArtifactFilenameFromListingHref('./kdf_bd413dc-wasm.zip'),
        'kdf_bd413dc-wasm.zip',
      );
    });

    test('ignores Caddy query-only navigation links', () {
      expect(apiArtifactFilenameFromListingHref('?sort=name'), isNull);
    });
  });

  group('apiArtifactFilenameMatchesCommit', () {
    test('accepts an exact SHA prefix token', () {
      expect(
        apiArtifactFilenameMatchesCommit('kdf_bd413dc-wasm.zip', commit),
        isTrue,
      );
    });

    test('rejects a commit substring inside another SHA token', () {
      expect(
        apiArtifactFilenameMatchesCommit('kdf_0bd413dc-wasm.zip', commit),
        isFalse,
      );
    });

    test('does not authorize a filename from a commit in its directory', () {
      expect(
        apiArtifactFilenameMatchesCommit(
          '/builds/bd413dc/kdf_997332e-wasm.zip',
          commit,
        ),
        isFalse,
      );
    });
  });
}
