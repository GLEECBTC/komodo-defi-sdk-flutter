import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
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

Map<String, dynamic> _trc20Config() => {
  'coin': 'USDT-TRC20',
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

void main() {
  group('ActivationManager gas-free activation lifecycle', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockAssetHistory assetHistory;
    late _MockAssetLookup assetLookup;
    late _MockBalanceManager balanceManager;
    late _MockConfigService configService;
    late _MockAssetsUpdateManager assetsUpdateManager;
    late _MockActivatedAssetsCache cache;
    late GaslessCapabilityRegistry gaslessCapabilities;

    final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
    final child = Asset.fromJson(_trc20Config(), knownIds: {parent.id});

    const provider = TronGaslessProviderConfig(
      baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
      service: GaslessServiceKomodoProxy(),
      serviceProvider: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
    );

    ActivationManager build() => ActivationManager(
      client,
      auth,
      assetHistory,
      assetLookup,
      balanceManager,
      configService,
      assetsUpdateManager,
      cache,
      tronGaslessProvider: provider,
      gaslessCapabilities: gaslessCapabilities,
    );

    setUpAll(() {
      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(
        const WalletId(
          name: 'fallback',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
      );
      registerFallbackValue(child);
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
      gaslessCapabilities = GaslessCapabilityRegistry(
        configuredAssetIds: const {'USDT-TRC20'},
        pinnedProviderAddress: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
      );

      when(() => auth.currentUser).thenAnswer(
        (_) async => const KdfUser(
          walletId: WalletId(
            name: 'wallet',
            pubkeyHash: 'wallet-pubkey',
            authOptions: AuthOptions(
              derivationMethod: DerivationMethod.hdWallet,
            ),
          ),
          isBip39Seed: true,
        ),
      );
      when(
        () => assetHistory.addAssetToWallet(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => balanceManager.precacheBalance(any()),
      ).thenAnswer((_) async {});
      when(() => cache.invalidate()).thenReturn(null);
      // `_groupByPrimary` resolves a token's parent via the lookup; return TRX
      // so [TRX, USDT-TRC20] groups as one platform+child group.
      when(() => assetLookup.fromId(parent.id)).thenReturn(parent);
    });

    test(
      'already-active capability succeeds only after account status',
      () async {
        // Both TRX and USDT-TRC20 are already active in KDF. With a gasless
        // provider configured and the per-session refresh not yet attempted,
        // `activateAssets` does NOT short-circuit; it runs the strategy, which
        // skips the already-active child and yields no terminal event. The
        // manager must synthesise a terminal completion so the coordinator's
        // Future resolves instead of hanging forever.
        // Stub both the no-arg form (used by SmartAssetActivator._isAssetActive)
        // and the forceRefresh form (used by _checkActivationStatus).
        when(
          () => cache.getActivatedAssetIds(),
        ).thenAnswer((_) async => {parent.id, child.id});
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => {parent.id, child.id});
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          if (request['method'] == 'gasless::configure') {
            return {
              'mmrpc': '2.0',
              'result': {
                'platform_coin': 'TRX',
                'service_provider': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
                'tokens': [
                  {
                    'coin': 'USDT-TRC20',
                    'account_status': {
                      'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
                      'active': true,
                      'on_chain_balance': '0',
                      'transfer_fee': '1',
                      'max_withdrawable': '0',
                      'availability': 'available',
                    },
                  },
                ],
              },
            };
          }
          expect(request['method'], 'gasless::account_status');
          return {
            'mmrpc': '2.0',
            'result': {
              'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
              'active': true,
              'on_chain_balance': '0',
              'frozen_balance': '0',
              'spendable_balance': '0',
              'transfer_fee': '1',
              'max_withdrawable': '0',
              'availability': 'available',
            },
          };
        });

        final manager = build();

        // Precondition: a refresh is pending for the token.
        expect(manager.shouldRefreshTronGaslessActivation(child), isTrue);

        final progress = await manager
            .activateAssets([parent, child])
            .toList()
            .timeout(const Duration(seconds: 5));

        // The stream MUST emit a terminal success event.
        expect(
          progress.where((p) => p.isComplete && p.isSuccess),
          isNotEmpty,
          reason: 'must emit a terminal success so the coordinator never hangs',
        );
        // And the refresh flag must be cleared so we never re-enter this path
        // (which would otherwise loop / re-hang) for the rest of the session.
        expect(manager.shouldRefreshTronGaslessActivation(child), isFalse);
      },
    );

    test(
      'legacy KDF falls back only when configure method is unavailable',
      () async {
        when(
          () => cache.getActivatedAssetIds(),
        ).thenAnswer((_) async => {parent.id, child.id});
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => {parent.id, child.id});
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as Map<String, dynamic>;
          if (request['method'] == 'gasless::configure') {
            return {
              'mmrpc': '2.0',
              'error': 'No such method',
              'error_type': 'NoSuchMethod',
            };
          }
          expect(request['method'], 'gasless::account_status');
          return {
            'mmrpc': '2.0',
            'result': {
              'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
              'active': true,
              'on_chain_balance': '0',
              'frozen_balance': '0',
              'spendable_balance': '0',
              'transfer_fee': '1',
              'max_withdrawable': '0',
              'availability': 'available',
              'service_provider': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
            },
          };
        });

        final manager = build();
        final progress = await manager.activateAssets([parent, child]).toList();

        expect(progress.last.isSuccess, isTrue);
        expect(manager.shouldRefreshTronGaslessActivation(child), isFalse);
        verify(
          () => client.executeRpc(
            any(
              that: predicate<Map<String, dynamic>>(
                (request) => request['method'] == 'gasless::configure',
              ),
            ),
          ),
        ).called(1);
      },
    );

    test('legacy fallback rejects every non-method-missing error', () async {
      when(
        () => cache.getActivatedAssetIds(),
      ).thenAnswer((_) async => {parent.id, child.id});
      when(
        () => cache.getActivatedAssetIds(
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((_) async => {parent.id, child.id});
      when(() => client.executeRpc(any())).thenAnswer(
        (_) async => {
          'mmrpc': '2.0',
          'error': 'Provider authentication rejected',
          'error_type': 'Unauthorized',
        },
      );

      final manager = build();
      final progress = await manager.activateAssets([parent, child]).toList();

      expect(progress.last.isError, isTrue);
      expect(manager.shouldRefreshTronGaslessActivation(child), isTrue);
      verify(() => client.executeRpc(any())).called(1);
    });

    test('already-active runtime performs real reconfiguration and remains '
        'unconfirmed when account status is unavailable', () async {
      when(
        () => cache.getActivatedAssetIds(),
      ).thenAnswer((_) async => {parent.id, child.id});
      when(
        () => cache.getActivatedAssetIds(
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((_) async => {parent.id, child.id});
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as Map<String, dynamic>;
        if (request['method'] == 'gasless::account_status') {
          throw StateError('GaslessNotConfigured');
        }
        if (request['method'] == 'gasless::configure') {
          return {
            'mmrpc': '2.0',
            'result': {
              'platform_coin': 'TRX',
              'service_provider': 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
              'tokens': [
                {
                  'coin': 'USDT-TRC20',
                  'account_status': {
                    'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
                    'on_chain_balance': '0',
                    'availability': 'available',
                  },
                },
              ],
            },
          };
        }
        throw StateError('Unexpected method: ${request['method']}');
      });

      final manager = build();
      final progress = await manager.activateAssets([parent, child]).toList();

      expect(progress.last.isError, isTrue);
      expect(manager.shouldRefreshTronGaslessActivation(child), isTrue);
      verify(
        () => client.executeRpc(
          any(
            that: predicate<Map<String, dynamic>>(
              (request) => request['method'] == 'gasless::configure',
            ),
          ),
        ),
      ).called(1);
      verifyNever(
        () => client.executeRpc(
          any(
            that: predicate<Map<String, dynamic>>(
              (request) => request['method'] == 'enable_eth_with_tokens',
            ),
          ),
        ),
      );
    });
  });
}
