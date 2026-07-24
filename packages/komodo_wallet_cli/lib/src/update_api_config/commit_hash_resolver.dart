final RegExp _fullCommitSha = RegExp(r'^[a-f0-9]{40}$');
final RegExp _supportedCommitSha = RegExp(r'^[a-f0-9]{7,40}$');

/// Validates a commit after optional short-SHA resolution.
void validateResolvedCommitHashForUpdate(
  String commitHash, {
  required bool strict,
  required bool requireFullCommitHash,
}) {
  final pattern = strict || requireFullCommitHash
      ? _fullCommitSha
      : _supportedCommitSha;
  if (!pattern.hasMatch(commitHash)) {
    throw FormatException(
      strict || requireFullCommitHash
          ? 'Commit hash must be a full 40-character lowercase SHA: '
                '$commitHash'
          : 'Commit hash must be 7-40 lowercase hexadecimal characters: '
                '$commitHash',
    );
  }
}

/// Resolves and validates the commit written to the KDF artifact manifest.
///
/// Strict artifact selection and manifests with `require_full_commit_hash`
/// both require an immutable full SHA. A legacy non-strict manifest may keep
/// using a short SHA only when remote resolution is unavailable.
Future<String> resolveCommitHashForUpdate(
  String commitHash, {
  required bool strict,
  required bool requireFullCommitHash,
  required Future<String> Function(String commitHash) resolveShortCommit,
}) async {
  if (!_supportedCommitSha.hasMatch(commitHash)) {
    throw FormatException(
      'Commit hash must be 7-40 lowercase hexadecimal characters: '
      '$commitHash',
    );
  }
  if (_fullCommitSha.hasMatch(commitHash)) {
    validateResolvedCommitHashForUpdate(
      commitHash,
      strict: strict,
      requireFullCommitHash: requireFullCommitHash,
    );
    return commitHash;
  }

  String resolvedCommit;
  try {
    resolvedCommit = await resolveShortCommit(commitHash);
  } catch (error) {
    if (strict || requireFullCommitHash) {
      throw StateError(
        'A full 40-character lowercase commit SHA is required, but '
        '$commitHash could not be resolved: $error',
      );
    }
    validateResolvedCommitHashForUpdate(
      commitHash,
      strict: strict,
      requireFullCommitHash: requireFullCommitHash,
    );
    return commitHash;
  }

  if (!_fullCommitSha.hasMatch(resolvedCommit)) {
    throw FormatException(
      'Resolved commit must be a full 40-character lowercase SHA: '
      '$resolvedCommit',
    );
  }
  validateResolvedCommitHashForUpdate(
    resolvedCommit,
    strict: strict,
    requireFullCommitHash: requireFullCommitHash,
  );
  return resolvedCommit;
}
