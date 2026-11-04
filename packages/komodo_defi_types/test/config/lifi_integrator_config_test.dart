import 'dart:convert';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  test('serializes the global KDF policy with integer basis points', () {
    final config = LifiIntegratorConfig(
      name: 'gleec-dex-staging',
      feeBps: 178,
      lifiFeeBps: 22,
    );
    expect(jsonDecode(jsonEncode(config.toJson())), {
      'name': 'gleec-dex-staging',
      'fee_bps': 178,
      'lifi_fee_bps': 22,
    });
    expect(
      config,
      LifiIntegratorConfig(
        name: 'gleec-dex-staging',
        feeBps: 178,
        lifiFeeBps: 22,
      ),
    );
  });
  test('rejects invalid names and fee totals before engine start', () {
    for (final name in ['', '  ', 'lifi']) {
      expect(
        () => LifiIntegratorConfig(name: name, feeBps: 178, lifiFeeBps: 22),
        throwsArgumentError,
      );
    }
    for (final rates in [(-1, 0), (0, -1), (9999, 1), (10000, 0)]) {
      expect(
        () => LifiIntegratorConfig(
          name: 'gleec',
          feeBps: rates.$1,
          lifiFeeBps: rates.$2,
        ),
        throwsArgumentError,
      );
    }
    expect(
      LifiIntegratorConfig(name: 'gleec', feeBps: 0, lifiFeeBps: 0).feeBps,
      0,
    );
  });
}
