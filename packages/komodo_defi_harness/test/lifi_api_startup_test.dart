import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

/// Boots a real SDK, registers a wallet, and returns every KDF start conf.
///
/// The replay backend always answers `version`, so KDF looks started already
/// and only the sign-in start happens here. The signed-out start is covered
/// in komodo_defi_local_auth.
Future<List<Map<String, dynamic>>> _startConfs(
  KomodoDefiSdkConfig config,
) async {
  final script = KdfWalletFixture().build();
  final activateWallet = script.onKdfStart;
  final starts = <Map<String, dynamic>>[];
  script.onKdfStart = (params) {
    starts.add(params);
    activateWallet?.call(params);
  };
  final harness = await KdfHarness.replayed(script: script, config: config);
  addTearDown(harness.dispose);
  await harness.signIn(walletType: KdfWalletType.hd);
  return starts;
}

void main() {
  test('the sign-in start carries the configured LI.FI URL', () async {
    const url = 'https://swap.example.com/lifi';
    final starts = await _startConfs(
      const KomodoDefiSdkConfig(lifiApiUrl: url),
    );

    expect(starts.single['wallet_name'], 'harness-wallet');
    expect(starts.single['lifi_api'], url);
  });

  test('KDF keeps its default LI.FI URL when none is configured', () async {
    final starts = await _startConfs(const KomodoDefiSdkConfig());

    expect(starts.single, isNot(contains('lifi_api')));
  });
}
