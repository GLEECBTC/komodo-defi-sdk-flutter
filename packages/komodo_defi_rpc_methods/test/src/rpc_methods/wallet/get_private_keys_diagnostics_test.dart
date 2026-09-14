import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:test/test.dart';

void main() {
  test('key DTO diagnostics redact while explicit export preserves values', () {
    const standard = CoinKeyInfo(
      coin: 'synthetic-coin',
      publicKeySecp256k1: 'synthetic-public-key',
      publicKeyAddress: 'synthetic-address',
      privKey: 'synthetic-private-key',
      viewingKey: 'synthetic-viewing-key',
    );
    const address = HdAddressInfo(
      derivationPath: 'synthetic-path',
      zDerivationPath: 'synthetic-shielded-path',
      publicKeySecp256k1: 'synthetic-public-key',
      publicKeyAddress: 'synthetic-address',
      privKey: 'synthetic-private-key',
      viewingKey: 'synthetic-viewing-key',
    );
    const hd = HdCoinKeyInfo(coin: 'synthetic-coin', addresses: [address]);
    final standardResponse = GetPrivateKeysResponse.standard(
      mmrpc: '2.0',
      keys: [standard],
    );
    final hdResponse = GetPrivateKeysResponse.hd(mmrpc: '2.0', keys: [hd]);
    final request = GetPrivateKeysRequest(
      rpcPass: 'synthetic-rpc-password',
      coins: ['synthetic-coin'],
    );
    for (final value in [
      standard,
      address,
      hd,
      standardResponse,
      hdResponse,
      request,
    ]) {
      expect(value.toString(), isNot(contains('synthetic-')));
    }
    expect(standard.toJson()['priv_key'], 'synthetic-private-key');
    expect(address.toJson()['priv_key'], 'synthetic-private-key');
    expect(
      CoinKeyInfo.fromJson(standard.toJson()).viewingKey,
      'synthetic-viewing-key',
    );
    final restoredAddress = HdAddressInfo.fromJson(address.toJson());
    expect(restoredAddress.viewingKey, 'synthetic-viewing-key');
    expect(restoredAddress.zDerivationPath, 'synthetic-shielded-path');
    expect(
      standardResponse.toJson().toString(),
      contains('synthetic-private-key'),
    );
    expect(hdResponse.toJson().toString(), contains('synthetic-private-key'));
    expect(request.toJson()['rpc_pass'], 'synthetic-rpc-password');
  });
}
