import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/etherscan_transaction_history_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/gnosis_blockscout_transaction_history_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/tron_grid_transaction_history_strategy.dart';
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

Asset _createGnosisAsset() =>
    _createEvmAsset(coin: 'XDAI', chainId: 100, type: 'Gnosis');

Asset _createGnosisTokenAsset() {
  final parent = _createGnosisAsset();
  return Asset.fromJson(
    const {
      'coin': 'USDC-GNO',
      'type': 'Gnosis',
      'name': 'USD Coin',
      'fname': 'USD Coin',
      'wallet_only': true,
      'mm2': 1,
      'chain_id': 100,
      'decimals': 6,
      'required_confirmations': 3,
      'protocol': {
        'type': 'ETH',
        'protocol_data': {
          'platform': 'XDAI',
          'contract_address': '0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0',
          'decimals': 6,
        },
      },
      'contract_address': '0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0',
      'parent_coin': 'XDAI',
      'swap_contract_address': '0x0000000000000000000000000000000000000001',
      'fallback_swap_contract': '0x0000000000000000000000000000000000000001',
      'nodes': [
        {'url': 'https://rpc.example.com'},
      ],
    },
    knownIds: {parent.id},
  );
}

Asset _createTrxAsset() {
  return Asset.fromJson(const {
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
  return Asset.fromJson(const {
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
  return Asset.fromJson(const {
    'coin': 'SC',
    'type': 'SIA',
    'name': 'Siacoin',
    'fname': 'Siacoin',
    'wallet_only': false,
    'mm2': 1,
    'chain_id': 2024,
    'decimals': 24,
    'required_confirmations': 1,
    'nodes': [
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

AssetPubkeys _makePubkeysForAddress(Asset asset, String address) =>
    AssetPubkeys(
      assetId: asset.id,
      keys: [
        PubkeyInfo(
          address: address,
          derivationPath: null,
          chain: null,
          balance: BalanceInfo.zero(),
          coinTicker: asset.id.id,
        ),
      ],
      availableAddressesCount: 1,
      syncStatus: SyncStatusEnum.success,
    );

AssetPubkeys _makePubkeysForAddresses(Asset asset, List<String> addresses) =>
    AssetPubkeys(
      assetId: asset.id,
      keys: [
        for (final address in addresses)
          PubkeyInfo(
            address: address,
            derivationPath: null,
            chain: null,
            balance: BalanceInfo.zero(),
            coinTicker: asset.id.id,
          ),
      ],
      availableAddressesCount: addresses.length,
      syncStatus: SyncStatusEnum.success,
    );

String _sampleGnosisAddress(String digit) =>
    '0x${List.filled(40, digit).join()}';

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

Map<String, Object> _makeTrxNonTransferRow({
  required String txId,
  int timestamp = 1700000000000,
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
        'type': 'TriggerSmartContract',
        'parameter': {'value': <String, Object>{}},
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

    test('does not map Gnosis to Etherscan proxy endpoints', () {
      final xdai = _createGnosisAsset();

      expect(helper.supportsProtocol(xdai), isFalse);
      expect(helper.getApiUrlForAsset(xdai), isNull);
      expect(helper.shouldEnableTransactionHistory(xdai), isFalse);
    });
  });

  group('GnosisBlockscoutProtocolHelper', () {
    const helper = GnosisBlockscoutProtocolHelper(
      baseUrl: 'https://example.blockscout/api/v2',
    );

    test('builds native transaction history URL', () {
      final sampleAddress = _sampleGnosisAddress('1');
      final uri = helper.getApiUrlForAsset(_createGnosisAsset(), sampleAddress);

      expect(uri.path, '/api/v2/addresses/$sampleAddress/transactions');
      expect(uri.queryParameters, isEmpty);
    });

    test('builds ERC-20 token transfer URL with contract filter', () {
      final sampleAddress = _sampleGnosisAddress('1');
      final asset = _createGnosisTokenAsset();
      final uri = helper.getApiUrlForAsset(asset, sampleAddress);

      expect(uri.path, '/api/v2/addresses/$sampleAddress/token-transfers');
      expect(uri.queryParameters['type'], 'ERC-20');
      expect(uri.queryParameters['token'], asset.protocol.contractAddress);
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

    test('selects Gnosis Blockscout strategy for XDAI', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);

      final strategy = factory.forAsset(_createGnosisAsset());

      expect(strategy, isA<GnosisBlockscoutTransactionStrategy>());
    });

    test('selects Gnosis Blockscout strategy for Gnosis ERC-20 tokens', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);

      final strategy = factory.forAsset(_createGnosisTokenAsset());

      expect(strategy, isA<GnosisBlockscoutTransactionStrategy>());
    });

    test('uses Legacy strategy for SIA assets', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);

      final strategy = factory.forAsset(_createSiaAsset());

      expect(strategy, isA<LegacyTransactionStrategy>());
      expect(strategy, isNot(isA<V2TransactionStrategy>()));
    });

    test('selects TronGrid strategy for TRX asset', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final trx = _createTrxAsset();

      final strategy = factory.forAsset(trx);

      expect(strategy, isA<TronGridTransactionStrategy>());
    });

    test('selects TronGrid strategy for TRC20 on TRX', () {
      final factory = TransactionHistoryStrategyFactory(pubkeyManager, auth);
      final usdt = _createUsdtTrc20Asset();

      final strategy = factory.forAsset(usdt);

      expect(strategy, isA<TronGridTransactionStrategy>());
    });

    test('Legacy strategy wins over TronGrid when registered first', () {
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

  group('GnosisBlockscoutTransactionStrategy', () {
    test(
      'maps native Blockscout transactions into KDF history shape',
      () async {
        final httpClient = _MockHttpClient();
        final apiClient = _MockApiClient();
        Uri? capturedUri;
        final sampleAddress = _sampleGnosisAddress('1');
        final xdai = _createGnosisAsset();

        when(
          () => pubkeyManager.getPubkeys(xdai),
        ).thenAnswer((_) async => _makePubkeysForAddress(xdai, sampleAddress));
        when(() => httpClient.get(any())).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments.first as Uri;
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'hash': '0xnative',
                  'from': {'hash': sampleAddress},
                  'to': {'hash': _sampleGnosisAddress('2')},
                  'value': '1000000000000000000',
                  'fee': {'value': '21000000000000'},
                  'block_number': 123,
                  'timestamp': '2024-01-02T03:04:05.000000Z',
                },
              ],
            }),
            200,
          );
        });

        final strategy = GnosisBlockscoutTransactionStrategy(
          pubkeyManager: pubkeyManager,
          httpClient: httpClient,
          baseUrl: 'https://example.blockscout/api/v2',
        );

        final response = await strategy.fetchTransactionHistory(
          apiClient,
          xdai,
          const PagePagination(pageNumber: 1, itemsPerPage: 20),
        );

        expect(capturedUri, isNotNull);
        expect(
          capturedUri!.path,
          '/api/v2/addresses/$sampleAddress/transactions',
        );
        expect(response.currentBlock, 123);
        expect(response.transactions, hasLength(1));
        expect(response.transactions.single.txHash, '0xnative');
        expect(response.transactions.single.myBalanceChange, '-1');
        expect(response.transactions.single.transactionFee, '21000000000000');
      },
    );

    test('maps ERC-20 Blockscout transfers into KDF history shape', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      Uri? capturedUri;
      final sampleAddress = _sampleGnosisAddress('1');
      final usdc = _createGnosisTokenAsset();

      when(
        () => pubkeyManager.getPubkeys(usdc),
      ).thenAnswer((_) async => _makePubkeysForAddress(usdc, sampleAddress));
      when(() => httpClient.get(any())).thenAnswer((invocation) async {
        capturedUri = invocation.positionalArguments.first as Uri;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'transaction_hash': '0xtoken',
                'from': {'hash': _sampleGnosisAddress('2')},
                'to': {'hash': sampleAddress},
                'total': {'value': '123456', 'decimals': '6'},
                'block_number': 124,
                'timestamp': '2024-01-02T04:04:05Z',
                'log_index': '7',
              },
            ],
          }),
          200,
        );
      });

      final strategy = GnosisBlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        baseUrl: 'https://example.blockscout/api/v2',
      );

      final response = await strategy.fetchTransactionHistory(
        apiClient,
        usdc,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(capturedUri, isNotNull);
      expect(
        capturedUri!.path,
        '/api/v2/addresses/$sampleAddress/token-transfers',
      );
      expect(capturedUri!.queryParameters['type'], 'ERC-20');
      expect(
        capturedUri!.queryParameters['token'],
        usdc.protocol.contractAddress,
      );
      expect(response.transactions, hasLength(1));
      expect(response.transactions.single.txHash, '0xtoken');
      expect(response.transactions.single.myBalanceChange, '0.123456');
      expect(response.transactions.single.internalId, 'USDC-GNO:0xtoken:7');
    });

    test(
      'follows Blockscout v2 next page params one API page at a time',
      () async {
        final httpClient = _MockHttpClient();
        final apiClient = _MockApiClient();
        final requestedUris = <Uri>[];
        final sampleAddress = _sampleGnosisAddress('1');
        final xdai = _createGnosisAsset();

        when(
          () => pubkeyManager.getPubkeys(xdai),
        ).thenAnswer((_) async => _makePubkeysForAddress(xdai, sampleAddress));
        when(() => httpClient.get(any())).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          requestedUris.add(uri);
          if (requestedUris.length == 1) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'hash': '0xpage1',
                    'from': {'hash': sampleAddress},
                    'to': {'hash': _sampleGnosisAddress('2')},
                    'value': '1',
                    'block_number': 124,
                    'timestamp': '2024-01-02T04:04:05Z',
                  },
                ],
                'next_page_params': {
                  'block_number': 123,
                  'index': 0,
                  'items_count': 1,
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'hash': '0xpage2',
                  'from': {'hash': _sampleGnosisAddress('2')},
                  'to': {'hash': sampleAddress},
                  'value': '2',
                  'block_number': 123,
                  'timestamp': '2024-01-02T03:04:05Z',
                },
              ],
              'next_page_params': null,
            }),
            200,
          );
        });

        final strategy = GnosisBlockscoutTransactionStrategy(
          pubkeyManager: pubkeyManager,
          httpClient: httpClient,
          baseUrl: 'https://example.blockscout/api/v2',
        );

        final response = await strategy.fetchTransactionHistory(
          apiClient,
          xdai,
          const PagePagination(pageNumber: 1, itemsPerPage: 20),
        );

        expect(requestedUris, hasLength(1));
        expect(response.transactions.map((tx) => tx.txHash), ['0xpage1']);
        expect(jsonDecode(response.fromId!), {
          sampleAddress: {
            'block_number': '123',
            'index': '0',
            'items_count': '1',
          },
        });

        final nextPage = await strategy.fetchTransactionHistory(
          apiClient,
          xdai,
          TransactionBasedPagination(fromId: response.fromId!, itemCount: 20),
        );

        expect(requestedUris, hasLength(2));
        expect(requestedUris.last.queryParameters['block_number'], '123');
        expect(requestedUris.last.queryParameters['index'], '0');
        expect(nextPage.transactions.map((tx) => tx.txHash), ['0xpage2']);
        expect(nextPage.fromId, isNull);
      },
    );

    test('retries Blockscout 429 without losing next page params', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      final requestedUris = <Uri>[];
      final sampleAddress = _sampleGnosisAddress('1');
      final xdai = _createGnosisAsset();
      final cursor = jsonEncode({
        sampleAddress: {
          'block_number': '124',
          'index': '7',
          'items_count': '1',
        },
      });

      when(
        () => pubkeyManager.getPubkeys(xdai),
      ).thenAnswer((_) async => _makePubkeysForAddress(xdai, sampleAddress));
      when(() => httpClient.get(any())).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        requestedUris.add(uri);
        if (requestedUris.length == 1) {
          return http.Response(
            'rate limited',
            429,
            headers: {'retry-after': '0'},
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              {
                'hash': '0xpage2',
                'from': {'hash': _sampleGnosisAddress('2')},
                'to': {'hash': sampleAddress},
                'value': '2',
                'block_number': 123,
                'timestamp': '2024-01-02T03:04:05Z',
              },
            ],
            'next_page_params': null,
          }),
          200,
        );
      });

      final strategy = GnosisBlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: httpClient,
        baseUrl: 'https://example.blockscout/api/v2',
      );

      final response = await strategy.fetchTransactionHistory(
        apiClient,
        xdai,
        TransactionBasedPagination(fromId: cursor, itemCount: 20),
      );

      expect(requestedUris, hasLength(2));
      for (final uri in requestedUris) {
        expect(uri.queryParameters['block_number'], '124');
        expect(uri.queryParameters['index'], '7');
      }
      expect(response.transactions.map((tx) => tx.txHash), ['0xpage2']);
      expect(response.fromId, isNull);
    });

    test(
      'returns opaque cursor instead of draining for local pagination',
      () async {
        final httpClient = _MockHttpClient();
        final apiClient = _MockApiClient();
        final requestedUris = <Uri>[];
        final sampleAddress = _sampleGnosisAddress('1');
        final usdc = _createGnosisTokenAsset();

        when(
          () => pubkeyManager.getPubkeys(usdc),
        ).thenAnswer((_) async => _makePubkeysForAddress(usdc, sampleAddress));
        when(() => httpClient.get(any())).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          requestedUris.add(uri);
          if (requestedUris.length == 1) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'transaction_hash': '0xshared',
                    'from': {'hash': _sampleGnosisAddress('2')},
                    'to': {'hash': sampleAddress},
                    'total': {'value': '2'},
                    'block_number': 125,
                    'timestamp': '2024-01-02T05:04:05Z',
                    'log_index': '9',
                  },
                ],
                'next_page_params': {
                  'block_number': 124,
                  'index': 7,
                  'items_count': 1,
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'transaction_hash': '0xshared',
                  'from': {'hash': _sampleGnosisAddress('2')},
                  'to': {'hash': sampleAddress},
                  'total': {'value': '1'},
                  'block_number': 124,
                  'timestamp': '2024-01-02T04:04:05Z',
                  'log_index': '7',
                },
              ],
              'next_page_params': null,
            }),
            200,
          );
        });

        final strategy = GnosisBlockscoutTransactionStrategy(
          pubkeyManager: pubkeyManager,
          httpClient: httpClient,
          baseUrl: 'https://example.blockscout/api/v2',
        );

        final firstPage = await strategy.fetchTransactionHistory(
          apiClient,
          usdc,
          const PagePagination(pageNumber: 1, itemsPerPage: 1),
        );
        expect(firstPage.transactions, hasLength(1));
        expect(firstPage.transactions.single.internalId, 'USDC-GNO:0xshared:9');
        expect(firstPage.fromId, isNot('USDC-GNO:0xshared:9'));

        final nextPage = await strategy.fetchTransactionHistory(
          apiClient,
          usdc,
          TransactionBasedPagination(fromId: firstPage.fromId!, itemCount: 1),
        );

        expect(nextPage.transactions, hasLength(1));
        expect(nextPage.transactions.single.internalId, 'USDC-GNO:0xshared:7');
      },
    );
  });

  group('TronGridTransactionStrategy', () {
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

    test('429 retry preserves the TRONGrid fingerprint cursor', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      final requestedUris = <Uri>[];
      var callCount = 0;
      when(() => httpClient.get(any())).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        requestedUris.add(uri);
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
      final address = _makePubkeys(trx).keys.single.address;
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
        TransactionBasedPagination(
          fromId: jsonEncode({address: 'cursor-x'}),
          itemCount: 20,
        ),
      );

      expect(requestedUris, hasLength(2));
      expect(requestedUris[0].queryParameters['fingerprint'], 'cursor-x');
      expect(requestedUris[1].queryParameters['fingerprint'], 'cursor-x');
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

    test('TRX empty filtered page advances fingerprint cursor', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      final requestedUris = <Uri>[];
      when(() => httpClient.get(any())).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        requestedUris.add(uri);
        if (requestedUris.length == 1) {
          return http.Response(
            jsonEncode({
              'data': <Object>[_makeTrxNonTransferRow(txId: 'ignored-1')],
              'meta': <String, Object>{'fingerprint': 'fp-2'},
            }),
            200,
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

      final first = await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(first.transactions, isEmpty);
      final address = _makePubkeys(trx).keys.single.address;
      expect(jsonDecode(first.fromId!), {
        address: {'__cursor__': 'fp-2', '__empty_pages__': 1},
      });

      await strategy.fetchTransactionHistory(
        apiClient,
        trx,
        TransactionBasedPagination(fromId: first.fromId!, itemCount: 20),
      );

      expect(requestedUris, hasLength(2));
      expect(requestedUris.last.queryParameters['fingerprint'], 'fp-2');
    });

    test(
      'TRX repeated empty filtered pages stop after configured cap',
      () async {
        final httpClient = _MockHttpClient();
        final apiClient = _MockApiClient();
        const addr1 = 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7';
        const addr2 = 'TKoCV62HPYYxghKQJV7bmW3g6KpWb1dGhQ';
        final requestedUris = <Uri>[];

        final trx = _createTrxAsset();
        when(() => pubkeyManager.getPubkeys(trx)).thenAnswer(
          (_) async => _makePubkeysForAddresses(trx, [addr1, addr2]),
        );

        when(() => httpClient.get(any())).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          requestedUris.add(uri);
          if (uri.path.contains(addr1)) {
            return http.Response(
              jsonEncode({
                'data': <Object>[
                  _makeTrxNonTransferRow(
                    txId: 'ignored-${requestedUris.length}',
                  ),
                ],
                'meta': <String, Object>{
                  'fingerprint': 'fp-${requestedUris.length}',
                },
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
          maxEmptyPagesPerAddress: 1,
        );

        final first = await strategy.fetchTransactionHistory(
          apiClient,
          trx,
          const PagePagination(pageNumber: 1, itemsPerPage: 20),
        );
        final second = await strategy.fetchTransactionHistory(
          apiClient,
          trx,
          TransactionBasedPagination(fromId: first.fromId!, itemCount: 20),
        );

        expect(jsonDecode(second.fromId!), {addr2: '__pending__'});

        await strategy.fetchTransactionHistory(
          apiClient,
          trx,
          TransactionBasedPagination(fromId: second.fromId!, itemCount: 20),
        );

        expect(requestedUris, hasLength(3));
        expect(requestedUris[0].path, contains(addr1));
        expect(requestedUris[1].path, contains(addr1));
        expect(requestedUris[2].path, contains(addr2));
      },
    );

    test('multi-address pending cursor stays JSON to avoid refetch', () async {
      final httpClient = _MockHttpClient();
      final apiClient = _MockApiClient();
      const addr1 = 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7';
      const addr2 = 'TKoCV62HPYYxghKQJV7bmW3g6KpWb1dGhQ';
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
    });

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
