import 'package:komodo_wallet_cli/src/update_api_config/commit_hash_resolver.dart';
import 'package:test/test.dart';

void main() {
  const shortCommit = 'bd413dc';
  const fullCommit = 'bd413dcfea73c9de2e85903323946a378b180fa7';

  Future<String> resolutionFails(String _) =>
      Future<String>.error(Exception('unavailable'));

  group('resolveCommitHashForUpdate', () {
    test('write-boundary validation rejects a strict short commit', () {
      expect(
        () => validateResolvedCommitHashForUpdate(
          shortCommit,
          strict: true,
          requireFullCommitHash: false,
        ),
        throwsFormatException,
      );
    });

    test(
      'write-boundary validation rejects a manifest-required short commit',
      () {
        expect(
          () => validateResolvedCommitHashForUpdate(
            shortCommit,
            strict: false,
            requireFullCommitHash: true,
          ),
          throwsFormatException,
        );
      },
    );

    test('strict mode rejects an unresolved short commit before update', () {
      expect(
        () => resolveCommitHashForUpdate(
          shortCommit,
          strict: true,
          requireFullCommitHash: false,
          resolveShortCommit: resolutionFails,
        ),
        throwsStateError,
      );
    });

    test('full-hash manifests reject an unresolved short commit', () {
      expect(
        () => resolveCommitHashForUpdate(
          shortCommit,
          strict: false,
          requireFullCommitHash: true,
          resolveShortCommit: resolutionFails,
        ),
        throwsStateError,
      );
    });

    test(
      'legacy non-strict manifests may retain an unresolved short commit',
      () async {
        expect(
          await resolveCommitHashForUpdate(
            shortCommit,
            strict: false,
            requireFullCommitHash: false,
            resolveShortCommit: resolutionFails,
          ),
          shortCommit,
        );
      },
    );

    test('accepts a remotely resolved full lowercase commit', () async {
      expect(
        await resolveCommitHashForUpdate(
          shortCommit,
          strict: true,
          requireFullCommitHash: true,
          resolveShortCommit: (_) async => fullCommit,
        ),
        fullCommit,
      );
    });

    test('rejects invalid full commit text before remote resolution', () async {
      var resolverCalled = false;

      await expectLater(
        resolveCommitHashForUpdate(
          fullCommit.toUpperCase(),
          strict: true,
          requireFullCommitHash: true,
          resolveShortCommit: (_) async {
            resolverCalled = true;
            return fullCommit;
          },
        ),
        throwsFormatException,
      );
      expect(resolverCalled, isFalse);
    });

    test('rejects a malformed response from the commit resolver', () {
      expect(
        () => resolveCommitHashForUpdate(
          shortCommit,
          strict: false,
          requireFullCommitHash: false,
          resolveShortCommit: (_) async => shortCommit,
        ),
        throwsFormatException,
      );
    });
  });
}
