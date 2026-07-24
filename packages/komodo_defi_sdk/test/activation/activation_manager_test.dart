import 'dart:async';

import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockAssetHistory extends Mock implements AssetHistoryStorage {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockBalanceManager extends Mock implements IBalanceManager {}

class _MockConfigService extends Mock implements ActivationConfigService {}

class _MockAssetsUpdateManager extends Mock
    implements KomodoAssetsUpdateManager {}

class _MockActivatedAssetsCache extends Mock implements ActivatedAssetsCache {}

const _provider = 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E';
const _custody = 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF';
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

Map<String, dynamic> _trc20Config({bool gaslessEnabled = true}) => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'gasless': {'enabled': gaslessEnabled, 'transfer_max_fee': '5'},
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': 'TRX', 'contract_address': _contract},
  },
  'contract_address': _contract,
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _availableStatus({bool active = true}) => {
  'mmrpc': '2.0',
  'result': {
    'gasfree_address': _custody,
    'service_provider': _provider,
    'availability': 'available',
    'active': active,
    'on_chain_balance': '25',
    'frozen_balance': '0',
    'spendable_balance': '25',
    'transfer_fee': '1',
    'max_withdrawable': '24',
  },
};

Map<String, dynamic> _pendingStatus() => {
  'mmrpc': '2.0',
  'result': {
    'gasfree_address': _custody,
    'service_provider': _provider,
    'availability': 'pending_transfer',
    'active': true,
    'on_chain_balance': '25',
    'frozen_balance': '5',
    'spendable_balance': '20',
    'transfer_fee': '1',
  },
};

