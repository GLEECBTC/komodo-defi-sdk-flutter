import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/blockscout_transaction_history_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/etherscan_transaction_history_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_strategies.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockLocalAuth extends Mock implements KomodoDefiLocalAuth {}

const _myAddress = '0x20C3E0c4A8d438f01B1C59376D83519d53b716Ad';
const _otherAddress = '0xe99a6931c84d04973bb237b79d8dc45c6bc8ae15';
const _secondOwnAddress = '0x1b94Ec780D34dc950f74167430F7F7D437A1b8B9';
const _tokenContract = '0x90E100a7fdad752c97ae5B5F2De76EbacfA5f6b5';

Asset _gleec({String explorerUrl = 'https://evm-explorer.gleec.com/'}) =>
    Asset.fromJson({
      'coin': 'GLEEC',
      'type': 'GRC-20',
      'fname': 'Gleec',
      'chain_id': 11169,
      'explorer_url': explorerUrl,
      'explorer_tx_url': 'tx/',
      'explorer_address_url': 'address/',
      'nodes': const [
        {'url': 'https://evm-rpc.gleec.com'},
      ],
      'swap_contract_address': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
      'fallback_swap_contract': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
      'protocol': {
        'type': 'ETH',
        'protocol_data': {'chain_id': 11169},
      },
    });

Asset _grc20Token() => Asset.fromJson({
  'coin': 'BCASH-GRC20',
  'type': 'GRC-20',
  'fname': 'B-CASH',
  'chain_id': 11169,
  'decimals': 18,
  'parent_coin': 'GLEEC',
  'explorer_url': 'https://evm-explorer.gleec.com/',
  'explorer_tx_url': 'tx/',
  'nodes': const [
    {'url': 'https://evm-rpc.gleec.com'},
  ],
  'swap_contract_address': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
  'fallback_swap_contract': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
  'contract_address': _tokenContract,
  'protocol': {
    'type': 'ERC20',
    'protocol_data': {'platform': 'GLEEC', 'contract_address': _tokenContract},
  },
});

Asset _eth() => Asset.fromJson({
  'coin': 'ETH',
  'type': 'ETH',
  'fname': 'Ethereum',
  'chain_id': 1,
  'explorer_url': 'https://etherscan.io/',
  'nodes': const [
    {'url': 'https://rpc.example.com'},
  ],
  'swap_contract_address': '0x0000000000000000000000000000000000000001',
  'fallback_swap_contract': '0x0000000000000000000000000000000000000001',
});

