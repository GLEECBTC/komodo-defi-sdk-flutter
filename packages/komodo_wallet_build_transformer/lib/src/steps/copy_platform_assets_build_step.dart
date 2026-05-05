import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

class CopyPlatformAssetsBuildStep extends BuildStep {
  CopyPlatformAssetsBuildStep({
    required this.projectRoot,
    required this.buildConfig,
    required this.artifactOutputDirectory,
  });

  final BuildConfig buildConfig;
  final Directory projectRoot;
  final Directory artifactOutputDirectory;

  @override
  final String id = idStatic;

  final _log = Logger('komodo_wallet_build_transformer');

  static const idStatic = 'copy_platform_assets';

  @override
  Future<void> build() async {
    _log.info('Artifact output directory: $artifactOutputDirectory\n');
    await _copyLinuxAssets();
    await _copyKdfWebFiles();
    await _copyOtherWebFiles();
  }

  @override
  Future<bool> canSkip() async {
    return _canSkipLinuxAssets() && _canSkipKdfWebFiles();
  }

  @override
  Future<void> revert([Exception? e]) async {
    _log.info('Reverting copy platform assets build step');
    // await _revertLinuxAssets();

    return;
    //  TODO: Implement. Consider if it is better to just clear the folder or
    // if we should keep a backup of the folder before the step is run. Since
    // the web assets are small, it could be safe to "back up" the folder in
    // memory which simplifies the success/cleanup logic.
    // await _revertKdfWebFiles();
  }

  Future<void> _copyLinuxAssets() async {
    final appName = _getAppName();
    await _copyAssets(
      sourceFiles: [_sourceIcon(appName), _sourceDesktop(appName)],
      destFiles: [_destIcon(appName), _destDesktop(appName)],
    );
  }

  Future<void> _copyKdfWebFiles() async {
    final kdfWebPath = buildConfig.apiConfig.platforms['web']!.path;
    final sourceDir =
        Directory(path.join(artifactOutputDirectory.path, kdfWebPath));
    final destDir = Directory(path.joinAll([projectRoot.path, kdfWebPath]));
    await _copyAssetsFromDir(
      sourceDir: sourceDir,
      destDir: destDir,
    );
  }

  Future<void> _copyOtherWebFiles() async {
    final kdfWebPath = buildConfig.apiConfig.platforms['web']!.path;
    final kdfLibDestDirectory =
        Directory(path.join(projectRoot.path, kdfWebPath));
    final sourceDir = Directory(path.join(artifactOutputDirectory.path, 'web'));
    // TODO: Make configurable with a pubspec.yaml setting (cli parameter)
    final destDir = kdfLibDestDirectory.parent;

    await _copyAssetsFromDir(
      sourceDir: sourceDir,
      destDir: destDir,
      skipDir: kdfLibDestDirectory,
    );
  }

  Future<void> _copyAssets({
    required List<File> sourceFiles,
    required List<File> destFiles,
  }) async {
    try {
      for (var i = 0; i < sourceFiles.length; i++) {
        final sourceFile = sourceFiles[i];
        final destFile = destFiles[i];

        if (!destFile.parent.existsSync()) {
          destFile.parent.createSync(recursive: true);
        }

        if (sourceFile.existsSync()) {
          sourceFile.copySync(destFile.path);
        }
      }
      _log.info('Copying assets completed');
    } catch (e, s) {
      _log.severe('Failed to copy assets with error', e, s);
      rethrow;
    }
  }

