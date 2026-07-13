import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
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

GaslessAccountStatusResponse _status({
  String? provider = _provider,
  String address = 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
  GaslessAccountAvailability availability =
      GaslessAccountAvailability.available,
  bool complete = true,
}) => GaslessAccountStatusResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'gasfree_address': address,
    'on_chain_balance': '10',
    'availability': availability.wireValue,
    if (provider != null) 'service_provider': provider,
    if (complete) ...{
      'active': true,
      'frozen_balance': '1',
      'spendable_balance': '9',
      'transfer_fee': '1',
      'max_withdrawable': '8',
    },
  },
});

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
    expect(
      capabilities.receiveEvidenceFor(asset.id),
      GaslessReceiveEvidence.boundRelayV2,
    );

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
      capabilities.receiveEvidenceFor(asset.id),
      GaslessReceiveEvidence.none,
    );

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

  test(
    'status attestation enables wallet receive but not bound integrations',
    () {
      final asset = token();
      final capabilities = registry();

      expect(
        capabilities.markStatusAttestedFor(asset, identity(asset), _status()),
        isTrue,
      );
      expect(capabilities.isReady(asset.id), isFalse);
      expect(capabilities.canReceiveGasless(asset.id), isFalse);
      expect(capabilities.canReceiveGaslessFromStatus(asset.id), isTrue);
      expect(
        capabilities.receiveEvidenceFor(asset.id),
        GaslessReceiveEvidence.statusAttestedV1,
      );
    },
  );

  test('status attestation requires provider identity and complete fields', () {
    final asset = token();
    final missingProvider = registry();
    final incomplete = registry();

    expect(
      missingProvider.markStatusAttestedFor(
        asset,
        identity(asset),
        _status(provider: null),
      ),
      isFalse,
    );
    expect(
      missingProvider.capabilityFor(asset).reasonCode,
      'provider_identity_mismatch',
    );
    expect(
      incomplete.markStatusAttestedFor(
        asset,
        identity(asset),
        _status(complete: false),
      ),
      isFalse,
    );
    expect(incomplete.canReceiveGaslessFromStatus(asset.id), isFalse);
  });

  test('legacy boolean availability never enables receive', () {
    final asset = token();
    final capabilities = registry();
    final legacyStatus = GaslessAccountStatusResponse.parse({
      'mmrpc': '2.0',
      'result': {
        ...(_status().toJson()['result'] as Map<String, dynamic>),
        'provider_available': true,
      }..remove('availability'),
    });

    expect(legacyStatus.hasExplicitAvailability, isFalse);
    expect(
      capabilities.markStatusAttestedFor(asset, identity(asset), legacyStatus),
      isFalse,
    );
    expect(capabilities.canReceiveGaslessFromStatus(asset.id), isFalse);
    expect(
      capabilities.capabilityFor(asset).reasonCode,
      'availability_unattested',
    );
  });

  test('typed KDF mismatches become stable security reasons', () {
    final asset = token();
    for (final entry in const {
      'TokenDecimalsMismatch': 'token_decimals_mismatch',
      'CustodyAddressMismatch': 'custody_address_mismatch',
      'ProviderIdentityMismatch': 'provider_identity_mismatch',
    }.entries) {
      final capabilities = registry();
      final error = GeneralErrorResponse.parse({
        'mmrpc': '2.0',
        'error': 'redacted',
        'error_type': entry.key,
      });

      expect(capabilities.markAccountStatusError(asset.id, error), isTrue);
      expect(capabilities.capabilityFor(asset).reasonCode, entry.value);
      expect(
        capabilities.capabilityFor(asset).state,
        GaslessCapabilityState.securityMismatch,
      );
    }
  });

  test('sensitive refresh revokes evidence on custody mismatch', () {
    final asset = token();
    final capabilities = registry();
    capabilities.markStatusAttestedFor(asset, identity(asset), _status());

    expect(
      capabilities.refreshStatusAttestation(
        asset.id,
        _status(),
        expectedGasfreeAddress: 'TDifferentCustodyAddress',
      ),
      isFalse,
    );
    expect(capabilities.canReceiveGaslessFromStatus(asset.id), isFalse);
    expect(
      capabilities.capabilityFor(asset).reasonCode,
      'custody_address_mismatch',
    );
  });

  test('provider outage preserves candidate but revokes receive evidence', () {
    final asset = token();
    final capabilities = registry();
    capabilities.markStatusAttestedFor(asset, identity(asset), _status());

    expect(
      capabilities.refreshStatusAttestation(
        asset.id,
        _status(
          provider: null,
          availability: GaslessAccountAvailability.providerUnreachable,
          complete: false,
        ),
        expectedGasfreeAddress: 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
      ),
      isFalse,
    );
    expect(capabilities.canAccessExistingCustody(asset.id), isTrue);
    expect(capabilities.canReceiveGaslessFromStatus(asset.id), isFalse);
    expect(
      capabilities.capabilityFor(asset).reasonCode,
      'provider_unreachable',
    );
  });

  test('pending and unsupported availability remain recovery-only', () {
    final asset = token();
    for (final entry in const {
      GaslessAccountAvailability.pendingTransfer: 'pending_transfer',
      GaslessAccountAvailability.tokenUnsupported: 'token_unsupported',
    }.entries) {
      final capabilities = registry();

      expect(
        capabilities.markStatusAttestedFor(
          asset,
          identity(asset),
          _status(provider: null, availability: entry.key, complete: false),
        ),
        isFalse,
      );
      expect(capabilities.canAccessExistingCustody(asset.id), isTrue);
      expect(capabilities.canReceiveGaslessFromStatus(asset.id), isFalse);
      expect(capabilities.capabilityFor(asset).reasonCode, entry.value);
    }
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