void main() {
  group('ActivationManager final GasFree activation contract', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockAssetHistory assetHistory;
    late _MockAssetLookup assetLookup;
    late _MockBalanceManager balanceManager;
    late _MockConfigService configService;
    late _MockAssetsUpdateManager assetsUpdateManager;
    late _MockActivatedAssetsCache cache;
    late GaslessCapabilityRegistry capabilities;
    late KdfUser currentUser;
    late List<String> calledMethods;

    final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
    final child = Asset.fromJson(_trc20Config(), knownIds: {parent.id});

    const providerConfig = TronGaslessProviderConfig(
      baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
      service: GaslessServiceKomodoProxy(),
      serviceProvider: _provider,
    );

    ActivationManager buildManager() => ActivationManager(
      client,
      auth,
      assetHistory,
      assetLookup,
      balanceManager,
      configService,
      assetsUpdateManager,
      cache,
      tronGaslessProvider: providerConfig,
      gaslessCapabilities: capabilities,
    );

    void stubAlreadyActive() {
      when(
        () => cache.getActivatedAssetIds(),
      ).thenAnswer((_) async => {parent.id, child.id});
      when(
        () => cache.getActivatedAssetIds(
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((_) async => {parent.id, child.id});
    }

    setUpAll(() {
      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(child);
      registerFallbackValue(
        const WalletId(
          name: 'fallback',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
      );
    });

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      assetHistory = _MockAssetHistory();
      assetLookup = _MockAssetLookup();
      balanceManager = _MockBalanceManager();
      configService = _MockConfigService();
      assetsUpdateManager = _MockAssetsUpdateManager();
      cache = _MockActivatedAssetsCache();
      capabilities = GaslessCapabilityRegistry(
        configuredAssetIds: const {'USDT-TRC20'},
        pinnedProviderAddress: _provider,
      );
      calledMethods = [];
      currentUser = const KdfUser(
        walletId: WalletId(
          name: 'wallet',
          pubkeyHash: 'wallet-pubkey',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
        isBip39Seed: true,
      );

      when(() => auth.currentUser).thenAnswer((_) async => currentUser);
      when(() => assetLookup.fromId(parent.id)).thenReturn(parent);
      when(
        () => assetHistory.addAssetToWallet(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => balanceManager.precacheBalance(any()),
      ).thenAnswer((_) async {});
      when(() => cache.invalidate()).thenReturn(null);
    });

    test(
      'already-active token probes status without runtime configure',
      () async {
        stubAlreadyActive();
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          calledMethods.add(request['method'] as String);
          return _availableStatus(active: false);
        });

        final manager = buildManager();
        final progress = await manager
            .activateAssets([parent, child])
            .toList()
            .timeout(const Duration(seconds: 5));

        expect(progress.last.isSuccess, isTrue);
        expect(calledMethods, ['gasless::account_status']);
        expect(capabilities.isReady(child.id), isTrue);
        expect(capabilities.statusFor(child.id)?.active, isFalse);
        expect(manager.shouldRefreshTronGaslessActivation(child), isFalse);
      },
    );

    test(
      'Trezor activation keeps the configured token on Standard TRON',
      () async {
        stubAlreadyActive();
        currentUser = const KdfUser(
          walletId: WalletId(
            name: 'trezor-wallet',
            pubkeyHash: 'trezor-pubkey',
            authOptions: AuthOptions(
              derivationMethod: DerivationMethod.hdWallet,
              privKeyPolicy: PrivateKeyPolicy.trezor(),
            ),
          ),
          isBip39Seed: true,
        );

        final progress = await buildManager().activateAssets([
          parent,
          child,
        ]).toList();

        expect(progress.last.isSuccess, isTrue);
        expect(calledMethods, isEmpty);
        expect(capabilities.isReady(child.id), isFalse);
      },
    );

    test(
      'first activation serializes only the documented GasFree fields',
      () async {
        Map<String, dynamic>? activationRequest;
        when(
          () => cache.getActivatedAssetIds(),
        ).thenAnswer((_) async => <AssetId>{});
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => {parent.id, child.id});
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          calledMethods.add(request['method'] as String);
          if (request['method'] == 'enable_eth_with_tokens') {
            activationRequest = request;
            return {
              'mmrpc': '2.0',
              'result': {
                'current_block': 1,
                'wallet_balance': {
                  'wallet_type': 'iguana',
                  'accounts': <Map<String, dynamic>>[],
                },
                'nfts_infos': <String, dynamic>{},
              },
            };
          }
          return _availableStatus();
        });

        final progress = await buildManager().activateAssets([
          parent,
          child,
        ]).toList();

        expect(progress.last.isSuccess, isTrue);
        expect(calledMethods, [
          'enable_eth_with_tokens',
          'gasless::account_status',
        ]);
        final params = activationRequest!['params'] as Map<String, dynamic>;
        final provider =
            params['tron_gasless_provider'] as Map<String, dynamic>;
        expect(
          provider.keys,
          unorderedEquals({
            'base_url',
            'service',
            'service_provider',
            'request_timeout_ms',
            'status_poll_interval_ms',
          }),
        );
        expect(provider, {
          'base_url': 'https://quicknode.gleec.com/gasfree/tron',
          'service': 'komodo_proxy',
          'service_provider': _provider,
          'request_timeout_ms': 15000,
          'status_poll_interval_ms': 3000,
        });
        final tokens =
            params['erc20_tokens_requests'] as List<Map<String, dynamic>>;
        expect(tokens.single['gasless'], {
          'enabled': true,
          'transfer_max_fee': '5',
        });
      },
    );

    test(
      'TRX-only activation installs the provider before any token',
      () async {
        Map<String, dynamic>? activationRequest;
        when(
          () => cache.getActivatedAssetIds(),
        ).thenAnswer((_) async => <AssetId>{});
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => {parent.id});
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          calledMethods.add(request['method'] as String);
          activationRequest = request;
          return {
            'mmrpc': '2.0',
            'result': {
              'current_block': 1,
              'wallet_balance': {
                'wallet_type': 'iguana',
                'accounts': <Map<String, dynamic>>[],
              },
              'nfts_infos': <String, dynamic>{},
            },
          };
        });

        final progress = await buildManager().activateAsset(parent).toList();

        expect(progress.last.isSuccess, isTrue);
        expect(calledMethods, ['enable_eth_with_tokens']);
        final params = activationRequest!['params'] as Map<String, dynamic>;
        expect(params['tron_gasless_provider'], {
          'base_url': 'https://quicknode.gleec.com/gasfree/tron',
          'service': 'komodo_proxy',
          'service_provider': _provider,
          'request_timeout_ms': 15000,
          'status_poll_interval_ms': 3000,
        });
        expect(params['erc20_tokens_requests'], isEmpty);
      },
    );

    test(
      'an explicit disabled token config cannot be overridden by rollout IDs',
      () async {
        final disabledChild = Asset.fromJson(
          _trc20Config(gaslessEnabled: false),
          knownIds: {parent.id},
        );
        Map<String, dynamic>? activationRequest;
        when(
          () => cache.getActivatedAssetIds(),
        ).thenAnswer((_) async => <AssetId>{});
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => {parent.id, disabledChild.id});
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          calledMethods.add(request['method'] as String);
          activationRequest = request;
          return {
            'mmrpc': '2.0',
            'result': {
              'current_block': 1,
              'wallet_balance': {
                'wallet_type': 'iguana',
                'accounts': <Map<String, dynamic>>[],
              },
              'nfts_infos': <String, dynamic>{},
            },
          };
        });

        final progress = await buildManager().activateAssets([
          parent,
          disabledChild,
        ]).toList();

        expect(progress.last.isSuccess, isTrue);
        expect(calledMethods, ['enable_eth_with_tokens']);
        final params = activationRequest!['params'] as Map<String, dynamic>;
        final tokens =
            params['erc20_tokens_requests'] as List<Map<String, dynamic>>;
        expect(tokens.single, isNot(contains('gasless')));
        expect(capabilities.isConfigured(disabledChild), isFalse);
      },
    );

    test(
      'GaslessNotConfigured requires reactivation but preserves Standard TRON',
      () async {
        stubAlreadyActive();
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          calledMethods.add(request['method'] as String);
          return {
            'mmrpc': '2.0',
            'error': 'redacted',
            'error_type': 'GaslessNotConfigured',
            'error_data': null,
          };
        });

        final progress = await buildManager().activateAssets([
          parent,
          child,
        ]).toList();

        expect(progress.last.isSuccess, isTrue);
        expect(calledMethods, ['gasless::account_status']);
        expect(
          capabilities.capabilityFor(child).state,
          GaslessCapabilityState.disabled,
        );
        expect(
          buildManager().shouldRefreshTronGaslessActivation(child),
          isFalse,
        );
      },
    );

    test(
      'pending transfer retains the typed status and blocks GasFree',
      () async {
        stubAlreadyActive();
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          calledMethods.add(request['method'] as String);
          return _pendingStatus();
        });

        final progress = await buildManager().activateAssets([
          parent,
          child,
        ]).toList();

        expect(progress.last.isSuccess, isTrue);
        expect(calledMethods, ['gasless::account_status']);
        expect(
          capabilities.capabilityFor(child).state,
          GaslessCapabilityState.temporarilyUnavailable,
        );
        expect(
          capabilities.statusFor(child.id)?.availability,
          GaslessAccountAvailability.pendingTransfer,
        );
        expect(capabilities.statusFor(child.id)?.frozenBalance.toString(), '5');
        expect(capabilities.canSendGasless(child.id), isFalse);
      },
    );

    test('in-flight status cannot cross a wallet reset', () async {
      final statusStarted = Completer<void>();
      final statusResponse = Completer<Map<String, dynamic>>();
      stubAlreadyActive();
      when(() => client.executeRpc(any())).thenAnswer((_) async {
        statusStarted.complete();
        return statusResponse.future;
      });

      final manager = buildManager();
      final pending = manager.activateAssets([parent, child]).toList();
      await statusStarted.future;
      manager.resetActivationSessionState();
      currentUser = const KdfUser(
        walletId: WalletId(
          name: 'wallet-b',
          pubkeyHash: 'wallet-b-pubkey',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
        isBip39Seed: true,
      );
      statusResponse.complete(_availableStatus());

      final progress = await pending;
      expect(progress.last.isError, isTrue);
      expect(capabilities.statusFor(child.id), isNull);
      expect(capabilities.isReady(child.id), isFalse);
    });
  });
}