  Future<void> _copyAssetsFromDir({
    required Directory sourceDir,
    required Directory destDir,
    Directory? skipDir,
  }) async {
    try {
      if (!sourceDir.existsSync()) {
        _log.info(
          'Source directory ${sourceDir.path} does not exist. Skipping copy.',
        );
        return;
      }

      if (sourceDir.path == destDir.path) {
        _log
          ..info(
            'Source and destination directories are the same. Skipping copy.',
          )
          ..fine('Source directory (absolute): ${sourceDir.absolute}')
          ..fine('Destination directory (absolute): ${destDir.absolute}');
        return;
      }

      if (_shouldClearDestFolder(sourceDir, destDir)) {
        if (destDir.existsSync()) {
          destDir.deleteSync(recursive: true);
        }
        destDir.createSync(recursive: true);
      }

      await for (final entity in sourceDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = path.relative(entity.path, from: sourceDir.path);

          if (skipDir != null &&
              path.isWithin(
                skipDir.absolute.path,
                entity.absolute.path,
              )) {
            // Skip files within the skipDir
            continue;
          }

          // Check if this is a WASM file that needs compression
          if (path.basename(entity.path) == 'kdflib_bg.wasm') {
            // Compress and save as .wasm.gz
            final destFile = File(path.join(destDir.path, relativePath + '.gz'));

            if (!destFile.parent.existsSync()) {
              destFile.parent.createSync(recursive: true);
            }
            if (destFile.existsSync()) {
              destFile.deleteSync();
            }

            // Read, compress, and write
            final wasmBytes = await entity.readAsBytes();
            final originalSize = wasmBytes.length;
            final compressedBytes = gzip.encode(wasmBytes);
            final compressedSize = compressedBytes.length;
            await destFile.writeAsBytes(compressedBytes);

            final compressionRatio =
                ((originalSize - compressedSize) / originalSize * 100).toStringAsFixed(1);
            _log.info(
              'Compressed kdflib_bg.wasm during copy: '
              '${originalSize} bytes -> ${compressedSize} bytes '
              '($compressionRatio% reduction)',
            );
          } else {
            // Normal file copy
            final destFile = File(path.join(destDir.path, relativePath));

            if (!destFile.parent.existsSync()) {
              destFile.parent.createSync(recursive: true);
            }
            if (destFile.existsSync()) {
              destFile.deleteSync();
            }
            entity.copySync(destFile.path);
          }
        }
      }
      _log.info(
        'Copying assets from ${sourceDir.path} to ${destDir.path} completed',
      );
    } catch (e, s) {
      _log.severe('Failed to copy assets from directory with error', e, s);
      rethrow;
    }
  }

  // ignore: unused_element
  Future<void> _revertLinuxAssets() async {
    final appName = _getAppName();
    await _revertAssets([_destIcon(appName), _destDesktop(appName)]);
  }

  Future<void> _revertAssets(List<File> files) async {
    try {
      for (final file in files) {
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
      _log.info('Reverting assets completed');
    } catch (e, s) {
      _log.severe('Failed to revert assets with error', e, s);
      rethrow;
    }
  }

  bool _canSkipLinuxAssets() {
    final appName = _getAppName();
    return _canSkipFiles(
      sourceFiles: [_sourceIcon(appName), _sourceDesktop(appName)],
      destFiles: [_destIcon(appName), _destDesktop(appName)],
    );
  }

  bool _canSkipKdfWebFiles() {
    final kdfWebPath = buildConfig.apiConfig.platforms['web']!.path;
    final sourceDir = Directory(
      path.join(
        projectRoot.path,
        kdfWebPath,
      ),
    );
    final destDir = Directory(path.join(projectRoot.path, kdfWebPath));

    if (!sourceDir.existsSync()) {
      _log.info(
        'Source directory ${sourceDir.path} does not exist. Skipping check.',
      );
      return true;
    }

    return !_shouldClearDestFolder(sourceDir, destDir);
  }

  bool _canSkipFiles({
    required List<File> sourceFiles,
    required List<File> destFiles,
  }) {
    for (var i = 0; i < sourceFiles.length; i++) {
      final sourceFile = sourceFiles[i];
      final destFile = destFiles[i];

      if (!sourceFile.existsSync() || !destFile.existsSync()) {
        return false;
      }

      if (sourceFile.lastModifiedSync().isAfter(destFile.lastModifiedSync())) {
        return false;
      }
    }
    return true;
  }

  bool _shouldClearDestFolder(Directory sourceDir, Directory destDir) {
    if (!destDir.existsSync()) return true;

    final sourceFiles = sourceDir.listSync(recursive: true).whereType<File>();
    final destFiles = destDir.listSync(recursive: true).whereType<File>();
    final destFilePaths =
        destFiles.map((f) => path.relative(f.path, from: destDir.path)).toSet();

    for (final sourceFile in sourceFiles) {
      final relativePath = path.relative(sourceFile.path, from: sourceDir.path);
      final correspondingDestFile = File(path.join(destDir.path, relativePath));

      if (!correspondingDestFile.existsSync() ||
          sourceFile
              .lastModifiedSync()
              .isAfter(correspondingDestFile.lastModifiedSync())) {
        return true;
      }

      destFilePaths.remove(relativePath);
    }

    if (destFilePaths.isNotEmpty) {
      return true;
    }

    return false;
  }

  String _getAppName() {
    // TODO: This isn't correct/reliable
    return path.basename(projectRoot.path);
  }

  File _sourceIcon(String appName) =>
      File(path.joinAll([projectRoot.path, 'linux', '$appName.svg']));

  File _destIcon(String appName) => File(
        path.joinAll([
          projectRoot.path,
          'build',
          'linux',
          'x64',
          'release',
          'bundle',
          '$appName.svg',
        ]),
      );

  File _sourceDesktop(String appName) =>
      File(path.joinAll([projectRoot.path, 'linux', '$appName.desktop']));

  File _destDesktop(String appName) => File(
        path.joinAll([
          projectRoot.path,
          'build',
          'linux',
          'x64',
          'release',
          'bundle',
          '$appName.desktop',
        ]),
      );
}
