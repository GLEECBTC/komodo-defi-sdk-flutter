import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/security/private_key_export_request.dart';
import 'package:komodo_defi_sdk/src/security/security_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/runtime_auth_fixture.dart';
import 'solana_fixtures.dart';

class _Auth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _Assets extends Mock implements IAssetProvider {}

class _Activation extends Mock implements SharedActivationCoordinator {}

class _Client implements ApiClient {
  final requests = <Map<String, dynamic>>[];
  void Function()? afterDisclosure;
  @override
  Future<Map<String, dynamic>> executeRpc(Map<String, dynamic> request) async {
    requests.add(request);
    switch (request['method']) {
      case 'my_balance':
        return {
          'coin': 'TESTSOL',
          'address': 'WalletBase58',
          'balance': '0',
          'unspendable_balance': '0',
        };
      case 'show_priv_key':
        afterDisclosure?.call();
        return {
          'result': {'coin': 'TESTSOL', 'priv_key': 'SyntheticFixtureKeypair'},
        };
      default:
        throw StateError('Unexpected key export request');
    }
  }
}

void main() {
  final asset = solanaAsset();
  late _Auth auth;
  late _Assets assets;
  late _Client client;
  late SecurityManager manager;
  late int generation;
  var active = true;
  setUpAll(() => registerFallbackValue(asset.id));
  setUp(() {
    generation = 1;
    active = true;
    auth = _Auth();
    when(() => auth.isAuthTransitionInProgress).thenReturn(false);
    when(() => auth.authGeneration).thenAnswer((_) => generation);
    when(() => auth.currentUser).thenAnswer(
      (_) async => const KdfUser(
        walletId: WalletId(
          name: 'fixture',
          pubkeyHash: 'verified-public',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
        isBip39Seed: true,
      ),
    );
    assets = _Assets();
    when(() => assets.fromId(any())).thenReturn(asset);
    when(
      () => assets.getActivatedAssets(),
    ).thenAnswer((_) async => active ? [asset] : []);
    client = _Client();
    manager = SecurityManager(
      client,
      auth,
      assets,
      _Activation(),
      solanaCapabilities: const SolanaCapabilities(enabled: true),
    );
  });
  tearDown(() => manager.dispose());

  test(
    'active HD wallet exports one keypair without offline derivation or selectors',
    () async {
      final result = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(assets: [asset.id]),
      );
      expect(result.isComplete, isTrue);
      final outcome = result.outcomes.single;
      expect(outcome.coverage!.kind, PrivateKeyExportCoverageKind.activeWallet);
      expect(outcome.keys.single.hdInfo, isNull);
      expect(outcome.keys.single.publicKeySecp256k1, isEmpty);
      expect(outcome.keys.single.publicKeyAddress, 'WalletBase58');
      expect(client.requests.map((r) => r['method']), [
        'my_balance',
        'show_priv_key',
      ]);
      expect(client.requests.last['coin'], asset.id.id);
      expect(client.requests.last, isNot(contains('params')));
    },
  );

  test(
    'explicit HD ranges and inactive assets refuse without activation',
    () async {
      final ranged = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(
          assets: [asset.id],
          startIndex: 0,
          endIndex: 1,
        ),
      );
      expect(
        ranged.outcomes.single.failure,
        PrivateKeyExportFailure.unsupportedProtocol,
      );
      active = false;
      final inactive = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(assets: [asset.id]),
      );
      expect(
        inactive.outcomes.single.failure,
        PrivateKeyExportFailure.assetUnavailable,
      );
      expect(client.requests, isEmpty);
    },
  );

  test(
    'strict offline API does not silently substitute active-wallet export',
    () async {
      await expectLater(
        manager.getPrivateKeys(assets: [asset.id]),
        throwsUnsupportedError,
      );
      expect(client.requests, isEmpty);
    },
  );

  test(
    'authentication change during key RPC invalidates all results',
    () async {
      client.afterDisclosure = () => generation++;
      await expectLater(
        manager.exportPrivateKeys(
          request: PrivateKeyExportRequest(assets: [asset.id]),
        ),
        throwsA(isA<PrivateKeyExportSessionChangedException>()),
      );
    },
  );
}
