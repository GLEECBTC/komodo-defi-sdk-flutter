import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
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

class _MockAssetHistoryStorage extends Mock implements AssetHistoryStorage {}

/// A real subscription rather than a mock: `BalanceManager` calls `onData` on
/// it and `cancel`s it during dispose, and a mocked `cancel` returns null where
/// a `Future<void>` is awaited.
StreamSubscription<BalanceEvent> _idleBalanceSubscription() =>
    StreamController<BalanceEvent>.broadcast().stream.listen((_) {});

const _wallet = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
);

/// GLEEC, an EVM platform coin, and one of its GRC-20 tokens.
///
/// The token declares `parent_coin`, which is what `AssetId.parentId` reads and
/// therefore what tells `BalanceManager` the platform streamer already covers
/// it.
(Asset platform, Asset token) _evmPair() {
  // Field-for-field the shipped coins_config shapes. Both carry
  // `type: GRC-20`; what separates them is `protocol.type` (ETH vs ERC20) and
  // the token's `parent_coin`.
  final platform = Asset.fromJson(const {
    'coin': 'GLEEC',
    'type': 'GRC-20',
    'name': 'Gleec',
    'fname': 'Gleec',
    'mm2': 1,
    'chain_id': 11169,
    'decimals': 18,
    'required_confirmations': 3,
    'derivation_path': "m/44'/60'",
    'protocol': {
      'type': 'ETH',
      'protocol_data': {'chain_id': 11169},
    },
    'nodes': [
      {'url': 'https://evm-rpc.gleec.com', 'ws_url': 'wss://evm-ws.gleec.com'},
    ],
    'swap_contract_address': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
    'fallback_swap_contract': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
  }, knownIds: const {});

  final token = Asset.fromJson(
    const {
      'coin': 'A29-GRC20',
      'type': 'GRC-20',
      'name': 'A29',
      'fname': 'A29',
      'mm2': 1,
      'chain_id': 11169,
      'decimals': 18,
      'required_confirmations': 3,
      'derivation_path': "m/44'/60'",
      'protocol': {
        'type': 'ERC20',
        'protocol_data': {
          'platform': 'GLEEC',
          'contract_address': '0x08E8F49921C9650f13473cCadb948B3cf3C6c4F9',
        },
      },
      'contract_address': '0x08E8F49921C9650f13473cCadb948B3cf3C6c4F9',
      'parent_coin': 'GLEEC',
      'nodes': [
        {
          'url': 'https://evm-rpc.gleec.com',
          'ws_url': 'wss://evm-ws.gleec.com',
        },
      ],
      'swap_contract_address': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
      'fallback_swap_contract': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
    },
    knownIds: {platform.id},
  );

  return (platform, token);
}

