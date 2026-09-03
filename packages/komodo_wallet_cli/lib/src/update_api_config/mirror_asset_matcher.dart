import 'package:komodo_wallet_cli/src/update_api_config/artifact_filename.dart';
import 'package:path/path.dart' as path;

/// Matches an archive link from a mirror directory listing.
///
/// Mirror servers may render links as bare filenames, relative paths such as
/// `./kdf_abcdef0-wasm.zip`, or absolute URLs. Only the path basename belongs
/// to the artifact naming contract; callers must retain the original [href]
/// when resolving the download URL.
bool matchesMirrorArchiveHref(
  String href, {
  required List<String> extensions,
  required String? matchingPattern,
  required String? matchingKeyword,
  String? commitHash,
}) {
  final hrefPath = Uri.tryParse(href)?.path ?? href;
  final fileName = path.basename(hrefPath);

  if (!extensions.any(fileName.endsWith)) return false;
  if (fileName.contains('wallet')) return false;

  return matchesApiArtifactFilename(
    fileName,
    matchingPattern: matchingPattern,
    matchingKeyword: matchingKeyword,
    commitHash: commitHash,
  );
}
