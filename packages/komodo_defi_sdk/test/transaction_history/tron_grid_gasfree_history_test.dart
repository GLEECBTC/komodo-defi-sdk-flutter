import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/tronscan_transaction_history_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockApiClient extends Mock implements ApiClient {}

const _eoa = 'TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7';
const _custody = 'TKoCV62HPYYxghKQJV7bmW3g6KpWb1dGhQ';
const _eoa2 = 'TNUC9Qb1rRpS5CbWLmNMxXBjyFoydXjWFR';
const _custody2 = 'TSSMHYeV2uE9qYH95DqyoCuNCzEL1NvU3S';
const _external = 'TEkxiTehnzSmSe2XqrBj4w32RUN966rdz8';
const _recipient = 'TVj7RNVHy6thbM7BWdSe9G6gXwKhjhdNZS';
const _provider = 'TWd4WrZ9wn84f5x1hZhL4DHvk738ns5jwb';
const _finalityHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _mismatchHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

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

Asset _createUsdtTrc20Asset({bool nile = false}) {
  final platform = nile ? 'TRXT' : 'TRX';
  final coin = nile ? 'TESTUSDT-TRC20' : 'USDT-TRC20';
  final contract = nile
      ? 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf'
      : 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
  final parent = Asset.fromJson({
    'coin': platform,
    'type': 'TRX',
    'name': platform,
    'fname': platform,
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'protocol': {
      'type': 'TRX',
      'protocol_data': {'network': nile ? 'Nile' : 'Mainnet'},
    },
    'nodes': <Map<String, dynamic>>[],
  }, knownIds: const {});
  return Asset.fromJson(
    {
      'coin': coin,
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
        'protocol_data': {'platform': platform, 'contract_address': contract},
      },
      'contract_address': contract,
      'parent_coin': platform,
      'nodes': <Map<String, dynamic>>[],
    },
    knownIds: {parent.id},
  );
}

/// Pubkeys for [asset] with one entry per `{address: gasfreeAddress}` pair.
/// A null (or empty) gasfree address models a non-gasless pubkey.
AssetPubkeys _makePubkeys(
  Asset asset, {
  Map<String, String?> addresses = const {_eoa: null},
}) => AssetPubkeys(
  assetId: asset.id,
  keys: [
    for (final entry in addresses.entries)
      PubkeyInfo(
        address: entry.key,
        derivationPath: null,
        chain: null,
        balance: BalanceInfo.zero(),
        coinTicker: asset.id.id,
        gasfreeAddress: entry.value,
      ),
  ],
  availableAddressesCount: addresses.length,
  syncStatus: SyncStatusEnum.success,
);

/// TRONGrid `/v1/accounts/{addr}/transactions/trc20` row shape.
Map<String, Object> _makeTrc20Row({
  required String txId,
  required String from,
  required String to,
  required String value,
  String tokenAddress = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  int timestampMs = 1700000000000,
}) => {
  'transaction_id': txId,
  'from': from,
  'to': to,
  'value': value,
  'type': 'Transfer',
  'token_info': {
    'symbol': 'USDT',
    'address': tokenAddress,
    'decimals': 6,
    'name': 'Tether USD',
  },
  'block_timestamp': timestampMs,
};

http.Response _gridResponse(List<Object> rows, {String? fingerprint}) =>
    http.Response(
      jsonEncode({
        'data': rows,
        'meta': fingerprint != null
            ? <String, Object>{'fingerprint': fingerprint}
            : <String, Object>{},
      }),
      200,
    );

