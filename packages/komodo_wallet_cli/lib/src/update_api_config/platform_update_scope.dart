/// Resolves the exact `--platform all` sentinel or validates one named target.
List<String> resolveRequestedApiPlatforms({
  required String requestedPlatform,
  required List<String> supportedPlatforms,
}) {
  if (requestedPlatform == 'all') {
    return List<String>.unmodifiable(supportedPlatforms);
  }
  if (!supportedPlatforms.contains(requestedPlatform)) {
    throw ArgumentError.value(
      requestedPlatform,
      'requestedPlatform',
      'Platform is not configured',
    );
  }
  return List<String>.unmodifiable([requestedPlatform]);
}

/// Returns only platforms completed for the commit currently being written.
Iterable<String> apiPlatformsUpdatedForCommit(
  Map<String, String> platformCommits,
  String commitHash,
) => platformCommits.entries
    .where((entry) => entry.value == commitHash)
    .map((entry) => entry.key);

/// Prevents a global commit from advancing while required platform checksums
/// still describe artifacts from the previous commit.
///
/// The manifest has one global artifact identity, so every required target
/// must complete in memory before the single manifest write. Strict/full-SHA
/// policy additionally governs exact artifact selection. When
/// `required_platforms` is absent, every configured platform is required.
void validateApiCommitUpdateScope({
  required String previousCommitHash,
  required String nextCommitHash,
  required Iterable<String> updatedPlatforms,
  required List<String> requiredPlatforms,
  required List<String> supportedPlatforms,
  required bool strict,
  required bool requireFullCommitHash,
}) {
  if (previousCommitHash == nextCommitHash) {
    return;
  }

  final supported = supportedPlatforms.toSet();
  final required =
      (requiredPlatforms.isEmpty ? supportedPlatforms : requiredPlatforms)
          .toSet();
  final unknownRequired = required.difference(supported);
  if (unknownRequired.isNotEmpty) {
    throw StateError(
      'Required API platforms are not configured: '
      '${unknownRequired.join(', ')}',
    );
  }

  final completed = updatedPlatforms.toSet();
  final missing = required.difference(completed);
  if (missing.isNotEmpty) {
    final policy = strict || requireFullCommitHash
        ? 'Strict/full-SHA manifests'
        : 'Global-commit manifests';
    throw StateError(
      'Cannot update global KDF commit from $previousCommitHash to '
      '$nextCommitHash after a partial platform refresh. Missing required '
      'targets: ${missing.join(', ')}. $policy require --platform all so '
      'every required checksum is updated before the manifest is written.',
    );
  }
}
