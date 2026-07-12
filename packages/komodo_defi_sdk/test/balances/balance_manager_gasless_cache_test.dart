import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _MockApiClient extends Mock implements ApiClient {}

class _MockCustodyBalanceReader extends Mock
    implements GaslessCustodyBalanceReader {}

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

Map<String, dynamic> _accountStatusJson({
  String onChain = '100',
  String frozen = '1.5',
  String spendable = '98.5',
}) => {
  'mmrpc': '2.0',
  'result': {
    'gasfree_address': 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
    'active': true,
    'on_chain_balance': onChain,
    'frozen_balance': frozen,
    'spendable_balance': spendable,
    'transfer_fee': '1.5',
    'max_withdrawable': '97',
    'provider_available': true,
  },
};

void main() {
  late _MockAuth auth;
  late _MockActivationCoordinator activation;
  late _MockPubkeyManager pubkeyManager;
  late _MockAssetLookup assetLookup;
  late _MockEventStreamingManager eventStreamingManager;
  late _MockApiClient client;
  late BalanceManager manager;
  late GaslessCapabilityRegistry gaslessCapabilities;
  late Asset trc20Asset;
  late StreamController<KdfUser?> authChanges;
  late KdfUser? currentUser;

  const walletA = KdfUser(
    walletId: WalletId(
      name: 'wallet-a',
      pubkeyHash: 'wallet-a-pubkey',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
  );
  const walletB = KdfUser(
    walletId: WalletId(
      name: 'wallet-b',
      pubkeyHash: 'wallet-b-pubkey',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
  );

  final eoaBalance = BalanceInfo(
    total: Decimal.parse('5'),
    spendable: Decimal.parse('5'),
    unspendable: Decimal.zero,
  );

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    final trxParent = Asset.fromJson(_trxConfig(), knownIds: const {});
    final fallbackAsset = Asset.fromJson(
      _trc20Config(),
      knownIds: {trxParent.id},
    );
    registerFallbackValue(fallbackAsset.id);
    registerFallbackValue(fallbackAsset);
  });

  setUp(() {
    auth = _MockAuth();
    activation = _MockActivationCoordinator();
    pubkeyManager = _MockPubkeyManager();
    assetLookup = _MockAssetLookup();
    eventStreamingManager = _MockEventStreamingManager();
    client = _MockApiClient();
    authChanges = StreamController<KdfUser?>.broadcast(sync: true);
    currentUser = walletA;

    final trxParent = Asset.fromJson(_trxConfig(), knownIds: const {});
    trc20Asset = Asset.fromJson(_trc20Config(), knownIds: {trxParent.id});
    gaslessCapabilities =
        GaslessCapabilityRegistry(
          configuredAssetIds: const {'USDT-TRC20'},
          pinnedProviderAddress: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
        )..markReadyFor(
          trc20Asset,
          GaslessCapabilityIdentity(
            assetId: trc20Asset.id,
            platform: 'TRX',
            contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
            providerAddress: 'TKtWbdzEq5ss9vTS9kwRhBp5mXmBfBns3E',
            walletPubkeyHash: 'wallet-pubkey',
            walletType: GaslessWalletType.softwareIguana,
            derivationPath: '',
          ),
        );

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => currentUser);
    when(() => assetLookup.fromId(trc20Asset.id)).thenReturn(trc20Asset);
    when(() => pubkeyManager.getPubkeys(trc20Asset)).thenAnswer(
      (_) async => AssetPubkeys(
        assetId: trc20Asset.id,
        keys: [
          PubkeyInfo(
            address: 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
            derivationPath: null,
            chain: null,
            balance: eoaBalance,
            coinTicker: trc20Asset.id.id,
          ),
        ],
        availableAddressesCount: 1,
        syncStatus: SyncStatusEnum.success,
      ),
    );

    manager = BalanceManager(
      assetLookup: assetLookup,
      auth: auth,
      pubkeyManager: pubkeyManager,
      activationCoordinator: activation,
      eventStreamingManager: eventStreamingManager,
      client: client,
      gaslessCapabilities: gaslessCapabilities,
    );
  });

  tearDown(() async {
    await manager.dispose();
    await authChanges.close();
  });

  group('BalanceManager gasless custody cache', () {
    test(
      'snapshot success populates total-owned cache; a later transient failure '
      'does not fall back to the EOA-only balance',
      () async {
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) async => _accountStatusJson());

        final custody = await manager.getBalance(trc20Asset.id);
        expect(custody.total, Decimal.parse('105'));
        expect(custody.spendable, Decimal.parse('103.5'));
        expect(custody.unspendable, Decimal.parse('1.5'));

        when(
          () => client.executeRpc(any()),
        ).thenThrow(Exception('TronRpcUnavailable: node not responding'));

        final afterFailure = await manager.getBalance(trc20Asset.id);
        expect(afterFailure.total, Decimal.parse('105'));
        expect(afterFailure.spendable, Decimal.parse('103.5'));
        expect(
          manager.lastKnownGaslessBalanceSnapshot(trc20Asset.id)?.custodyTotal,
          Decimal.parse('100'),
        );
      },
    );

    test('first-ever custody failure never falls back to the EOA', () async {
      when(
        () => client.executeRpc(any()),
      ).thenThrow(Exception('TronRpcUnavailable: node not responding'));

      await expectLater(
        manager.getBalance(trc20Asset.id),
        throwsA(isA<StateError>()),
      );
      verify(() => pubkeyManager.getPubkeys(trc20Asset)).called(1);
    });

    test('snapshot keeps custody and Standard balances distinct', () async {
      when(
        () => client.executeRpc(any()),
      ).thenAnswer((_) async => _accountStatusJson());

      final snapshot = await manager.getGaslessBalanceSnapshot(trc20Asset.id);

      expect(snapshot.custodyTotal, Decimal.parse('100'));
      expect(snapshot.custodySpendable, Decimal.parse('98.5'));
      expect(snapshot.frozenAmount, Decimal.parse('1.5'));
      expect(
        snapshot.standardBalances.single.balance.total,
        Decimal.parse('5'),
      );
      expect(snapshot.totalWalletOwned, Decimal.parse('105'));
      expect(
        snapshot.provenance,
        GaslessBalanceProvenance.authoritativeProvider,
      );
      expect(snapshot.isFresh, isTrue);
    });

    test(
      'unconfirmed capability uses the Standard rail without custody RPC',
      () async {
        gaslessCapabilities.markUnconfirmed(trc20Asset.id);

        expect(await manager.getBalance(trc20Asset.id), eoaBalance);
        verifyNever(() => client.executeRpc(any()));
      },
    );

    test(
      'kill switch restart retains custody through on-chain recovery',
      () async {
        final reader = _MockCustodyBalanceReader();
        when(() => pubkeyManager.getPubkeys(trc20Asset)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: trc20Asset.id,
            keys: [
              PubkeyInfo(
                address: 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
                derivationPath: null,
                chain: null,
                balance: eoaBalance,
                coinTicker: trc20Asset.id.id,
                gasfreeAddress: 'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );
        when(
          () => reader.readBalance(
            trc20Asset,
            'TCtSt8fCkZcVdrGpaVHUr6P8EmdjysswMF',
          ),
        ).thenAnswer((_) async => Decimal.parse('42'));
        final recoveryManager = BalanceManager(
          assetLookup: assetLookup,
          auth: auth,
          pubkeyManager: pubkeyManager,
          activationCoordinator: activation,
          eventStreamingManager: eventStreamingManager,
          client: client,
          gaslessCapabilities: GaslessCapabilityRegistry(
            configuredAssetIds: const {},
          ),
          gaslessCustodyBalanceReader: reader,
        );

        final snapshot = await recoveryManager.getGaslessBalanceSnapshot(
          trc20Asset.id,
        );

        expect(snapshot.custodyTotal, Decimal.parse('42'));
        expect(snapshot.custodySpendable, isNull);
        expect(snapshot.totalWalletOwned, Decimal.parse('47'));
        expect(snapshot.provenance, GaslessBalanceProvenance.onChainOnly);
        verifyNever(() => client.executeRpc(any()));
        await recoveryManager.dispose();
      },
    );

    test(
      'a permanent GaslessNotConfigured error preserves cached custody',
      () async {
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) async => _accountStatusJson());
        await manager.getBalance(trc20Asset.id);

        // The real KDF error envelope: error_type only reaches the substring
        // match via GeneralErrorResponse.toString() embedding the raw response,
        // so pin that load-bearing path rather than a hand-rolled Exception.
        when(() => client.executeRpc(any())).thenAnswer(
          (_) async => <String, dynamic>{
            'mmrpc': '2.0',
            'error': "Coin 'USDT-TRC20' has no GasFree provider configured",
            'error_path': 'gasless',
            'error_trace': 'gasless:80]',
            'error_type': 'GaslessNotConfigured',
            'error_data': 'USDT-TRC20',
            'id': 0,
          },
        );

        final balance = await manager.getBalance(trc20Asset.id);
        expect(balance.total, Decimal.parse('105'));
      },
    );

    test('precacheBalance keeps the total-owned snapshot on transient failure '
        'instead of overwriting it with the EOA-only balance', () async {
      when(
        () => client.executeRpc(any()),
      ).thenAnswer((_) async => _accountStatusJson());
      await manager.getBalance(trc20Asset.id);

      when(
        () => client.executeRpc(any()),
      ).thenThrow(Exception('TronRpcUnavailable: node not responding'));

      await manager.precacheBalance(trc20Asset);

      expect(manager.lastKnown(trc20Asset.id)?.total, Decimal.parse('105'));
    });

    test('non-TRC-20 assets never consult the gasless RPC', () async {
      final atomId = AssetId(
        id: 'ATOM',
        name: 'Cosmos',
        symbol: AssetSymbol(assetConfigId: 'ATOM'),
        chainId: AssetChainId(chainId: 118, decimalsValue: 6),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      );
      final atom = Asset(
        id: atomId,
        protocol: TendermintProtocol.fromJson({
          'type': 'Tendermint',
          'rpc_urls': [
            {'url': 'http://localhost:26657'},
          ],
        }),
        isWalletOnly: false,
        signMessagePrefix: null,
      );
      when(() => assetLookup.fromId(atomId)).thenReturn(atom);
      when(() => pubkeyManager.getPubkeys(atom)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: atomId,
          keys: [
            PubkeyInfo(
              address: 'cosmos1abc',
              derivationPath: null,
              chain: null,
              balance: eoaBalance,
              coinTicker: atomId.id,
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      final balance = await manager.getBalance(atomId);
      expect(balance, eoaBalance);
      verifyNever(() => client.executeRpc(any()));
    });

    test(
      'wallet switch invalidates an in-flight custody snapshot before cache write',
      () async {
        final statusCompleter = Completer<Map<String, dynamic>>();
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) => statusCompleter.future);

        final pending = manager.getGaslessBalanceSnapshot(trc20Asset.id);
        await Future<void>.delayed(Duration.zero);

        currentUser = walletB;
        authChanges.add(walletB);
        statusCompleter.complete(_accountStatusJson());

        await expectLater(
          pending,
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        expect(manager.lastKnownGaslessBalanceSnapshot(trc20Asset.id), isNull);
      },
    );

    test(
      'delayed auth event cannot return wallet A cached custody to wallet B',
      () async {
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) async => _accountStatusJson());
        await manager.getBalance(trc20Asset.id);

        final statusCompleter = Completer<Map<String, dynamic>>();
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) => statusCompleter.future);
        final pending = manager.getBalance(trc20Asset.id);
        await Future<void>.delayed(Duration.zero);

        currentUser = walletB;
        statusCompleter.complete(_accountStatusJson(onChain: '101'));

        await expectLater(pending, throwsA(isA<StateError>()));
      },
    );

    test(
      'wallet switch invalidates an in-flight Standard balance before cache write',
      () async {
        gaslessCapabilities.markUnconfirmed(trc20Asset.id);
        final pubkeysCompleter = Completer<AssetPubkeys>();
        when(
          () => pubkeyManager.getPubkeys(trc20Asset),
        ).thenAnswer((_) => pubkeysCompleter.future);

        final pending = manager.getBalance(trc20Asset.id);
        await Future<void>.delayed(Duration.zero);

        currentUser = walletB;
        pubkeysCompleter.complete(
          AssetPubkeys(
            assetId: trc20Asset.id,
            keys: [
              PubkeyInfo(
                address: 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
                derivationPath: null,
                chain: null,
                balance: eoaBalance,
                coinTicker: trc20Asset.id.id,
              ),
            ],
            availableAddressesCount: 1,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        await expectLater(pending, throwsA(isA<StateError>()));
        expect(manager.lastKnown(trc20Asset.id), isNull);
      },
    );
  });
}
