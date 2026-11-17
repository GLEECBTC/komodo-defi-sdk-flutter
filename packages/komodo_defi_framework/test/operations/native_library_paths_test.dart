@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/operations/kdf_operations_native.dart';

void main() {
  group('bundled native engine discovery', () {
    test('Linux resolves only shared libraries in the installed bundle', () {
      expect(linuxKdfLibraryPaths('/opt/gleec/GleecDEX'), [
        '/opt/gleec/lib/libkdflib.so',
        '/opt/gleec/lib/libkdflib_static.so',
      ]);
    });

    test('Linux preserves spaces in a relocated application bundle', () {
      expect(linuxKdfLibraryPaths('/media/Wallet Apps/Gleec/GleecDEX'), [
        '/media/Wallet Apps/Gleec/lib/libkdflib.so',
        '/media/Wallet Apps/Gleec/lib/libkdflib_static.so',
      ]);
    });

    test('Windows resolves only the DLL next to the installed application', () {
      expect(windowsKdfLibraryPaths(r'C:\Program Files\Gleec\gleecdex.exe'), [
        r'C:\Program Files\Gleec\kdflib.dll',
      ]);
    });

    test('Windows preserves a UNC installation directory', () {
      expect(windowsKdfLibraryPaths(r'\\server\apps\Gleec\gleecdex.exe'), [
        r'\\server\apps\Gleec\kdflib.dll',
      ]);
    });

    test('macOS resolves the embedded dylib from the app executable', () {
      expect(
        macOsKdfLibraryPaths(
          '/Applications/Gleec DEX.app/Contents/MacOS/Gleec',
        ),
        [
          '/Applications/Gleec DEX.app/Contents/Frameworks/libkdflib.dylib',
          'PROCESS',
          'EXECUTABLE',
        ],
      );
    });

    test(
      'macOS preserves an app moved to a different installation directory',
      () {
        expect(
          macOsKdfLibraryPaths(
            '/Volumes/External Apps/Gleec.app/Contents/MacOS/Gleec',
          ).first,
          '/Volumes/External Apps/Gleec.app/Contents/Frameworks/libkdflib.dylib',
        );
      },
    );
  });
}
