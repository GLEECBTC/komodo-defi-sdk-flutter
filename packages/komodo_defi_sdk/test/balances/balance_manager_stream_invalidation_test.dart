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
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/runtime_auth_fixture.dart';

class _MockAuth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockAssetHistoryStorage extends Mock implements AssetHistoryStorage {}

class _MockApiClient extends Mock implements ApiClient {}

class _MockEventStreamingService extends Mock
    implements KdfEventStreamingService {}

const _fallbackLog = 'Falling back to balance polling for asset';

const _wallet = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
);

final _atom = Asset(
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
      {'url': 'http://localhost:26657'},
    ],
  }),
  isWalletOnly: false,
  signMessagePrefix: null,
);

AssetPubkeys _pubkeys() => AssetPubkeys(
  assetId: _atom.id,
  keys: [
    PubkeyInfo(
      address: 'cosmos1example',
      derivationPath: null,
      chain: null,
      balance: BalanceInfo(
        total: Decimal.one,
        spendable: Decimal.one,
        unspendable: Decimal.zero,
      ),
      coinTicker: _atom.id.id,
    ),
  ],
  availableAddressesCount: 1,
  syncStatus: SyncStatusEnum.success,
);

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _MockAuth auth;
  late _MockActivationCoordinator activation;
  late _MockPubkeyManager pubkeys;
  late _MockAssetLookup assetLookup;
  late _MockAssetHistoryStorage assetHistory;
  late _MockApiClient client;
  late _MockEventStreamingService service;
  late StreamController<KdfUser?> authChanges;
  late StreamController<BalanceEvent> balanceEvents;
  late StreamController<KdfEventDisconnection> disconnections;
  late EventStreamingManager streaming;
  late BalanceManager manager;
  late Completer<void> walletCheck;
  late bool holdWalletCheck;
  late bool isEnableRequested;
  late bool isHeld;
  late List<String> balanceLogs;
  late StreamSubscription<LogRecord> balanceLogSubscription;

  setUp(() {
    auth = _MockAuth();
    activation = _MockActivationCoordinator();
    pubkeys = _MockPubkeyManager();
    assetLookup = _MockAssetLookup();
    assetHistory = _MockAssetHistoryStorage();
    client = _MockApiClient();
    service = _MockEventStreamingService();
    authChanges = StreamController<KdfUser?>.broadcast();
    balanceEvents = StreamController<BalanceEvent>.broadcast();
    disconnections = StreamController<KdfEventDisconnection>.broadcast(
      sync: true,
    );
    walletCheck = Completer<void>();
    isEnableRequested = false;
    isHeld = false;
    balanceLogs = <String>[];
    balanceLogSubscription = Logger.root.onRecord
        .where((record) => record.loggerName == 'BalanceManager')
        .listen((record) => balanceLogs.add(record.message));

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async {
      if (holdWalletCheck && isEnableRequested) {
        isHeld = true;
        await walletCheck.future;
      }
      return _wallet;
    });
    when(() => assetLookup.fromId(_atom.id)).thenReturn(_atom);
    when(
      () => activation.isAssetActive(_atom.id),
    ).thenAnswer((_) async => true);
    when(
      () => assetHistory.getWalletAssets(_wallet.walletId),
    ).thenAnswer((_) async => {_atom.id.id});
    when(() => pubkeys.hydratedPubkeys(_atom)).thenAnswer((_) async => null);
    when(() => pubkeys.getPubkeys(_atom)).thenAnswer((_) async => _pubkeys());
    when(
      () => pubkeys.refreshPubkeys(_atom),
    ).thenAnswer((_) async => _pubkeys());

    when(() => service.balanceEvents).thenAnswer((_) => balanceEvents.stream);
    when(() => service.disconnections).thenAnswer((_) => disconnections.stream);
    when(() => service.firstByteReceived).thenAnswer((_) async {});
    when(() => service.isConnected).thenReturn(true);
    when(() => service.connectIfNeeded()).thenAnswer((_) {});
    when(() => service.disconnect()).thenAnswer((_) async {});
    when(() => client.executeRpc(any())).thenAnswer((invocation) async {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      if (request['method'] != 'stream::balance::enable') {
        return {
          'mmrpc': '2.0',
          'result': {'result': 'Success'},
        };
      }
      isEnableRequested = true;
      return {
        'mmrpc': '2.0',
        'result': {'streamer_id': 'BALANCE:${_atom.id.id}'},
      };
    });

    streaming = EventStreamingManager(client: client, eventService: service);
    manager = BalanceManager(
      assetLookup: assetLookup,
      auth: auth,
      pubkeyManager: pubkeys,
      activationCoordinator: activation,
      eventStreamingManager: streaming,
      assetHistoryStorage: assetHistory,
    );
  });

  tearDown(() async {
    await balanceLogSubscription.cancel();
    await manager.dispose();
    await streaming.dispose();
    await authChanges.close();
    await balanceEvents.close();
    await disconnections.close();
  });

  /// Starts a watcher, disconnects streaming as sign-out does once the watcher
  /// has subscribed, and returns what escaped the watcher's zone as uncaught.
  ///
  /// Sign-out disconnects before it signs out, so the watcher's wallet check
  /// after subscribing, which queues on auth, still passes. With
  /// [holdAtWalletCheck] the disconnect lands during that check, before the
  /// watcher has set its handlers.
  Future<List<Object>> signOutDuringWatcherStart({
    required bool holdAtWalletCheck,
  }) async {
    holdWalletCheck = holdAtWalletCheck;
    final uncaught = <Object>[];
    final finished = Completer<void>();
    unawaited(
      runZonedGuarded(() async {
        try {
          final watcher = manager.watchBalance(_atom.id).listen((_) {});
          bool isInPlace() =>
              streaming.isStreamActive('balance:${_atom.id.id}') &&
              isHeld == holdAtWalletCheck;
          await _waitUntil(isInPlace);
          expect(
            isInPlace(),
            isTrue,
            reason: 'sign-out must disconnect after the watcher subscribes',
          );
          await streaming.disconnect();
          walletCheck.complete();
          await _waitUntil(() => balanceLogs.contains(_fallbackLog));
          await watcher.cancel();
          finished.complete();
        } catch (error, stackTrace) {
          finished.completeError(error, stackTrace);
        }
      }, (error, _) => uncaught.add(error)),
    );
    await finished.future;
    return uncaught;
  }

  group('a sign-out disconnect while a balance watcher starts', () {
    test('moves a watcher whose handlers are set to polling', () async {
      final uncaught = await signOutDuringWatcherStart(
        holdAtWalletCheck: false,
      );

      expect(uncaught, isEmpty);
      expect(balanceLogs, contains(_fallbackLog));
    });

    test('moves a watcher still at its wallet check the same way', () async {
      final uncaught = await signOutDuringWatcherStart(holdAtWalletCheck: true);

      expect(uncaught, isEmpty);
      expect(balanceLogs, contains(_fallbackLog));
    });
  });
}
