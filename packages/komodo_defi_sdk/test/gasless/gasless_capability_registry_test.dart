import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

const _provider = 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E';
const _custody = 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF';
const _contract = 'TArbitraryEnrolledTrc20Contract111111111';

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
  String ticker = 'ANY-TRC20',
  bool gaslessEnabled = true,
  bool includeGaslessConfig = true,
}) => {
  'coin': ticker,
  'type': 'TRC-20',
  'name': 'Enrolled token',
  'fname': 'Enrolled token',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  if (includeGaslessConfig)
    'gasless': {'enabled': gaslessEnabled, 'transfer_max_fee': '3.5'},
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': 'TRX', 'contract_address': _contract},
  },
  'contract_address': _contract,
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

GaslessAccountStatusResponse _status(
  GaslessAccountAvailability availability, {
  String gasfreeAddress = _custody,
  String? serviceProvider = _provider,
  String? active = 'true',
  String? frozenBalance = '0',
  String? spendableBalance = '25',
  String? transferFee = '1',
  String? activationFee,
  String? maxWithdrawable = '24',
}) {
  return GaslessAccountStatusResponse.parse({
    'mmrpc': '2.0',
    'result': {
      'gasfree_address': gasfreeAddress,
      'service_provider': serviceProvider,
      'availability': availability.wireValue,
      'active': active == null ? null : active == 'true',
      'on_chain_balance': '25',
      'frozen_balance': frozenBalance,
      'spendable_balance': spendableBalance,
      'transfer_fee': transferFee,
      'activation_fee': activationFee,
      'max_withdrawable': maxWithdrawable,
    },
  });
}

