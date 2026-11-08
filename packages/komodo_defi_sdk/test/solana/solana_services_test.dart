import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/protocol_strategies/solana_activation_strategy.dart';
import 'package:komodo_defi_sdk/src/message_signing/message_signing_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_strategies.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_record_codec.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/runtime_auth_fixture.dart';
import 'solana_fixtures.dart';

class _Client implements ApiClient {
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic> response = {};
  Map<String, dynamic> Function(Map<String, dynamic>)? respond;
  void Function(Map<String, dynamic>)? beforeDispatch;
  @override
  Future<Map<String, dynamic>> executeRpc(Map<String, dynamic> request) async {
    beforeDispatch?.call(request);
    RpcDispatchGuard.ensureCurrent(request['method'] as String);
    requests.add(request);
    return respond?.call(request) ?? response;
  }
}

class _Auth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

void main() {
  final sol = solanaAsset();
  final token = solanaToken(sol);
  const verified = SolanaCapabilities(enabled: true);

  test(
    'batch activation retains complete mint metadata and permits zero ATA balance',
    () async {
      final client = _Client()
        ..response = {
          'mmrpc': '2.0',
          'result': {
            'ticker': sol.id.id,
            'address': 'WalletBase58',
            'current_block': 42,
            'balance': {'spendable': '0', 'unspendable': '0'},
            'tokens_balances': {
              token.id.id: {'spendable': '0', 'unspendable': '0'},
            },
          },
        };
      final strategy = SolanaActivationStrategy(
        client,
        const PrivateKeyPolicy.contextPrivKey(),
        verified,
      );
      final events = await strategy.activate(sol, [token]).toList();
      expect(events.last.isSuccess, isTrue);
      expect(client.requests.single['mmrpc'], '2.0');
      expect(client.requests.single['params'], {
        'ticker': 'SOL-DEV',
        'nodes': [
          {'url': 'https://api.devnet.solana.com'},
        ],
        'tokens_params': [
          {
            'ticker': token.id.id,
            'protocol': token.protocol.config['protocol'],
          },
        ],
        'tx_history': true,
      });
    },
  );

  test('later token activation sends a complete protocol override', () async {
    final client = _Client()
      ..response = {
        'mmrpc': '2.0',
        'result': {
          'ticker': token.id.id,
          'address': 'WalletBase58',
          'current_block': 42,
          'balance': {'spendable': '0', 'unspendable': '0'},
        },
      };
    final strategy = SolanaActivationStrategy(
      client,
      const PrivateKeyPolicy.contextPrivKey(),
      verified,
    );
    expect((await strategy.activate(token).toList()).last.isSuccess, isTrue);
    expect(
      client.requests.single['method'],
      'experimental::enable_solana_token',
    );
    expect(client.requests.single['params'], {
      'ticker': token.id.id,
      'activation_params': <String, dynamic>{},
      'protocol': token.protocol.config['protocol'],
    });
  });

  test('unsupported engine and Token-2022 refuse before any RPC', () async {
    final client = _Client();
    final disabled = SolanaActivationStrategy(
      client,
      const PrivateKeyPolicy.contextPrivKey(),
      const SolanaCapabilities(),
    );
    await expectLater(disabled.activate(sol).toList(), throwsUnsupportedError);
    final classic = SolanaActivationStrategy(
      client,
      const PrivateKeyPolicy.contextPrivKey(),
      verified,
    );
    await expectLater(
      classic.activate(sol, [solanaToken(sol, token2022: true)]).toList(),
      throwsUnsupportedError,
    );
    final external = SolanaActivationStrategy(
      client,
      const PrivateKeyPolicy.trezor(),
      verified,
    );
    await expectLater(external.activate(sol).toList(), throwsUnsupportedError);
    expect(client.requests, isEmpty);
  });

  for (final method in [DerivationMethod.iguana, DerivationMethod.hdWallet]) {
    test('history uses v2 without account target for $method', () async {
      final auth = _Auth();
      when(() => auth.currentUser).thenAnswer(
        (_) async => KdfUser(
          walletId: WalletId(
            name: 'fixture',
            pubkeyHash: 'public',
            authOptions: AuthOptions(derivationMethod: method),
          ),
          isBip39Seed: method == DerivationMethod.hdWallet,
        ),
      );
      final client = _Client()
        ..response = {
          'mmrpc': '2.0',
          'result': {
            'coin': token.id.id,
            'transactions': <Map<String, dynamic>>[],
            'current_block': 42,
            'sync_status': {'state': 'Finished'},
            'limit': 10,
            'skipped': 0,
            'total': 0,
            'total_pages': 0,
          },
        };
      await V2TransactionStrategy(auth).fetchTransactionHistory(
        client,
        token,
        const PagePagination(pageNumber: 1, itemsPerPage: 10),
      );
      expect(client.requests.single['mmrpc'], '2.0');
      expect(client.requests.single['params'], isNot(contains('target')));
    });
  }

  group('Solana message signing', () {
    late _Auth auth;
    late _Client client;
    late MessageSigningManager manager;
    final address = PubkeyInfo(
      address: 'WalletBase58',
      coinTicker: sol.id.id,
      derivationPath: "m/44'/501'/0'/0'",
      chain: null,
      balance: BalanceInfo.zero(),
    );
    setUp(() {
      auth = _Auth();
      when(() => auth.currentUser).thenAnswer(
        (_) async => const KdfUser(
          walletId: WalletId(
            name: 'fixture',
            pubkeyHash: 'public',
            authOptions: AuthOptions(
              derivationMethod: DerivationMethod.hdWallet,
            ),
          ),
          isBip39Seed: true,
        ),
      );
      client = _Client()
        ..respond = (request) => request['method'] == 'my_balance'
            ? {
                'coin': sol.id.id,
                'address': 'WalletBase58',
                'balance': '0',
                'unspendable_balance': '0',
              }
            : {
                'mmrpc': '2.0',
                'result': {'signature': 'SignedBase58'},
              };
      manager = MessageSigningManager(
        client,
        auth: auth,
        solanaCapabilities: verified,
      );
    });

    test('omits even a supplied HD address selector', () async {
      final signature = await manager.signMessage(
        asset: sol,
        addressInfo: address,
        message: 'Proof',
      );
      expect(signature, 'SignedBase58');
      expect(client.requests.map((r) => r['method']), [
        'my_balance',
        'sign_message',
      ]);
      expect(client.requests.last['params'], isNot(contains('address')));
      expect(client.requests.last['params'], isNot(contains('address_path')));
    });

    test('rejects a stale wallet address before signing', () async {
      client.respond = (_) => {
        'coin': sol.id.id,
        'address': 'DifferentWallet',
        'balance': '0',
        'unspendable_balance': '0',
      };
      await expectLater(
        manager.signMessage(asset: sol, addressInfo: address, message: 'Proof'),
        throwsA(isA<UnknownAddressException>()),
      );
      expect(client.requests.map((r) => r['method']), ['my_balance']);
    });

    test('rejects wallet transition during address lookup', () async {
      final respond = client.respond!;
      client.respond = (request) {
        final response = respond(request);
        auth.runtimeSessions.invalidate();
        return response;
      };
      await expectLater(
        manager.signMessage(asset: sol, addressInfo: address, message: 'Proof'),
        throwsA(isA<AuthSessionChangedException>()),
      );
      expect(client.requests.map((r) => r['method']), ['my_balance']);
    });

    test(
      'transport preparation cannot dispatch signing after auth changes',
      () async {
        client.beforeDispatch = (request) {
          if (request['method'] == 'sign_message')
            auth.runtimeSessions.invalidate();
        };
        await expectLater(
          manager.signMessage(
            asset: sol,
            addressInfo: address,
            message: 'Proof',
          ),
          throwsA(isA<RpcDispatchRejected>()),
        );
        expect(client.requests.map((r) => r['method']), ['my_balance']);
      },
    );

    test('discards signature when wallet changes during signing', () async {
      final respond = client.respond!;
      client.respond = (request) {
        if (request['method'] == 'sign_message')
          auth.runtimeSessions.invalidate();
        return respond(request);
      };
      await expectLater(
        manager.signMessage(asset: sol, addressInfo: address, message: 'Proof'),
        throwsA(isA<AuthSessionChangedException>()),
      );
    });
  });

  test(
    'Solana fee persistence retains rent, SOL currency and signature case',
    () {
      final info = TransactionInfo.fromJson(solanaHistoryRow());
      final transaction = info.asTransaction(token.id);
      final restored = TransactionRecordCodec.decode(
        TransactionRecordCodec.encode(transaction),
      );
      expect(restored, transaction);
      expect(restored.id, 'AbCdeF123Base58Signature');
      expect(restored.memo, isNull);
      final fee = restored.fee! as SolanaFeeInfo;
      expect(fee.coin, sol.id.id);
      expect(fee.feeAmount, Decimal.parse('0.000005'));
      expect(fee.rentAmount, Decimal.parse('0.00203928'));
      expect(fee.totalFee, Decimal.parse('0.00204428'));
    },
  );
}
