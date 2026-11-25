import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_failure_backoff.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/activation_policy.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/runtime_auth_fixture.dart';

class _MockAuth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _MockActivationManager extends Mock implements ActivationManager {}

Map<String, dynamic> _utxoConfig(String coin) => {
  'coin': coin,
  'type': 'UTXO',
  'name': coin,
  'fname': coin,
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'",
  'protocol': {'type': 'UTXO'},
};

const _user = KdfUser(
  walletId: WalletId(
    name: 'backoff-wallet',
    pubkeyHash: 'backoff-wallet-hash',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: true,
);

void main() {
  late Asset clc;
  late _MockAuth auth;
  late StreamController<KdfUser?> authChanges;
  late _MockActivationManager manager;
  late DateTime now;
  late ActivationPolicy policy;
  late SharedActivationCoordinator coordinator;
  late int kdfAttempts;
  late bool nextAttemptSucceeds;

  setUpAll(() {
    final fallback = Asset.fromJson(_utxoConfig('KMD'), knownIds: const {});
    registerFallbackValue(fallback);
    registerFallbackValue(fallback.id);
  });

  setUp(() {
    clc = Asset.fromJson(_utxoConfig('CLC'), knownIds: const {});
    auth = _MockAuth();
    authChanges = StreamController<KdfUser?>.broadcast();
    addTearDown(authChanges.close);
    when(() => auth.currentUser).thenAnswer((_) async => _user);
    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);

    manager = _MockActivationManager();
    kdfAttempts = 0;
    nextAttemptSucceeds = false;
    when(() => manager.isAssetActive(any())).thenAnswer((_) async => false);
    when(() => manager.isAssetActive(any(), forceRefresh: true))
        .thenAnswer((_) async => nextAttemptSucceeds);
    when(() => manager.shouldRefreshTronGaslessActivation(any()))
        .thenReturn(false);
    when(() => manager.activateAsset(any())).thenAnswer((_) {
      kdfAttempts++;
      return Stream.value(
        nextAttemptSucceeds
            ? ActivationProgress.success()
            : ActivationProgress.error(message: 'servers list is empty'),
      );
    });

    now = DateTime.utc(2026, 11, 25, 12);
    policy = ActivationPolicy();
    addTearDown(policy.dispose);
    coordinator = SharedActivationCoordinator(
      manager,
      auth,
      activationPolicy: policy,
      failureBackoff: ActivationFailureBackoff(clock: () => now),
    );
    addTearDown(coordinator.dispose);
  });

  Future<void> failTimes(int count) async {
    for (var i = 0; i < count; i++) {
      await coordinator.activateAsset(clc);
    }
  }

  test('stops contacting KDF after three identical failures', () async {
    await failTimes(3);
    final deferred = await coordinator.activateAsset(clc);

    expect(kdfAttempts, 3);
    expect(deferred.isFailure, isTrue);
    expect(deferred.cause, isA<ActivationDeferredException>());
    expect(deferred.throwIfFailed, throwsA(isA<ActivationDeferredException>()));
    expect(coordinator.activationDeferral(clc.id), isNotNull);
  });

  test('tries again once the deferral has passed, then waits longer', () async {
    await failTimes(3);
    now = now.add(const Duration(minutes: 1));

    await coordinator.activateAsset(clc);

    expect(kdfAttempts, 4);
    expect(
      coordinator.activationDeferral(clc.id)?.retryAfter,
      now.add(const Duration(minutes: 2)),
    );
  });

  test('an attempt shared by concurrent callers counts once', () async {
    await Future.wait([
      coordinator.activateAsset(clc),
      coordinator.activateAsset(clc),
    ]);
    await coordinator.activateAsset(clc);

    expect(kdfAttempts, 2);
    expect(coordinator.activationDeferral(clc.id), isNull);
  });

  test('a success clears the failure count', () async {
    await failTimes(2);
    nextAttemptSucceeds = true;
    expect((await coordinator.activateAsset(clc)).isSuccess, isTrue);
    nextAttemptSucceeds = false;
    await failTimes(2);

    expect(coordinator.activationDeferral(clc.id), isNull);
  });

  test('resetActivationBackoff lets the next attempt run at once', () async {
    await failTimes(3);
    coordinator.resetActivationBackoff([clc.id]);

    await coordinator.activateAsset(clc);

    expect(kdfAttempts, 4);
  });

  group('policy', () {
    Future<void> publish(
      ActivationPolicyStatus status, {
      Set<AssetId> blocked = const {},
    }) async {
      policy.update(
        ActivationPolicySnapshot(status: status, blockedAssets: blocked),
      );
      await pumpEventQueue();
    }

    test('a routine refresh keeps the deferral', () async {
      await failTimes(3);
      await publish(ActivationPolicyStatus.loading);
      await publish(ActivationPolicyStatus.ready);

      expect(coordinator.activationDeferral(clc.id), isNotNull);
    });

    test('a lookup recovering from unavailable clears it', () async {
      await failTimes(3);
      await publish(ActivationPolicyStatus.unavailable);
      expect(coordinator.activationDeferral(clc.id), isNotNull);

      await publish(ActivationPolicyStatus.loading);
      await publish(ActivationPolicyStatus.ready);

      expect(coordinator.activationDeferral(clc.id), isNull);
    });

    test('changed restrictions clear it', () async {
      final other = Asset.fromJson(_utxoConfig('KMD'), knownIds: const {});
      await failTimes(3);

      await publish(ActivationPolicyStatus.ready, blocked: {other.id});

      expect(coordinator.activationDeferral(clc.id), isNull);
    });
  });

  test('signing out clears it', () async {
    authChanges.add(_user);
    await pumpEventQueue();
    await failTimes(3);

    authChanges.add(null);
    await pumpEventQueue();

    expect(coordinator.activationDeferral(clc.id), isNull);
  });
}
