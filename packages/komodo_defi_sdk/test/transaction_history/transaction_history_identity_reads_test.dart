import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_strategies.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/counting_session_auth.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAssetProvider extends Mock implements IAssetProvider {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _MockAssetHistoryStorage extends Mock implements AssetHistoryStorage {}

class _CountingStrategy extends TransactionHistoryStrategy {
  int fetches = 0;

  @override
  Set<Type> get supportedPaginationModes => const {PagePagination};

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) async {
    fetches++;
    return MyTxHistoryResponse.parse(_emptyHistory);
  }

  @override
  bool supportsAsset(Asset asset) => true;
}

const _emptyHistory = <String, dynamic>{
  'mmrpc': '2.0',
  'result': {
    'current_block': 100,
    'from_id': null,
    'limit': 50,
    'skipped': 0,
    'sync_status': {'state': 'Finished'},
    'total': 0,
    'total_pages': 1,
    'page_number': 1,
    'transactions': <dynamic>[],
  },
};

const _user = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
  metadata: {'isImported': true},
);

Asset _atom() => Asset(
  id: AssetId(
    id: 'ATOM',
    name: 'Cosmos',
    symbol: AssetSymbol(assetConfigId: 'ATOM'),
    chainId: AssetChainId(chainId: 118, decimalsValue: 6),
    derivationPath: null,
    subClass: CoinSubClass.tendermint,
  ),
  protocol: TendermintProtocol.fromJson({
    'type': 'Tendermint',
    'rpc_urls': [
      {'url': 'https://rpc.example.com'},
    ],
  }),
  isWalletOnly: false,
  signMessagePrefix: null,
);

/// History fetches must not re-verify the wallet identity per page.
///
/// Every fetch used to read `currentUser` while capturing its context, again
/// for the new-wallet shortcut, and once more at each commit check; the v2
/// strategy read it again for the HD target. Each read is a
/// `get_wallet_names` plus `get_public_key_hash` round trip.
void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  test('repeated history fetches read the signed-in user once', () {
    final asset = _atom();
    final auth = CountingSessionAuth(_user);
    addTearDown(auth.authChanges.close);
    final assetProvider = _MockAssetProvider();
    final activation = _MockActivationCoordinator();
    final assetHistory = _MockAssetHistoryStorage();
    final strategy = _CountingStrategy();

    when(() => assetProvider.fromId(asset.id)).thenReturn(asset);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(
      () => assetHistory.getWalletAssets(_user.walletId),
    ).thenAnswer((_) async => {asset.id.id});

    fakeAsync((async) {
      final manager = TransactionHistoryManager(
        _MockApiClient(),
        auth,
        assetProvider,
        activation,
        pubkeyManager: _MockPubkeyManager(),
        eventStreamingManager: _MockEventStreamingManager(),
        storage: InMemoryTransactionStorage(),
        assetHistoryStorage: assetHistory,
        transactionHistoryStrategies: [strategy],
      );

      for (var page = 0; page < 5; page++) {
        unawaited(manager.getTransactionHistory(asset));
        // Past the manager's 500 ms rate limiter.
        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
      }

      expect(strategy.fetches, 5);
      expect(
        auth.identityReads,
        lessThanOrEqualTo(2),
        reason:
            'one read opens the session and one serves the new-wallet '
            'shortcut; this was about five reads per fetch before the fix',
      );

      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  for (final hd in [true, false]) {
    test('the v2 strategy takes HD mode from the session (HD: $hd)', () async {
      final user = hd
          ? _user
          : _user.copyWith(
              walletId: _user.walletId.copyWith(
                authOptions: const AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
            );
      final auth = CountingSessionAuth(user);
      addTearDown(auth.authChanges.close);
      await auth.captureSessionContext();
      final readsWithSession = auth.identityReads;
      final client = _MockApiClient();
      Map<String, dynamic>? sent;
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        sent = invocation.positionalArguments.single as Map<String, dynamic>;
        return _emptyHistory;
      });

      await V2TransactionStrategy(auth).fetchTransactionHistory(
        client,
        _atom(),
        const PagePagination(pageNumber: 1, itemsPerPage: 10),
      );

      expect(auth.identityReads, readsWithSession);
      expect(
        (sent!['params'] as Map<String, dynamic>).containsKey('target'),
        hd,
        reason:
            'an HD wallet queries its account; an iguana wallet its address',
      );
    });
  }
}
