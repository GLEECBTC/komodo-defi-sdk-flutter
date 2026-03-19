import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/seed_node_validator.dart';

void main() {
  group('SeedNodeValidator', () {
    test('accepts a single seed node for non-bootstrap peers', () {
      expect(
        () => SeedNodeValidator.validate(
          seedNodes: const ['seed01.kmdefi.net'],
          disableP2p: false,
          iAmSeed: false,
          isBootstrapNode: false,
        ),
        returnsNormally,
      );
    });

    test('default seed nodes contain the single supported host', () {
      expect(
        SeedNodeValidator.getDefaultSeedNodes(),
        equals(const ['seed01.kmdefi.net']),
      );
    });
  });
}
