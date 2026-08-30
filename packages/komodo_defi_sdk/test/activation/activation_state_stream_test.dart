import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockAssetHistory extends Mock implements AssetHistoryStorage {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockBalanceManager extends Mock implements IBalanceManager {}

class _MockConfigService extends Mock implements ActivationConfigService {}

class _MockAssetsUpdateManager extends Mock
    implements KomodoAssetsUpdateManager {}

class _MockActivatedAssetsCache extends Mock implements ActivatedAssetsCache {}

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

Map<String, dynamic> _kmdConfig() => {
  'coin': 'KMD',
  'type': 'UTXO',
  'name': 'Komodo',
  'fname': 'Komodo',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'",
  'protocol': {'type': 'UTXO'},
};

/// The SDK publishes per-asset activation state so consumers stop polling.
///
/// The property that matters most is **replay**: the app's previous bridge was
/// a bufferless broadcast that dropped events delivered while nothing was
/// listening, which left wallet rows stuck on `activating` for the session.
void main() {
  late _MockApiClient client;
  late _MockAuth auth;
  late _MockAssetHistory assetHistory;
  late _MockAssetLookup assetLookup;
  late _MockBalanceManager balanceManager;
  late _MockConfigService configService;
  late _MockAssetsUpdateManager assetsUpdateManager;
  late _MockActivatedAssetsCache cache;
  late Asset trx;
  late Asset kmd;

  const user = KdfUser(
    walletId: WalletId(
      name: 'wallet',
      pubkeyHash: 'wallet-pubkey',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    ),
    isBip39Seed: true,
  );

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(Asset.fromJson(_trxConfig(), knownIds: const {}));
    registerFallbackValue(user.walletId);
  });

  setUp(() {
    client = _MockApiClient();
    auth = _MockAuth();
    assetHistory = _MockAssetHistory();
    assetLookup = _MockAssetLookup();
    balanceManager = _MockBalanceManager();
    configService = _MockConfigService();
    assetsUpdateManager = _MockAssetsUpdateManager();
    cache = _MockActivatedAssetsCache();
    trx = Asset.fromJson(_trxConfig(), knownIds: const {});
    kmd = Asset.fromJson(_kmdConfig(), knownIds: const {});

    when(() => auth.currentUser).thenAnswer((_) async => user);
    when(
      () => auth.authStateChanges,
    ).thenAnswer((_) => const Stream<KdfUser?>.empty());
    when(() => assetLookup.fromId(trx.id)).thenReturn(trx);
    when(() => assetLookup.fromId(kmd.id)).thenReturn(kmd);
    when(cache.getActivatedAssetIds).thenAnswer((_) async => {});
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {});
    when(cache.invalidate).thenReturn(null);
    when(
      () => assetHistory.addAssetToWallet(any(), any()),
    ).thenAnswer((_) async {});
    when(() => balanceManager.precacheBalance(any())).thenAnswer((_) async {});
  });

  ActivationManager build() {
    final manager = ActivationManager(
      client,
      auth,
      assetHistory,
      assetLookup,
      balanceManager,
      configService,
      assetsUpdateManager,
      cache,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test('replays the current snapshot to a late subscriber', () async {
    // The defect this stream exists to fix: a subscriber that attaches after
    // the fact used to learn nothing, because the app's bridge was a
    // bufferless broadcast.
    final manager = build();
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {trx.id});

    await manager.isAssetActive(trx.id, forceRefresh: true);
    expect(manager.activationStates[trx.id]?.isActive, isTrue);

    // Subscribing only now still yields the truth, immediately.
    final first = await manager.watchActivationStates().first;
    expect(first[trx.id]?.isActive, isTrue);
  });

  test('a signed-out empty read never deactivates anything', () async {
    // ActivatedAssetsCache returns `const []` without an RPC when no user is
    // signed in. Acting on that would blank the wallet mid sign-out race;
    // the reset path owns clearing the map.
    final manager = build();
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {trx.id});
    await manager.isAssetActive(trx.id, forceRefresh: true);

    when(() => auth.currentUser).thenAnswer((_) async => null);
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => <AssetId>{});
    await manager.isAssetActive(trx.id, forceRefresh: true);

    expect(manager.activationStates[trx.id]?.isActive, isTrue);
  });

  test('a signed-in empty read sweeps stale actives', () async {
    // With a user signed in, a successful empty `get_enabled_coins` is KDF's
    // authoritative "nothing enabled" - the last coin disabled elsewhere, or
    // an authenticated KDF restart that re-enabled nothing. Preserving the
    // previous snapshot would leave activationStates - and everything gated
    // on it - claiming assets that are not there.
    final manager = build();
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {trx.id});
    await manager.isAssetActive(trx.id, forceRefresh: true);

    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => <AssetId>{});
    await manager.isAssetActive(trx.id, forceRefresh: true);

    expect(manager.activationStates.containsKey(trx.id), isFalse);
  });

  test('an asset KDF stops reporting is dropped', () async {
    final manager = build();
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {trx.id});
    await manager.isAssetActive(trx.id, forceRefresh: true);

    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {kmd.id});
    await manager.isAssetActive(kmd.id, forceRefresh: true);

    expect(manager.activationStates.containsKey(trx.id), isFalse);
    expect(manager.activationStates[kmd.id]?.isActive, isTrue);
  });

  test('repeated identical reads emit only once', () async {
    // SharedActivationCoordinator._waitForCoinAvailability polls up to 15
    // times per asset and every read folds back into the state map.
    final manager = build();
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {trx.id});

    final emissions = <Map<AssetId, AssetActivationState>>[];
    final sub = manager.watchActivationStates().listen(emissions.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    for (var i = 0; i < 15; i++) {
      await manager.isAssetActive(trx.id, forceRefresh: true);
    }
    await Future<void>.delayed(Duration.zero);

    // The replayed empty snapshot, then exactly one change.
    expect(emissions, hasLength(2));
    expect(emissions.last[trx.id]?.isActive, isTrue);
  });

  test('a wallet change clears the map and replays empty', () async {
    final manager = build();
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {trx.id});
    await manager.isAssetActive(trx.id, forceRefresh: true);

    manager.resetActivationSessionState();

    expect(manager.activationStates, isEmpty);
    // The stream stays open across a wallet change - a CoinsBloc subscription
    // outlives sign-out - so a late subscriber replays the empty snapshot.
    final first = await manager.watchActivationStates().first;
    expect(first, isEmpty);
  });

  test('recordActivationFailure overrides a recorded success', () async {
    // The coordinator's availability check is stricter than progress.isSuccess
    // and may contradict it.
    final manager = build();
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {trx.id});
    await manager.isAssetActive(trx.id, forceRefresh: true);
    expect(manager.activationStates[trx.id]?.isActive, isTrue);

    manager.recordActivationFailure(trx.id, 'did not become available');

    final state = manager.activationStates[trx.id]!;
    expect(state.isFailed, isTrue);
    expect(state.errorMessage, 'did not become available');
  });

  test('watchActivationStateOf ignores unrelated assets', () async {
    final manager = build();
    final seen = <AssetActivationState?>[];
    final sub = manager.watchActivationStateOf(trx.id).listen(seen.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    manager.recordActivationFailure(kmd.id, 'unrelated');
    await Future<void>.delayed(Duration.zero);

    // Only the initial null; the unrelated change is filtered by distinct().
    expect(seen, [null]);

    manager.recordActivationFailure(trx.id, 'mine');
    await Future<void>.delayed(Duration.zero);
    expect(seen.last?.isFailed, isTrue);
  });

  test('the emitted snapshot is a copy, not the live map', () async {
    final manager = build();
    final emissions = <Map<AssetId, AssetActivationState>>[];
    final sub = manager.watchActivationStates().listen(emissions.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    manager.recordActivationFailure(trx.id, 'first');
    await Future<void>.delayed(Duration.zero);
    final captured = emissions.last;

    manager.recordActivationFailure(kmd.id, 'second');
    await Future<void>.delayed(Duration.zero);

    expect(captured.containsKey(kmd.id), isFalse);
  });

  test('the stream closes on dispose', () async {
    final manager = ActivationManager(
      client,
      auth,
      assetHistory,
      assetLookup,
      balanceManager,
      configService,
      assetsUpdateManager,
      cache,
    );
    final done = expectLater(
      manager.watchActivationStates(),
      emitsThrough(emitsDone),
    );
    await manager.dispose();
    await done;
  });
}
