import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/copy_platform_assets_build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_build_platform_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/coin_assets/coin_build_config.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('CopyPlatformAssetsBuildStep', () {
    late Directory tempDir;
    late Directory projectRoot;
    late Directory artifactOutputDirectory;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'copy_platform_assets_test_',
      );
      projectRoot = Directory(path.join(tempDir.path, 'project'))
        ..createSync(recursive: true);
      artifactOutputDirectory = Directory(path.join(tempDir.path, 'artifacts'))
        ..createSync(recursive: true);

      _writeLinuxFixture(projectRoot);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('does not skip when the verified artifact marker is newer', () async {
      final sourceMarker =
          File(
              path.join(
                artifactOutputDirectory.path,
                'web',
                'kdf',
                'bin',
                '.api_last_updated_web',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('new aggregate marker');

      final destinationMarker =
          File(
              path.join(
                projectRoot.path,
                'web',
                'kdf',
                'kdf',
                'bin',
                '.api_last_updated_web',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('stale wasm-only marker');

      final sourceResource =
          File(
              path.join(
                artifactOutputDirectory.path,
                'web',
                'res',
                'kdflib_bootstrapper.js',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('verified bootstrapper');
      final destinationResource =
          File(
              path.join(
                projectRoot.path,
                'web',
                'kdf',
                'res',
                'kdflib_bootstrapper.js',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('verified bootstrapper');

      final now = DateTime.now();
      destinationMarker.setLastModifiedSync(
        now.subtract(const Duration(seconds: 2)),
      );
      sourceMarker.setLastModifiedSync(now);
      sourceResource.setLastModifiedSync(
        now.subtract(const Duration(seconds: 2)),
      );
      destinationResource.setLastModifiedSync(
        now.subtract(const Duration(seconds: 1)),
      );

      final step = CopyPlatformAssetsBuildStep(
        projectRoot: projectRoot,
        artifactOutputDirectory: artifactOutputDirectory,
        buildConfig: _buildConfig(),
      );

      expect(await step.canSkip(), isFalse);

      destinationMarker
        ..writeAsStringSync(sourceMarker.readAsStringSync())
        ..setLastModifiedSync(now.add(const Duration(seconds: 1)));

      expect(await step.canSkip(), isTrue);
    });
  });
}

void _writeLinuxFixture(Directory projectRoot) {
  final appName = path.basename(projectRoot.path);
  final sourceDirectory = Directory(path.join(projectRoot.path, 'linux'))
    ..createSync(recursive: true);
  final destinationDirectory = Directory(
    path.join(projectRoot.path, 'build', 'linux', 'x64', 'release', 'bundle'),
  )..createSync(recursive: true);

  final sourceTime = DateTime.now().subtract(const Duration(seconds: 2));
  final destinationTime = sourceTime.add(const Duration(seconds: 1));
  for (final extension in ['svg', 'desktop']) {
    final source = File(path.join(sourceDirectory.path, '$appName.$extension'))
      ..writeAsStringSync(extension);
    final destination = File(
      path.join(destinationDirectory.path, '$appName.$extension'),
    )..writeAsStringSync(extension);
    source.setLastModifiedSync(sourceTime);
    destination.setLastModifiedSync(destinationTime);
  }
}

BuildConfig _buildConfig() => BuildConfig(
  apiConfig: ApiBuildConfig(
    apiCommitHash: 'bd413dcfea73c9de2e85903323946a378b180fa7',
    branch: 'feat/tron-gasfree',
    fetchAtBuildEnabled: true,
    concurrentDownloadsEnabled: true,
    sourceUrls: const ['https://devbuilds.gleec.com'],
    platforms: {
      'web': ApiBuildPlatformConfig(
        matchingConfig: ApiFileMatchingConfig(
          matchingPattern: r'^kdf_[a-f0-9]{7,40}-wasm\.zip$',
        ),
        validZipSha256Checksums: const [
          '9242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c',
        ],
        path: 'web/kdf/bin',
      ),
    },
  ),
  coinCIConfig: CoinBuildConfig(
    fetchAtBuildEnabled: false,
    bundledCoinsRepoCommit: 'b0cb1b9e0d201c7a09850fe070adca2b08d9962e',
    updateCommitOnBuild: false,
    coinsRepoApiUrl: 'https://example.invalid/api',
    coinsRepoContentUrl: 'https://example.invalid/content',
    coinsRepoBranch: 'main',
    runtimeUpdatesEnabled: false,
    mappedFiles: const {},
    mappedFolders: const {},
    concurrentDownloadsEnabled: false,
  ),
);
