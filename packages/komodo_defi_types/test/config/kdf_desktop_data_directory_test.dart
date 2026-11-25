import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  KdfDesktopDataDirectory both(String name) =>
      KdfDesktopDataDirectory(windowsFolder: name, linuxFolder: name);

  test('accepts single folder names', () {
    for (final name in [
      'Gleec',
      'com.gleec.GleecDEX',
      'Gleec DEX',
      'a',
      'A-1_b',
    ]) {
      expect(both(name).windowsFolder, name);
    }
  });

  test('rejects anything that is not one folder name', () {
    for (final name in [
      '',
      '.',
      '..',
      '.kdf',
      'a/b',
      r'a\b',
      'C:',
      'name.',
      'name ',
      ' name',
      'a*b',
      'a?b',
    ]) {
      expect(
        () => KdfDesktopDataDirectory(windowsFolder: name, linuxFolder: 'ok'),
        throwsArgumentError,
        reason: 'windowsFolder "$name"',
      );
      expect(
        () => KdfDesktopDataDirectory(windowsFolder: 'ok', linuxFolder: name),
        throwsArgumentError,
        reason: 'linuxFolder "$name"',
      );
    }
  });

  test('compares by value', () {
    expect(both('Gleec'), both('Gleec'));
    expect(both('Gleec'), isNot(both('Other')));
  });
}
