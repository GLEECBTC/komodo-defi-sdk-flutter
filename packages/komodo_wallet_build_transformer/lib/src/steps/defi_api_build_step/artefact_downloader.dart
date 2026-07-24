import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';
import 'package:path/path.dart' as path;

final RegExp _supportedCommitSha = RegExp(r'^[a-f0-9]{7,40}$');

/// Returns the archive basename from a URL or relative archive reference.
String apiArtifactFilenameFromUrl(String url) {
  final fileName = path.basename(Uri.parse(url).path);
  if (fileName.isEmpty || fileName == '.') {
    throw FormatException('KDF artifact URL has no filename: $url');
  }
  return fileName;
}

/// Returns a listing href's archive basename, or `null` for navigation links.
///
/// Caddy directory indexes include query-only sort links and parent-directory
/// links alongside artifact anchors. Those entries must not invalidate the
/// complete listing.
String? apiArtifactFilenameFromListingHref(String href) {
  try {
    return apiArtifactFilenameFromUrl(href);
  } on FormatException {
    return null;
  }
}

/// Whether the basename contains an exact SHA token prefixing [commitHash].
bool apiArtifactFilenameMatchesCommit(String fileName, String commitHash) {
  if (!_supportedCommitSha.hasMatch(commitHash)) return false;

  return apiArtifactFilenameFromUrl(fileName)
      .split(RegExp('[._-]'))
      .where(_supportedCommitSha.hasMatch)
      .any(commitHash.startsWith);
}

abstract class ArtefactDownloader {
  ArtefactDownloader({
    required this.apiCommitHash,
    required this.sourceUrl,
    required this.apiBranch,
  });

  final String apiCommitHash;
  final String sourceUrl;
  final String apiBranch;

  Future<String> fetchDownloadUrl(
    ApiFileMatchingConfig matchingConfig,
    String platform,
  );

  Future<String> downloadArtefact({
    required String url,
    required String destinationPath,
  });

  Future<void> extractArtefact({
    required String filePath,
    required String destinationFolder,
  });
}

extension ResponseCode on http.Response {
  void throwIfNotSuccessResponse() {
    if (statusCode != 200) {
      throw HttpException('Failed to fetch data: $statusCode $reasonPhrase');
    }
  }
}
