@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows native library packaging failure matrix', () async {
    final cmake = Platform.environment['GLEEC_CMAKE'] ?? 'cmake';
    try {
      await Process.run(cmake, ['--version']);
    } on ProcessException {
      markTestSkipped(
        'CMake unavailable; set GLEEC_CMAKE to run packaging checks.',
      );
      return;
    }
    final result = await Process.run(
      Platform.isWindows ? 'python' : 'python3',
      ['test/operations/windows_library_packaging_test.py'],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('Ran 10 tests'));
    expect(result.stderr, contains('OK'));
  });
}
