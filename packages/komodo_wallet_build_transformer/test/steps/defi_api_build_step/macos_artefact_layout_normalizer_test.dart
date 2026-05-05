import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/defi_api_build_step/macos_artefact_layout_normalizer.dart';
import 'package:test/test.dart';

void main() {
  group('MacosArtefactLayoutNormalizer', () {
    late Directory tempDir;
    late Directory extractedDir;
    late Directory destinationRoot;
    late MacosArtefactLayoutNormalizer normalizer;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('macos_artefact_test_');
      extractedDir = Directory('${tempDir.path}/extracted');
      destinationRoot = Directory('${tempDir.path}/macos');
      extractedDir.createSync(recursive: true);
      destinationRoot.createSync(recursive: true);
      normalizer = MacosArtefactLayoutNormalizer();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('installs executable archives into macos/bin/kdf', () async {
      final executable = File('${extractedDir.path}/nested/kdf');
      await executable.parent.create(recursive: true);
      await executable.writeAsString('executable');

      final result = await normalizer.installFromExtractedDirectory(
        extractedDirectory: extractedDir,
        destinationRoot: destinationRoot,
      );

      expect(result.hasExecutable, isTrue);
      expect(result.hasDynamicLibrary, isFalse);
      expect(result.hasStaticLibrary, isFalse);
      expect(
        File('${destinationRoot.path}/bin/kdf').readAsStringSync(),
        equals('executable'),
      );
    });

    test(
      'installs static archives into macos/Frameworks/libkdflib.a',
      () async {
        final staticLibrary = File('${extractedDir.path}/libkdflib.a');
        await staticLibrary.writeAsString('static-library');

        final result = await normalizer.installFromExtractedDirectory(
          extractedDirectory: extractedDir,
          destinationRoot: destinationRoot,
        );

        expect(result.hasExecutable, isFalse);
        expect(result.hasDynamicLibrary, isFalse);
        expect(result.hasStaticLibrary, isTrue);
        expect(
          File(
            '${destinationRoot.path}/Frameworks/libkdflib.a',
          ).readAsStringSync(),
          equals('static-library'),
        );
      },
    );

    test('installs dynamic libraries into macos/lib/libkdflib.dylib', () async {
      final dynamicLibrary = File('${extractedDir.path}/lib/libkdflib.dylib');
      await dynamicLibrary.parent.create(recursive: true);
      await dynamicLibrary.writeAsString('dynamic-library');

      final result = await normalizer.installFromExtractedDirectory(
        extractedDirectory: extractedDir,
        destinationRoot: destinationRoot,
      );

      expect(result.hasExecutable, isFalse);
      expect(result.hasDynamicLibrary, isTrue);
      expect(result.hasStaticLibrary, isFalse);
      expect(
        File('${destinationRoot.path}/lib/libkdflib.dylib').readAsStringSync(),
        equals('dynamic-library'),
      );
    });

    test(
      'renames legacy mm2 artefacts into the canonical macOS layout',
      () async {
        final executable = File('${extractedDir.path}/legacy/mm2');
        final dynamicLibrary = File('${extractedDir.path}/legacy/libmm2.dylib');
        final staticLibrary = File('${extractedDir.path}/legacy/libmm2.a');

        await executable.parent.create(recursive: true);
        await executable.writeAsString('mm2-executable');
        await dynamicLibrary.writeAsString('mm2-dylib');
        await staticLibrary.writeAsString('mm2-static');

        final result = await normalizer.installFromExtractedDirectory(
          extractedDirectory: extractedDir,
          destinationRoot: destinationRoot,
        );

        expect(result.hasExecutable, isTrue);
        expect(result.hasDynamicLibrary, isTrue);
        expect(result.hasStaticLibrary, isTrue);
        expect(
          File('${destinationRoot.path}/bin/kdf').readAsStringSync(),
          equals('mm2-executable'),
        );
        expect(
          File(
            '${destinationRoot.path}/lib/libkdflib.dylib',
          ).readAsStringSync(),
          equals('mm2-dylib'),
        );
        expect(
          File(
            '${destinationRoot.path}/Frameworks/libkdflib.a',
          ).readAsStringSync(),
          equals('mm2-static'),
        );
      },
    );

    test(
      'invalid extracted layouts do not overwrite existing artefacts',
      () async {
        final existingExecutable = File('${destinationRoot.path}/bin/kdf');
        await existingExecutable.parent.create(recursive: true);
        await existingExecutable.writeAsString('existing-executable');

        await File('${extractedDir.path}/README.txt').writeAsString('invalid');

        await expectLater(
          () => normalizer.installFromExtractedDirectory(
            extractedDirectory: extractedDir,
            destinationRoot: destinationRoot,
          ),
          throwsStateError,
        );

        expect(
          existingExecutable.readAsStringSync(),
          equals('existing-executable'),
        );
      },
    );
  });
}
