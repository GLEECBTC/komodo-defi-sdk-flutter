import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/artefact_downloader.dart';
import 'package:komodo_wallet_build_transformer/src/steps/fetch_defi_api_build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_file_matching_config.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:test/test.dart';

void main() {
  const pinnedCommit = '997332e5d6b0c5ca471aa7dc9727a7be96938ae2';

  group('shouldUpdateApiArtifact', () {
    test('does not allow network opt-out to bypass stale provenance', () {
      expect(
        () => shouldUpdateApiArtifact(
          isOutdated: true,
          forceUpdate: false,
          overrideDownload: false,
          platform: 'android-aarch64',
          apiCommitHash: pinnedCommit,
        ),
        throwsStateError,
      );
    });

    test('allows network opt-out for an artifact already at parity', () {
      expect(
        shouldUpdateApiArtifact(
          isOutdated: false,
          forceUpdate: false,
          overrideDownload: false,
          platform: 'android-aarch64',
          apiCommitHash: pinnedCommit,
        ),
        isFalse,
      );
    });

    test('updates stale provenance by default', () {
      expect(
        shouldUpdateApiArtifact(
          isOutdated: true,
          forceUpdate: false,
          overrideDownload: null,
          platform: 'android-aarch64',
          apiCommitHash: pinnedCommit,
        ),
        isTrue,
      );
    });
  });

  group('apiPlatformsForTarget', () {
    const platforms = ['web', 'ios', 'android-aarch64'];

    test('keeps all configured platforms for a general build', () {
      expect(
        apiPlatformsForTarget(platforms, isTargetIphone: false),
        platforms,
      );
    });

    test('does not apply Android blockers to an iOS-only build', () {
      expect(apiPlatformsForTarget(platforms, isTargetIphone: true), const [
        'ios',
      ]);
    });
  });

  group('configured artifact destination', () {
    late Directory tempDirectory;
    late Directory trustedRoot;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'kdf-artifact-destination-',
      );
      trustedRoot = Directory('${tempDirectory.path}/artifacts')..createSync();
    });

    tearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('rejects an escaping path before any fetch or filesystem write', () {
      const sourceUrl = 'https://devbuilds.example.test';
      final archiveBytes = 'verified-archive'.codeUnits;
      final buildConfig = BuildConfig.fromJson({
        'api': {
          'api_commit_hash': pinnedCommit,
          'branch': 'feat/tron-gasfree',
          'fetch_at_build_enabled': true,
          'concurrent_downloads_enabled': false,
          'source_urls': [sourceUrl],
          'platforms': {
            'ios': {
              'matching_keyword': 'ios-aarch64',
              'valid_zip_sha256_checksums': [
                sha256.convert(archiveBytes).toString(),
              ],
              'path': '../outside/kdf',
            },
          },
        },
        'coins': {
          'fetch_at_build_enabled': false,
          'update_commit_on_build': false,
          'bundled_coins_repo_commit': pinnedCommit,
          'coins_repo_api_url': 'https://api.example.test',
          'coins_repo_content_url': 'https://content.example.test',
          'coins_repo_branch': 'main',
          'runtime_updates_enabled': false,
          'concurrent_downloads_enabled': false,
          'mapped_files': <String, String>{},
          'mapped_folders': <String, String>{},
        },
      });
      final step = FetchDefiApiStep.withBuildConfig(
        buildConfig,
        trustedRoot,
        File('${tempDirectory.path}/build_config.json'),
      );
      final downloader = _WritingArtefactDownloader(
        apiCommitHash: pinnedCommit,
        sourceUrl: sourceUrl,
        archiveBytes: archiveBytes,
      );
      step.artefactDownloaders[sourceUrl] = downloader;
      final outside = Directory('${tempDirectory.path}/outside');

      expect(
        step.updatePlatformWithProgress('ios'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('outside its trusted root'),
          ),
        ),
      );
      expect(downloader.calls, isEmpty);
      expect(outside.existsSync(), isFalse);
      expect(trustedRoot.listSync(), isEmpty);
    });
  });

  group('extracted API artifact provenance', () {
    late Directory tempDirectory;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'kdf-artifact-provenance-',
      );
    });

    tearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    const canonicalArtifacts = {
      'ios': 'libkdf.a',
      'macos': 'kdf',
      'android-armv7': 'libkdf.a',
      'android-aarch64': 'libkdf.a',
      'linux': 'kdf',
      'windows': 'kdf.exe',
    };

    for (final entry in canonicalArtifacts.entries) {
      test('hashes the shipping ${entry.key} artifact', () async {
        final bytes = 'pinned-${entry.key}-artifact'.codeUnits;
        File('${tempDirectory.path}/${entry.value}').writeAsBytesSync(bytes);

        expect(
          await calculateExtractedApiArtifactSha256(
            platform: entry.key,
            destinationFolder: tempDirectory.path,
          ),
          sha256.convert(bytes).toString(),
        );
      });
    }

    test('hashes every web runtime output as one deterministic set', () async {
      final wasm = File('${tempDirectory.path}/kdflib_bg.wasm')
        ..writeAsStringSync('wasm-runtime');
      final glue = File('${tempDirectory.path}/kdflib.js')
        ..writeAsStringSync('js-glue');
      final snippet = File(
        '${tempDirectory.path}/snippets/provider/inline0.js',
      );
      snippet.parent.createSync(recursive: true);
      snippet.writeAsStringSync('provider-runtime');

      expect(
        await calculateExtractedApiArtifactSha256(
          platform: 'web',
          destinationFolder: tempDirectory.path,
        ),
        sha256.convert(wasm.readAsBytesSync()).toString(),
      );
      final originalDigest = await calculateExtractedApiRuntimeSetSha256(
        platform: 'web',
        destinationFolder: tempDirectory.path,
      );

      glue.writeAsStringSync('tampered-js-glue');
      final tamperedGlueDigest = await calculateExtractedApiRuntimeSetSha256(
        platform: 'web',
        destinationFolder: tempDirectory.path,
      );
      expect(tamperedGlueDigest, isNot(originalDigest));
      expect(
        await calculateExtractedApiArtifactSha256(
          platform: 'web',
          destinationFolder: tempDirectory.path,
        ),
        sha256.convert(wasm.readAsBytesSync()).toString(),
      );

      glue.writeAsStringSync('js-glue');
      snippet.writeAsStringSync('tampered-provider-runtime');
      final tamperedSnippetDigest = await calculateExtractedApiRuntimeSetSha256(
        platform: 'web',
        destinationFolder: tempDirectory.path,
      );
      expect(tamperedSnippetDigest, isNot(originalDigest));
    });

    test(
      'web runtime aggregate is independent of file creation order',
      () async {
        final otherDirectory = Directory.systemTemp.createTempSync(
          'kdf-artifact-provenance-order-',
        );
        addTearDown(() {
          if (otherDirectory.existsSync()) {
            otherDirectory.deleteSync(recursive: true);
          }
        });

        File('${tempDirectory.path}/kdflib.js').writeAsStringSync('js-glue');
        File(
          '${tempDirectory.path}/kdflib_bg.wasm',
        ).writeAsStringSync('wasm-runtime');

        File(
          '${otherDirectory.path}/kdflib_bg.wasm',
        ).writeAsStringSync('wasm-runtime');
        File('${otherDirectory.path}/kdflib.js').writeAsStringSync('js-glue');

        expect(
          await calculateExtractedApiRuntimeSetSha256(
            platform: 'web',
            destinationFolder: tempDirectory.path,
          ),
          await calculateExtractedApiRuntimeSetSha256(
            platform: 'web',
            destinationFolder: otherDirectory.path,
          ),
        );
      },
    );

    test('web provenance requires the JavaScript glue output', () async {
      File(
        '${tempDirectory.path}/kdflib_bg.wasm',
      ).writeAsStringSync('wasm-runtime');

      await expectLater(
        calculateExtractedApiArtifactSha256(
          platform: 'web',
          destinationFolder: tempDirectory.path,
        ),
        throwsStateError,
      );
    });

    test(
      'clears stale web JavaScript, snippets, and WASM before extraction',
      () {
        final glue = File('${tempDirectory.path}/kdflib.js')
          ..writeAsStringSync('stale-glue');
        final wasm = File('${tempDirectory.path}/kdflib_bg.wasm')
          ..writeAsStringSync('stale-wasm');
        final snippet = File(
          '${tempDirectory.path}/snippets/provider/inline0.js',
        );
        snippet.parent.createSync(recursive: true);
        snippet.writeAsStringSync('stale-snippet');
        final unrelatedFile = File('${tempDirectory.path}/README.txt')
          ..writeAsStringSync('keep me');

        clearExtractedApiArtifactCandidates(
          platform: 'web',
          destinationFolder: tempDirectory.path,
        );

        expect(glue.existsSync(), isFalse);
        expect(wasm.existsSync(), isFalse);
        expect(snippet.existsSync(), isFalse);
        expect(unrelatedFile.existsSync(), isTrue);
      },
    );

    test('supports a legacy artifact name before canonical rename', () async {
      final bytes = 'legacy-mm2-artifact'.codeUnits;
      File('${tempDirectory.path}/libmm2.a').writeAsBytesSync(bytes);

      expect(
        await calculateExtractedApiArtifactSha256(
          platform: 'android-aarch64',
          destinationFolder: tempDirectory.path,
        ),
        sha256.convert(bytes).toString(),
      );
    });

    test('hashes every native companion runtime as one set', () async {
      final executable = File('${tempDirectory.path}/kdf.exe')
        ..writeAsStringSync('pinned-executable');
      final companion = File('${tempDirectory.path}/kdflib.dll')
        ..writeAsStringSync('pinned-companion');

      final coreDigest = await calculateExtractedApiArtifactSha256(
        platform: 'windows',
        destinationFolder: tempDirectory.path,
      );
      expect(
        coreDigest,
        sha256.convert(executable.readAsBytesSync()).toString(),
      );
      final originalSetDigest = await calculateExtractedApiRuntimeSetSha256(
        platform: 'windows',
        destinationFolder: tempDirectory.path,
      );
      expect(originalSetDigest, isNot(coreDigest));

      companion.writeAsStringSync('stale-companion');
      expect(
        await calculateExtractedApiRuntimeSetSha256(
          platform: 'windows',
          destinationFolder: tempDirectory.path,
        ),
        isNot(originalSetDigest),
      );
      expect(
        await calculateExtractedApiArtifactSha256(
          platform: 'windows',
          destinationFolder: tempDirectory.path,
        ),
        coreDigest,
      );
    });

    test('clears stale macOS static-library companions', () {
      final executable = File('${tempDirectory.path}/kdf')
        ..writeAsStringSync('pinned-executable');
      final staleLibrary = File('${tempDirectory.path}/libkdflib.a')
        ..writeAsStringSync('stale-library');
      final unrelatedFile = File('${tempDirectory.path}/README.txt')
        ..writeAsStringSync('keep me');

      clearExtractedApiArtifactCandidates(
        platform: 'macos',
        destinationFolder: tempDirectory.path,
      );

      expect(executable.existsSync(), isFalse);
      expect(staleLibrary.existsSync(), isFalse);
      expect(unrelatedFile.existsSync(), isTrue);
    });

    test('clears stale Windows DLL companions', () {
      final executable = File('${tempDirectory.path}/kdf.exe')
        ..writeAsStringSync('pinned-executable');
      final staleLibrary = File('${tempDirectory.path}/kdflib.dll')
        ..writeAsStringSync('stale-library');
      final unrelatedFile = File('${tempDirectory.path}/README.txt')
        ..writeAsStringSync('keep me');

      clearExtractedApiArtifactCandidates(
        platform: 'windows',
        destinationFolder: tempDirectory.path,
      );

      expect(executable.existsSync(), isFalse);
      expect(staleLibrary.existsSync(), isFalse);
      expect(unrelatedFile.existsSync(), isTrue);
    });

    test(
      'does not hash or clear unrelated nested iOS libraries and links',
      () async {
        File(
          '${tempDirectory.path}/libkdf.a',
        ).writeAsStringSync('pinned-runtime');
        final dependency = File(
          '${tempDirectory.path}/Pods/Dependency/libdependency.a',
        );
        dependency.parent.createSync(recursive: true);
        dependency.writeAsStringSync('dependency-v1');
        final dependencyLink = Link(
          '${tempDirectory.path}/Pods/Dependency/current',
        )..createSync(dependency.path);

        final runtimeDigest = await calculateExtractedApiRuntimeSetSha256(
          platform: 'ios',
          destinationFolder: tempDirectory.path,
        );
        dependency.writeAsStringSync('dependency-v2');
        expect(
          await calculateExtractedApiRuntimeSetSha256(
            platform: 'ios',
            destinationFolder: tempDirectory.path,
          ),
          runtimeDigest,
        );

        clearExtractedApiArtifactCandidates(
          platform: 'ios',
          destinationFolder: tempDirectory.path,
        );
        expect(dependency.existsSync(), isTrue);
        expect(dependencyLink.existsSync(), isTrue);
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires additional Windows privileges'
          : false,
    );

    test('fails closed when the platform artifact is missing', () async {
      await expectLater(
        calculateExtractedApiArtifactSha256(
          platform: 'android-aarch64',
          destinationFolder: tempDirectory.path,
        ),
        throwsStateError,
      );
    });

    test(
      'fails closed when canonical and legacy entrypoints coexist',
      () async {
        File('${tempDirectory.path}/libkdf.a').writeAsStringSync('canonical');
        File('${tempDirectory.path}/libmm2.a').writeAsStringSync('legacy');

        await expectLater(
          calculateExtractedApiArtifactSha256(
            platform: 'android-aarch64',
            destinationFolder: tempDirectory.path,
          ),
          throwsStateError,
        );
      },
    );

    test(
      'fails closed when a native artifact candidate is a symbolic link',
      () async {
        final linkedTarget = File('${tempDirectory.path}/outside-runtime')
          ..writeAsStringSync('linked-runtime');
        Link('${tempDirectory.path}/libkdf.a').createSync(linkedTarget.path);

        await expectLater(
          calculateExtractedApiArtifactSha256(
            platform: 'android-aarch64',
            destinationFolder: tempDirectory.path,
          ),
          throwsStateError,
        );
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires additional Windows privileges'
          : false,
    );

    test(
      'old runtime cannot survive and certify an empty extraction',
      () async {
        final oldArtifact = File('${tempDirectory.path}/libkdf.a')
          ..writeAsStringSync('stale-runtime');
        final unrelatedFile = File('${tempDirectory.path}/README.txt')
          ..writeAsStringSync('keep me');

        clearExtractedApiArtifactCandidates(
          platform: 'android-aarch64',
          destinationFolder: tempDirectory.path,
        );

        expect(oldArtifact.existsSync(), isFalse);
        expect(unrelatedFile.existsSync(), isTrue);
        await expectLater(
          calculateExtractedApiArtifactSha256(
            platform: 'android-aarch64',
            destinationFolder: tempDirectory.path,
          ),
          throwsStateError,
        );
      },
    );

    test('fails closed for an unknown platform identity', () async {
      await expectLater(
        calculateExtractedApiArtifactSha256(
          platform: 'freebsd',
          destinationFolder: tempDirectory.path,
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('replaceExtractedApiArtifactAtomically', () {
    late Directory tempDirectory;
    late Directory destination;
    late Directory staging;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'kdf-artifact-transaction-',
      );
      destination = Directory('${tempDirectory.path}/live')..createSync();
      staging = Directory('${tempDirectory.path}/staging')..createSync();
    });

    tearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test(
      'restores the previous runtime and marker on finalization failure',
      () async {
        final oldGlue = File('${destination.path}/kdflib.js')
          ..writeAsStringSync('old-glue');
        final oldWasm = File('${destination.path}/kdflib_bg.wasm')
          ..writeAsStringSync('old-wasm');
        final oldSnippet = File('${destination.path}/snippets/old.js');
        oldSnippet.parent.createSync(recursive: true);
        oldSnippet.writeAsStringSync('old-snippet');
        final marker = File('${destination.path}/.api_last_updated_web')
          ..writeAsStringSync('old-marker');

        File('${staging.path}/kdflib.js').writeAsStringSync('new-glue');
        File('${staging.path}/kdflib_bg.wasm').writeAsStringSync('new-wasm');
        final newSnippet = File('${staging.path}/snippets/new.js');
        newSnippet.parent.createSync(recursive: true);
        newSnippet.writeAsStringSync('new-snippet');

        await expectLater(
          replaceExtractedApiArtifactAtomically(
            platform: 'web',
            stagingFolder: staging.path,
            destinationFolder: destination.path,
            trustedRootFolder: tempDirectory.path,
            finalizeInstall: () async {
              marker.writeAsStringSync('new-marker');
              throw StateError('simulated marker failure');
            },
          ),
          throwsStateError,
        );

        expect(oldGlue.readAsStringSync(), 'old-glue');
        expect(oldWasm.readAsStringSync(), 'old-wasm');
        expect(oldSnippet.readAsStringSync(), 'old-snippet');
        expect(marker.readAsStringSync(), 'old-marker');
        expect(
          File('${destination.path}/snippets/new.js').existsSync(),
          isFalse,
        );
        expect(staging.existsSync(), isFalse);
      },
    );

    test(
      'commits the staged runtime and removes omitted stale outputs',
      () async {
        File('${destination.path}/kdflib.js').writeAsStringSync('old-glue');
        File(
          '${destination.path}/kdflib_bg.wasm',
        ).writeAsStringSync('old-wasm');
        final staleSnippet = File('${destination.path}/snippets/stale.js');
        staleSnippet.parent.createSync(recursive: true);
        staleSnippet.writeAsStringSync('stale-snippet');

        File('${staging.path}/kdflib.js').writeAsStringSync('new-glue');
        File('${staging.path}/kdflib_bg.wasm').writeAsStringSync('new-wasm');

        await replaceExtractedApiArtifactAtomically(
          platform: 'web',
          stagingFolder: staging.path,
          destinationFolder: destination.path,
          trustedRootFolder: tempDirectory.path,
          finalizeInstall: () async {
            File(
              '${destination.path}/.api_last_updated_web',
            ).writeAsStringSync('new-marker');
          },
        );

        expect(
          File('${destination.path}/kdflib.js').readAsStringSync(),
          'new-glue',
        );
        expect(
          File('${destination.path}/kdflib_bg.wasm').readAsStringSync(),
          'new-wasm',
        );
        expect(staleSnippet.existsSync(), isFalse);
        expect(
          File('${destination.path}/.api_last_updated_web').readAsStringSync(),
          'new-marker',
        );
        expect(staging.existsSync(), isFalse);
      },
    );

    test(
      'removes omitted native companion runtimes before finalization',
      () async {
        final oldExecutable = File('${destination.path}/kdf.exe')
          ..writeAsStringSync('old-executable');
        final staleLibrary = File('${destination.path}/kdflib.dll')
          ..writeAsStringSync('stale-library');
        File('${staging.path}/kdf.exe').writeAsStringSync('new-executable');

        await replaceExtractedApiArtifactAtomically(
          platform: 'windows',
          stagingFolder: staging.path,
          destinationFolder: destination.path,
          trustedRootFolder: tempDirectory.path,
          finalizeInstall: () async {
            File(
              '${destination.path}/.api_last_updated_windows',
            ).writeAsStringSync('new-marker');
          },
        );

        expect(oldExecutable.readAsStringSync(), 'new-executable');
        expect(staleLibrary.existsSync(), isFalse);
        expect(
          File(
            '${destination.path}/.api_last_updated_windows',
          ).readAsStringSync(),
          'new-marker',
        );
      },
    );

    test(
      'rejects a linked destination ancestor before installing nested files',
      () async {
        final outside = Directory('${tempDirectory.path}/outside')
          ..createSync();
        Link('${destination.path}/snippets').createSync(outside.path);
        final stagedSnippet = File('${staging.path}/snippets/inline0.js');
        stagedSnippet.parent.createSync(recursive: true);
        stagedSnippet.writeAsStringSync('new-snippet');

        await expectLater(
          replaceExtractedApiArtifactAtomically(
            platform: 'web',
            stagingFolder: staging.path,
            destinationFolder: destination.path,
            trustedRootFolder: tempDirectory.path,
            finalizeInstall: () async {},
          ),
          throwsStateError,
        );

        expect(File('${outside.path}/inline0.js').existsSync(), isFalse);
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires additional Windows privileges'
          : false,
    );

    test(
      'rejects a linked platform directory below the trusted artifact root',
      () async {
        final trustedRoot = Directory('${tempDirectory.path}/artifacts')
          ..createSync();
        final outside = Directory('${tempDirectory.path}/outside')
          ..createSync();
        Link('${trustedRoot.path}/web').createSync(outside.path);
        File('${staging.path}/kdflib.js').writeAsStringSync('new-glue');
        File('${staging.path}/kdflib_bg.wasm').writeAsStringSync('new-wasm');

        await expectLater(
          replaceExtractedApiArtifactAtomically(
            platform: 'web',
            stagingFolder: staging.path,
            destinationFolder: '${trustedRoot.path}/web/kdf/bin',
            trustedRootFolder: trustedRoot.path,
            finalizeInstall: () async {},
          ),
          throwsStateError,
        );

        expect(Directory('${outside.path}/kdf/bin').existsSync(), isFalse);
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires additional Windows privileges'
          : false,
    );

    test(
      'rejects nested native archive payloads outside owned paths',
      () async {
        File('${staging.path}/kdf.exe').writeAsStringSync('new-executable');
        final nestedLibrary = File(
          '${staging.path}/runtime/companions/kdflib.dll',
        );
        nestedLibrary.parent.createSync(recursive: true);
        nestedLibrary.writeAsStringSync('nested-library');

        await expectLater(
          replaceExtractedApiArtifactAtomically(
            platform: 'windows',
            stagingFolder: staging.path,
            destinationFolder: destination.path,
            trustedRootFolder: tempDirectory.path,
            finalizeInstall: () async {},
          ),
          throwsStateError,
        );

        expect(Directory('${destination.path}/runtime').existsSync(), isFalse);
      },
    );

    test(
      'preserves unrelated nested iOS package libraries during replacement',
      () async {
        File('${destination.path}/libkdf.a').writeAsStringSync('old-runtime');
        final podLibrary = File(
          '${destination.path}/Pods/Dependency/libdependency.a',
        );
        podLibrary.parent.createSync(recursive: true);
        podLibrary.writeAsStringSync('pod-library');
        final podLink = Link('${destination.path}/Pods/Dependency/current')
          ..createSync(podLibrary.path);
        File('${staging.path}/libkdf.a').writeAsStringSync('new-runtime');

        await replaceExtractedApiArtifactAtomically(
          platform: 'ios',
          stagingFolder: staging.path,
          destinationFolder: destination.path,
          trustedRootFolder: tempDirectory.path,
          finalizeInstall: () async {},
        );

        expect(
          File('${destination.path}/libkdf.a').readAsStringSync(),
          'new-runtime',
        );
        expect(podLibrary.readAsStringSync(), 'pod-library');
        expect(podLink.existsSync(), isTrue);
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires additional Windows privileges'
          : false,
    );

    test(
      'drops the Windows proc-macro DLLs instead of installing them',
      () async {
        // `kdf_f3efd2c-win-x86-64.zip` (KDF main) carries three proc-macro DLLs
        // alongside the runtime; `kdf_538724e-win-x86-64.zip` carried only
        // kdf.exe and kdflib.dll. They are compile-time only, so they must
        // neither be installed nor fail the extraction.
        File('${staging.path}/kdf.exe').writeAsStringSync('new-executable');
        File('${staging.path}/kdflib.dll').writeAsStringSync('new-library');
        for (final residue in const [
          'enum_derives.dll',
          'ser_error_derive.dll',
          'serialization_derive.dll',
        ]) {
          File('${staging.path}/$residue').writeAsStringSync('proc-macro');
        }

        await replaceExtractedApiArtifactAtomically(
          platform: 'windows',
          stagingFolder: staging.path,
          destinationFolder: destination.path,
          trustedRootFolder: tempDirectory.path,
          finalizeInstall: () async {},
        );

        expect(
          File('${destination.path}/kdf.exe').readAsStringSync(),
          'new-executable',
        );
        expect(
          File('${destination.path}/kdflib.dll').readAsStringSync(),
          'new-library',
        );
        for (final residue in const [
          'enum_derives.dll',
          'ser_error_derive.dll',
          'serialization_derive.dll',
        ]) {
          expect(
            File('${destination.path}/$residue').existsSync(),
            isFalse,
            reason: '$residue is build residue and must not ship',
          );
        }
      },
    );

    test(
      'still fails closed on an unrecognised top-level Windows file',
      () async {
        // The discard list is a named exemption, not a relaxation: anything not
        // on it must still stop the extraction.
        File('${staging.path}/kdf.exe').writeAsStringSync('new-executable');
        File('${staging.path}/payload.dll').writeAsStringSync('unexpected');

        await expectLater(
          replaceExtractedApiArtifactAtomically(
            platform: 'windows',
            stagingFolder: staging.path,
            destinationFolder: destination.path,
            trustedRootFolder: tempDirectory.path,
            finalizeInstall: () async {},
          ),
          throwsA(isStateError),
        );
      },
    );

    test('does not discard a proc-macro DLL buried in a directory', () async {
      // Matching on basename alone would let an archive smuggle a nested file
      // past the owned-set check by naming it after known residue.
      File('${staging.path}/kdf.exe').writeAsStringSync('new-executable');
      final nested = File('${staging.path}/nested/enum_derives.dll');
      nested.parent.createSync(recursive: true);
      nested.writeAsStringSync('proc-macro');

      await expectLater(
        replaceExtractedApiArtifactAtomically(
          platform: 'windows',
          stagingFolder: staging.path,
          destinationFolder: destination.path,
          trustedRootFolder: tempDirectory.path,
          finalizeInstall: () async {},
        ),
        throwsA(isStateError),
      );
    });
  });
}

class _WritingArtefactDownloader extends ArtefactDownloader {
  _WritingArtefactDownloader({
    required super.apiCommitHash,
    required super.sourceUrl,
    required this.archiveBytes,
  }) : super(apiBranch: 'feat/tron-gasfree');

  final List<String> calls = [];
  final List<int> archiveBytes;

  @override
  Future<String> fetchDownloadUrl(
    ApiFileMatchingConfig matchingConfig,
    String platform,
  ) async {
    calls.add('fetchDownloadUrl');
    return '$sourceUrl/kdf_$apiCommitHash-ios-aarch64.zip';
  }

  @override
  Future<String> downloadArtefact({
    required String url,
    required String destinationPath,
  }) async {
    calls.add('downloadArtefact');
    final archive = File('$destinationPath/archive.zip');
    archive.parent.createSync(recursive: true);
    archive.writeAsBytesSync(archiveBytes);
    return archive.path;
  }

  @override
  Future<void> extractArtefact({
    required String filePath,
    required String destinationFolder,
  }) async {
    calls.add('extractArtefact');
    File('$destinationFolder/libkdf.a').writeAsStringSync('runtime');
  }
}