void main() {
  late PubkeyManager pubkeyManager;
  late _MockHttpClient httpClient;
  late _MockApiClient apiClient;

  setUpAll(() {
    registerFallbackValue(
      Uri.parse('https://api.trongrid.io/v1/accounts/T/transactions'),
    );
  });

  setUp(() {
    pubkeyManager = _MockPubkeyManager();
    httpClient = _MockHttpClient();
    apiClient = _MockApiClient();
  });

  TronGridTransactionStrategy createStrategy() => TronGridTransactionStrategy(
    pubkeyManager: pubkeyManager,
    httpClient: httpClient,
    apiHostOverride: 'api.trongrid.io',
  );

  /// Routes requests to per-address responses (matched on the URI path) and
  /// records every request URI in the returned list.
  List<Uri> stubResponses(Map<String, http.Response Function(Uri)> handlers) {
    final requestUris = <Uri>[];
    when(() => httpClient.get(any())).thenAnswer((invocation) async {
      final uri = invocation.positionalArguments.first as Uri;
      requestUris.add(uri);
      for (final entry in handlers.entries) {
        if (uri.path.contains(entry.key)) return entry.value(uri);
      }
      throw StateError('Unexpected TRONGrid URI: $uri');
    });
    return requestUris;
  }

  group('TronGridTransactionStrategy GasFree custody history', () {
    for (final nile in [false, true]) {
      test(
        'verifies exact ${nile ? 'Nile' : 'mainnet'} recipient event',
        () async {
          final asset = _createUsdtTrc20Asset(nile: nile);
          final contract = nile
              ? 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf'
              : 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
          stubResponses({
            _custody: (_) => _gridResponse([
              _makeTrc20Row(
                txId: _finalityHash,
                from: _custody,
                to: _recipient,
                value: '10000000',
                tokenAddress: contract,
              ),
              _makeTrc20Row(
                txId: _finalityHash,
                from: _custody,
                to: _provider,
                value: '1500000',
                tokenAddress: contract,
              ),
            ]),
          });

          final result = await createStrategy().verifyGaslessTransferEvent(
            asset: asset,
            transactionHash: _finalityHash,
            custodyAddress: _custody,
            recipientAddress: _recipient,
            authorizationValue: '10000000',
          );

          expect(result, GaslessOnChainVerification.verified);
        },
      );
    }

    test(
      'does not accept the provider-fee aggregate as recipient amount',
      () async {
        final usdt = _createUsdtTrc20Asset();
        stubResponses({
          _custody: (_) => _gridResponse([
            _makeTrc20Row(
              txId: _mismatchHash,
              from: _custody,
              to: _recipient,
              value: '10000000',
            ),
            _makeTrc20Row(
              txId: _mismatchHash,
              from: _custody,
              to: _provider,
              value: '1500000',
            ),
          ]),
        });

        final result = await createStrategy().verifyGaslessTransferEvent(
          asset: usdt,
          transactionHash: _mismatchHash,
          custodyAddress: _custody,
          recipientAddress: _recipient,
          authorizationValue: '11500000',
        );

        expect(result, GaslessOnChainVerification.mismatch);
      },
    );

    test('queries EOA and custody address in a single call', () async {
      final usdt = _createUsdtTrc20Asset();
      when(() => pubkeyManager.getPubkeys(usdt)).thenAnswer(
        (_) async => _makePubkeys(usdt, addresses: {_eoa: _custody}),
      );
      final requestUris = stubResponses({
        _eoa: (_) => _gridResponse([]),
        _custody: (_) => _gridResponse([]),
      });

      await createStrategy().fetchTransactionHistory(
        apiClient,
        usdt,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(requestUris, hasLength(2));
      expect(requestUris[0].path, '/v1/accounts/$_eoa/transactions/trc20');
      expect(requestUris[1].path, '/v1/accounts/$_custody/transactions/trc20');
    });

    test('does not query custody for non-gasless pubkeys', () async {
      final usdt = _createUsdtTrc20Asset();
      when(
        () => pubkeyManager.getPubkeys(usdt),
      ).thenAnswer((_) async => _makePubkeys(usdt));
      final requestUris = stubResponses({_eoa: (_) => _gridResponse([])});

      await createStrategy().fetchTransactionHistory(
        apiClient,
        usdt,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(requestUris, hasLength(1));
      expect(requestUris.single.path.contains(_custody), isFalse);
    });

    test('treats an empty-string gasfree address as absent', () async {
      final usdt = _createUsdtTrc20Asset();
      when(
        () => pubkeyManager.getPubkeys(usdt),
      ).thenAnswer((_) async => _makePubkeys(usdt, addresses: {_eoa: ''}));
      final requestUris = stubResponses({_eoa: (_) => _gridResponse([])});

      await createStrategy().fetchTransactionHistory(
        apiClient,
        usdt,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(requestUris, hasLength(1));
    });

    test('does not query custody for TRX-native assets', () async {
      final trx = _createTrxAsset();
      when(
        () => pubkeyManager.getPubkeys(trx),
      ).thenAnswer((_) async => _makePubkeys(trx, addresses: {_eoa: _custody}));
      final requestUris = stubResponses({_eoa: (_) => _gridResponse([])});

      await createStrategy().fetchTransactionHistory(
        apiClient,
        trx,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(requestUris, hasLength(1));
      expect(requestUris.single.path, '/v1/accounts/$_eoa/transactions');
    });

    test('custody deposit renders as a single incoming transaction', () async {
      final usdt = _createUsdtTrc20Asset();
      when(() => pubkeyManager.getPubkeys(usdt)).thenAnswer(
        (_) async => _makePubkeys(usdt, addresses: {_eoa: _custody}),
      );
      stubResponses({
        _eoa: (_) => _gridResponse([]),
        _custody: (_) => _gridResponse([
          _makeTrc20Row(
            txId: 'deposit1',
            from: _external,
            to: _custody,
            value: '25000000',
          ),
        ]),
      });

      final response = await createStrategy().fetchTransactionHistory(
        apiClient,
        usdt,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(response.transactions, hasLength(1));
      final tx = response.transactions.single;
      expect(Decimal.parse(tx.myBalanceChange), Decimal.parse('25'));
      expect(Decimal.parse(tx.receivedByMe!), Decimal.parse('25'));
      expect(Decimal.parse(tx.spentByMe!), Decimal.zero);
      expect(tx.to, contains(_custody));
    });

    test('gasless send merges same-hash transfer events into one tx', () async {
      final usdt = _createUsdtTrc20Asset();
      when(() => pubkeyManager.getPubkeys(usdt)).thenAnswer(
        (_) async => _makePubkeys(usdt, addresses: {_eoa: _custody}),
      );
      stubResponses({
        _eoa: (_) => _gridResponse([]),
        // One TRONGrid row per Transfer event: recipient, provider fee, and
        // account-activation fee, all sharing the same transaction hash.
        _custody: (_) => _gridResponse([
          _makeTrc20Row(
            txId: 'gasless1',
            from: _custody,
            to: _recipient,
            value: '10000000',
          ),
          _makeTrc20Row(
            txId: 'gasless1',
            from: _custody,
            to: _provider,
            value: '1500000',
          ),
          _makeTrc20Row(
            txId: 'gasless1',
            from: _custody,
            to: _provider,
            value: '1500000',
          ),
        ]),
      });

      final response = await createStrategy().fetchTransactionHistory(
        apiClient,
        usdt,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(response.transactions, hasLength(1));
      final tx = response.transactions.single;
      expect(Decimal.parse(tx.myBalanceChange), Decimal.parse('-13'));
      expect(Decimal.parse(tx.spentByMe!), Decimal.parse('13'));
      expect(Decimal.parse(tx.receivedByMe!), Decimal.zero);
      expect(tx.to, containsAll([_recipient, _provider]));
    });

    test(
      'consolidation nets to zero within one call with no pending split',
      () async {
        final usdt = _createUsdtTrc20Asset();
        when(() => pubkeyManager.getPubkeys(usdt)).thenAnswer(
          (_) async => _makePubkeys(usdt, addresses: {_eoa: _custody}),
        );
        final consolidation = _makeTrc20Row(
          txId: 'consol1',
          from: _eoa,
          to: _custody,
          value: '40000000',
        );
        final requestUris = stubResponses({
          _eoa: (_) => _gridResponse([consolidation]),
          _custody: (_) => _gridResponse([consolidation]),
        });

        final response = await createStrategy().fetchTransactionHistory(
          apiClient,
          usdt,
          const PagePagination(pageNumber: 1, itemsPerPage: 20),
        );

        // Both group members are fetched in the same call even though the
        // EOA already produced data: no __pending__ marker between an EOA
        // and its custody address.
        expect(requestUris, hasLength(2));
        expect(response.fromId, isNull);

        expect(response.transactions, hasLength(1));
        final tx = response.transactions.single;
        expect(Decimal.parse(tx.myBalanceChange), Decimal.zero);
        expect(Decimal.parse(tx.spentByMe!), Decimal.parse('40'));
        expect(Decimal.parse(tx.receivedByMe!), Decimal.parse('40'));
        expect(tx.from, [_eoa]);
        expect(tx.to, [_custody]);
      },
    );

    test('continues mixed EOA and custody cursors independently', () async {
      final usdt = _createUsdtTrc20Asset();
      when(() => pubkeyManager.getPubkeys(usdt)).thenAnswer(
        (_) async => _makePubkeys(usdt, addresses: {_eoa: _custody}),
      );
      final requestUris = stubResponses({
        _eoa: (uri) => uri.queryParameters.containsKey('fingerprint')
            ? _gridResponse([])
            : _gridResponse([
                _makeTrc20Row(
                  txId: 'txE1',
                  from: _eoa,
                  to: _external,
                  value: '1000000',
                ),
              ], fingerprint: 'fpE'),
        _custody: (uri) => uri.queryParameters.containsKey('fingerprint')
            ? _gridResponse([
                _makeTrc20Row(
                  txId: 'txC2',
                  from: _external,
                  to: _custody,
                  value: '3000000',
                ),
              ], fingerprint: 'fpC2')
            : _gridResponse([
                _makeTrc20Row(
                  txId: 'txC1',
                  from: _external,
                  to: _custody,
                  value: '2000000',
                ),
              ], fingerprint: 'fpC'),
      });

      final strategy = createStrategy();
      final first = await strategy.fetchTransactionHistory(
        apiClient,
        usdt,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      expect(jsonDecode(first.fromId!), {_eoa: 'fpE', _custody: 'fpC'});

      final second = await strategy.fetchTransactionHistory(
        apiClient,
        usdt,
        TransactionBasedPagination(fromId: first.fromId!, itemCount: 20),
      );

      // Each address is continued with its own fingerprint.
      expect(requestUris, hasLength(4));
      expect(requestUris[2].path, contains(_eoa));
      expect(requestUris[2].queryParameters['fingerprint'], 'fpE');
      expect(requestUris[3].path, contains(_custody));
      expect(requestUris[3].queryParameters['fingerprint'], 'fpC');

      // The exhausted EOA is dropped from the next cursor.
      expect(jsonDecode(second.fromId!), {_custody: 'fpC2'});
      expect(second.transactions, hasLength(1));

      // A third call with the custody-only cursor skips the exhausted EOA
      // inside the group and continues only the live custody address.
      await strategy.fetchTransactionHistory(
        apiClient,
        usdt,
        TransactionBasedPagination(fromId: second.fromId!, itemCount: 20),
      );
      expect(requestUris, hasLength(5));
      expect(requestUris[4].path, contains(_custody));
      expect(requestUris[4].queryParameters['fingerprint'], 'fpC2');
    });

    test('early-yields only at group boundaries with two pubkeys', () async {
      final usdt = _createUsdtTrc20Asset();
      when(() => pubkeyManager.getPubkeys(usdt)).thenAnswer(
        (_) async =>
            _makePubkeys(usdt, addresses: {_eoa: _custody, _eoa2: _custody2}),
      );
      final requestUris = stubResponses({
        _eoa: (_) => _gridResponse([
          _makeTrc20Row(
            txId: 'txE1',
            from: _eoa,
            to: _external,
            value: '1000000',
          ),
        ]),
        _custody: (_) => _gridResponse([]),
        _eoa2: (_) => _gridResponse([]),
        _custody2: (_) => _gridResponse([]),
      });

      final strategy = createStrategy();
      final first = await strategy.fetchTransactionHistory(
        apiClient,
        usdt,
        const PagePagination(pageNumber: 1, itemsPerPage: 20),
      );

      // Group 1 produced data, so its custody address is still fetched but
      // all of group 2's addresses are deferred as pending.
      expect(requestUris, hasLength(2));
      expect(requestUris[0].path, contains(_eoa));
      expect(requestUris[1].path, contains(_custody));
      expect(jsonDecode(first.fromId!), {
        _eoa2: '__pending__',
        _custody2: '__pending__',
      });

      await strategy.fetchTransactionHistory(
        apiClient,
        usdt,
        TransactionBasedPagination(fromId: first.fromId!, itemCount: 20),
      );

      // The continuation call fetches only group 2.
      expect(requestUris, hasLength(4));
      expect(requestUris[2].path, contains(_eoa2));
      expect(requestUris[3].path, contains(_custody2));
    });
  });
}
