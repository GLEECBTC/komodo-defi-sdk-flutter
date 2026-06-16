/// Web implementation of the coins-file reader.
///
/// On web there is no filesystem path to read from — the file content must be
/// captured in memory at selection time (see [CustomCoinsFileSource.content]).
/// This stub exists only so the platform-conditional import resolves; it should
/// never be reached because web sources always carry in-memory content.
Future<String> readCustomCoinsFileFromPath(String path) {
  throw UnsupportedError(
    'Reading a coins file from a filesystem path is not supported on web. '
    'Capture the file content in memory instead '
    '(CustomCoinsFileSource.content).',
  );
}
