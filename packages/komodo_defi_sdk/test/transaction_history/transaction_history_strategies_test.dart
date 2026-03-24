import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/etherscan_transaction_history_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/tronscan_transaction_history_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/zhtlc_transaction_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_strategies.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockLocalAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockApiClient extends Mock implements ApiClient {}

Asset _createEvmAsset({
  required String coin,
  required int chainId,
  String type = 'ETH',
  bool isTestnet = false,
}) {
  return Asset.fromJson({
    'coin': coin,
    'type': type,
    'fname': coin,
    'chain_id': chainId,
    'is_testnet': isTestnet,
    'nodes': const [
      {'url': 'https://rpc.example.com'},
    ],
    'swap_contract_address': '0x0000000000000000000000000000000000000001',
    'fallback_swap_contract': '0x0000000000000000000000000000000000000001',
  });
}

Asset _createTrxAsset() {
  return Asset.fromJson({
    'coin': 'TRX',
    'type': 'TRX',
    'name': 'TRON',
    'fname': 'TRON',
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'required_confirmations': 1,
    'derivation_path': "m/44'/195'",
    'explorer_url': 'https://tronscan.org/',
    'explorer_tx_url': '#/transaction/',
    'explorer_address_url': '#/address/',
    'protocol': {
      'type': 'TRX',
      'protocol_data': {'network': 'Mainnet'},
    },
    'nodes': <Map<String, dynamic>>[],
  });
}

Asset _createUsdtTrc20Asset() {
  return Asset.fromJson({
    'coin': 'USDT-TRC20',
    'type': 'TRC-20',
    'name': 'Tether',
    'fname': 'Tether',
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'derivation_path': "m/44'/195'",
    'explorer_url': 'https://tronscan.org/',
    'explorer_tx_url': '#/transaction/',
    'explorer_address_url': '#/address/',
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
  });
}

Asset _createZhtlcAsset() {
  final protocol = ZhtlcProtocol.fromJson(const {
    'type': 'ZHTLC',
    'electrum_servers': [
      {'url': 'lightwalletd.pirate.black', 'port': 9067, 'protocol': 'SSL'},
    ],
  });

  return Asset(
    id: AssetId(
      id: 'ARRR',
      name: 'Pirate Chain',
      symbol: AssetSymbol(assetConfigId: 'ARRR'),
      chainId: AssetChainId(chainId: 1),
      derivationPath: null,
      subClass: CoinSubClass.zhtlc,
    ),
    protocol: protocol,
    isWalletOnly: false,
    signMessagePrefix: null,
  );
}

