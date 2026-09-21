@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/bootstrap.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/runtime_auth_fixture.dart';

class _Client extends Mock implements ApiClient {}

class _Auth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _History extends Mock implements AssetHistoryStorage {}

class _Assets extends Mock implements IAssetProvider {}

class _Balances extends Mock implements IBalanceManager {}

class _Config extends Mock implements ActivationConfigService {}

class _Updates extends Mock implements KomodoAssetsUpdateManager {}

class _Cache extends Mock implements ActivatedAssetsCache {}

class _Fees extends Mock implements FeeManager {}

class _LegacyWithdrawals extends Mock implements LegacyWithdrawalManager {}

class _Journal extends Mock implements PendingGaslessTransferRepository {}

class _Pending extends Mock implements PendingGaslessTransfer {}

const _user = KdfUser(
  walletId: WalletId(
    name: 'restored-policy-wallet',
    pubkeyHash: '1111111111111111111111111111111111111111',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: true,
);

final _parent = Asset.fromJson(const {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
}, knownIds: const {});

final _token = Asset.fromJson(
  const {
    'coin': 'USDT-TRC20',
    'type': 'TRC-20',
    'name': 'Tether',
    'fname': 'Tether',
    'decimals': 6,
    'derivation_path': "m/44'/195'",
    'protocol': {
      'type': 'TRC20',
      'protocol_data': {
        'platform': 'TRX',
        'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      },
    },
    'parent_coin': 'TRX',
    'nodes': <Map<String, dynamic>>[],
  },
  knownIds: {_parent.id},
);

/// Runs real bootstrap through its first asynchronous platform dependency.
/// Stop there so this unit test does not start a KDF process or touch storage.
Future<ActivationPolicy> _initialPolicy(KomodoDefiSdkConfig config) async {
  final container = GetIt.asNewInstance();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var storageCalls = 0;
  messenger.setMockMethodCallHandler(channel, (_) async {
    storageCalls++;
    expect(container.isRegistered<ActivationPolicy>(), isTrue);
    expect(container.isRegistered<KomodoDefiFramework>(), isFalse);
    throw PlatformException(code: 'bootstrap-test-stop');
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  // This test controls the debug-only RPC-password fallback too.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await expectLater(
    bootstrap(hostConfig: null, config: config, container: container),
    throwsA(
      isA<PlatformException>().having(
        (error) => error.code,
        'code',
        'bootstrap-test-stop',
      ),
    ),
  );
  expect(storageCalls, 2);
  final policy = container<ActivationPolicy>();
  addTearDown(container.reset);
  addTearDown(policy.dispose);
  return policy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_token);
    registerFallbackValue(_user.walletId);
  });

  test('standalone bootstrap retains its unrestricted default', () async {
    final policy = await _initialPolicy(const KomodoDefiSdkConfig());
    expect(policy.current.canActivate(_token.id), isTrue);
  });

  test('restored legacy journal cannot activate before '
      'the initial policy is ready', () async {
    final initial = ActivationPolicySnapshot(
      status: ActivationPolicyStatus.loading,
    );
    final config = KomodoDefiSdkConfig(initialActivationPolicy: initial);
    final policy = await _initialPolicy(config.copyWith());
    expect(policy.current, same(initial));

    final client = _Client();
    final auth = _Auth();
    final assets = _Assets();
    final history = _History();
    final balances = _Balances();
    final cache = _Cache();
    final journal = _Journal();
    final pending = _Pending();
    final enabled = <AssetId>{};
    final requests = <String>[];
    final lookupAttempt = Completer<void>();
    var sourceProofResolved = false;

    when(() => auth.currentUser).thenAnswer((_) async => _user);
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
    // Mirrors bootstrap's initial watchCurrentUser emission.
    when(auth.watchCurrentUser).thenAnswer((_) => Stream.value(_user));
    when(() => assets.fromId(_parent.id)).thenReturn(_parent);
    when(() => assets.fromId(_token.id)).thenReturn(_token);
    when(() => assets.findAssetsByConfigId(_token.id.id)).thenReturn({_token});
    when(cache.getActivatedAssetIds).thenAnswer((_) async => {...enabled});
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {...enabled});
    when(() => history.addAssetToWallet(any(), any())).thenAnswer((_) async {});
    when(() => balances.precacheBalance(any())).thenAnswer((_) async {});
    when(() => pending.assetId).thenReturn(_token.id.id);
    when(
      () => journal.listAmbiguousLegacyTransfers(_user.walletId),
    ).thenAnswer((_) async => sourceProofResolved ? [] : [pending]);
    when(() => journal.list(_user.walletId)).thenAnswer((_) async => []);
    when(
      () => journal.resolveAmbiguousLegacyTransfers(
        _user.walletId,
        ownedSourceAddressesByAsset: any(named: 'ownedSourceAddressesByAsset'),
      ),
    ).thenAnswer((_) async => sourceProofResolved = true);
    when(() => client.executeRpc(any())).thenAnswer((invocation) async {
      final request = invocation.positionalArguments.single as Map;
      final method = request['method'] as String;
      requests.add(method);
      if (method == 'my_balance') {
        return {
          'coin': _token.id.id,
          'address': 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
          'balance': '1',
          'unspendable_balance': '0',
        };
      }
      enabled.addAll({_parent.id, _token.id});
      return {
        'mmrpc': '2.0',
        'result': {
          'current_block': 1,
          'wallet_balance': {
            'wallet_type': 'iguana',
            'accounts': <Map<String, dynamic>>[],
          },
          'nfts_infos': <String, dynamic>{},
        },
      };
    });
    final activation = ActivationManager(
      client,
      auth,
      history,
      assets,
      balances,
      _Config(),
      _Updates(),
      cache,
      activationPolicy: policy,
    );
    final coordinator = SharedActivationCoordinator(activation, auth);
    final pubkeys = PubkeyManager(client, auth, coordinator);
    final withdrawals = WithdrawalManager(
      client,
      assets,
      _Fees(),
      coordinator,
      _LegacyWithdrawals(),
      auth: auth,
      pendingGaslessTransfers: journal,
      freshSourceAddressResolver: (asset) async {
        try {
          final fresh = await pubkeys.getFreshPubkeys(asset);
          return {for (final key in fresh.keys) key.address};
        } finally {
          if (!lookupAttempt.isCompleted) lookupAttempt.complete();
        }
      },
    );
    addTearDown(withdrawals.dispose);
    addTearDown(pubkeys.dispose);
    addTearDown(coordinator.dispose);
    addTearDown(activation.dispose);

    await lookupAttempt.future.timeout(const Duration(seconds: 5));
    expect(requests, isEmpty);
    expect(sourceProofResolved, isFalse);
    // Let the first recovery cycle observe the policy rejection fully.
    await withdrawals.stopGaslessReconciliation();
    policy.update(
      ActivationPolicySnapshot(status: ActivationPolicyStatus.ready),
    );
    expect(await withdrawals.listPendingGaslessTransfers(), isEmpty);
    expect(requests, contains('enable_eth_with_tokens'));
    expect(requests, contains('my_balance'));
    expect(sourceProofResolved, isTrue);
  });
}
