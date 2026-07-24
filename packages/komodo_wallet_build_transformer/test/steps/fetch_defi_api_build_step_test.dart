import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:komodo_wallet_build_transformer/src/steps/fetch_defi_api_build_step.dart';
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

  group('calculateExtractedApiArtifactSha256', () {
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
      File(
        '${tempDirectory.path}/kdflib_bg.wasm',
      ).writeAsStringSync('wasm-runtime');
      final glue = File('${tempDirectory.path}/kdflib.js')
        ..writeAsStringSync('js-glue');
      final snippet = File(
        '${tempDirectory.path}/snippets/provider/inline0.js',
      );
      snippet.parent.createSync(recursive: true);
      snippet.writeAsStringSync('provider-runtime');

      final originalDigest = await calculateExtractedApiArtifactSha256(
        platform: 'web',
        destinationFolder: tempDirectory.path,
      );

      glue.writeAsStringSync('tampered-js-glue');
      final tamperedGlueDigest = await calculateExtractedApiArtifactSha256(
        platform: 'web',
        destinationFolder: tempDirectory.path,
      );
      expect(tamperedGlueDigest, isNot(originalDigest));

      glue.writeAsStringSync('js-glue');
      snippet.writeAsStringSync('tampered-provider-runtime');
      final tamperedSnippetDigest = await calculateExtractedApiArtifactSha256(
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
          await calculateExtractedApiArtifactSha256(
            platform: 'web',
            destinationFolder: tempDirectory.path,
          ),
          await calculateExtractedApiArtifactSha256(
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

    test('fails closed when the platform artifact is missing', () async {
      await expectLater(
        calculateExtractedApiArtifactSha256(
          platform: 'android-aarch64',
          destinationFolder: tempDirectory.path,
        ),
        throwsStateError,
      );
    });

    test('fails closed when canonical and legacy artifacts coexist', () async {
      File('${tempDirectory.path}/libkdf.a').writeAsStringSync('canonical');
      File('${tempDirectory.path}/libmm2.a').writeAsStringSync('legacy');

      await expectLater(
        calculateExtractedApiArtifactSha256(
          platform: 'android-aarch64',
          destinationFolder: tempDirectory.path,
        ),
        throwsStateError,
      );
    });

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
  });
}
