import 'dart:io';
import 'dart:typed_data';

import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_migration.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_record.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_data_tree.dart';
import 'package:path/path.dart' as p;

/// A sandbox with a Documents folder and an app data folder.
class KdfDataSandbox {
  KdfDataSandbox._(this.base);

  static Future<KdfDataSandbox> create() async =>
      KdfDataSandbox._(await Directory.systemTemp.createTemp('kdf_data_'));

  final Directory base;
  DateTime now = DateTime.utc(2026, 11, 20, 12);

  Directory get documents => Directory(p.join(base.path, 'Documents'));
  Directory get legacy => Directory(p.join(documents.path, '.kdf'));
  Directory get retired => Directory('${legacy.path}.moved');
  Directory get appData => Directory(p.join(base.path, 'AppData', 'Gleec'));
  Directory get target => Directory(p.join(appData.path, 'kdf'));
  File get recordFile => File(p.join(appData.path, KdfDataRecord.fileName));

  /// Whether another KDF seems to be running.
  bool engineRunning = false;

  KdfDataMigration migration({
    Future<void> Function(File source, File destination) copyFile =
        copyKdfDataFile,
  }) => KdfDataMigration(
    root: appData,
    legacy: legacy,
    clock: () => now,
    engineRunning: () async => engineRunning,
    lockTimeout: const Duration(seconds: 2),
    copyFile: copyFile,
  );

  Future<Directory> run() => migration().run();

  Future<KdfDataRecord?> record() => KdfDataRecord.read(recordFile);

  Future<void> verifyStart() =>
      KdfDataMigration.recordVerifiedStart(target.path, clock: () => now);

  Future<void> dispose() async {
    await _makeReadable(base);
    await base.delete(recursive: true);
  }
}

const seedFolder = '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c';
const sharedFolder = 'aabbccddeeff00112233445566778899aabbccdd';

/// What KDF leaves in its data directory: wallet files at the top, a folder
/// per seed with its databases and swaps, and the shared database.
Map<String, List<int>> kdfData() => {
  'alpha.json': '{"version":1,"ciphertext":"alpha"}'.codeUnits,
  'beta.json': '{"version":1,"ciphertext":"beta"}'.codeUnits,
  '$seedFolder/MM2.db': Uint8List.fromList(
    List.generate(70000, (i) => (i * 31) % 256),
  ),
  '$seedFolder/MM2.db-wal': [0, 255, 1, 254, 0, 0, 7],
  '$seedFolder/SWAPS/MY/3f2a9c.json': '{"swap":"in progress"}'.codeUnits,
  '$sharedFolder/MM2-shared.db': 'shared'.codeUnits,
};

/// An empty folder KDF creates for each seed.
const emptyFolder = '$seedFolder/ORDERS/MY/MAKER';

Future<void> plant(Directory directory, Map<String, List<int>> files) async {
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File(p.joinAll([directory.path, ...key.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(value, flush: true);
  }
  await Directory(p.joinAll([directory.path, ...emptyFolder.split('/')]))
      .create(recursive: true);
}

/// Every file under [directory], by `/`-separated relative path.
Future<Map<String, List<int>>> readTree(Directory directory) async {
  final tree = <String, List<int>>{};
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) {
      final relative = p.relative(entity.path, from: directory.path);
      tree[p.split(relative).join('/')] = await entity.readAsBytes();
    }
  }
  return tree;
}

Future<List<String>> topLevel(Directory directory) async => [
  for (final entity in await directory.list().toList()) p.basename(entity.path),
]..sort();

Future<void> setMode(FileSystemEntity entity, String mode) async {
  final result = await Process.run('chmod', [mode, entity.path]);
  if (result.exitCode != 0) throw StateError('chmod failed: ${result.stderr}');
}

Future<void> _makeReadable(Directory directory) async {
  if (Platform.isWindows || !await directory.exists()) return;
  await Process.run('chmod', ['-R', 'u+rwX', directory.path]);
}
