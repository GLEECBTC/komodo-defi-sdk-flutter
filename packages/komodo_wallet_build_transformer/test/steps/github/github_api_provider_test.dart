import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_wallet_build_transformer/src/steps/github/github_api_provider.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('GithubApiProvider failed requests', () {
    const token = 'secret-test-token';
    late GithubApiProvider provider;
    late List<http.BaseRequest> sentRequests;
    late List<LogRecord> records;
    late StreamSubscription<LogRecord> subscription;
    late Level rootLevel;

    setUp(() {
      sentRequests = [];
      records = [];
      rootLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      subscription = Logger.root.onRecord.listen(records.add);
      provider = GithubApiProvider.withBaseUrl(
        baseUrl: 'https://api.github.com/repos/GLEECBTC/coins',
        branch: 'master',
        token: token,
      );
    });

    tearDown(() async {
      await subscription.cancel();
      Logger.root.level = rootLevel;
    });

    /// Runs [call] against an API that refuses every request the way GitHub
    /// does once the rate limit is used up, and returns the exception thrown.
    Future<Exception> rateLimited(Future<Object?> Function() call) =>
        http.runWithClient(
          () async {
            try {
              await call();
            } on Exception catch (error) {
              return error;
            }
            fail('Expected the request to fail');
          },
          () => MockClient((request) async {
            sentRequests.add(request);
            return http.Response(
              '{"message":"API rate limit exceeded"}',
              403,
              reasonPhrase: 'rate limit exceeded',
            );
          }),
        );

    String loggedText() =>
        records.map((record) => '${record.message} ${record.error}').join('\n');

    test('logs whether a failed commit lookup was authenticated', () async {
      await rateLimited(provider.getLatestCommitHash);

      expect(
        records
            .where((record) => record.level >= Level.SEVERE)
            .map((record) => record.message),
        contains('Using authentication: yes'),
      );
    });

    final calls = <String, Future<Object?> Function()>{
      'getFileMetadata': () => provider.getFileMetadata('coins_config.json'),
      'getLatestCommitHash': () => provider.getLatestCommitHash(),
      'getDirectoryContents': () =>
          provider.getDirectoryContents('icons', 'master'),
      'getLatestReleaseTag': () => provider.getLatestReleaseTag(),
      'getReleases': () => provider.getReleases(),
    };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      test(
        '$name sends the token but keeps it out of logs and errors',
        () async {
          final error = await rateLimited(call);

          expect(sentRequests.single.headers['Authorization'], 'Bearer $token');
          expect(loggedText(), isNot(contains(token)));
          expect(error.toString(), isNot(contains(token)));
        },
      );
    }
  });
}
