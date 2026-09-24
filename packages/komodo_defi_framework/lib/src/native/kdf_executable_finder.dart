import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum BuildMode {
  debug,
  profile,
  release;

  String get name {
    switch (this) {
      case BuildMode.debug:
        return 'Debug';
      case BuildMode.profile:
        return 'Profile';
      case BuildMode.release:
        return 'Release';
    }
  }
}

/// Helper class for locating the KDF executable across different platforms
class KdfExecutableFinder {
  KdfExecutableFinder({required this.logCallback});

  final void Function(String) logCallback;

  /// The build mode of the application
  BuildMode get currentBuildMode => kDebugMode
      ? BuildMode.debug
      : (kProfileMode ? BuildMode.profile : BuildMode.release);

  /// Attempts to find the KDF executable in standard and platform-specific
  /// locations
  Future<File?> findExecutable({String executableName = 'kdf'}) async {
    final macosHelpersInFrameworkPath = p.joinAll([
      p.dirname(p.dirname(Platform.resolvedExecutable)),
      'Frameworks',
      'komodo_defi_framework.framework',
      'Versions',
      'Current',
      'Helpers',
      executableName,
    ]);

    final files = [
      '/usr/local/bin/$executableName',
      '/usr/bin/$executableName',
      p.join(Directory.current.path, executableName),
      p.join(Directory.current.path, '$executableName.exe'),
      p.join(Directory.current.path, 'lib/$executableName'),
      p.join(Directory.current.path, 'lib/$executableName.exe'),
      macosHelpersInFrameworkPath,
      constructWindowsBuildArtifactPath(
        mode: currentBuildMode,
        executableName: executableName,
      ),
      constructLinuxBuildArtifactPath(
        mode: currentBuildMode,
        executableName: executableName,
      ),
      constructMacOsBuildArtifactPath(
        mode: currentBuildMode,
        executableName: executableName,
      ),
    ].map((path) => File(p.normalize(path))).toList();

    for (final file in files) {
      if (file.existsSync()) {
        logCallback('Found executable: ${file.path}');
        return file.absolute;
      }
    }

    logCallback(
      'Executable not found in paths: ${files.map((e) => e.absolute.path).join('\n')}. '
      'If you are using the KDF Flutter SDK, open an issue on GitHub.',
    );

    return null;
  }

  /// Build path to KDF executable on Linux
  String constructLinuxBuildArtifactPath({
    BuildMode mode = BuildMode.release,
    bool isLib = false,
    String executableName = 'kdf',
  }) {
    // Linux uses lowercase folder names
    final modeName = mode.name.toLowerCase();
    return p.join(
      Directory.current.path,
      'build',
      'linux',
      'x64',
      modeName,
      'bundle',
      'lib',
      isLib ? 'lib$executableName.so' : executableName,
    );
  }

  /// Build path to KDF executable on Windows
  String constructWindowsBuildArtifactPath({
    BuildMode mode = BuildMode.release,
    bool isLib = false,
    String executableName = 'kdf',
  }) {
    final modeName = mode.name;
    return p.join(
      Directory.current.path,
      'build',
      'windows',
      'x64',
      'runner',
      modeName,
      isLib ? '$executableName.dll' : '$executableName.exe',
    );
  }

  /// Build path to KDF executable on macOS
  String constructMacOsBuildArtifactPath({
    BuildMode mode = BuildMode.release,
    bool isLib = false,
    String executableName = 'kdf',
  }) {
    final modeName = mode.name;
    return p.join(
      Directory.current.path,
      'build',
      'macos',
      'Build',
      'Products',
      modeName,
      'komodo_defi_framework',
      'kdf_resources.bundle',
      'Contents',
      'Resources',
      isLib ? 'lib$executableName.dylib' : executableName,
    );
  }
}
