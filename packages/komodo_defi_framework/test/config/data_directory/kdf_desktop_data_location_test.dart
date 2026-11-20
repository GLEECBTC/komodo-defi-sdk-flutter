import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/data_directory/kdf_desktop_data_location_native.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

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
