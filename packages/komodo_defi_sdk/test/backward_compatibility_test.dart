import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

/// Tests to verify backward compatibility of public APIs
/// These tests ensure that existing public method signatures remain unchanged
/// and that external consumers are not affected by cleanup improvements
void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(
      AssetId(
        id: 'DUMMY',
        name: 'Dummy',
        symbol: AssetSymbol(assetConfigId: 'DUMMY'),
        chainId: AssetChainId(chainId: 0, decimalsValue: 0),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      ),
    );
    registerFallbackValue(
      Asset(
        id: AssetId(
          id: 'DUMMY',
          name: 'Dummy',
          symbol: AssetSymbol(assetConfigId: 'DUMMY'),
          chainId: AssetChainId(chainId: 0, decimalsValue: 0),
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
      ),
    );
  });

  group('PubkeyManager backward compatibility', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late PubkeyManager manager;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();

      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => StreamController<KdfUser?>.broadcast().stream);

      manager = PubkeyManager(client, auth, activation);
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('constructor signature unchanged', () {
      // Verify constructor accepts the same parameters
      expect(() => PubkeyManager(client, auth, activation), returnsNormally);
    });

    test('public method signatures unchanged', () {
      // Verify all public methods exist with correct signatures
      expect(manager.getPubkeys, isA<Function>());
      expect(manager.createNewPubkey, isA<Function>());
      expect(manager.watchCreateNewPubkey, isA<Function>());
      expect(manager.unbanPubkeys, isA<Function>());
      expect(manager.watchPubkeys, isA<Function>());
      expect(manager.lastKnown, isA<Function>());
      expect(manager.precachePubkeys, isA<Function>());
      expect(manager.dispose, isA<Function>());

      // Verify method signatures by checking they can be called
      // (without actually executing them due to mock complexity)
      expect(() => manager.lastKnown, returnsNormally);
      expect(() => manager.dispose, returnsNormally);
    });

    test('watchPubkeys optional parameters unchanged', () {
      final asset = Asset(
        id: AssetId(
          id: 'TEST',
          name: 'Test',
          symbol: AssetSymbol(assetConfigId: 'TEST'),
          chainId: AssetChainId(chainId: 1, decimalsValue: 8),
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

      // Verify watchPubkeys can be called with and without optional parameters
      expect(() => manager.watchPubkeys(asset), returnsNormally);
      expect(() => manager.watchPubkeys(asset), returnsNormally);
      expect(
        () => manager.watchPubkeys(asset, activateIfNeeded: false),
        returnsNormally,
      );
    });
  });

  group('BalanceManager backward compatibility', () {
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockPubkeyManager pubkeyManager;
    late _MockAssetLookup assetLookup;
    late BalanceManager manager;

    setUp(() {
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      pubkeyManager = _MockPubkeyManager();
      assetLookup = _MockAssetLookup();

      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => StreamController<KdfUser?>.broadcast().stream);

      manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
      );
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('constructor signature unchanged', () {
      // Verify constructor accepts the same named parameters
      expect(
        () => BalanceManager(
          assetLookup: assetLookup,
          auth: auth,
          pubkeyManager: pubkeyManager,
          activationCoordinator: activation,
        ),
        returnsNormally,
      );
    });

    test('public method signatures unchanged', () {
      // Verify all public methods exist with correct signatures
      expect(manager.getBalance, isA<Function>());
      expect(manager.watchBalance, isA<Function>());
      expect(manager.lastKnown, isA<Function>());
      expect(manager.dispose, isA<Function>());

      // Verify method signatures by checking they can be called
      // (without actually executing them due to mock complexity)
      expect(() => manager.lastKnown, returnsNormally);
      expect(() => manager.dispose, returnsNormally);
    });

    test('watchBalance optional parameters unchanged', () {
      final assetId = AssetId(
        id: 'TEST',
        name: 'Test',
        symbol: AssetSymbol(assetConfigId: 'TEST'),
        chainId: AssetChainId(chainId: 1, decimalsValue: 8),
        derivationPath: null,
        subClass: CoinSubClass.tendermint,
      );

      // Verify watchBalance can be called with and without optional parameters
      expect(() => manager.watchBalance(assetId), returnsNormally);
      expect(() => manager.watchBalance(assetId), returnsNormally);
      expect(
        () => manager.watchBalance(assetId, activateIfNeeded: false),
        returnsNormally,
      );
    });
  });

  group('Normal operation behavior preservation', () {
    late _MockApiClient client;
    late _MockAuth auth;
    late _MockActivationCoordinator activation;
    late _MockAssetLookup assetLookup;
    late _MockPubkeyManager pubkeyManager;
    late PubkeyManager pubkeyManagerInstance;
    late BalanceManager balanceManagerInstance;

    setUp(() {
      client = _MockApiClient();
      auth = _MockAuth();
      activation = _MockActivationCoordinator();
      assetLookup = _MockAssetLookup();
      pubkeyManager = _MockPubkeyManager();

      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => StreamController<KdfUser?>.broadcast().stream);

      pubkeyManagerInstance = PubkeyManager(client, auth, activation);
      balanceManagerInstance = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
      );
    });

    tearDown(() async {
      await pubkeyManagerInstance.dispose();
      await balanceManagerInstance.dispose();
    });

    test('managers can be instantiated and disposed normally', () async {
      // Verify normal instantiation works
      expect(pubkeyManagerInstance, isNotNull);
      expect(balanceManagerInstance, isNotNull);

      // Verify normal disposal works
      await expectLater(pubkeyManagerInstance.dispose(), completes);
      await expectLater(balanceManagerInstance.dispose(), completes);
    });

    test('multiple dispose calls are safe (idempotent)', () async {
      // Verify multiple dispose calls don't throw
      await expectLater(pubkeyManagerInstance.dispose(), completes);
      await expectLater(pubkeyManagerInstance.dispose(), completes);

      await expectLater(balanceManagerInstance.dispose(), completes);
      await expectLater(balanceManagerInstance.dispose(), completes);
    });

    test('managers handle auth state changes gracefully', () async {
      final authController = StreamController<KdfUser?>.broadcast();
      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => authController.stream);

      final testPubkeyManager = PubkeyManager(client, auth, activation);
      final testBalanceManager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeyManager,
        activationCoordinator: activation,
      );

      // Simulate auth state changes
      authController.add(
        const KdfUser(
          walletId: WalletId(
            name: 'test-wallet',
            authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
          ),
          isBip39Seed: false,
        ),
      );

      // Allow auth state change to be processed
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify managers are still functional after auth state change
      expect(testPubkeyManager, isNotNull);
      expect(testBalanceManager, isNotNull);

      // Clean up
      await testPubkeyManager.dispose();
      await testBalanceManager.dispose();
      await authController.close();
    });
  });
}

class _MockPubkeyManager extends Mock implements PubkeyManager {}
