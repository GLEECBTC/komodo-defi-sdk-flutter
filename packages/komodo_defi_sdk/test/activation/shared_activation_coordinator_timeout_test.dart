import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationManager extends Mock implements ActivationManager {}

Map<String, dynamic> _utxoConfig() => {
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

/// A progress stream that keeps reporting progress but never terminates - the
/// shape every `while (!isComplete)` protocol strategy produces when KDF never
/// returns a terminal status. It emits events, so no inter-event timeout can
/// detect it; only a total deadline can.
Stream<ActivationProgress> _neverCompletingProgress() async* {
  var percentage = 1.0;
  while (true) {
    yield ActivationProgress(
      status: 'Activating',
      progressPercentage: percentage,
    );
    percentage = percentage >= 99 ? 99 : percentage + 1;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Asset asset;
  late _MockAuth auth;
  late _MockActivationManager manager;

  setUpAll(() {
    final fallbackAsset = Asset.fromJson(_utxoConfig(), knownIds: const {});
    registerFallbackValue(fallbackAsset);
    registerFallbackValue(fallbackAsset.id);
  });

  setUp(() {
    asset = Asset.fromJson(_utxoConfig(), knownIds: const {});
    auth = _MockAuth();
    manager = _MockActivationManager();

    when(
      () => auth.authStateChanges,
    ).thenAnswer((_) => const Stream<KdfUser?>.empty());
    when(() => manager.isAssetActive(any())).thenAnswer((_) async => false);
    when(
      () => manager.shouldRefreshTronGaslessActivation(any()),
    ).thenReturn(false);
    when(
      () => manager.recordActivationFailure(any(), any()),
    ).thenAnswer((_) {});
    when(
      () => manager.abandonActivation(any(), any()),
    ).thenAnswer((_) async {});
  });

  test('the deadline releases the manager\'s registration too', () async {
    // There are two in-flight registries on this path, and only one of them
    // lives in this class. A deadline that clears `_pendingActivations` but
    // leaves `ActivationManager._activationCompleters` holding the dead
    // completer produces a retry that registers a fresh coordinator attempt
    // and then immediately parks on the old one - a "fresh" attempt that
    // issues no RPC.
    //
    // The mock below cannot show that: it has no real completer map, which is
    // exactly why the version of this suite that predates
    // [ActivationManager.abandonActivation] passed against a coordinator that
    // still had the bug. The end-to-end proof is in komodo_defi_harness
    // (`test/activation_deadline_test.dart`, which counts
    // `task::enable_utxo::init`); what is pinned here is the contract that the
    // coordinator must tell the manager to let go.
    when(
      () => manager.activateAsset(any()),
    ).thenAnswer((_) => _neverCompletingProgress());

    final coordinator = SharedActivationCoordinator(manager, auth);
    addTearDown(coordinator.dispose);

    await coordinator.activateAsset(
      asset,
      timeout: const Duration(milliseconds: 200),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    verify(() => manager.abandonActivation(asset.id, any())).called(1);
  });

  test('an activation that never terminates fails on the deadline', () async {
    when(
      () => manager.activateAsset(any()),
    ).thenAnswer((_) => _neverCompletingProgress());

    final coordinator = SharedActivationCoordinator(manager, auth);
    addTearDown(coordinator.dispose);

    final result = await coordinator
        .activateAsset(asset, timeout: const Duration(milliseconds: 200))
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('the deadline did not bound the activation'),
        );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('timed out'));
  });

  test('a joined caller is released by the deadline too', () async {
    when(
      () => manager.activateAsset(any()),
    ).thenAnswer((_) => _neverCompletingProgress());

    final coordinator = SharedActivationCoordinator(manager, auth);
    addTearDown(coordinator.dispose);

    final first = coordinator.activateAsset(
      asset,
      timeout: const Duration(milliseconds: 200),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final joined = coordinator.activateAsset(asset);

    final results = await Future.wait([first, joined]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('a joined caller outlived the deadline'),
    );

    expect(results.every((r) => !r.isSuccess), isTrue);
  });

  test(
    'a retry after the deadline starts a fresh attempt, not a dead join',
    () async {
      // This is the defect that turned a 90s app-side timeout into ~360s of
      // waiting: the retry re-joined the wedged completer instead of
      // re-activating, so attempts 2..4 did no work at all.
      var attempts = 0;
      when(() => manager.activateAsset(any())).thenAnswer((_) {
        attempts += 1;
        if (attempts == 1) return _neverCompletingProgress();
        return Stream<ActivationProgress>.fromIterable([
          ActivationProgress.success(),
        ]);
      });
      // Only the post-activation availability probe reports active; the
      // pre-check must stay false or `activateAsset` short-circuits.
      when(
        () => manager.isAssetActive(any(), forceRefresh: true),
      ).thenAnswer((_) async => true);

      final coordinator = SharedActivationCoordinator(manager, auth);
      addTearDown(coordinator.dispose);

      final first = await coordinator.activateAsset(
        asset,
        timeout: const Duration(milliseconds: 200),
      );
      expect(first.isSuccess, isFalse);

      final second = await coordinator
          .activateAsset(asset)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('the retry joined the abandoned attempt'),
          );

      expect(second.isSuccess, isTrue);
      expect(attempts, 2, reason: 'the retry must re-enter activation');
    },
  );

  test('the deadline releases the caller on a completely silent stream', () async {
    // `_neverCompletingProgress` emits every 10ms, so the `await for` keeps
    // resuming and the method reaches its `return` on its own. A stream that
    // never emits AND never closes does not: the initiating caller used to be
    // suspended before `return completer.future` was ever reached, so the
    // deadline fired, completed the completer, and the caller still waited
    // forever. Joiners were unaffected, which is what hid it.
    final silent = StreamController<ActivationProgress>();
    addTearDown(silent.close);
    when(() => manager.activateAsset(any())).thenAnswer((_) => silent.stream);

    final coordinator = SharedActivationCoordinator(manager, auth);
    addTearDown(coordinator.dispose);

    final result = await coordinator
        .activateAsset(asset, timeout: const Duration(milliseconds: 200))
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('the caller was never released'),
        );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('timed out'));
  });
}
