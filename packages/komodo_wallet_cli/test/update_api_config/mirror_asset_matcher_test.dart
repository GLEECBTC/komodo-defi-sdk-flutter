import 'package:komodo_wallet_cli/src/update_api_config/mirror_asset_matcher.dart';
import 'package:test/test.dart';

void main() {
  const commit = 'bd413dcfea73c9de2e85903323946a378b180fa7';
  const pattern =
      r'^(?:kdf_[a-f0-9]{7,40}-wasm|mm2_[a-f0-9]{7,40}-wasm|mm2-[a-f0-9]{7,40}-wasm)\.zip$';
  const caddyListingHref = './kdf_bd413dc-wasm.zip';

  group('matchesMirrorArchiveHref', () {
    test('matches a Caddy relative link in the strict commit pass', () {
      expect(
        matchesMirrorArchiveHref(
          caddyListingHref,
          extensions: const ['.zip'],
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isTrue,
      );
    });

    test('matches a Caddy relative link in the non-strict fallback pass', () {
      expect(
        matchesMirrorArchiveHref(
          caddyListingHref,
          extensions: const ['.zip'],
          matchingPattern: pattern,
          matchingKeyword: null,
        ),
        isTrue,
      );
    });

    test('keeps the anchored pattern and exact commit boundary', () {
      expect(
        matchesMirrorArchiveHref(
          './prefix-kdf_bd413dc-wasm.zip',
          extensions: const ['.zip'],
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isFalse,
      );
      expect(
        matchesMirrorArchiveHref(
          './kdf_0bd413dc-wasm.zip',
          extensions: const ['.zip'],
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isFalse,
        reason: 'a commit substring inside another SHA token must not match',
      );
      expect(
        matchesMirrorArchiveHref(
          './kdf_997332e-wasm.zip',
          extensions: const ['.zip'],
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isFalse,
      );
    });

    test('ignores query parameters while matching the archive basename', () {
      expect(
        matchesMirrorArchiveHref(
          './kdf_bd413dc-wasm.zip?download=1',
          extensions: const ['.zip'],
          matchingPattern: pattern,
          matchingKeyword: null,
          commitHash: commit,
        ),
        isTrue,
      );
    });
  });
}
