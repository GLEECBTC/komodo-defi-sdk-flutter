import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _RecordingPubkeysStorage implements PubkeysStorage {
  final savedWallets = <WalletId>[];
  int readCount = 0;

  @override
  Future<Map<String, Map<String, dynamic>>> listForWallet(
    WalletId walletId,
  ) async {
    readCount++;
    return const {};
  }

  @override
  Future<void> savePubkeys(
    WalletId walletId,
    String assetTicker,
    AssetPubkeys pubkeys, {
    Set<String> everFundedAddresses = const {},
  }) async {
    savedWallets.add(walletId);
  }
}

const _walletA = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

const _walletB = KdfUser(
  walletId: WalletId(
    name: 'wallet-b',
    pubkeyHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

const _nameOnlyWallet = KdfUser(
  walletId: WalletId(
    name: 'shared-name',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

const _hashAWallet = KdfUser(
  walletId: WalletId(
    name: 'shared-name',
    pubkeyHash: 'hash-a',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

const _hashBWallet = KdfUser(
  walletId: WalletId(
    name: 'shared-name',
    pubkeyHash: 'hash-b',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

Asset _trc20Asset() {
  final trx = Asset.fromJson(const {
    'coin': 'TRX',
    'type': 'TRX',
    'name': 'TRON',
    'fname': 'TRON',
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'required_confirmations': 1,
    'derivation_path': "m/44'/195'",
    'protocol': {
      'type': 'TRX',
      'protocol_data': {'network': 'Mainnet'},
    },
    'nodes': <Map<String, dynamic>>[],
  }, knownIds: const {});
  return Asset.fromJson(
    const {
      'coin': 'USDT-TRC20',
      'type': 'TRC-20',
      'name': 'Tether',
      'fname': 'Tether',
      'wallet_only': true,
      'mm2': 1,
      'decimals': 6,
      'required_confirmations': 1,
      'derivation_path': "m/44'/195'",
      'protocol': {
        'type': 'TRC20',
        'protocol_data': {
          'platform': 'TRX',
          'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        },
      },
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      'parent_coin': 'TRX',
      'nodes': <Map<String, dynamic>>[],
    },
    knownIds: {trx.id},
  );
}

Asset _singleAddressAsset() {
  final assetId = AssetId(
    id: 'ATOM',
    name: 'Cosmos',
    symbol: AssetSymbol(assetConfigId: 'ATOM'),
    chainId: AssetChainId(chainId: 118, decimalsValue: 6),
    derivationPath: null,
    subClass: CoinSubClass.tendermint,
  );
  return Asset(
    id: assetId,
    protocol: TendermintProtocol.fromJson({
      'type': 'Tendermint',
      'rpc_urls': [
        {'url': 'https://rpc.example.com'},
      ],
    }),
    isWalletOnly: false,
    signMessagePrefix: null,
  );
}

Map<String, dynamic> _taskStarted(int taskId) => {
  'mmrpc': '2.0',
  'result': {'task_id': taskId},
};

Map<String, dynamic> _scanComplete() => {
  'mmrpc': '2.0',
  'result': {'status': 'Ok', 'details': null},
};

Map<String, dynamic> _accountBalance({
  required String primaryAddress,
  required String custodyAddress,
  required String sharedSecondaryBalance,
}) => {
  'mmrpc': '2.0',
  'result': {
    'status': 'Ok',
    'details': {
      'account_index': 0,
      'derivation_path': "m/44'/195'/0'",
      'total_balance': {
        'USDT-TRC20': {'spendable': sharedSecondaryBalance, 'unspendable': '0'},
      },
      'addresses': [
        {
          'address': primaryAddress,
          'derivation_path': "m/44'/195'/0'/0/0",
          'chain': 'External',
          'balance': {
            'USDT-TRC20': {'spendable': '0', 'unspendable': '0'},
          },
          'gasfree_address': custodyAddress,
        },
        {
          'address': 'TSharedSecondary',
          'derivation_path': "m/44'/195'/0'/0/1",
          'chain': 'External',
          'balance': {
            'USDT-TRC20': {
              'spendable': sharedSecondaryBalance,
              'unspendable': '0',
            },
          },
          'gasfree_address': '${custodyAddress}Secondary',
        },
      ],
    },
  },
};

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  test('fresh fetch bypasses memory and persisted pubkey caches', () async {
    final client = _MockApiClient();
    final auth = _MockAuth();
    final activation = _MockActivationCoordinator();
    final storage = _RecordingPubkeysStorage();
    final authChanges = StreamController<KdfUser?>.broadcast();
    final asset = _singleAddressAsset();
    var fetchCount = 0;

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => _walletA);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(() => client.executeRpc(any())).thenAnswer((invocation) async {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      if (request['method'] != 'my_balance') {
        throw StateError('Unexpected RPC method: ${request['method']}');
      }
      fetchCount++;
      return {
        'address': 'cosmos1fresh$fetchCount',
        'balance': '$fetchCount',
        'unspendable_balance': '0',
        'coin': asset.id.id,
      };
    });

    final manager = PubkeyManager(client, auth, activation, storage: storage);
    addTearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    final cached = await manager.getPubkeys(asset);
    expect(cached.keys.single.address, 'cosmos1fresh1');
    expect(
      (await manager.getPubkeys(asset)).keys.single.address,
      'cosmos1fresh1',
    );
    expect(fetchCount, 1);
    expect(storage.readCount, 1);

    final fresh = await manager.getFreshPubkeys(asset);
    expect(fresh.keys.single.address, 'cosmos1fresh2');
    expect(fetchCount, 2);
    expect(storage.readCount, 1);
    expect(manager.lastKnown(asset.id), cached);
  });

  test('fresh fetch rejects a response from the previous wallet', () async {
    final client = _MockApiClient();
    final auth = _MockAuth();
    final activation = _MockActivationCoordinator();
    final storage = _RecordingPubkeysStorage();
    final authChanges = StreamController<KdfUser?>.broadcast();
    final response = Completer<Map<String, dynamic>>();
    final fetchStarted = Completer<void>();
    final asset = _singleAddressAsset();
    KdfUser? currentUser = _walletA;

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => currentUser);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(() => client.executeRpc(any())).thenAnswer((invocation) {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      if (request['method'] != 'my_balance') {
        throw StateError('Unexpected RPC method: ${request['method']}');
      }
      fetchStarted.complete();
      return response.future;
    });

    final manager = PubkeyManager(client, auth, activation, storage: storage);
    addTearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    final freshFetch = manager.getFreshPubkeys(asset);
    await fetchStarted.future;
    currentUser = _walletB;
    response.complete({
      'address': 'cosmos1walleta',
      'balance': '5',
      'unspendable_balance': '0',
      'coin': asset.id.id,
    });

    await expectLater(
      freshFetch,
      throwsA(isA<WalletChangedDisconnectException>()),
    );
    expect(manager.lastKnown(asset.id), isNull);
  });

  test(
    'wallet switch rejects stale fetch and preserves KDF GasFree HD sources',
    () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final storage = _RecordingPubkeysStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      final walletAResponse = Completer<Map<String, dynamic>>();
      final walletBResponse = Completer<Map<String, dynamic>>();
      final walletAFetchStarted = Completer<void>();
      final walletBFetchStarted = Completer<void>();
      KdfUser? currentUser = _walletA;
      final asset = _trc20Asset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => currentUser);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));
      when(() => client.executeRpc(any())).thenAnswer((invocation) {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        final method = request['method'] as String;
        final params = request['params'] as Map<String, dynamic>? ?? const {};

        switch (method) {
          case 'task::scan_for_new_addresses::init':
            return Future.value(_taskStarted(1));
          case 'task::scan_for_new_addresses::status':
            return Future.value(_scanComplete());
          case 'task::account_balance::init':
            return Future.value(
              _taskStarted(currentUser == _walletA ? 101 : 202),
            );
          case 'task::account_balance::status':
            final taskId = params['task_id'] as int;
            if (taskId == 101) {
              if (!walletAFetchStarted.isCompleted) {
                walletAFetchStarted.complete();
              }
              return walletAResponse.future;
            }
            if (!walletBFetchStarted.isCompleted) {
              walletBFetchStarted.complete();
            }
            return walletBResponse.future;
          default:
            throw StateError('Unexpected RPC method: $method');
        }
      });

      final manager = PubkeyManager(client, auth, activation, storage: storage);
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final walletAFetch = manager.getPubkeys(asset);
      await walletAFetchStarted.future;

      currentUser = _walletB;
      // Deliberately do not emit authChanges. getPubkeys must consult
      // currentUser before looking at A's asset-only cache/in-flight request.
      expect(manager.lastKnownForWallet(asset.id, _walletB.walletId), isNull);

      final walletBFetch = manager.getPubkeys(asset);
      await walletBFetchStarted.future;

      walletAResponse.complete(
        _accountBalance(
          primaryAddress: 'TWalletAPrimary',
          custodyAddress: 'TWalletACustody',
          sharedSecondaryBalance: '1',
        ),
      );
      await expectLater(
        walletAFetch,
        throwsA(isA<WalletChangedDisconnectException>()),
      );

      walletBResponse.complete(
        _accountBalance(
          primaryAddress: 'TWalletBPrimary',
          custodyAddress: 'TWalletBCustody',
          sharedSecondaryBalance: '0',
        ),
      );
      final walletBPubkeys = await walletBFetch;

      expect(walletBPubkeys.keys.map((key) => key.address), [
        'TWalletBPrimary',
        'TSharedSecondary',
      ]);
      expect(walletBPubkeys.keys.first.gasfreeAddress, 'TWalletBCustody');
      expect(
        walletBPubkeys.keys.last.gasfreeAddress,
        'TWalletBCustodySecondary',
      );
      expect(
        manager.lastKnownForWallet(asset.id, _walletB.walletId),
        walletBPubkeys,
      );
      expect(
        (await manager.getPubkeys(asset)).keys.last.gasfreeAddress,
        'TWalletBCustodySecondary',
      );
      expect(storage.savedWallets, [_walletB.walletId]);
    },
  );

  test(
    'wallet-bound cache lookup fails closed before delayed auth event',
    () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final storage = _RecordingPubkeysStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      KdfUser? currentUser = _walletA;
      final asset = _singleAddressAsset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => currentUser);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        if (request['method'] != 'my_balance') {
          throw StateError('Unexpected RPC method: ${request['method']}');
        }
        final isWalletA = currentUser == _walletA;
        return {
          'address': isWalletA ? 'cosmos1walleta' : 'cosmos1walletb',
          'balance': isWalletA ? '5' : '9',
          'unspendable_balance': '0',
          'coin': asset.id.id,
        };
      });

      final manager = PubkeyManager(client, auth, activation, storage: storage);
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final walletAPubkeys = await manager.getPubkeys(asset);
      expect(
        manager.lastKnownForWallet(asset.id, _walletA.walletId),
        walletAPubkeys,
      );

      currentUser = _walletB;
      // No auth event: the wallet-bound cache cannot reveal A to B.
      expect(manager.lastKnownForWallet(asset.id, _walletB.walletId), isNull);

      final walletBPubkeys = await manager.getPubkeys(asset);
      expect(walletBPubkeys.keys.single.address, 'cosmos1walletb');
      expect(
        manager.lastKnownForWallet(asset.id, _walletB.walletId),
        walletBPubkeys,
      );
      expect(manager.lastKnownForWallet(asset.id, _walletA.walletId), isNull);
    },
  );

  test(
    'identity enrichment makes a later same-name hash switch invalidate cache',
    () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final storage = _RecordingPubkeysStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      KdfUser? currentUser = _nameOnlyWallet;
      final asset = _singleAddressAsset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => currentUser);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));
      when(() => client.executeRpc(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.single as Map<String, dynamic>;
        if (request['method'] != 'my_balance') {
          throw StateError('Unexpected RPC method: ${request['method']}');
        }
        final isHashB = currentUser?.walletId.pubkeyHash == 'hash-b';
        return {
          'address': isHashB ? 'cosmos1hashb' : 'cosmos1hasha',
          'balance': isHashB ? '9' : '5',
          'unspendable_balance': '0',
          'coin': asset.id.id,
        };
      });

      final manager = PubkeyManager(client, auth, activation, storage: storage);
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final nameOnlyPubkeys = await manager.getPubkeys(asset);
      expect(nameOnlyPubkeys.keys.single.address, 'cosmos1hasha');

      currentUser = _hashAWallet;
      expect(await manager.getPubkeys(asset), nameOnlyPubkeys);

      currentUser = _hashBWallet;
      expect(
        manager.lastKnownForWallet(asset.id, _hashBWallet.walletId),
        isNull,
      );
      final hashBPubkeys = await manager.getPubkeys(asset);

      expect(hashBPubkeys.keys.single.address, 'cosmos1hashb');
      expect(
        manager.lastKnownForWallet(asset.id, _hashAWallet.walletId),
        isNull,
      );
    },
  );
}
