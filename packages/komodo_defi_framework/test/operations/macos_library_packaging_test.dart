@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS native library packaging failure matrix', () async {
    final result = await Process.run('ruby', [
      'test/operations/macos_library_packaging_test.rb',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('11 runs'));
    expect(result.stdout, contains('0 failures, 0 errors'));
  });
}
