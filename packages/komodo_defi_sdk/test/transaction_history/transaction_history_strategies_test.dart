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

Asset _createSiaAsset() {
  return Asset.fromJson({
    'coin': 'SC',
    'type': 'SIA',
    'name': 'Siacoin',
    'fname': 'Siacoin',
    'wallet_only': false,
    'mm2': 1,
    'chain_id': 2024,
    'decimals': 24,
    'required_confirmations': 1,
    'nodes': const [
      {'url': 'https://api.siascan.com/wallet/api'},
    ],
  });
}

AssetPubkeys _makePubkeys(Asset asset) => AssetPubkeys(
  assetId: asset.id,
  keys: [
    PubkeyInfo(
      address: 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
      derivationPath: null,
      chain: null,
      balance: BalanceInfo.zero(),
      coinTicker: asset.id.id,
    ),
  ],
  availableAddressesCount: 1,
  syncStatus: SyncStatusEnum.success,
);

Map<String, Object> _makeTrxTransferRow({
  required String txId,
  required String ownerAddress,
  required String toAddress,
  required int amount,
  required int timestamp,
}) => {
  'txID': txId,
  'blockNumber': 12345,
  'block_timestamp': timestamp,
  'ret': <Object>[
    {'contractRet': 'SUCCESS'},
  ],
  'raw_data': {
    'contract': <Object>[
      {
        'type': 'TransferContract',
        'parameter': {
          'value': {
            'owner_address': ownerAddress,
            'to_address': toAddress,
            'amount': amount,
          },
        },
      },
    ],
  },
};

