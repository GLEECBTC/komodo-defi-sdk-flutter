import 'package:equatable/equatable.dart';

/// Where KDF keeps its data on Windows and Linux.
///
/// KDF's data directory holds each wallet's password-encrypted seed and the
/// databases it needs to finish or refund a swap. Without this setting the SDK
/// keeps it in `Documents/.kdf`. Windows often backs Documents up to OneDrive,
/// and on Linux Documents is wherever `xdg-user-dir` points.
///
/// With it, KDF uses `%LOCALAPPDATA%\<windowsFolder>\kdf` on Windows and
/// `$XDG_DATA_HOME/<linuxFolder>/kdf` on Linux, and the first start moves any
/// data out of `Documents/.kdf`. Other platforms ignore it.
///
/// Choose the names once: changing them later leaves the data behind.
class KdfDesktopDataDirectory extends Equatable {
  KdfDesktopDataDirectory({
    required this.windowsFolder,
    required this.linuxFolder,
  }) {
    _checkFolderName(windowsFolder, 'windowsFolder');
    _checkFolderName(linuxFolder, 'linuxFolder');
  }

  /// A single folder name under `%LOCALAPPDATA%`, such as `Gleec`.
  final String windowsFolder;

  /// A single folder name under `$XDG_DATA_HOME`, usually the application ID.
  final String linuxFolder;

  @override
  List<Object?> get props => [windowsFolder, linuxFolder];
}

// Letters, digits, `.`, `-`, `_` and spaces. Not starting with a dot, so never
// `.` or `..`, and not ending in a dot or space, which Windows drops.
final _folderName = RegExp(
  r'^[A-Za-z0-9_-](?:[A-Za-z0-9._ -]*[A-Za-z0-9_-])?$',
);

void _checkFolderName(String name, String argument) {
  if (!_folderName.hasMatch(name)) {
    throw ArgumentError.value(name, argument, 'Must be a single folder name');
  }
}
