// Not required for test files
// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';

void main() {
  group('KomodoLegacyWalletMigration', () {
    test('can be instantiated', () {
      expect(KomodoLegacyWalletMigration(), isNotNull);
    });
  });
}
