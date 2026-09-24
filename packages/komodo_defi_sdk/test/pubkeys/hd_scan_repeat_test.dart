import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// The HD address gap scan must not repeat on every poll.
///
/// `watchPubkeys` calls `_fetchFreshPubkeys` on every 30-second tick, and
/// `_fetchFreshPubkeys` calls `_scanForNewHdAddressesIfNeeded`. Before the
/// repeat guard, nothing bounded a *successful* scan:
///
///  * `_activationAlreadyScanned` is false for every ETH-family asset (their
///    activation params carry no `scan_policy`), so the activation skip never
///    fired for EVM at all;
///  * for UTXO, where it did fire, it was a one-shot `Set` - the second tick
///    found the key present, fell through, and scanned anyway;
///  * `_hdAddressScanRetryAfter` is a failure-only cooldown, *removed* on
///    success;
///  * `_inFlightPubkeyRequests` joins concurrent fetches, never sequential
///    ones.
///
/// So every asset walked its full gap every 30 seconds, forever. A scan is
/// `gap_limit + 1` = 21 candidate addresses, each costing `1 + 1 + N` node
/// RPCs for an unused EVM address - 168 requests per scan for GLEEC with six
/// GRC-20 tokens, against an endpoint measured at ~20 req/s.
class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

/// Keeps Hive out of a plain `package:test` run.
class _EmptyPubkeysStorage implements PubkeysStorage {
  @override
  Future<void> purgeWallet(WalletId walletId) async {}

  @override
  Future<Map<String, Map<String, dynamic>>> listForWallet(
    WalletId walletId,
  ) async => const {};

  @override
  Future<void> savePubkeys(
    WalletId walletId,
    String assetTicker,
    AssetPubkeys pubkeys, {
    Set<String> everFundedAddresses = const {},
  }) async {}
}