void main() {
  final platform = Asset.fromJson(_trxConfig(), knownIds: const {});

  Asset token({
    String ticker = 'ANY-TRC20',
    bool gaslessEnabled = true,
    bool includeGaslessConfig = true,
  }) => Asset.fromJson(
    _tokenConfig(
      ticker: ticker,
      gaslessEnabled: gaslessEnabled,
      includeGaslessConfig: includeGaslessConfig,
    ),
    knownIds: {platform.id},
  );

  GaslessCapabilityRegistry registry({String? provider = _provider}) =>
      GaslessCapabilityRegistry(pinnedProviderAddress: provider);

  GaslessCapabilityIdentity identity(
    Asset asset, {
    String provider = _provider,
    String walletPubkeyHash = 'wallet-pubkey',
    GaslessWalletType walletType = GaslessWalletType.softwareHd,
    String derivationPath = "m/44'/195'",
  }) => GaslessCapabilityIdentity(
    assetId: asset.id,
    platform: 'TRX',
    contractAddress: _contract,
    providerAddress: provider,
    walletPubkeyHash: walletPubkeyHash,
    walletType: walletType,
    derivationPath: derivationPath,
  );

  test('derives generic TRC20 eligibility from the activated asset config', () {
    final capabilities = registry();

    expect(capabilities.isConfigured(token()), isTrue);
    expect(capabilities.isConfigured(token(gaslessEnabled: false)), isFalse);

    expect(
      capabilities.isConfigured(
        token(ticker: 'ROLLOUT-TRC20', gaslessEnabled: false),
      ),
      isFalse,
    );
    expect(
      capabilities.isConfigured(
        token(ticker: 'ROLLOUT-TRC20', includeGaslessConfig: false),
      ),
      isFalse,
    );
  });

  test('available status authorizes send and receive with an optional pin', () {
    final asset = token();
    final capabilities = registry();
    final inactiveWithoutActivationFee = _status(
      GaslessAccountAvailability.available,
      active: 'false',
    );

    expect(
      capabilities.recordAccountStatus(
        asset,
        identity(asset),
        inactiveWithoutActivationFee,
      ),
      isTrue,
    );
    expect(capabilities.isReady(asset.id), isTrue);
    expect(capabilities.canSendGasless(asset.id), isTrue);
    expect(capabilities.canReceiveGasless(asset.id), isTrue);
    expect(
      capabilities.statusFor(asset.id),
      same(inactiveWithoutActivationFee),
    );
  });

  test('provider discovery is accepted by the generic SDK', () {
    final asset = token();
    final capabilities = registry(provider: null);
    final status = _status(GaslessAccountAvailability.available);

    expect(
      capabilities.bindActivatedIdentity(asset, identity(asset, provider: '')),
      isTrue,
    );
    expect(capabilities.refreshAccountStatus(asset, status), isTrue);
    expect(
      capabilities.bindActivatedIdentity(asset, identity(asset, provider: '')),
      isTrue,
    );
    expect(capabilities.isReady(asset.id), isTrue);

    expect(
      capabilities.refreshAccountStatus(
        asset,
        _status(
          GaslessAccountAvailability.available,
          serviceProvider: 'TChangedProvider',
        ),
      ),
      isFalse,
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.securityMismatch,
    );
  });

  test('an unbound identity is recoverable, not a security mismatch', () {
    // A session reset while the asset stays active leaves `_identities` empty
    // with the asset still configured. That is a caller-ordering condition, not
    // evidence that anything disagrees - and `securityMismatch` is terminal
    // (`canRefreshAccountStatus` refuses it), so latching it here used to
    // permanently disable the gas-free rail for that asset.
    final asset = token();
    final capabilities = registry(provider: null);

    expect(
      capabilities.refreshAccountStatus(
        asset,
        _status(GaslessAccountAvailability.available),
      ),
      isFalse,
      reason: 'no identity is bound, so the refresh cannot succeed',
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.temporarilyUnavailable,
    );
    expect(
      capabilities.canRefreshAccountStatus(asset),
      isTrue,
      reason: 'the asset must stay refreshable once an identity binds',
    );

    // And binding then recovers normally.
    expect(
      capabilities.bindActivatedIdentity(asset, identity(asset, provider: '')),
      isTrue,
    );
    expect(
      capabilities.refreshAccountStatus(
        asset,
        _status(GaslessAccountAvailability.available),
      ),
      isTrue,
    );
  });

  test('generic SDK accepts a non-primary KDF HD source identity', () {
    final asset = token();
    final capabilities = registry();
    final secondaryIdentity = identity(
      asset,
      derivationPath: "m/44'/195'/3'/1/7",
    );

    expect(
      capabilities.recordAccountStatus(
        asset,
        secondaryIdentity,
        _status(GaslessAccountAvailability.available),
      ),
      isTrue,
    );
    expect(capabilities.isReadyFor(secondaryIdentity), isTrue);
  });

  test('generic SDK does not reject a hardware HD status identity', () {
    final asset = token();
    final capabilities = registry();
    final hardwareIdentity = identity(
      asset,
      walletType: GaslessWalletType.hardwareHd,
    );

    expect(
      capabilities.recordAccountStatus(
        asset,
        hardwareIdentity,
        _status(GaslessAccountAvailability.available),
      ),
      isTrue,
    );
    expect(capabilities.isReadyFor(hardwareIdentity), isTrue);
  });

  test('an activation-bound identity can recover after a provider outage', () {
    final asset = token();
    final capabilities = registry();

    expect(capabilities.bindActivatedIdentity(asset, identity(asset)), isTrue);
    capabilities.markAccountStatusError(
      asset.id,
      const GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.providerError,
        message: 'redacted',
      ),
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.temporarilyUnavailable,
    );

    expect(
      capabilities.refreshAccountStatus(
        asset,
        _status(GaslessAccountAvailability.available),
      ),
      isTrue,
    );
    expect(capabilities.isReady(asset.id), isTrue);
  });

  test('a refreshed status cannot replace the wallet custody identity', () {
    final asset = token();
    final capabilities = registry();

    expect(
      capabilities.recordAccountStatus(
        asset,
        identity(asset),
        _status(GaslessAccountAvailability.available),
      ),
      isTrue,
    );
    expect(
      capabilities.refreshAccountStatus(
        asset,
        _status(
          GaslessAccountAvailability.available,
          gasfreeAddress: 'TChangedGasfreeAddress1111111111111',
        ),
      ),
      isFalse,
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.securityMismatch,
    );
  });

  test('a provider mismatch is a hard security state', () {
    final asset = token();
    final capabilities = registry();
    final status = _status(
      GaslessAccountAvailability.available,
      serviceProvider: 'TUnexpectedProvider',
    );

    expect(
      capabilities.recordAccountStatus(
        asset,
        identity(asset, provider: 'TUnexpectedProvider'),
        status,
      ),
      isFalse,
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.securityMismatch,
    );
  });

  test('pending transfer retains provider balance and fee status', () {
    final asset = token();
    final capabilities = registry();
    final status = _status(
      GaslessAccountAvailability.pendingTransfer,
      frozenBalance: '5',
      spendableBalance: '20',
      maxWithdrawable: null,
    );

    expect(
      capabilities.recordAccountStatus(asset, identity(asset), status),
      isTrue,
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.temporarilyUnavailable,
    );
    expect(capabilities.statusFor(asset.id)?.frozenBalance.toString(), '5');
    expect(capabilities.statusFor(asset.id)?.transferFee.toString(), '1');
    expect(capabilities.canSendGasless(asset.id), isFalse);
  });

  test('unsupported status retains the service provider for recovery UI', () {
    final asset = token();
    final capabilities = registry();
    final status = _status(
      GaslessAccountAvailability.tokenUnsupported,
      active: null,
      frozenBalance: null,
      spendableBalance: null,
      transferFee: null,
      maxWithdrawable: null,
    );

    expect(
      capabilities.recordAccountStatus(asset, identity(asset), status),
      isTrue,
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.unsupported,
    );
    expect(capabilities.statusFor(asset.id)?.serviceProvider, _provider);
    expect(capabilities.canAccessExistingCustody(asset.id), isTrue);
  });

  test('provider outage retains only KDF fresh on-chain custody data', () {
    final asset = token();
    final capabilities = registry();
    final status = _status(
      GaslessAccountAvailability.providerUnreachable,
      serviceProvider: null,
      active: null,
      frozenBalance: null,
      spendableBalance: null,
      transferFee: null,
      maxWithdrawable: null,
    );

    expect(
      capabilities.recordAccountStatus(asset, identity(asset), status),
      isTrue,
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.temporarilyUnavailable,
    );
    expect(capabilities.statusFor(asset.id)?.onChainBalance.toString(), '25');
    expect(capabilities.statusFor(asset.id)?.spendableBalance, isNull);
  });

  test('maps exact KDF safety errors without inspecting messages', () {
    final asset = token();
    final capabilities = registry();

    for (final type in [
      GaslessAccountStatusErrorType.providerIdentityMismatch,
      GaslessAccountStatusErrorType.gasfreeAddressMismatch,
      GaslessAccountStatusErrorType.tokenDecimalMismatch,
    ]) {
      expect(
        capabilities.markAccountStatusError(
          asset.id,
          GaslessAccountStatusException(type: type, message: 'redacted'),
        ),
        isTrue,
      );
      expect(
        capabilities.capabilityFor(asset).state,
        GaslessCapabilityState.securityMismatch,
      );
    }
  });

  test('ignores exact-looking error types from generic RPC envelopes', () {
    final asset = token();
    final capabilities = registry();
    final generic = GeneralErrorResponse.parse({
      'error': 'generic error',
      'error_type': 'ProviderIdentityMismatch',
      'error_data': null,
    });

    expect(capabilities.markAccountStatusError(asset.id, generic), isFalse);
    expect(
      capabilities.markAccountStatusError(
        asset.id,
        const GetFeeEstimationRequestErrorCoinNotFoundException(),
      ),
      isFalse,
    );
    expect(
      capabilities.capabilityFor(asset).state,
      GaslessCapabilityState.initial,
    );
  });

  test('wallet reset removes all capability and custody state', () {
    final asset = token();
    final capabilities = registry();
    capabilities.recordAccountStatus(
      asset,
      identity(asset),
      _status(GaslessAccountAvailability.available),
    );

    expect(capabilities.ensureWalletSession('another-wallet'), isFalse);
    expect(capabilities.statusFor(asset.id), isNull);
    expect(capabilities.isReady(asset.id), isFalse);
  });
}
