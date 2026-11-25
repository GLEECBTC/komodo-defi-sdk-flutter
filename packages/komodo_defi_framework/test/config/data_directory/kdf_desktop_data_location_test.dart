import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_desktop_data_location_native.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:path/path.dart' as p;

void main() {
  final config = KdfDesktopDataDirectory(
    windowsFolder: 'Gleec',
    linuxFolder: 'com.gleec.GleecDEX',
  );

  group('Windows', () {
    test('uses the folder under Local AppData', () async {
      final root = await kdfDesktopDataRoot(
        config,
        windows: true,
        localAppData: () async => r'C:\Users\Ada\AppData\Local',
      );

      expect(root, r'C:\Users\Ada\AppData\Local\Gleec');
    });

    test('has no folder when Local AppData is unknown', () async {
      for (final missing in [null, '']) {
        expect(
          await kdfDesktopDataRoot(
            config,
            windows: true,
            localAppData: () async => missing,
          ),
          isNull,
        );
      }
    });
  });

  group('Linux', () {
    Future<String?> rootFor(Map<String, String> environment) =>
        kdfDesktopDataRoot(config, windows: false, environment: environment);

    test('uses XDG_DATA_HOME', () async {
      expect(
        await rootFor({'XDG_DATA_HOME': '/data/ada', 'HOME': '/home/ada'}),
        '/data/ada/com.gleec.GleecDEX',
      );
    });

    test('falls back to ~/.local/share', () async {
      for (final xdg in [null, '', 'relative/share']) {
        expect(
          await rootFor({'XDG_DATA_HOME': ?xdg, 'HOME': '/home/ada'}),
          '/home/ada/.local/share/com.gleec.GleecDEX',
          reason: 'XDG_DATA_HOME=$xdg',
        );
      }
    });

    test('has no folder without an absolute HOME', () async {
      expect(await rootFor({}), isNull);
      expect(await rootFor({'HOME': 'home/ada'}), isNull);
    });
  });

  group('resolving local data roots', () {
    late Directory sandbox;

    setUp(() async {
      resetKdfDesktopDataResolution();
      sandbox = await Directory.systemTemp.createTemp('kdf_data_roots_');
    });
    tearDown(() async {
      resetKdfDesktopDataResolution();
      await sandbox.delete(recursive: true);
    });

    Future<String> resolve(
      String root,
      Future<Directory?> Function() legacyDirectory, {
      Future<String?> Function()? dataRoot,
    }) => resolveKdfDataForFolder(
      p.basename(root),
      dataRoot: dataRoot ?? () async => root,
      legacyDirectory: legacyDirectory,
      engineRunning: () async => false,
    );

    Future<Directory?> offlineDocuments() async =>
        throw const FileSystemException('Documents is offline');

    test('opens migrated wallets without looking up Documents', () async {
      final root = p.join(sandbox.path, 'existing');
      final target = await Directory(p.join(root, 'kdf'))
          .create(recursive: true);
      final wallet = File(p.join(target.path, 'wallet.json'));
      await wallet.writeAsString('wallet');

      expect(await resolve(root, offlineDocuments), target.path);
      expect(await wallet.readAsString(), 'wallet');
    });

    test('shares one resolution per root and keeps roots separate', () async {
      final first = p.join(sandbox.path, 'first');
      final second = p.join(sandbox.path, 'second');
      final legacy = Completer<Directory?>();
      final resolved = Future.wait([
        resolve(first, () => legacy.future),
        resolve(first, offlineDocuments),
        resolve(second, () async => null),
      ]);
      legacy.complete(null);

      expect(await resolved, [
        p.join(first, 'kdf'),
        p.join(first, 'kdf'),
        p.join(second, 'kdf'),
      ]);
    });

    test(
      'keeps the original resolution if Local AppData returns later',
      () async {
        final root = p.join(sandbox.path, 'existing');
        final legacy = await Directory(p.join(sandbox.path, '.kdf')).create();
        await File(p.join(legacy.path, 'wallet.json')).writeAsString('wallet');

        expect(
          await resolve(root, () async => legacy, dataRoot: () async => null),
          legacy.path,
        );
        expect(await resolve(root, offlineDocuments), legacy.path);
        expect(await Directory(p.join(root, 'kdf')).exists(), isFalse);
      },
    );

    test('a failed root retries without clearing another root', () async {
      final first = p.join(sandbox.path, 'first');
      final second = p.join(sandbox.path, 'second');
      final secondTarget = await resolve(second, () async => null);

      await expectLater(
        resolve(first, offlineDocuments),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory(p.join(first, 'kdf')).exists(), isFalse);
      expect(await resolve(first, () async => null), p.join(first, 'kdf'));
      expect(await resolve(second, offlineDocuments), secondTarget);
    });
  });

  group('falling back to Documents/.kdf', () {
    late Directory documents;
    late Directory legacy;

    setUp(() async {
      documents = await Directory.systemTemp.createTemp('kdf_fallback_');
      legacy = await Directory('${documents.path}/.kdf').create();
      await File('${legacy.path}/alpha.json').writeAsString('wallet');
    });
    tearDown(() async => documents.delete(recursive: true));

    test('uses it while its data has not moved', () async {
      expect(await kdfLegacyFallback(legacy, 'test'), legacy.path);
    });

    test('refuses once the data has moved, not to show no wallets', () async {
      await File('${legacy.path}/README.txt').writeAsString('moved');
      await expectLater(kdfLegacyFallback(legacy, 'test'), throwsStateError);

      await File('${legacy.path}/README.txt').delete();
      await Directory('${legacy.path}.moved').create();
      await expectLater(kdfLegacyFallback(legacy, 'test'), throwsStateError);
    });

    test('refuses without a Documents folder', () async {
      await expectLater(kdfLegacyFallback(null, 'test'), throwsStateError);
    });
  });

  test('other platforms keep Documents/.kdf', () async {
    expect(
      Platform.isWindows || Platform.isLinux,
      isFalse,
      reason: 'run on a macOS host',
    );
    expect(await resolveKdfDesktopData(config, 7783), isNull);
  }, testOn: 'mac-os');
}