/// `DerivationMethod.hdWallet` is what makes `PubkeyStrategyFactory` pick the
/// HD strategy, whose `supportsMultipleAddresses` is what lets the scan run at
/// all.
const _hdUser = KdfUser(
  walletId: WalletId(
    name: 'hd-wallet',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

Asset _ethAsset() => Asset(
  id: AssetId(
    id: 'ETH',
    name: 'Ethereum',
    symbol: AssetSymbol(assetConfigId: 'ETH'),
    chainId: AssetChainId(chainId: 1, decimalsValue: 18),
    derivationPath: "m/44'/60'",
    subClass: CoinSubClass.erc20,
  ),
  protocol: Erc20Protocol.fromJson({
    'type': 'ERC20',
    'protocol': {
      'type': 'ETH',
      'protocol_data': {'platform': 'ETH'},
    },
    'derivation_path': "m/44'/60'",
    'nodes': [
      {'url': 'https://eth.example'},
    ],
    'swap_contract_address': '0x0000000000000000000000000000000000000001',
    'fallback_swap_contract': '0x0000000000000000000000000000000000000002',
  }),
  isWalletOnly: false,
  signMessagePrefix: null,
);

Asset _utxoAsset() => Asset(
  id: AssetId(
    id: 'KMD',
    name: 'Komodo',
    symbol: AssetSymbol(assetConfigId: 'KMD'),
    chainId: AssetChainId(chainId: 141, decimalsValue: 8),
    derivationPath: "m/44'/141'",
    subClass: CoinSubClass.smartChain,
  ),
  protocol: UtxoProtocol.fromJson({
    'type': 'UTXO',
    'protocol': {'type': 'UTXO'},
    'derivation_path': "m/44'/141'",
    'is_testnet': true,
    'electrum': [
      {'url': 'electrum1.example:10001'},
    ],
  }),
  isWalletOnly: false,
  signMessagePrefix: null,
);

Map<String, dynamic> _taskStarted(int taskId) => {
  'mmrpc': '2.0',
  'result': {'task_id': taskId},
};

Map<String, dynamic> _scanComplete() => {
  'mmrpc': '2.0',
  'result': {'status': 'Ok', 'details': null},
};

Map<String, dynamic> _accountBalance(String ticker, String address) => {
  'mmrpc': '2.0',
  'result': {
    'status': 'Ok',
    'details': {
      'account_index': 0,
      'derivation_path': "m/44'/60'/0'",
      'total_balance': {
        ticker: {'spendable': '0', 'unspendable': '0'},
      },
      'addresses': [
        {
          'address': address,
          'derivation_path': "m/44'/60'/0'/0/0",
          'chain': 'External',
          'balance': {
            ticker: {'spendable': '0', 'unspendable': '0'},
          },
        },
      ],
    },
  },
};

/// Counts `task::scan_for_new_addresses::init` calls and answers everything
/// else instantly.
///
/// Instant answers matter: `asyncMap` pauses the periodic source while its
/// future is pending, and a paused `Stream.periodic` cancels and re-arms its
/// timer, so any simulated latency would stretch the cadence and the elapse
/// arithmetic below would stop lining up with ticks.
class _ScanCounter {
  int scans = 0;

  void install(_MockApiClient client, Asset asset, {bool scanFails = false}) {
    when(() => client.executeRpc(any())).thenAnswer((invocation) {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      switch (request['method'] as String) {
        case 'task::scan_for_new_addresses::init':
          scans++;
          if (scanFails) {
            return Future<Map<String, dynamic>>.error(
              StateError('scan refused'),
            );
          }
          return Future.value(_taskStarted(1));
        case 'task::scan_for_new_addresses::status':
          return Future.value(_scanComplete());
        case 'task::account_balance::init':
          return Future.value(_taskStarted(2));
        case 'task::account_balance::status':
          return Future.value(_accountBalance(asset.id.id, '0xabc'));
        default:
          throw StateError('Unexpected RPC method: ${request['method']}');
      }
    });
  }
}

void main() {
  late _MockApiClient client;
  late _MockAuth auth;
  late _MockActivationCoordinator activation;
  late StreamController<KdfUser?> authChanges;
  late _ScanCounter rpc;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_ethAsset());
    registerFallbackValue(_ethAsset().id);
  });

  setUp(() {
    client = _MockApiClient();
    auth = _MockAuth();
    activation = _MockActivationCoordinator();
    authChanges = StreamController<KdfUser?>.broadcast();
    rpc = _ScanCounter();
    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => _hdUser);
  });

  tearDown(() async {
    await authChanges.close();
  });

  void stubActive(Asset asset, {required bool freshlyActivated}) {
    when(() => activation.isAssetActive(asset.id)).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(
      () => activation.wasFreshlyActivated(asset.id),
    ).thenReturn(freshlyActivated);
  }

  /// Subscribes to `watchPubkeys` and elapses [ticks] polling intervals.
  ///
  /// [now] is threaded in so the wall-clock guard can be moved independently of
  /// timer time - `fakeAsync` does not fake `DateTime.now()`.
  void runTicks({
    required Asset asset,
    required int ticks,
    DateTime Function()? now,
  }) {
    fakeAsync((async) {
      final manager = PubkeyManager(
        client,
        auth,
        activation,
        storage: _EmptyPubkeysStorage(),
        now: now,
      );
      final sub = manager.watchPubkeys(asset).listen((_) {});
      async.flushMicrotasks();

      for (var i = 0; i < ticks; i++) {
        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
      }

      unawaited(sub.cancel());
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  }

  test('ten watchPubkeys ticks on an EVM asset issue at most one gap scan', () {
    final asset = _ethAsset();
    stubActive(asset, freshlyActivated: false);
    rpc.install(client, asset);

    runTicks(asset: asset, ticks: 10);

    expect(
      rpc.scans,
      1,
      reason:
          'before the repeat guard this was 11 - one for the watcher\'s initial '
          'fetch and one per 30s tick - each walking 21 addresses. Exactly one, '
          'not zero: bounding the repeat must not disable discovery.',
    );
  });

  test('a UTXO asset scans once across many ticks, not once per tick', () {
    // The activation skip fired here, but only once: the second tick found the
    // key already in the done-set and fell straight through to a real scan,
    // and so did every tick after it.
    //
    // One scan, not zero, is deliberate. The activation credit only means the
    // protocol *asked* KDF to scan - `scan_if_new_wallet` walks only when KDF
    // has no stored HD account, so on every launch after the first the credit
    // is granted and nothing was actually walked. Treating the credit as a
    // completed scan would delay real discovery by the whole interval on every
    // warm re-login.
    final asset = _utxoAsset();
    stubActive(asset, freshlyActivated: true);
    rpc.install(client, asset);

    runTicks(asset: asset, ticks: 5);

    expect(
      rpc.scans,
      1,
      reason:
          'the post-activation duplicate is skipped once, one real scan then '
          'arms the interval, and every later tick is suppressed',
    );
  });

  test('the scan resumes once the interval has elapsed', () {
    final asset = _ethAsset();
    stubActive(asset, freshlyActivated: false);
    rpc.install(client, asset);

    // Wall clock advances a day per read while timer time advances normally,
    // so every tick sees far more than the six-hour interval since the last
    // completion stamp. (The guard reads the clock twice per scan - once to
    // compare, once to stamp - so a clock that advances only once would leave
    // the two readings a day apart and never re-arm.)
    var call = 0;
    DateTime clock() => DateTime(2026).add(Duration(days: call++));

    runTicks(asset: asset, ticks: 3, now: clock);

    expect(
      rpc.scans,
      greaterThan(1),
      reason:
          'the guard must bound the repeat, not disable discovery outright - '
          'an address set can still change between sessions',
    );
  });

  test('a failed scan does not arm the interval', () {
    final asset = _ethAsset();
    stubActive(asset, freshlyActivated: false);
    rpc.install(client, asset, scanFails: true);

    // Move the clock past the 2-minute failure cooldown on every read, so the
    // only thing that could suppress a retry is the success interval.
    var call = 0;
    DateTime clock() => DateTime(2026).add(Duration(minutes: 5 * call++));

    runTicks(asset: asset, ticks: 3, now: clock);

    expect(
      rpc.scans,
      greaterThan(1),
      reason:
          'the completion stamp is written after the await, so a throwing scan '
          'must leave the asset eligible once its failure cooldown expires',
    );
  });
}