void main() {
  late PubkeyManager pubkeyManager;
  late KomodoDefiLocalAuth auth;

  setUpAll(() {
    registerFallbackValue(_createTrxAsset());
    registerFallbackValue(
      Uri.parse('https://apilist.tronscanapi.com/api/transfer'),
    );
  });

  setUp(() {
    pubkeyManager = _MockPubkeyManager();
    auth = _MockLocalAuth();
  });

  group('EtherscanProtocolHelper', () {
    const helper = EtherscanProtocolHelper();

    test('supports ETH endpoint and keeps KDF tx history disabled', () {
      final eth = _createEvmAsset(coin: 'ETH', chainId: 1);

      expect(helper.supportsProtocol(eth), isTrue);
      expect(
        helper.getApiUrlForAsset(eth)?.toString(),
        endsWith('/v2/eth_tx_history'),
      );
      expect(helper.shouldEnableTransactionHistory(eth), isFalse);
    });

    test('does not map GLEECT (GRC20) to Etherscan proxy endpoints', () {
      final gleect = _createEvmAsset(
        coin: 'GLEECT',
        chainId: 11169,
        type: 'GRC20',
        isTestnet: true,
      );

      expect(helper.supportsProtocol(gleect), isFalse);
      expect(helper.getApiUrlForAsset(gleect), isNull);
      expect(helper.shouldEnableTransactionHistory(gleect), isFalse);
    });
  });

  group('TransactionHistoryStrategyFactory', () {
    test('selects ZHTLC strategy for ZHTLC asset', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final asset = _createZhtlcAsset();

      final strategy = factory.forAsset(asset);

      expect(strategy, isA<ZhtlcTransactionStrategy>());
    });

    test('ZHTLC strategy wins regardless of registration order', () {
      final asset = _createZhtlcAsset();
      final factory = TransactionHistoryStrategyFactory(
        pubkeyManager,
        auth,
        strategies: [
          const LegacyTransactionStrategy(),
          V2TransactionStrategy(auth),
          EtherscanTransactionStrategy(pubkeyManager: pubkeyManager),
          const ZhtlcTransactionStrategy(),
        ],
      );

      final strategy = factory.forAsset(asset);

      expect(strategy, isA<ZhtlcTransactionStrategy>());
    });

    test('uses Legacy strategy for GRC20 when Etherscan has no endpoint', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final gleect = _createEvmAsset(
        coin: 'GLEECT',
        chainId: 11169,
        type: 'GRC20',
        isTestnet: true,
      );

      final strategy = factory.forAsset(gleect);

      expect(strategy, isA<LegacyTransactionStrategy>());
    });

    test('selects Tronscan strategy for TRX asset', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final trx = _createTrxAsset();

      final strategy = factory.forAsset(trx);

      expect(strategy, isA<TronscanTransactionStrategy>());
    });

    test('selects Tronscan strategy for TRC20 on TRX', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final usdt = _createUsdtTrc20Asset();

      final strategy = factory.forAsset(usdt);

      expect(strategy, isA<TronscanTransactionStrategy>());
    });

    test('Legacy strategy wins over Tronscan when registered first', () {
      final factory = TransactionHistoryStrategyFactory(
        pubkeyManager,
        auth,
        strategies: [
          EtherscanTransactionStrategy(pubkeyManager: pubkeyManager),
          const LegacyTransactionStrategy(),
          TronscanTransactionStrategy(pubkeyManager: pubkeyManager),
          V2TransactionStrategy(auth),
          const ZhtlcTransactionStrategy(),
        ],
      );

      final strategy = factory.forAsset(_createTrxAsset());

      expect(strategy, isA<LegacyTransactionStrategy>());
    });
  });

  group('TronscanTransactionStrategy', () {
    test('retries on 429 with Retry-After then succeeds', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      var callCount = 0;
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            'rate limited',
            429,
            headers: {'retry-after': '0'},
          );
        }
        return http.Response(jsonEncode({'data': <Object>[], 'total': 0}), 200);
      });

      final trx = _createTrxAsset();
      when(() => pubkeyManager.getPubkeys(trx)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: trx.id,
          keys: [
            PubkeyInfo(
              address: 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo.zero(),
              coinTicker: 'TRX',
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      final strategy = TronscanTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        apiHostOverride: 'apilist.tronscanapi.com',
      );

      final response = await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(callCount, 2);
      expect(response.transactions, isEmpty);
      verify(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).called(2);
    });

    test('sends TRON-PRO-API-KEY when tronProApiKey is set', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async =>
            http.Response(jsonEncode({'data': <Object>[], 'total': 0}), 200),
      );

      final trx = _createTrxAsset();
      when(() => pubkeyManager.getPubkeys(trx)).thenAnswer(
        (_) async => AssetPubkeys(
          assetId: trx.id,
          keys: [
            PubkeyInfo(
              address: 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
              derivationPath: null,
              chain: null,
              balance: BalanceInfo.zero(),
              coinTicker: 'TRX',
            ),
          ],
          availableAddressesCount: 1,
          syncStatus: SyncStatusEnum.success,
        ),
      );

      final strategy = TronscanTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        tronProApiKey: 'test-key',
        apiHostOverride: 'apilist.tronscanapi.com',
      );

      await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      final captured =
          verify(
                () => httpClient.get(
                  any(),
                  headers: captureAny(named: 'headers'),
                ),
              ).captured.single
              as Map<String, String>;

      expect(captured['TRON-PRO-API-KEY'], 'test-key');
    });
  });
}