AssetPubkeys _pubkeys(Asset asset, List<String> addresses) => AssetPubkeys(
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

/// A `txlist` row in the exact shape the live explorer returns.
Map<String, dynamic> _nativeRow({
  required String hash,
  required String from,
  required String to,
  String value = '77700000000000',
  String gasUsed = '21000',
  String gasPrice = '1125000000',
  String isError = '0',
  int timeStamp = 1786731540,
  int blockNumber = 3165533,
  int confirmations = 54135,
}) => {
  'blockHash': '0xblock',
  'blockNumber': '$blockNumber',
  'confirmations': '$confirmations',
  'contractAddress': '',
  'cumulativeGasUsed': gasUsed,
  'from': from,
  'gas': '150000',
  'gasPrice': gasPrice,
  'gasUsed': gasUsed,
  'hash': hash,
  'input': '0x',
  'isError': isError,
  'nonce': '5',
  'timeStamp': '$timeStamp',
  'to': to,
  'transactionIndex': '0',
  'txreceipt_status': isError == '0' ? '1' : '0',
  'value': value,
};

/// A `tokentx` row. Note the live API omits `isError` here.
Map<String, dynamic> _tokenRow({
  required String hash,
  required String from,
  required String to,
  String value = '9987146529562982005',
  String tokenDecimal = '18',
  int timeStamp = 1785974395,
}) => {
  'blockHash': '0xblock',
  'blockNumber': '3074943',
  'confirmations': '144703',
  'contractAddress': _tokenContract.toLowerCase(),
  'cumulativeGasUsed': '75000',
  'from': from,
  'functionName': 'transfer(address,uint256)',
  'gas': '150000',
  'gasPrice': '1000000000',
  'gasUsed': '75000',
  'hash': hash,
  'input': '0x',
  'methodId': '0xa9059cbb',
  'nonce': '5',
  'timeStamp': '$timeStamp',
  'to': to,
  'tokenDecimal': tokenDecimal,
  'tokenName': 'B-CASH',
  'tokenSymbol': 'B-CASH',
  'transactionIndex': '0',
  'value': value,
};

/// Serves canned bodies per (address, action) and records every request.
class _FakeApi {
  _FakeApi(this.responder);

  final String Function(Uri uri) responder;
  final List<Uri> requests = [];

  http.Client get client => _MockClientAdapter(this);
}

class _MockClientAdapter extends http.BaseClient {
  _MockClientAdapter(this._api);
  final _FakeApi _api;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _api.requests.add(request.url);
    final body = _api.responder(request.url);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}

String _ok(List<Map<String, dynamic>> rows) =>
    jsonEncode({'message': 'OK', 'status': '1', 'result': rows});

/// The live shape for an address with no history: a *successful* HTTP 200
/// carrying `status: "0"`.
String _empty(String message) =>
    jsonEncode({'message': message, 'status': '0', 'result': <Object>[]});

void main() {
  late PubkeyManager pubkeyManager;

  setUpAll(() {
    registerFallbackValue(_gleec());
  });

  setUp(() {
    pubkeyManager = _MockPubkeyManager();
  });

  void stubPubkeys(Asset asset, List<String> addresses) {
    when(
      () => pubkeyManager.getPubkeys(any()),
    ).thenAnswer((_) async => _pubkeys(asset, addresses));
  }

  group('asset support', () {
    test('claims GRC-20 assets, which the Etherscan proxy cannot serve', () {
      final strategy = BlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
      );

      expect(strategy.supportsAsset(_gleec()), isTrue);
      expect(strategy.supportsAsset(_grc20Token()), isTrue);
    });

    test('leaves ETH to the Etherscan proxy strategy', () {
      final strategy = BlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
      );

      expect(strategy.supportsAsset(_eth()), isFalse);
    });

    test('declines a GRC-20 asset with no explorer configured', () {
      final strategy = BlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
      );

      expect(strategy.supportsAsset(_gleec(explorerUrl: '')), isFalse);
    });

    test('does not ask KDF to enable its own history', () {
      final strategy = BlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
      );

      expect(strategy.requiresKdfTransactionHistory(_gleec()), isFalse);
    });
  });

  group('factory routing', () {
    test('GLEEC selects Blockscout, not the legacy KDF store', () {
      final factory = TransactionHistoryStrategyFactory(
        pubkeyManager,
        _MockLocalAuth(),
      );

      expect(
        factory.forAsset(_gleec()),
        isA<BlockscoutTransactionStrategy>(),
        reason:
            'falling through to LegacyTransactionStrategy is the bug: '
            'activation disables KDF tx_history for every EVM asset',
      );
      expect(
        factory.forAsset(_grc20Token()),
        isA<BlockscoutTransactionStrategy>(),
      );
    });

    test('ETH still selects the Etherscan proxy strategy', () {
      final factory = TransactionHistoryStrategyFactory(
        pubkeyManager,
        _MockLocalAuth(),
      );

      expect(factory.forAsset(_eth()), isA<EtherscanTransactionStrategy>());
    });
  });

  group('endpoint construction', () {
    test('derives /api from the asset explorer, and queries txlist', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi((_) => _ok([]));

      await BlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: api.client,
      ).fetchTransactionHistory(
        _MockApiClient(),
        asset,
        const PagePagination(pageNumber: 1, itemsPerPage: 50),
      );

      final uri = api.requests.single;
      expect(uri.origin, 'https://evm-explorer.gleec.com');
      expect(uri.path, '/api');
      expect(uri.queryParameters['module'], 'account');
      expect(uri.queryParameters['action'], 'txlist');
      expect(uri.queryParameters['address'], _myAddress);
      expect(uri.queryParameters.containsKey('contractaddress'), isFalse);
    });

    test(
      'a token is detected by its contract, not by a resolved parent',
      () async {
        // `AssetId.parentId` is only populated when the asset registry supplies
        // `knownIds`; it is null here, exactly as it would be if the parent
        // failed to resolve in production. The token must still be read as a
        // token, or its amounts and fees come out wrong.
        final asset = _grc20Token();
        expect(
          asset.id.parentId,
          isNull,
          reason: 'fixture must exercise the unresolved-parent case',
        );
        stubPubkeys(asset, [_myAddress]);
        final api = _FakeApi((_) => _ok([]));

        await BlockscoutTransactionStrategy(
          pubkeyManager: pubkeyManager,
          httpClient: api.client,
        ).fetchTransactionHistory(
          _MockApiClient(),
          asset,
          const PagePagination(pageNumber: 1, itemsPerPage: 50),
        );

        expect(api.requests.single.queryParameters['action'], 'tokentx');
      },
    );

    test('a token queries tokentx filtered to its contract', () async {
      final asset = _grc20Token();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi((_) => _ok([]));

      await BlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: api.client,
      ).fetchTransactionHistory(
        _MockApiClient(),
        asset,
        const PagePagination(pageNumber: 1, itemsPerPage: 50),
      );

      final uri = api.requests.single;
      expect(uri.queryParameters['action'], 'tokentx');
      expect(uri.queryParameters['contractaddress'], _tokenContract);
    });
  });

  group('response handling', () {
    test('"No transactions found" is an empty history, not an error', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi((_) => _empty('No transactions found'));

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 50),
          );

      expect(response.transactions, isEmpty);
      expect(response.total, 0);
      expect(response.fromId, isNull);
    });

    test('maps an incoming native transfer, charging no fee', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi(
        (_) => _ok([
          _nativeRow(hash: '0xaaa', from: _otherAddress, to: _myAddress),
        ]),
      );

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 50),
          );

      final tx = response.transactions.single;
      expect(tx.txHash, '0xaaa');
      expect(tx.myBalanceChange, '0.0000777');
      expect(tx.receivedByMe, '0.0000777');
      expect(tx.spentByMe, '0');
      expect(tx.blockHeight, 3165533);
      expect(tx.confirmations, 54135);
      expect(tx.coin, 'GLEEC');
    });

    test('an outgoing native transfer spends the amount plus gas', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi(
        (_) => _ok([
          _nativeRow(
            hash: '0xbbb',
            from: _myAddress,
            to: _otherAddress,
            value: '1000000000000000000',
            gasUsed: '21000',
            gasPrice: '1000000000',
          ),
        ]),
      );

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 50),
          );

      final tx = response.transactions.single;
      // 21000 * 1 gwei = 0.000021 GLEEC
      expect(tx.spentByMe, '1.000021');
      expect(tx.myBalanceChange, '-1.000021');
      expect(tx.receivedByMe, '0');
    });

    test('a reverted transaction moves no value but still burns gas', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi(
        (_) => _ok([
          _nativeRow(
            hash: '0xccc',
            from: _myAddress,
            to: _otherAddress,
            value: '1000000000000000000',
            gasUsed: '21000',
            gasPrice: '1000000000',
            isError: '1',
          ),
        ]),
      );

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 50),
          );

      final tx = response.transactions.single;
      expect(tx.myBalanceChange, '-0.000021');
      expect(tx.spentByMe, '0.000021');
    });

    test('token history is not charged the platform-coin gas', () async {
      final asset = _grc20Token();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi(
        (_) => _ok([
          _tokenRow(
            hash: '0xddd',
            from: _myAddress,
            to: _otherAddress,
            value: '2000000000000000000',
          ),
        ]),
      );

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 50),
          );

      final tx = response.transactions.single;
      expect(tx.spentByMe, '2', reason: 'gas is paid in GLEEC, not the token');
      expect(tx.myBalanceChange, '-2');
      expect(tx.coin, 'BCASH-GRC20');
    });

    test(
      'token decimals come from the row, not the platform default',
      () async {
        final asset = _grc20Token();
        stubPubkeys(asset, [_myAddress]);
        final api = _FakeApi(
          (_) => _ok([
            _tokenRow(
              hash: '0xeee',
              from: _otherAddress,
              to: _myAddress,
              value: '1500000',
              tokenDecimal: '6',
            ),
          ]),
        );

        final response =
            await BlockscoutTransactionStrategy(
              pubkeyManager: pubkeyManager,
              httpClient: api.client,
            ).fetchTransactionHistory(
              _MockApiClient(),
              asset,
              const PagePagination(pageNumber: 1, itemsPerPage: 50),
            );

        expect(response.transactions.single.receivedByMe, '1.5');
      },
    );

    test('rows unrelated to the wallet are dropped', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi(
        (_) => _ok([
          _nativeRow(hash: '0xfff', from: _otherAddress, to: _secondOwnAddress),
        ]),
      );

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 50),
          );

      expect(response.transactions, isEmpty);
    });
  });

  group('multi-address wallets', () {
    test('queries every address once', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress, _secondOwnAddress]);
      final api = _FakeApi((_) => _ok([]));

      await BlockscoutTransactionStrategy(
        pubkeyManager: pubkeyManager,
        httpClient: api.client,
      ).fetchTransactionHistory(
        _MockApiClient(),
        asset,
        const PagePagination(pageNumber: 1, itemsPerPage: 50),
      );

      expect(
        api.requests.map((u) => u.queryParameters['address']),
        containsAll([_myAddress, _secondOwnAddress]),
      );
      expect(api.requests, hasLength(2));
    });

    test('a transfer between own addresses nets to its fee, once', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress, _secondOwnAddress]);
      // Both addresses report the same transaction — the classic double-count.
      final api = _FakeApi(
        (_) => _ok([
          _nativeRow(
            hash: '0x123',
            from: _myAddress,
            to: _secondOwnAddress,
            value: '1000000000000000000',
            gasUsed: '21000',
            gasPrice: '1000000000',
          ),
        ]),
      );

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 50),
          );

      expect(response.transactions, hasLength(1));
      // Sent 1 and received 1 within the wallet: only the gas actually left.
      expect(response.transactions.single.myBalanceChange, '-0.000021');
    });
  });

  group('pagination', () {
    List<Map<String, dynamic>> manyRows(int count) => [
      for (var i = 0; i < count; i++)
        _nativeRow(
          hash: '0x${i.toString().padLeft(4, '0')}',
          from: _otherAddress,
          to: _myAddress,
          timeStamp: 1786731540 - i,
        ),
    ];

    test('sorts newest first and reports more pages remaining', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi((_) => _ok(manyRows(5)));

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 2),
          );

      expect(response.transactions.map((t) => t.txHash), ['0x0000', '0x0001']);
      expect(response.total, 5);
      expect(response.fromId, '0x0001');
    });

    test('fromId is null on the final page so the walk terminates', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi((_) => _ok(manyRows(3)));

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const TransactionBasedPagination(fromId: '0x0000', itemCount: 10),
          );

      expect(response.transactions.map((t) => t.txHash), ['0x0001', '0x0002']);
      expect(
        response.fromId,
        isNull,
        reason: 'a non-null fromId here would loop the manager forever',
      );
    });

    test('an exhausted page ends the walk rather than repeating', () async {
      final asset = _gleec();
      stubPubkeys(asset, [_myAddress]);
      final api = _FakeApi((_) => _ok(manyRows(2)));

      final response =
          await BlockscoutTransactionStrategy(
            pubkeyManager: pubkeyManager,
            httpClient: api.client,
          ).fetchTransactionHistory(
            _MockApiClient(),
            asset,
            const PagePagination(pageNumber: 1, itemsPerPage: 2),
          );

      expect(response.transactions, hasLength(2));
      expect(response.fromId, isNull);
    });
  });
}

class _MockApiClient extends Mock implements ApiClient {}
