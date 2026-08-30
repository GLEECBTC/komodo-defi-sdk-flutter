import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../bin/update_api_config.dart' as update_cli;

void main() {
  const previousCommit = '997332e5d6b0c5ca471aa7dc9727a7be96938ae2';
  const nextCommit = 'bd413dcfea73c9de2e85903323946a378b180fa7';
  const trustedChecksum =
      '9242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c';
  const untrustedChecksum =
      '1242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c';

  group('strict artifact checksum provenance', () {
    test('keeps the exact independently trusted set unchanged', () {
      final configured = <String>[trustedChecksum];

      final resolved = update_cli.resolvePlatformArtifactChecksums(
        configuredChecksums: configured,
        calculatedChecksum: trustedChecksum,
        previousCommitHash: nextCommit,
        nextCommitHash: nextCommit,
        strict: true,
      );

      expect(resolved, configured);
      expect(identical(resolved, configured), isFalse);
    });

    test('rejects an untrusted mirror artifact for the same commit', () {
      expect(
        () => update_cli.resolvePlatformArtifactChecksums(
          configuredChecksums: const <String>[trustedChecksum],
          calculatedChecksum: untrustedChecksum,
          previousCommitHash: nextCommit,
          nextCommitHash: nextCommit,
          strict: true,
        ),
        throwsStateError,
      );
    });

    test('changed commits retain manifest update compatibility', () {
      expect(
        update_cli.resolvePlatformArtifactChecksums(
          configuredChecksums: const <String>[trustedChecksum],
          calculatedChecksum: untrustedChecksum,
          previousCommitHash: previousCommit,
          nextCommitHash: nextCommit,
          strict: true,
        ),
        const <String>[untrustedChecksum],
      );
    });
  });

  test(
    'write boundary cannot advance a global commit after no target updates',
    () async {
      final tempDirectory = Directory.systemTemp.createTempSync(
        'kdf-cli-manifest-write-',
      );
      addTearDown(() {
        if (tempDirectory.existsSync()) {
          tempDirectory.deleteSync(recursive: true);
        }
      });
      final configFile = File('${tempDirectory.path}/build_config.json');
      final originalConfig = jsonEncode({
        'api': {
          'api_commit_hash': previousCommit,
          'branch': 'previous',
          'require_full_commit_hash': true,
          'required_platforms': ['web', 'linux'],
          'platforms': {
            'web': <String, dynamic>{},
            'linux': <String, dynamic>{},
          },
        },
      });
      configFile.writeAsStringSync(originalConfig);

      final fetcher = update_cli.KdfFetcher(
        branch: 'next',
        repo: 'owner/repository',
        configPath: configFile.path,
        outputDir: '${tempDirectory.path}/downloads',
        verbose: false,
      );
      await fetcher.loadBuildConfig();

      await expectLater(
        fetcher.updateBuildConfig(nextCommit),
        throwsStateError,
      );
      expect(configFile.readAsStringSync(), originalConfig);
    },
  );

  test(
    'write boundary rejects a short commit for provenance markers',
    () async {
      final tempDirectory = Directory.systemTemp.createTempSync(
        'kdf-cli-short-commit-',
      );
      addTearDown(() {
        if (tempDirectory.existsSync()) {
          tempDirectory.deleteSync(recursive: true);
        }
      });
      final configFile = File('${tempDirectory.path}/build_config.json');
      configFile.writeAsStringSync(
        jsonEncode({
          'api': {
            'api_commit_hash': previousCommit,
            'branch': 'previous',
            'require_full_commit_hash': false,
            'platforms': {'web': <String, dynamic>{}},
          },
        }),
      );

      final fetcher = update_cli.KdfFetcher(
        branch: 'next',
        repo: 'owner/repository',
        configPath: configFile.path,
        outputDir: '${tempDirectory.path}/downloads',
        verbose: false,
        strict: false,
      );
      await fetcher.loadBuildConfig();

      await expectLater(
        fetcher.updateBuildConfig('bd413dc'),
        throwsFormatException,
      );
    },
  );
}
