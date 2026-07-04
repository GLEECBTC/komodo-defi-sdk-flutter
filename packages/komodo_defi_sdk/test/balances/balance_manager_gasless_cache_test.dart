import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
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
  late Asset trc20Asset;

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

    final trxParent = Asset.fromJson(_trxConfig(), knownIds: const {});
    trc20Asset = Asset.fromJson(_trc20Config(), knownIds: {trxParent.id});

    when(
      () => auth.authStateChanges,
    ).thenAnswer((_) => const Stream<KdfUser?>.empty());
    when(() => auth.currentUser).thenAnswer(
      (_) async => const KdfUser(
        walletId: WalletId(
          name: 'w',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        ),
        isBip39Seed: false,
      ),
    );
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
    );
  });

  tearDown(() async {
    await manager.dispose();
  });

  group('BalanceManager gasless custody cache', () {
    test(
      'custody success populates cache; a later transient failure returns the '
      'cached custody value, not the EOA balance',
      () async {
        when(
          () => client.executeRpc(any()),
        ).thenAnswer((_) async => _accountStatusJson());

        final custody = await manager.getBalance(trc20Asset.id);
        expect(custody.total, Decimal.parse('100'));
        expect(custody.spendable, Decimal.parse('98.5'));
        expect(custody.unspendable, Decimal.parse('1.5'));

        when(
          () => client.executeRpc(any()),
        ).thenThrow(Exception('TronRpcUnavailable: node not responding'));

        final afterFailure = await manager.getBalance(trc20Asset.id);
        expect(afterFailure.total, Decimal.parse('100'));
        expect(afterFailure.spendable, Decimal.parse('98.5'));
        // The custody-sourced cache is served without falling back to the EOA
        // pubkeys balance.
        verifyNever(() => pubkeyManager.getPubkeys(trc20Asset));
      },
    );

    test('first-ever fetch failure with no cache falls back to EOA', () async {
      when(
        () => client.executeRpc(any()),
      ).thenThrow(Exception('TronRpcUnavailable: node not responding'));

      final balance = await manager.getBalance(trc20Asset.id);
      expect(balance, eoaBalance);
      verify(() => pubkeyManager.getPubkeys(trc20Asset)).called(1);
    });

    test('a permanent GaslessNotConfigured error unmarks the custody cache and '
        'degrades to the EOA balance', () async {
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
      expect(balance, eoaBalance);
      verify(() => pubkeyManager.getPubkeys(trc20Asset)).called(1);
    });

    test('precacheBalance keeps a custody-sourced cache on transient failure '
        'instead of overwriting it with the EOA balance', () async {
      when(
        () => client.executeRpc(any()),
      ).thenAnswer((_) async => _accountStatusJson());
      await manager.getBalance(trc20Asset.id);

      when(
        () => client.executeRpc(any()),
      ).thenThrow(Exception('TronRpcUnavailable: node not responding'));

      await manager.precacheBalance(trc20Asset);

      expect(manager.lastKnown(trc20Asset.id)?.total, Decimal.parse('100'));
      verifyNever(() => pubkeyManager.getPubkeys(trc20Asset));
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
  });
}
