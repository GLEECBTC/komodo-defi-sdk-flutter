import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_artifact_provenance.dart';
import 'package:test/test.dart';

void main() {
  const pinnedCommit = '997332e5d6b0c5ca471aa7dc9727a7be96938ae2';
  const checksum =
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
  const artifactChecksum =
      'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';
  const runtimeSetChecksum =
      '0abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456789';
  const otherChecksum =
      'fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321';

  Map<String, Object> markerJson({
    String commit = pinnedCommit,
    String archiveFilename = 'kdf_997332e-android-aarch64.zip',
    String archiveSha256 = checksum,
    String extractedSha256 = artifactChecksum,
    String runtimeSha256 = runtimeSetChecksum,
  }) => {
    'api_commit_hash': commit,
    'checksums': [checksum],
    'archive_filename': archiveFilename,
    'archive_sha256': archiveSha256,
    'artifact_sha256': extractedSha256,
    'runtime_set_sha256': runtimeSha256,
  };

  bool matchesPinned(ApiArtifactProvenance marker) => marker.matches(
    expectedCommitHash: pinnedCommit,
    expectedChecksums: const [checksum],
    observedArtifactSha256: artifactChecksum,
    observedRuntimeSetSha256: runtimeSetChecksum,
  );

  group('ApiArtifactProvenance', () {
    test('rejects a matching legacy marker without immutable evidence', () {
      expect(
        () => ApiArtifactProvenance.fromJson({
          'api_commit_hash': pinnedCommit,
          'checksums': [checksum],
        }),
        throwsFormatException,
      );
    });

    test('accepts exact archive and extracted artifact provenance', () {
      final marker = ApiArtifactProvenance.fromJson(markerJson());

      expect(matchesPinned(marker), isTrue);
    });

    test('rejects a stale commit', () {
      final marker = ApiArtifactProvenance.fromJson(
        markerJson(
          commit: '43603a5a4fe74c789f8079f4bad46c3e2119865a',
          archiveFilename: 'kdf_43603a5-android-aarch64.zip',
        ),
      );

      expect(matchesPinned(marker), isFalse);
    });

    test('rejects archive metadata for another commit', () {
      expect(
        () => ApiArtifactProvenance.fromJson(
          markerJson(archiveFilename: 'kdf_43603a5-android-aarch64.zip'),
        ),
        throwsFormatException,
      );
    });

    test('rejects the pinned commit embedded in another SHA token', () {
      expect(
        () => ApiArtifactProvenance.fromJson(
          markerJson(archiveFilename: 'kdf_0997332e-android-aarch64.zip'),
        ),
        throwsFormatException,
      );
    });

    test('rejects a short commit in provenance-enabled markers', () {
      expect(
        () => ApiArtifactProvenance.fromJson(markerJson(commit: '997332e')),
        throwsFormatException,
      );
    });

    test('rejects an archive checksum outside the manifest allowlist', () {
      final marker = ApiArtifactProvenance.fromJson(
        markerJson(archiveSha256: otherChecksum),
      );

      expect(matchesPinned(marker), isFalse);
    });

    test('rejects a tampered extracted artifact digest', () {
      final marker = ApiArtifactProvenance.fromJson(markerJson());

      expect(
        marker.matches(
          expectedCommitHash: pinnedCommit,
          expectedChecksums: const [checksum],
          observedArtifactSha256: otherChecksum,
          observedRuntimeSetSha256: runtimeSetChecksum,
        ),
        isFalse,
      );
    });

    test('rejects a tampered extracted runtime-set digest', () {
      final marker = ApiArtifactProvenance.fromJson(markerJson());

      expect(
        marker.matches(
          expectedCommitHash: pinnedCommit,
          expectedChecksums: const [checksum],
          observedArtifactSha256: artifactChecksum,
          observedRuntimeSetSha256: otherChecksum,
        ),
        isFalse,
      );
    });

    test('rejects malformed or missing immutable evidence', () {
      expect(
        () => ApiArtifactProvenance.fromJson({
          ...markerJson(),
          'artifact_sha256': 42,
        }),
        throwsFormatException,
      );
      expect(
        () => ApiArtifactProvenance.fromJson({
          ...(markerJson()..remove('archive_sha256')),
        }),
        throwsFormatException,
      );
      expect(
        () => ApiArtifactProvenance.fromJson({
          ...(markerJson()..remove('runtime_set_sha256')),
        }),
        throwsFormatException,
      );
      expect(
        () => ApiArtifactProvenance.fromJson({
          ...markerJson(),
          'archive_filename': '../kdf_997332e.zip',
        }),
        throwsFormatException,
      );
    });

    test('rejects non-canonical SHA-256 strings', () {
      expect(
        () => ApiArtifactProvenance.fromJson(
          markerJson(archiveSha256: checksum.toUpperCase()),
        ),
        throwsFormatException,
      );
      expect(
        () =>
            ApiArtifactProvenance.fromJson(markerJson(extractedSha256: 'abc')),
        throwsFormatException,
      );
    });

    test('rejects all-zero provenance digests', () {
      const allZero =
          '0000000000000000000000000000000000000000000000000000000000000000';

      expect(
        () =>
            ApiArtifactProvenance.fromJson(markerJson(archiveSha256: allZero)),
        throwsFormatException,
      );
      expect(
        () => ApiArtifactProvenance.fromJson(
          markerJson(extractedSha256: allZero),
        ),
        throwsFormatException,
      );
      expect(
        () =>
            ApiArtifactProvenance.fromJson(markerJson(runtimeSha256: allZero)),
        throwsFormatException,
      );
    });
  });
}
