import 'dart:io';

/// Locates the KDF executable the build transformer fetches.
///
/// The binary is a ~120 MB build artifact under
/// `komodo_defi_framework/{macos,linux}/bin/kdf`. It is gitignored and only
/// present after the transformer has run, so **every lookup here returns null
/// rather than throwing**: "no binary" is the normal state of a fresh clone and
/// the correct response is for the process tier to skip, not to fail.
class KdfBinary {
  const KdfBinary._(this.file);

  final File file;

  String get path => file.absolute.path;

  /// Overrides auto-detection. Useful for a CI job that fetched the binary to
  /// a cache path of its own.
  static const String pathEnvironmentVariable = 'KDF_BINARY';

  /// The best guess at the platform's bin directory, or null.
  ///
  /// Deliberately does not consult
  /// `komodo_defi_framework`'s `KdfExecutableFinder`: that class searches the
  /// *bundle* layout of a built app (Frameworks/, Resources/) which does not
  /// exist under `flutter test`, and it logs through a callback this package
  /// has no reason to own.
  static Future<KdfBinary?> autoDetect() async {
    final override = Platform.environment[pathEnvironmentVariable]?.trim();
    if (override != null && override.isNotEmpty) {
      final file = File(override);
      return file.existsSync() ? _prepared(file) : null;
    }

    final platformDir = switch (Platform.operatingSystem) {
      'macos' => 'macos',
      'linux' => 'linux',
      // Windows and mobile have no transformer-fetched binary in this repo.
      _ => null,
    };
    if (platformDir == null) return null;

    // Walk up rather than assuming a working directory: `flutter test` runs
    // from the package root, a bench entrypoint may run from the workspace
    // root, and CI may run from either.
    for (
      var dir = Directory.current.absolute;
      dir.parent.path != dir.path;
      dir = dir.parent
    ) {
      final candidate = File(
        '${dir.path}/packages/komodo_defi_framework/$platformDir/bin/kdf',
      );
      if (candidate.existsSync()) return _prepared(candidate);

      final sibling = File(
        '${dir.path}/komodo_defi_framework/$platformDir/bin/kdf',
      );
      if (sibling.existsSync()) return _prepared(sibling);
    }
    return null;
  }

  static Future<KdfBinary?> _prepared(File file) async {
    // Linux CI resets the mode bit on every checkout, and macOS loses it
    // through some artifact caches. Cheaper to always set it than to detect.
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('chmod', ['+x', file.absolute.path]);
      if (result.exitCode != 0) return null;
    }
    return KdfBinary._(file);
  }

  @override
  String toString() => 'KdfBinary($path)';
}
