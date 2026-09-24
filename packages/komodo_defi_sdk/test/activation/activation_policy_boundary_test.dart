import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/activation_policy.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/runtime_auth_fixture.dart';

class _Client extends Mock implements ApiClient {}

class _Auth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _History extends Mock implements AssetHistoryStorage {}

class _Lookup extends Mock implements IAssetLookup {}

class _Balances extends Mock implements IBalanceManager {}

class _Config extends Mock implements ActivationConfigService {}

class _Updates extends Mock implements KomodoAssetsUpdateManager {}

class _Cache extends Mock implements ActivatedAssetsCache {}

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

final _child = Asset.fromJson(
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

const _user = KdfUser(
  walletId: WalletId(
    name: 'policy-wallet',
    pubkeyHash: 'policy-wallet-hash',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: true,
);

Map<String, dynamic> _activationSuccess() => {
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

void main() {
  late _Client client;
  late _Auth auth;
  late _History history;
  late _Lookup lookup;
  late _Balances balances;
  late _Cache cache;
  late ActivationPolicy policy;
  late ActivationManager manager;
  late Set<AssetId> enabled;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_parent);
    registerFallbackValue(_user.walletId);
  });

  void arrange() {
    client = _Client();
    auth = _Auth();
    history = _History();
    lookup = _Lookup();
    balances = _Balances();
    cache = _Cache();
    policy = ActivationPolicy();
    enabled = {};
    when(() => auth.currentUser).thenAnswer((_) async => _user);
    when(
      () => auth.authStateChanges,
    ).thenAnswer((_) => const Stream<KdfUser?>.empty());
    when(() => lookup.fromId(_parent.id)).thenReturn(_parent);
    when(() => lookup.fromId(_child.id)).thenReturn(_child);
    when(cache.getActivatedAssetIds).thenAnswer((_) async => {...enabled});
    when(
      () =>
          cache.getActivatedAssetIds(forceRefresh: any(named: 'forceRefresh')),
    ).thenAnswer((_) async => {...enabled});
    when(() => history.addAssetToWallet(any(), any())).thenAnswer((_) async {});
    when(() => balances.precacheBalance(any())).thenAnswer((_) async {});
    when(() => client.executeRpc(any())).thenAnswer((_) async {
      enabled.add(_parent.id);
      return _activationSuccess();
    });
    manager = ActivationManager(
      client,
      auth,
      history,
      lookup,
      balances,
      _Config(),
      _Updates(),
      cache,
      activationPolicy: policy,
    );
  }

  setUp(arrange);

  tearDown(() async {
    await manager.dispose();
    await policy.dispose();
  });

  for (final status in [
    ActivationPolicyStatus.loading,
    ActivationPolicyStatus.unavailable,
  ]) {
    test(
      '$status denies cold direct and batch activation before RPC',
      () async {
        policy.update(ActivationPolicySnapshot(status: status));
        for (final stream in [
          manager.activateAsset(_parent),
          manager.activateAsset(_child),
          manager.activateAssets([_parent, _child]),
        ]) {
          await expectLater(
            stream.toList(),
            throwsA(
              isA<ActivationPolicyException>().having(
                (error) => error.status,
                'policy status',
                status,
              ),
            ),
          );
        }
        verifyZeroInteractions(client);
        verifyZeroInteractions(history);
        expect(manager.activationStates, isEmpty);
      },
    );
  }

  for (final blocked in [_parent, _child]) {
    test(
      'blocking ${blocked.id.id} rejects parent/token group before RPC',
      () async {
        policy.update(
          ActivationPolicySnapshot(
            status: ActivationPolicyStatus.ready,
            blockedAssets: {blocked.id},
          ),
        );
        await expectLater(
          manager.activateAssets([_parent, _child]).toList(),
          throwsA(isA<ActivationPolicyException>()),
        );
        await expectLater(
          manager.activateAsset(_child).toList(),
          throwsA(isA<ActivationPolicyException>()),
        );
        verifyZeroInteractions(client);
        verifyZeroInteractions(history);
      },
    );
  }

  test(
    'cached active assets remain usable while lookup is unavailable',
    () async {
      enabled.add(_parent.id);
      policy.update(
        ActivationPolicySnapshot(status: ActivationPolicyStatus.unavailable),
      );
      final progress = await manager.activateAsset(_parent).toList();
      expect(progress.single.isSuccess, isTrue);
      expect(manager.activationStateOf(_parent.id)?.isActive, isTrue);
      final coordinator = SharedActivationCoordinator(manager, auth);
      addTearDown(coordinator.dispose);
      final result = await coordinator.activateAsset(_parent);
      expect(result.wasAlreadyActive, isTrue);
      verifyZeroInteractions(client);
    },
  );

  for (final status in [
    ActivationPolicyStatus.ready,
    ActivationPolicyStatus.unavailable,
  ]) {
    test(
      'a restriction applies to assets KDF still has enabled ($status)',
      () async {
        enabled.addAll({_parent.id, _child.id});
        final methods = <String>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request = invocation.positionalArguments.first as Map;
          methods.add(request['method'] as String);
          throw StateError('disable_coin unavailable');
        });
        final coordinator = SharedActivationCoordinator(manager, auth);
        addTearDown(coordinator.dispose);
        policy.update(
          ActivationPolicySnapshot(status: status, blockedAssets: {_parent.id}),
        );

        await expectLater(
          coordinator.activateAsset(_child),
          throwsA(isA<ActivationPolicyException>()),
        );
        for (final stream in [
          manager.activateAsset(_parent),
          manager.activateAssets([_parent, _child]),
        ]) {
          await expectLater(
            stream.toList(),
            throwsA(isA<ActivationPolicyException>()),
          );
        }
        expect(methods, everyElement('disable_coin'));
      },
    );
  }

  test(
    'successful policy recovery allows the same previously gated asset',
    () async {
      policy.update(
        ActivationPolicySnapshot(status: ActivationPolicyStatus.loading),
      );
      await expectLater(
        manager.activateAsset(_parent).toList(),
        throwsA(isA<ActivationPolicyException>()),
      );
      policy.update(
        ActivationPolicySnapshot(status: ActivationPolicyStatus.ready),
      );
      final progress = await manager.activateAsset(_parent).toList();
      expect(progress.last.isSuccess, isTrue);
      verify(() => client.executeRpc(any())).called(1);
      expect(manager.activationStateOf(_parent.id)?.isActive, isTrue);
    },
  );

  test('late activation after restriction is rejected and disabled', () {
    fakeAsync((clock) {
      unawaited(manager.dispose());
      unawaited(policy.dispose());
      arrange();
      final response = Completer<Map<String, dynamic>>();
      final calls = <String>[];
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request = invocation.positionalArguments.first as Map;
        final method = request['method'] as String;
        calls.add(method);
        if (method == 'disable_coin') {
          enabled.remove(_parent.id);
          return {'result': 'success'};
        }
        final result = await response.future;
        enabled.add(_parent.id);
        return result;
      });
      Object? failure;
      final events = <ActivationProgress>[];
      final subscription = manager
          .activateAsset(_parent)
          .listen(events.add, onError: (Object error) => failure = error);
      clock.flushMicrotasks();
      expect(calls, hasLength(1));
      policy.update(
        ActivationPolicySnapshot(
          status: ActivationPolicyStatus.ready,
          blockedAssets: {_parent.id},
        ),
      );
      clock.flushMicrotasks();
      response.complete(_activationSuccess());
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 5));
      expect(failure, isA<ActivationPolicyException>());
      expect(events.any((event) => event.isSuccess), isFalse);
      expect(calls, contains('disable_coin'));
      expect(enabled, isEmpty);
      expect(manager.activationStateOf(_parent.id)?.isActive, isNot(isTrue));
      verifyZeroInteractions(history);
      unawaited(subscription.cancel());
      unawaited(manager.dispose());
      clock.flushMicrotasks();
    });
  });

  test(
    'failed runtime disable retries child before parent and keeps selection',
    () {
      fakeAsync((clock) {
        unawaited(manager.dispose());
        unawaited(policy.dispose());
        arrange();
        enabled.addAll({_parent.id, _child.id});
        var fail = true;
        final disabled = <String>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request = invocation.positionalArguments.first as Map;
          expect(request['method'], 'disable_coin');
          if (fail) throw StateError('temporary runtime failure');
          final coin = request['coin'] as String;
          disabled.add(coin);
          enabled.removeWhere((asset) => asset.id == coin);
          return {'result': 'success'};
        });
        policy.update(
          ActivationPolicySnapshot(
            status: ActivationPolicyStatus.ready,
            blockedAssets: {_parent.id},
          ),
        );
        clock.flushMicrotasks();
        expect(enabled, hasLength(2));
        fail = false;
        clock.elapse(const Duration(seconds: 5));
        expect(disabled, [_child.id.id, _parent.id.id]);
        expect(enabled, isEmpty);
        verifyZeroInteractions(history);
        unawaited(manager.dispose());
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'restriction lifted during an enabled lookup prevents stale disable',
    () {
      fakeAsync((clock) {
        unawaited(manager.dispose());
        unawaited(policy.dispose());
        arrange();
        final pendingEnabled = Completer<Set<AssetId>>();
        when(
          () => cache.getActivatedAssetIds(forceRefresh: true),
        ).thenAnswer((_) => pendingEnabled.future);
        policy.update(
          ActivationPolicySnapshot(
            status: ActivationPolicyStatus.ready,
            blockedAssets: {_parent.id},
          ),
        );
        clock.flushMicrotasks();
        policy.update(
          ActivationPolicySnapshot(status: ActivationPolicyStatus.ready),
        );
        pendingEnabled.complete({_parent.id, _child.id});
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 10));
        verifyZeroInteractions(client);
        verifyZeroInteractions(history);
        unawaited(manager.dispose());
        clock.flushMicrotasks();
      });
    },
  );
  test(
    'restriction lifted during disable restores prior runtime availability',
    () {
      fakeAsync((clock) {
        unawaited(manager.dispose());
        unawaited(policy.dispose());
        arrange();
        clock.flushMicrotasks();
        enabled.add(_parent.id);
        final disabling = Completer<Map<String, dynamic>>();
        final calls = <String>[];
        when(() => client.executeRpc(any())).thenAnswer((invocation) async {
          final request = invocation.positionalArguments.first as Map;
          final method = request['method'] as String;
          calls.add(method);
          if (method == 'disable_coin') {
            final result = await disabling.future;
            enabled.remove(_parent.id);
            return result;
          }
          enabled.add(_parent.id);
          return _activationSuccess();
        });
        policy.update(
          ActivationPolicySnapshot(
            status: ActivationPolicyStatus.ready,
            blockedAssets: {_parent.id},
          ),
        );
        clock.flushMicrotasks();
        expect(calls, ['disable_coin']);
        policy.update(
          ActivationPolicySnapshot(status: ActivationPolicyStatus.ready),
        );
        clock.flushMicrotasks();
        disabling.complete({'result': 'success'});
        clock.flushMicrotasks();
        expect(enabled, {_parent.id});
        expect(calls, ['disable_coin', 'enable_eth_with_tokens']);
        expect(manager.activationStateOf(_parent.id)?.isActive, isTrue);
        unawaited(manager.dispose());
        clock.flushMicrotasks();
      });
    },
  );
}