AssetPubkeys _pubkeys(Asset asset, String total) => AssetPubkeys(
  assetId: asset.id,
  keys: [
    PubkeyInfo(
      address: '0xabc',
      derivationPath: null,
      chain: null,
      balance: BalanceInfo(
        total: Decimal.parse(total),
        spendable: Decimal.parse(total),
        unspendable: Decimal.zero,
      ),
      coinTicker: asset.id.id,
    ),
  ],
  availableAddressesCount: 1,
  syncStatus: SyncStatusEnum.success,
);

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  setUpAll(() {
    final (platform, _) = _evmPair();
    registerFallbackValue(platform);
    registerFallbackValue(platform.id);
    registerFallbackValue(_wallet.walletId);
  });

  group('one KDF balance streamer per EVM platform, not per token', () {
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockPubkeyManager pubkeys;
    late _MockAssetLookup assetLookup;
    late _MockAssetHistoryStorage assetHistory;
    late _MockEventStreamingManager streaming;
    late StreamController<KdfUser?> authChanges;
    late List<({String coin, String? streamerCoin})> subscribeCalls;

    setUp(() {
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      pubkeys = _MockPubkeyManager();
      assetLookup = _MockAssetLookup();
      assetHistory = _MockAssetHistoryStorage();
      streaming = _MockEventStreamingManager();
      authChanges = StreamController<KdfUser?>.broadcast();
      subscribeCalls = [];

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => _wallet);
      when(
        () => streaming.subscribeToBalance(
          coin: any(named: 'coin'),
          streamerCoin: any(named: 'streamerCoin'),
        ),
      ).thenAnswer((invocation) async {
        subscribeCalls.add((
          coin: invocation.namedArguments[#coin] as String,
          streamerCoin: invocation.namedArguments[#streamerCoin] as String?,
        ));
        return _idleBalanceSubscription();
      });
    });

    tearDown(() async {
      await authChanges.close();
    });

    BalanceManager buildManager() => BalanceManager(
      assetLookup: assetLookup,
      auth: auth,
      pubkeyManager: pubkeys,
      activationCoordinator: activation,
      eventStreamingManager: streaming,
      assetHistoryStorage: assetHistory,
    );

    void stubAsset(Asset asset) {
      when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
      when(
        () => activation.isAssetActive(asset.id),
      ).thenAnswer((_) async => true);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));
      when(
        () => assetHistory.getWalletAssets(_wallet.walletId),
      ).thenAnswer((_) async => {asset.id.id});
      when(
        () => pubkeys.getPubkeys(asset),
      ).thenAnswer((_) async => _pubkeys(asset, '1'));
      when(
        () => pubkeys.refreshPubkeys(asset),
      ).thenAnswer((_) async => _pubkeys(asset, '1'));
      when(
        () => pubkeys.watchPubkeys(asset),
      ).thenAnswer((_) => const Stream.empty());
    }

    test('an EVM token subscribes against its platform coin', () async {
      final (platform, token) = _evmPair();
      stubAsset(token);
      final manager = buildManager();

      final subscription = manager.watchBalance(token.id).listen((_) {});
      addTearDown(() async {
        await subscription.cancel();
        await manager.dispose();
      });

      await _waitUntil(() => subscribeCalls.isNotEmpty);

      expect(subscribeCalls, hasLength(1));
      expect(subscribeCalls.single.coin, token.id.id);
      expect(
        subscribeCalls.single.streamerCoin,
        platform.id.id,
        reason:
            "KDF's platform streamer already polls all_addresses() x (its own "
            'ticker plus every registered token), so a streamer enabled on the '
            'token re-polls the identical address set for nothing',
      );
    });

    test('an EVM platform coin still subscribes on its own ticker', () async {
      final (platform, _) = _evmPair();
      stubAsset(platform);
      final manager = buildManager();

      final subscription = manager.watchBalance(platform.id).listen((_) {});
      addTearDown(() async {
        await subscription.cancel();
        await manager.dispose();
      });

      await _waitUntil(() => subscribeCalls.isNotEmpty);

      expect(subscribeCalls.single.coin, platform.id.id);
      expect(
        subscribeCalls.single.streamerCoin,
        isNull,
        reason: 'a platform coin hosts its own streamer',
      );
    });

    test('a non-EVM asset is never redirected', () async {
      // TRON is deliberately out of scope: gas-free TRC-20 balances live at a
      // derived custody address, so whether the platform streamer covers a
      // token is a separate question with its own answer.
      final trx = Asset.fromJson(const {
        'coin': 'TRX',
        'type': 'TRX',
        'name': 'TRON',
        'fname': 'TRON',
        'mm2': 1,
        'decimals': 6,
        'required_confirmations': 1,
        'derivation_path': "m/44'/195'",
        'protocol': {
          'type': 'TRX',
          'protocol_data': {'network': 'Mainnet'},
        },
        'nodes': <Map<String, dynamic>>[],
      }, knownIds: const {});
      final usdt = Asset.fromJson(
        const {
          'coin': 'USDT-TRC20',
          'type': 'TRC-20',
          'name': 'Tether',
          'fname': 'Tether',
          'mm2': 1,
          'decimals': 6,
          'required_confirmations': 1,
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
        },
        knownIds: {trx.id},
      );

      stubAsset(usdt);
      final manager = buildManager();

      final subscription = manager.watchBalance(usdt.id).listen((_) {});
      addTearDown(() async {
        await subscription.cancel();
        await manager.dispose();
      });

      await _waitUntil(() => subscribeCalls.isNotEmpty);

      expect(subscribeCalls.single.streamerCoin, isNull);
    });
  });

  group('the polling fallback actually fetches', () {
    test('a forced balance read bypasses the pubkey cache', () async {
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final assetLookup = _MockAssetLookup();
      final assetHistory = _MockAssetHistoryStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      final (platform, _) = _evmPair();

      // `getPubkeys` models the real manager's TTL-less in-memory cache: once
      // populated it answers the same value forever, and nothing on the
      // fallback path writes it. `refreshPubkeys` is the only thing that goes
      // back to KDF.
      var onChainTotal = '1';
      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => _wallet);
      when(() => assetLookup.fromId(platform.id)).thenReturn(platform);
      when(
        () => pubkeys.getPubkeys(platform),
      ).thenAnswer((_) async => _pubkeys(platform, '1'));
      when(
        () => pubkeys.refreshPubkeys(platform),
      ).thenAnswer((_) async => _pubkeys(platform, onChainTotal));

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: activation,
        eventStreamingManager: _MockEventStreamingManager(),
        assetHistoryStorage: assetHistory,
      );
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      expect((await manager.getBalance(platform.id)).total, Decimal.one);

      // The on-chain balance moves while the stream is down.
      onChainTotal = '42';

      expect(
        (await manager.getBalance(platform.id)).total,
        Decimal.one,
        reason: 'the default read is still allowed to serve the cache',
      );
      expect(
        (await manager.getBalance(platform.id, forceRefresh: true)).total,
        Decimal.fromInt(42),
        reason:
            'without this the polling fallback re-reads a cache nothing '
            'refreshes and the balance freezes for the rest of the session, '
            'silently, with no error surfaced',
      );

      verify(() => pubkeys.refreshPubkeys(platform)).called(1);
    });
  });
}
