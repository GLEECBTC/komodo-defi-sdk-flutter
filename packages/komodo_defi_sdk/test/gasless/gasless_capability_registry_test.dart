import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _provider = 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E';
const _contract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _tokenConfig({
  String platform = 'TRX',
  String contract = _contract,
  bool custom = false,
}) => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'is_custom_token': custom,
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': platform, 'contract_address': contract},
  },
  'contract_address': contract,
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

void main() {
  final parent = Asset.fromJson(_trxConfig(), knownIds: const {});

  Asset token({
    String platform = 'TRX',
    String contract = _contract,
    bool custom = false,
  }) => Asset.fromJson(
    _tokenConfig(platform: platform, contract: contract, custom: custom),
    knownIds: {parent.id},
  );

  GaslessCapabilityRegistry registry() => GaslessCapabilityRegistry(
    configuredAssetIds: const {'USDT-TRC20'},
    pinnedProviderAddress: _provider,
  );

  GaslessCapabilityIdentity identity(
    Asset asset, {
    String provider = _provider,
    GaslessWalletType walletType = GaslessWalletType.softwareHd,
    String path = GaslessCapabilityRegistry.canonicalPrimaryDerivationPath,
  }) => GaslessCapabilityIdentity(
    assetId: asset.id,
    platform: 'TRX',
    contractAddress: _contract,
    providerAddress: provider,
    walletPubkeyHash: 'wallet-pubkey',
    walletType: walletType,
    derivationPath: path,
  );

  test('requires the exact canonical asset, network, and contract', () {
    final capabilities = registry();

    expect(capabilities.isConfigured(token()), isTrue);
    expect(capabilities.isConfigured(token(custom: true)), isFalse);
    expect(capabilities.isConfigured(token(platform: 'TRXT')), isFalse);
    expect(capabilities.isConfigured(token(contract: 'TWrong')), isFalse);
  });

  test('binds readiness to the pinned provider and HD primary path', () {
    final asset = token();
    final capabilities = registry();

    expect(capabilities.markReadyFor(asset, identity(asset)), isTrue);
    expect(capabilities.isReady(asset.id), isTrue);
    expect(capabilities.canReceiveGasless(asset.id), isTrue);

    final wrongProvider = registry();
    expect(
      wrongProvider.markReadyFor(
        asset,
        identity(asset, provider: 'TUnexpectedProvider'),
      ),
      isFalse,
    );
    expect(
      wrongProvider.capabilityFor(asset).state,
      GaslessCapabilityState.securityMismatch,
    );

    final secondary = registry();
    expect(
      secondary.markReadyFor(asset, identity(asset, path: "m/44'/195'/0'/0/1")),
      isFalse,
    );
  });

  test('legacy preview proof enables recovery send but never receive', () {
    final asset = token();
    final capabilities = registry();
    expect(capabilities.markProvisionalFor(asset, identity(asset)), isTrue);
    expect(capabilities.isReady(asset.id), isFalse);
    expect(capabilities.canReceiveGasless(asset.id), isFalse);

    expect(
      capabilities.proveLegacyReadyFromSignedPreview(
        asset.id,
        chainId: '728126428',
        tokenContract: _contract,
        providerAddress: _provider,
        walletPubkeyHash: 'wallet-pubkey',
      ),
      isTrue,
    );

    expect(capabilities.isReady(asset.id), isTrue);
    expect(capabilities.canReceiveGasless(asset.id), isFalse);
    expect(
      capabilities.matchesReadyAuthorizationContext(
        asset.id,
        chainId: '728126428',
        tokenContract: _contract,
        providerAddress: _provider,
        walletPubkeyHash: 'wallet-pubkey',
        verificationMode: GaslessVerificationMode.boundRelay,
      ),
      isFalse,
    );
  });

  test('permits Iguana primary without pretending it has an HD path', () {
    final asset = token();
    final capabilities = registry();

    expect(
      capabilities.markReadyFor(
        asset,
        identity(asset, walletType: GaslessWalletType.softwareIguana, path: ''),
      ),
      isTrue,
    );
  });

  test('stale verified identity keeps custody and preview recovery access', () {
    final asset = token();
    final capabilities = registry();
    capabilities.markReadyFor(asset, identity(asset));

    capabilities.markStale(asset.id);

    expect(capabilities.isReady(asset.id), isFalse);
    expect(capabilities.canAccessExistingCustody(asset.id), isTrue);
    expect(capabilities.canAttemptAuthoritativePreview(asset.id), isTrue);
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.stale,
    );
    expect(capabilities.restoreReadyAfterAuthoritativeStatus(asset.id), isTrue);
    expect(capabilities.isReady(asset.id), isTrue);
  });
}
