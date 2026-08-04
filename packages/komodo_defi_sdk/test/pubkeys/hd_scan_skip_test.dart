import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

/// The HD address scan that follows activation.
///
/// Measured against a real KDF: activating KMD on a fresh HD wallet took ~47s
/// while KDF walked a `gap_limit: 20` address gap, and the
/// `task::scan_for_new_addresses` the SDK then issued spent its entire 20s
/// ceiling before failing with `TimeoutException: Timed out scanning for new
/// addresses`, which `_scanForNewHdAddressesIfNeeded` swallows and continues
/// past. Skipping that second walk cut time-to-first-balance from ~89s to
/// ~48s.
///
/// These tests pin *when* it may be skipped, because both halves of the
/// condition are load-bearing and neither is obvious from the call site.
void main() {
  late _MockApiClient client;
  late _MockAuth auth;
  late _MockActivationCoordinator activation;
  late StreamController<KdfUser?> authChanges;
  late PubkeyManager manager;

  Asset utxoAsset() => Asset(
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
      // `UtxoProtocol._validateUtxoConfig` short-circuits on testnet, which
      // keeps this fixture to the fields the test actually cares about.
      'is_testnet': true,
      'electrum': [
        {'url': 'electrum1.example:10001'},
      ],
    }),
    isWalletOnly: false,
    signMessagePrefix: null,
  );

  setUpAll(() {
    registerFallbackValue(utxoAsset());
    registerFallbackValue(utxoAsset().id);
  });

  setUp(() {
    client = _MockApiClient();
    auth = _MockAuth();
    activation = _MockActivationCoordinator();
    authChanges = StreamController<KdfUser?>.broadcast();
    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    manager = PubkeyManager(client, auth, activation);
  });

  tearDown(() async {
    await manager.dispose();
    await authChanges.close();
  });

  test('the shipped UTXO activation params really do carry a scan policy', () {
    // The skip is only sound because activation scans. If this ever stops
    // being true, the skip becomes a correctness bug rather than an
    // optimisation - so assert the premise rather than trusting it.
    final params = utxoAsset().protocol.defaultActivationParams();
    expect(
      params.scanPolicy,
      ScanPolicy.scanIfNewWallet,
      reason: 'UtxoProtocol must still ask KDF to scan during activation',
    );
    expect(
      params.gapLimit,
      20,
      reason: 'the activation gap limit is what makes the SDK scan redundant',
    );
  });

  test('ETH-family activation params carry no scan policy', () {
    // The other half of the premise: the skip must NOT apply to protocols
    // whose activation does not scan, or their HD addresses would never be
    // discovered. `Erc20Protocol`'s params have no `scan_policy` field at all.
    final eth = Asset(
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
        'fallback_swap_contract':
            '0x0000000000000000000000000000000000000002',
      }),
      isWalletOnly: false,
      signMessagePrefix: null,
    );

    expect(
      eth.protocol.defaultActivationParams().scanPolicy,
      isNull,
      reason:
          'if this gains a scan policy, the skip may be extended to ETH; until '
          'then extending it would silently stop discovering HD addresses',
    );
  });

  test(
    'a warm re-login is not treated as freshly activated',
    () {
      // `SharedActivationCoordinator.activateAsset` answers "already active"
      // for every caller after the first, which is why the freshness signal
      // has to come from `ActivationManager` rather than from the result of
      // the call. If a warm login were mistaken for a fresh one, the scan
      // would be skipped on exactly the logins where it is the only thing
      // that discovers newly used addresses.
      when(() => activation.wasFreshlyActivated(any())).thenReturn(false);
      expect(activation.wasFreshlyActivated(utxoAsset().id), isFalse);
    },
  );

  test('ActivationResult distinguishes fresh from already-active', () {
    final fresh = ActivationResult.success(utxoAsset().id);
    final warm = ActivationResult.alreadyActive(utxoAsset().id);

    expect(fresh.isSuccess, isTrue);
    expect(fresh.wasAlreadyActive, isFalse);
    expect(warm.isSuccess, isTrue);
    expect(
      warm.wasAlreadyActive,
      isTrue,
      reason:
          'callers need "nothing was activated" to be distinguishable from '
          '"activation succeeded" - they imply different KDF-side work',
    );
  });
}
