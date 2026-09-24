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

/// `activateAsset` completes its completer only when it observes a terminal
/// `ActivationProgress`. A progress stream that ends without one used to fall
/// through to `return completer.future` with the completer still pending, and
/// that future is awaited by every activation caller in the app: the balance
/// watcher's `_ensureAssetActivated`, and the wallet's whole post-login fan-out
/// through `ensureAssetActivated`. One such stream stranded every coin on
/// `activating` for the rest of the session.
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
  });

  test(
    'fails rather than hanging when the progress stream yields nothing',
    () async {
      when(
        () => manager.activateAsset(any()),
      ).thenAnswer((_) => const Stream<ActivationProgress>.empty());

      final coordinator = SharedActivationCoordinator(manager, auth);
      addTearDown(coordinator.dispose);

      final result = await coordinator
          .activateAsset(asset)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                fail('activateAsset never completed - the completer leaked'),
          );

      expect(result.isSuccess, isFalse);
    },
  );

  test(
    'fails rather than hanging when the stream ends before a terminal progress',
    () async {
      when(() => manager.activateAsset(any())).thenAnswer(
        (_) => Stream<ActivationProgress>.fromIterable([
          const ActivationProgress(status: 'Starting', progressPercentage: 10),
        ]),
      );

      final coordinator = SharedActivationCoordinator(manager, auth);
      addTearDown(coordinator.dispose);

      final result = await coordinator
          .activateAsset(asset)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                fail('activateAsset never completed - the completer leaked'),
          );

      expect(result.isSuccess, isFalse);
    },
  );

  test('a joined caller is released too, rather than hanging', () async {
    final controller = StreamController<ActivationProgress>();
    when(
      () => manager.activateAsset(any()),
    ).thenAnswer((_) => controller.stream);

    final coordinator = SharedActivationCoordinator(manager, auth);
    addTearDown(coordinator.dispose);

    final first = coordinator.activateAsset(asset);
    // Let the first call register itself in _pendingActivations before the
    // second one joins it.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final joined = coordinator.activateAsset(asset);

    await controller.close();

    final results = await Future.wait([first, joined]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('a joined caller was left waiting forever'),
    );

    expect(results.every((r) => !r.isSuccess), isTrue);
  });
}
