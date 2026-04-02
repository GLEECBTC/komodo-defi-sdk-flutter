import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

class MacosArtefactInstallResult {
  const MacosArtefactInstallResult({
    required this.hasExecutable,
    required this.hasDynamicLibrary,
    required this.hasStaticLibrary,
  });

  final bool hasExecutable;
  final bool hasDynamicLibrary;
  final bool hasStaticLibrary;

  bool get hasAnyArtefact =>
      hasExecutable || hasDynamicLibrary || hasStaticLibrary;
}

class MacosArtefactLayoutNormalizer {
  MacosArtefactLayoutNormalizer({Logger? log})
    : _log = log ?? Logger('MacosArtefactLayoutNormalizer');

  static const executableRelativePath = 'bin/kdf';
  static const dynamicLibraryRelativePath = 'lib/libkdflib.dylib';
  static const staticLibraryRelativePath = 'Frameworks/libkdflib.a';

  static const _managedDirectoryNames = ['bin', 'lib', 'Frameworks'];

  final Logger _log;

  Future<MacosArtefactInstallResult> installFromExtractedDirectory({
    required Directory extractedDirectory,
    required Directory destinationRoot,
  }) async {
    final stagingDirectory = await Directory.systemTemp.createTemp(
      'kdf_macos_stage_',
    );

    try {
      final result = await _normalizeIntoStagingDirectory(
        extractedDirectory: extractedDirectory,
        stagingDirectory: stagingDirectory,
      );

      if (!result.hasAnyArtefact) {
        throw StateError(
          'No compatible macOS KDF artefacts were found in '
          '${extractedDirectory.path}',
        );
      }

      await _replaceManagedDirectories(
        sourceRoot: stagingDirectory,
        destinationRoot: destinationRoot,
      );

      return result;
    } finally {
      if (stagingDirectory.existsSync()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  }

  Future<MacosArtefactInstallResult> _normalizeIntoStagingDirectory({
    required Directory extractedDirectory,
    required Directory stagingDirectory,
  }) async {
    final files = await extractedDirectory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();

    final executable = _findPreferredFile(files, const ['kdf', 'mm2']);
    final dynamicLibrary = _findPreferredFile(files, const [
      'libkdflib.dylib',
      'libkdf.dylib',
      'libmm2.dylib',
    ]);
    final staticLibrary = _findPreferredFile(files, const [
      'libkdflib.a',
      'libkdf.a',
      'libmm2.a',
    ]);

    if (executable != null) {
      await _copyCanonicalFile(
        source: executable,
        destinationRoot: stagingDirectory,
        relativeDestinationPath: executableRelativePath,
        makeExecutable: true,
      );
    }

    if (dynamicLibrary != null) {
      await _copyCanonicalFile(
        source: dynamicLibrary,
        destinationRoot: stagingDirectory,
        relativeDestinationPath: dynamicLibraryRelativePath,
      );
    }

    if (staticLibrary != null) {
      await _copyCanonicalFile(
        source: staticLibrary,
        destinationRoot: stagingDirectory,
        relativeDestinationPath: staticLibraryRelativePath,
      );
    }

    return MacosArtefactInstallResult(
      hasExecutable: executable != null,
      hasDynamicLibrary: dynamicLibrary != null,
      hasStaticLibrary: staticLibrary != null,
    );
  }

  File? _findPreferredFile(List<File> files, List<String> preferredBasenames) {
    for (final basename in preferredBasenames) {
      final matches =
          files
              .where(
                (file) => path.basename(file.path).toLowerCase() == basename,
              )
              .toList()
            ..sort(_compareFilesBySpecificity);

      if (matches.isNotEmpty) {
        return matches.first;
      }
    }

    return null;
  }

  int _compareFilesBySpecificity(File left, File right) {
    final leftDepth = path.split(path.normalize(left.path)).length;
    final rightDepth = path.split(path.normalize(right.path)).length;
    final depthComparison = leftDepth.compareTo(rightDepth);
    if (depthComparison != 0) {
      return depthComparison;
    }

    return left.path.compareTo(right.path);
  }

  Future<void> _copyCanonicalFile({
    required File source,
    required Directory destinationRoot,
    required String relativeDestinationPath,
    bool makeExecutable = false,
  }) async {
    final destination = File(
      path.join(destinationRoot.path, relativeDestinationPath),
    );
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);

    if (makeExecutable) {
      await _setExecutablePermissions(destination);
    }

    _log.info(
      'Normalized macOS artefact ${source.path} -> ${destination.path}',
    );
  }

  Future<void> _replaceManagedDirectories({
    required Directory sourceRoot,
    required Directory destinationRoot,
  }) async {
    for (final directoryName in _managedDirectoryNames) {
      final destinationDirectory = Directory(
        path.join(destinationRoot.path, directoryName),
      );
      if (destinationDirectory.existsSync()) {
        await destinationDirectory.delete(recursive: true);
      }

      final sourceDirectory = Directory(
        path.join(sourceRoot.path, directoryName),
      );
      if (sourceDirectory.existsSync()) {
        await _copyDirectory(
          sourceDirectory: sourceDirectory,
          destinationDirectory: destinationDirectory,
        );
      }
    }
  }

  Future<void> _copyDirectory({
    required Directory sourceDirectory,
    required Directory destinationDirectory,
  }) async {
    await destinationDirectory.create(recursive: true);

    await for (final entity in sourceDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = path.relative(
        entity.path,
        from: sourceDirectory.path,
      );
      final destinationPath = path.join(
        destinationDirectory.path,
        relativePath,
      );

      if (entity is Directory) {
        await Directory(destinationPath).create(recursive: true);
        continue;
      }

      if (entity is File) {
        final destinationFile = File(destinationPath);
        await destinationFile.parent.create(recursive: true);
        await entity.copy(destinationFile.path);

        if (path.basename(destinationFile.path) == 'kdf') {
          await _setExecutablePermissions(destinationFile);
        }
      }
    }
  }

  Future<void> _setExecutablePermissions(File file) async {
    if (Platform.isWindows) {
      return;
    }

    final chmodResult = await Process.run('chmod', ['+x', file.path]);
    if (chmodResult.exitCode != 0) {
      throw ProcessException(
        'chmod',
        ['+x', file.path],
        chmodResult.stderr.toString(),
        chmodResult.exitCode,
      );
    }
  }
}
