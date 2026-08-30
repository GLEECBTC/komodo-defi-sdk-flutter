import 'package:komodo_wallet_cli/src/update_api_config/platform_update_scope.dart';
import 'package:test/test.dart';

void main() {
  const previousCommit = '997332e5d6b0c5ca471aa7dc9727a7be96938ae2';
  const nextCommit = 'bd413dcfea73c9de2e85903323946a378b180fa7';
  const supportedPlatforms = ['web', 'linux', 'windows'];
  const requiredPlatforms = ['web', 'linux'];

  group('resolveRequestedApiPlatforms', () {
    test('keeps the exact all command as the full configured platform set', () {
      expect(
        resolveRequestedApiPlatforms(
          requestedPlatform: 'all',
          supportedPlatforms: supportedPlatforms,
        ),
        supportedPlatforms,
      );
    });

    test('rejects an unknown platform before any artifact work', () {
      expect(
        () => resolveRequestedApiPlatforms(
          requestedPlatform: 'freebsd',
          supportedPlatforms: supportedPlatforms,
        ),
        throwsArgumentError,
      );
    });
  });

  group('validateApiCommitUpdateScope', () {
    test('rejects a partial changed-commit update in strict mode', () {
      expect(
        () => validateApiCommitUpdateScope(
          previousCommitHash: previousCommit,
          nextCommitHash: nextCommit,
          updatedPlatforms: const ['web'],
          requiredPlatforms: requiredPlatforms,
          supportedPlatforms: supportedPlatforms,
          strict: true,
          requireFullCommitHash: false,
        ),
        throwsStateError,
      );
    });

    test('rejects a partial changed-commit update for a full-SHA manifest', () {
      expect(
        () => validateApiCommitUpdateScope(
          previousCommitHash: previousCommit,
          nextCommitHash: nextCommit,
          updatedPlatforms: const ['web'],
          requiredPlatforms: requiredPlatforms,
          supportedPlatforms: supportedPlatforms,
          strict: false,
          requireFullCommitHash: true,
        ),
        throwsStateError,
      );
    });

    test('does not mix global commit provenance in legacy non-strict mode', () {
      expect(
        () => validateApiCommitUpdateScope(
          previousCommitHash: previousCommit,
          nextCommitHash: nextCommit,
          updatedPlatforms: const ['web'],
          requiredPlatforms: requiredPlatforms,
          supportedPlatforms: supportedPlatforms,
          strict: false,
          requireFullCommitHash: false,
        ),
        throwsStateError,
      );
    });

    test('accepts a changed commit after every required target completed', () {
      expect(
        () => validateApiCommitUpdateScope(
          previousCommitHash: previousCommit,
          nextCommitHash: nextCommit,
          updatedPlatforms: requiredPlatforms,
          requiredPlatforms: requiredPlatforms,
          supportedPlatforms: supportedPlatforms,
          strict: true,
          requireFullCommitHash: true,
        ),
        returnsNormally,
      );
    });

    test('allows a partial checksum refresh without changing the commit', () {
      expect(
        () => validateApiCommitUpdateScope(
          previousCommitHash: previousCommit,
          nextCommitHash: previousCommit,
          updatedPlatforms: const ['web'],
          requiredPlatforms: requiredPlatforms,
          supportedPlatforms: supportedPlatforms,
          strict: true,
          requireFullCommitHash: true,
        ),
        returnsNormally,
      );
    });

    test('uses all configured targets when required_platforms is absent', () {
      expect(
        () => validateApiCommitUpdateScope(
          previousCommitHash: previousCommit,
          nextCommitHash: nextCommit,
          updatedPlatforms: requiredPlatforms,
          requiredPlatforms: const [],
          supportedPlatforms: supportedPlatforms,
          strict: true,
          requireFullCommitHash: true,
        ),
        throwsStateError,
      );
    });
  });

  group('apiPlatformsUpdatedForCommit', () {
    test('does not carry completed targets into a later commit', () {
      final completed = {
        'web': previousCommit,
        'linux': previousCommit,
        'windows': nextCommit,
      };

      expect(apiPlatformsUpdatedForCommit(completed, nextCommit), ['windows']);
    });
  });
}
