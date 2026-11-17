@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Linux native library packaging failure matrix',
    () async {
      ProcessResult result;
      try {
        result = await Process.run(Platform.isWindows ? 'python' : 'python3', [
          'test/operations/linux_library_packaging_test.py',
          '-v',
        ]);
      } on ProcessException {
        markTestSkipped(
          'Python unavailable; required for ELF packaging checks.',
        );
        return;
      }
      final output = '${result.stdout}\n${result.stderr}';
      if (result.exitCode == 0 &&
          output.contains('Required tools unavailable')) {
        markTestSkipped(output.trim());
        return;
      }
      expect(result.exitCode, 0, reason: output);
      expect(result.stderr, contains('Ran 31 tests'));
      expect(result.stderr, contains('OK'));
      expect(result.stderr, isNot(contains('skipped=')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
