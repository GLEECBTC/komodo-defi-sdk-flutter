import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_migration.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_desktop_data_location.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_windows/path_provider_windows.dart';

final _log = Logger('KdfDesktopDataLocation');

KdfDesktopDataResolver platformKdfDesktopDataResolver() =>
    resolveKdfDesktopData;

KdfDataStartRecorder platformKdfDataStartRecorder() =>
    KdfDataMigration.recordVerifiedStart;

Future<String>? _resolution;

/// KDF's data directory on Windows and Linux, or null on other platforms.
///
/// The first call in a process moves any data out of `Documents/.kdf`. KDF
/// runs inside the app, so this process hasn't started one yet. Another app's
/// KDF answering on [rpcPort] may be using that data, so then nothing moves.
Future<String?> resolveKdfDesktopData(
  KdfDesktopDataDirectory config,
  int rpcPort,
) async {
  if (!Platform.isWindows && !Platform.isLinux) return null;
  try {
    return await (_resolution ??= _resolve(config, rpcPort));
  } on Object {
    _resolution = null;
    rethrow;
  }
}

Future<String> _resolve(KdfDesktopDataDirectory config, int rpcPort) async {
  final legacy = await _legacyDirectory();
  final root = await kdfDesktopDataRoot(config);
  if (root == null) return kdfLegacyFallback(legacy, 'No app data folder');
  try {
    return (await KdfDataMigration(
      root: Directory(root),
      legacy: legacy,
      engineRunning: () => _answers(rpcPort),
    ).run()).path;
  } on KdfDataRootException catch (error) {
    return kdfLegacyFallback(legacy, '$error');
  }
}

/// The old directory, unless its data has already moved: then KDF must not
/// start on it and find no wallets.
@visibleForTesting
Future<String> kdfLegacyFallback(Directory? legacy, String reason) async {
  if (legacy == null ||
      await Directory('${legacy.path}.moved').exists() ||
      await File(p.join(legacy.path, KdfDataMigration.readmeName)).exists()) {
    throw StateError('KDF data is unavailable: $reason');
  }
  _log.warning('$reason, so KDF keeps using ${legacy.path}');
  return legacy.path;
}

Future<Directory?> _legacyDirectory() async {
  try {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, '.kdf'));
  } on MissingPlatformDirectoryException {
    // On Linux this means `xdg-user-dir` is missing, and the SDK could never
    // start KDF there, so no old data exists. On Windows Documents is just
    // unavailable right now: that must not pass for a folder with no wallets.
    if (Platform.isLinux) return null;
    rethrow;
  }
}

Future<bool> _answers(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(milliseconds: 500),
    );
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

/// The folder that holds KDF's data directory: `%LOCALAPPDATA%\<windows>`
/// or `$XDG_DATA_HOME/<linux>`. Null when the platform reports neither.
@visibleForTesting
Future<String?> kdfDesktopDataRoot(
  KdfDesktopDataDirectory config, {
  bool? windows,
  Future<String?> Function()? localAppData,
  Map<String, String>? environment,
}) async {
  if (windows ?? Platform.isWindows) {
    final base = await (localAppData ?? _windowsLocalAppData)();
    if (base == null || base.isEmpty) return null;
    return p.windows.join(base, config.windowsFolder);
  }
  final base = xdgDataHome(environment ?? Platform.environment);
  return base == null ? null : p.posix.join(base, config.linuxFolder);
}

/// `$XDG_DATA_HOME`, or `$HOME/.local/share` when that is unset, empty or
/// relative: the XDG spec says to ignore a relative value.
@visibleForTesting
String? xdgDataHome(Map<String, String> environment) {
  final configured = environment['XDG_DATA_HOME'];
  if (configured != null && p.posix.isAbsolute(configured)) return configured;
  final home = environment['HOME'];
  if (home == null || !p.posix.isAbsolute(home)) return null;
  return p.posix.join(home, '.local', 'share');
}

// FOLDERID_LocalAppData. path_provider_windows names it
// `WindowsKnownFolder.LocalAppData`, but only in its FFI build.
const _localAppDataFolderId = '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}';

// The known-folder API, which follows the profile, rather than the
// overridable %LOCALAPPDATA% variable.
Future<String?> _windowsLocalAppData() async {
  try {
    return await PathProviderWindows().getPath(_localAppDataFolderId);
  } on Object catch (error) {
    _log.warning('Local AppData is unavailable: $error');
    return null;
  }
}

@visibleForTesting
void resetKdfDesktopDataResolution() => _resolution = null;
