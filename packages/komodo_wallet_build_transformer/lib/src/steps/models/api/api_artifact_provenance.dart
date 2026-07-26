/// Provenance written next to an extracted KDF artifact.
///
/// A marker is authoritative only when it identifies the pinned commit, the
/// exact downloaded archive, the extracted core artifact, and the complete
/// platform runtime set. Legacy partial markers deliberately fail closed.
class ApiArtifactProvenance {
  const ApiArtifactProvenance._({
    required this.apiCommitHash,
    required this.checksums,
    required this.archiveFilename,
    required this.archiveSha256,
    required this.artifactSha256,
    required this.runtimeSetSha256,
  });

  factory ApiArtifactProvenance.fromJson(Map<String, dynamic> json) {
    final apiCommitHash = _requiredNonEmptyString(json, 'api_commit_hash');
    final checksums = json['checksums'];
    final archiveFilename = _requiredNonEmptyString(json, 'archive_filename');
    final archiveSha256 = _requiredSha256(json, 'archive_sha256');
    final artifactSha256 = _requiredSha256(json, 'artifact_sha256');
    final runtimeSetSha256 = _requiredSha256(json, 'runtime_set_sha256');

    validateApiArtifactProvenanceCommitHash(apiCommitHash);

    if (checksums is! List ||
        checksums.isEmpty ||
        checksums.any((value) => value is! String || !_isSha256(value))) {
      throw const FormatException(
        'Artifact provenance checksums must be a non-empty, non-zero '
        'lowercase SHA-256 list',
      );
    }
    final parsedChecksums = checksums.cast<String>();
    if (parsedChecksums.toSet().length != parsedChecksums.length) {
      throw const FormatException(
        'Artifact provenance checksums must not contain duplicates',
      );
    }
    if (!_isArchiveFilename(archiveFilename) ||
        !_containsCommitHash(archiveFilename, apiCommitHash)) {
      throw const FormatException(
        'Artifact provenance archive_filename must be a safe zip filename '
        'containing the pinned commit hash',
      );
    }

    return ApiArtifactProvenance._(
      apiCommitHash: apiCommitHash,
      checksums: parsedChecksums,
      archiveFilename: archiveFilename,
      archiveSha256: archiveSha256,
      artifactSha256: artifactSha256,
      runtimeSetSha256: runtimeSetSha256,
    );
  }

  final String apiCommitHash;
  final List<String> checksums;
  final String archiveFilename;
  final String archiveSha256;
  final String artifactSha256;
  final String runtimeSetSha256;

  /// Whether this marker proves parity with the pinned manifest entry and the
  /// bytes currently present in the extracted artifact directory.
  bool matches({
    required String expectedCommitHash,
    required List<String> expectedChecksums,
    required String observedArtifactSha256,
    required String observedRuntimeSetSha256,
  }) {
    if (!_isFullCommitHash(expectedCommitHash) ||
        expectedChecksums.isEmpty ||
        expectedChecksums.any((checksum) => !_isSha256(checksum)) ||
        expectedChecksums.toSet().length != expectedChecksums.length ||
        apiCommitHash != expectedCommitHash ||
        !_isSha256(observedArtifactSha256) ||
        artifactSha256 != observedArtifactSha256 ||
        !_isSha256(observedRuntimeSetSha256) ||
        runtimeSetSha256 != observedRuntimeSetSha256) {
      return false;
    }

    final markerChecksums = checksums.toSet();
    final manifestChecksums = expectedChecksums.toSet();
    if (checksums.length != expectedChecksums.length ||
        markerChecksums.length != checksums.length ||
        markerChecksums.length != manifestChecksums.length ||
        !markerChecksums.containsAll(manifestChecksums) ||
        !manifestChecksums.contains(archiveSha256)) {
      return false;
    }

    return _containsCommitHash(archiveFilename, expectedCommitHash);
  }

  static String _requiredNonEmptyString(
    Map<String, dynamic> json,
    String field,
  ) {
    final value = json[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('Artifact provenance is missing $field');
    }
    return value;
  }

  static String _requiredSha256(Map<String, dynamic> json, String field) {
    final value = _requiredNonEmptyString(json, field);
    if (!_isSha256(value)) {
      throw FormatException(
        'Artifact provenance $field must be a non-zero lowercase SHA-256 value',
      );
    }
    return value;
  }

  static bool _isSha256(Object? value) =>
      value is String &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value) &&
      value != _allZeroSha256;

  static bool _isFullCommitHash(String value) =>
      RegExp(r'^[a-f0-9]{40}$').hasMatch(value);

  static bool _isArchiveFilename(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$').hasMatch(value);

  static bool _containsCommitHash(String value, String commitHash) {
    final tokens = value.split(RegExp('[._-]'));
    return tokens
        .where((token) => RegExp(r'^[a-f0-9]{7,40}$').hasMatch(token))
        .any(commitHash.startsWith);
  }
}

const String _allZeroSha256 =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// Enforces the immutable commit identity required by artifact provenance.
void validateApiArtifactProvenanceCommitHash(String commitHash) {
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(commitHash)) {
    throw const FormatException(
      'Artifact provenance api_commit_hash must be a full 40-character '
      'lowercase hash',
    );
  }
}