void main() {
  late PubkeyManager pubkeyManager;
  late KomodoDefiLocalAuth auth;

  setUpAll(() {
    registerFallbackValue(_createTrxAsset());
    registerFallbackValue(
      Uri.parse('https://api.trongrid.io/v1/accounts/T/transactions'),
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

    test('uses Legacy strategy for SIA assets', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);

      final strategy = factory.forAsset(_createSiaAsset());

      expect(strategy, isA<LegacyTransactionStrategy>());
      expect(strategy, isNot(isA<V2TransactionStrategy>()));
    });

    test('selects Tronscan strategy for TRX asset', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final trx = _createTrxAsset();

      final strategy = factory.forAsset(trx);

      expect(strategy, isA<TronGridTransactionStrategy>());
    });

    test('selects Tronscan strategy for TRC20 on TRX', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final usdt = _createUsdtTrc20Asset();

      final strategy = factory.forAsset(usdt);

      expect(strategy, isA<TronGridTransactionStrategy>());
    });

    test('Legacy strategy wins over Tronscan when registered first', () {
      final factory = TransactionHistoryStrategyFactory(
        pubkeyManager,
        auth,
        strategies: [
          EtherscanTransactionStrategy(pubkeyManager: pubkeyManager),
          const LegacyTransactionStrategy(),
          TronGridTransactionStrategy(pubkeyManager: pubkeyManager),
          V2TransactionStrategy(auth),
          const ZhtlcTransactionStrategy(),
        ],
      );

      final strategy = factory.forAsset(_createTrxAsset());

      expect(strategy, isA<LegacyTransactionStrategy>());
    });
  });

  group('TronscanTransactionStrategy', () {
    test('retries on 429 with Retry-After header then succeeds', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      var callCount = 0;
      when(() => httpClient.get(any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            'rate limited',
            429,
            headers: {'retry-after': '0'},
          );
        }
        return http.Response(
          jsonEncode({'data': <Object>[], 'meta': <String, Object>{}}),
          200,
        );
      });

      final trx = _createTrxAsset();
      when(
        () => pubkeyManager.getPubkeys(trx),
      ).thenAnswer((_) async => _makePubkeys(trx));

      final strategy = TronGridTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        apiHostOverride: 'api.trongrid.io',
      );

      final response = await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(callCount, 2);
      expect(response.transactions, isEmpty);
      verify(() => httpClient.get(any())).called(2);
    });

    test('retries on 429 with TRONGrid JSON body suspension', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      var callCount = 0;
      when(() => httpClient.get(any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            jsonEncode({
              'Error':
                  'request rate exceeded the allowed_rps(3), '
                  'and the query server is suspended for 3 s. '
                  'To obtain higher request quotas...',
            }),
            429,
          );
        }
        return http.Response(
          jsonEncode({'data': <Object>[], 'meta': <String, Object>{}}),
          200,
        );
      });

      final trx = _createTrxAsset();
      when(
        () => pubkeyManager.getPubkeys(trx),
      ).thenAnswer((_) async => _makePubkeys(trx));

      final strategy = TronGridTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        apiHostOverride: 'api.trongrid.io',
      );

      final response = await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(callCount, 2);
      expect(response.transactions, isEmpty);
    });

    test('uses TRONGrid API without custom auth headers', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      Uri? capturedUri;
      when(() => httpClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments.first as Uri;
        return http.Response(
          jsonEncode({'data': <Object>[], 'meta': <String, Object>{}}),
          200,
        );
      });

      final trx = _createTrxAsset();
      when(
        () => pubkeyManager.getPubkeys(trx),
      ).thenAnswer((_) async => _makePubkeys(trx));

      final strategy = TronGridTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        apiHostOverride: 'api.trongrid.io',
      );

      await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(capturedUri, isNotNull);
      expect(capturedUri!.host, 'api.trongrid.io');
      expect(
        capturedUri!.path,
        contains('/v1/accounts/TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7'),
      );
      verify(() => httpClient.get(any())).called(1);
    });

    test('returns fingerprint as fromId for cursor-based streaming', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      when(() => httpClient.get(any())).thenAnswer((_) async {
        return http.Response(
          jsonEncode({
            'data': <Object>[
              _makeTrxTransferRow(
                txId: 'abc123',
                ownerAddress: 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
                toAddress: 'TKoCV62HPYYxghKQJV7bmW3g6KpWb1dGhQ',
                amount: 1000000,
                timestamp: 1700000000000,
              ),
            ],
            'meta': <String, Object>{'fingerprint': 'next-page-cursor-token'},
          }),
          200,
        );
      });

      final trx = _createTrxAsset();
      when(
        () => pubkeyManager.getPubkeys(trx),
      ).thenAnswer((_) async => _makePubkeys(trx));

      final strategy = TronGridTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        apiHostOverride: 'api.trongrid.io',
      );

      final response = await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(jsonDecode(response.fromId!), {
        'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7': 'next-page-cursor-token',
      });
      expect(response.transactions, hasLength(1));
    });

    test(
      'multi-address: single __pending__ cursor stays JSON so address1 is not refetched',
      () async {
        final httpClient = _MockHttpClient();
        final apiClient = _MockApiClient();
        final addr1 = 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7';
        final addr2 = 'TKoCV62HPYYxghKQJV7bmW3g6KpWb1dGhQ';
        final requestUris = <Uri>[];

        final trx = _createTrxAsset();
        when(() => pubkeyManager.getPubkeys(trx)).thenAnswer(
          (_) async => AssetPubkeys(
            assetId: trx.id,
            keys: [
              PubkeyInfo(
                address: addr1,
                derivationPath: null,
                chain: null,
                balance: BalanceInfo.zero(),
                coinTicker: trx.id.id,
              ),
              PubkeyInfo(
                address: addr2,
                derivationPath: null,
                chain: null,
                balance: BalanceInfo.zero(),
                coinTicker: trx.id.id,
              ),
            ],
            availableAddressesCount: 2,
            syncStatus: SyncStatusEnum.success,
          ),
        );

        when(() => httpClient.get(any())).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          requestUris.add(uri);
          if (uri.path.contains(addr1)) {
            return http.Response(
              jsonEncode({
                'data': <Object>[
                  _makeTrxTransferRow(
                    txId: 'tx1',
                    ownerAddress: addr1,
                    toAddress: addr2,
                    amount: 1000000,
                    timestamp: 1700000000000,
                  ),
                ],
                'meta': <String, Object>{},
              }),
              200,
            );
          }
          if (uri.path.contains(addr2)) {
            return http.Response(
              jsonEncode({'data': <Object>[], 'meta': <String, Object>{}}),
              200,
            );
          }
          throw StateError('Unexpected TRONGrid URI: $uri');
        });

        final strategy = TronGridTransactionStrategy(
          pubkeyManager: pubkeyManager,
          httpClient: httpClient,
          apiHostOverride: 'api.trongrid.io',
        );

        final first = await strategy.fetchTransactionHistory(
          apiClient,
          trx,
          const PagePagination(pageNumber: 1, itemsPerPage: 20),
        );

        expect(first.transactions, hasLength(1));
        final decoded = jsonDecode(first.fromId!) as Map<String, dynamic>;
        expect(decoded, {addr2: '__pending__'});

        final cursor = first.fromId!;
        await strategy.fetchTransactionHistory(
          apiClient,
          trx,
          TransactionBasedPagination(fromId: cursor, itemCount: 20),
        );

        expect(requestUris, hasLength(2));
        expect(requestUris[0].path, contains(addr1));
        expect(requestUris[1].path, contains(addr2));
        expect(requestUris[1].path, isNot(contains(addr1)));
      },
    );

    test('passes fingerprint via TransactionBasedPagination', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      Uri? capturedUri;
      when(() => httpClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments.first as Uri;
        return http.Response(
          jsonEncode({'data': <Object>[], 'meta': <String, Object>{}}),
          200,
        );
      });

      final trx = _createTrxAsset();
      when(
        () => pubkeyManager.getPubkeys(trx),
      ).thenAnswer((_) async => _makePubkeys(trx));

      final strategy = TronGridTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        apiHostOverride: 'api.trongrid.io',
      );

      await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const TransactionBasedPagination(
          fromId: 'previous-fingerprint-token',
          itemCount: 50,
        ),
      );

      expect(capturedUri, isNotNull);
      expect(
        capturedUri!.queryParameters['fingerprint'],
        'previous-fingerprint-token',
      );
    });

    test(
      'does not treat a transaction hash as a TRONGrid fingerprint',
      () async {
        final httpClient = _MockHttpClient();
        final apiClient = _MockApiClient();
        Uri? capturedUri;
        const txHash =
            '0123456789abcdef0123456789abcdef'
            '0123456789abcdef0123456789abcdef';
        when(() => httpClient.get(any())).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments.first as Uri;
          return http.Response(
            jsonEncode({'data': <Object>[], 'meta': <String, Object>{}}),
            200,
          );
        });

        final trx = _createTrxAsset();
        when(
          () => pubkeyManager.getPubkeys(trx),
        ).thenAnswer((_) async => _makePubkeys(trx));

        final strategy = TronGridTransactionStrategy(
          pubkeyManager: pubkeyManager,
          httpClient: httpClient,
          apiHostOverride: 'api.trongrid.io',
        );

        await strategy.fetchTransactionHistory(
          apiClient,
          trx,
          const TransactionBasedPagination(fromId: txHash, itemCount: 50),
        );

        expect(capturedUri, isNotNull);
        expect(
          capturedUri!.queryParameters.containsKey('fingerprint'),
          isFalse,
        );
      },
    );

    test('returns null fromId when no more pages', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      when(() => httpClient.get(any())).thenAnswer((_) async {
        return http.Response(
          jsonEncode({
            'data': <Object>[
              _makeTrxTransferRow(
                txId: 'lastTx',
                ownerAddress: 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7',
                toAddress: 'TKoCV62HPYYxghKQJV7bmW3g6KpWb1dGhQ',
                amount: 500000,
                timestamp: 1700000000000,
              ),
            ],
            'meta': <String, Object>{},
          }),
          200,
        );
      });

      final trx = _createTrxAsset();
      when(
        () => pubkeyManager.getPubkeys(trx),
      ).thenAnswer((_) async => _makePubkeys(trx));

      final strategy = TronGridTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        apiHostOverride: 'api.trongrid.io',
      );

      final response = await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(response.fromId, isNull);
      expect(response.transactions, hasLength(1));
    });
  });
}
