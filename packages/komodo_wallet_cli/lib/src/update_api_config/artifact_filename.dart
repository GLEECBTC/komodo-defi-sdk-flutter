import 'package:path/path.dart' as path;

final RegExp _supportedCommitSha = RegExp(r'^[a-f0-9]{7,40}$');

/// Returns the archive basename from a URL or relative archive reference.
///
/// Query parameters are transport metadata and must never become part of the
/// local filename or artifact identity.
String apiArtifactFilenameFromUrl(String url) {
  final fileName = path.basename(Uri.parse(url).path);
  if (fileName.isEmpty || fileName == '.') {
    throw FormatException('KDF artifact URL has no filename: $url');
  }
  return fileName;
}

/// Whether [fileName] contains an exact SHA token that prefixes [commitHash].
///
/// The platform's anchored filename matcher owns the token position. This
/// helper prevents a requested SHA such as `bd413dc` from matching the middle
/// of a different token such as `0bd413dc`.
bool apiArtifactFilenameMatchesCommit(String fileName, String commitHash) {
  if (!_supportedCommitSha.hasMatch(commitHash)) return false;

  return apiArtifactFilenameFromUrl(fileName)
      .split(RegExp(r'[._-]'))
      .where(_supportedCommitSha.hasMatch)
      .any(commitHash.startsWith);
}

/// Applies the configured platform matcher to the archive basename, followed
/// by exact commit-token validation when [commitHash] is supplied.
bool matchesApiArtifactFilename(
  String archiveReference, {
  required String? matchingPattern,
  required String? matchingKeyword,
  String? commitHash,
}) {
  final fileName = apiArtifactFilenameFromUrl(archiveReference);
  final matchesPlatform = matchingPattern != null
      ? RegExp(matchingPattern).hasMatch(fileName)
      : matchingKeyword != null && fileName.contains(matchingKeyword);
  if (!matchesPlatform) return false;

  return commitHash == null ||
      apiArtifactFilenameMatchesCommit(fileName, commitHash);
}
