import 'dart:async';
import 'dart:convert';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/security/private_key_export_request.dart';
import 'package:komodo_defi_sdk/src/security/security_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Auth extends Mock implements KomodoDefiLocalAuth {}

class _Activation extends Mock implements SharedActivationCoordinator {}

class _Assets extends Mock implements IAssetProvider {}

class _Client implements ApiClient {
  final requests = <Map<String, dynamic>>[];
  late FutureOr<Map<String, dynamic>> Function(Map<String, dynamic>) respond;
  @override
  Future<Map<String, dynamic>> executeRpc(Map<String, dynamic> request) async {
    requests.add(request);
    return respond(request);
  }
}

Asset tron({String network = 'Mainnet', String ticker = 'TRX'}) =>
    Asset.fromJson({
      'coin': ticker,
      'type': 'TRX',
      'name': 'TRON',
      'fname': 'TRON',
      'wallet_only': true,
      'mm2': 1,
      'decimals': 6,
      'derivation_path': "m/44'/195'",
      'nodes': const <Map<String, dynamic>>[],
      'protocol': {
        'type': 'TRX',
        'protocol_data': {'network': network},
      },
    }, knownIds: const {});

Asset token(Asset parent) => Asset.fromJson(
  {
    'coin': 'USDT-TRC20',
    'type': 'TRC-20',
    'name': 'Tether',
    'fname': 'Tether',
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'derivation_path': "m/44'/195'",
    'nodes': const <Map<String, dynamic>>[],
    'parent_coin': parent.id.id,
    'protocol': {
      'type': 'TRC20',
      'protocol_data': {
        'platform': parent.id.id,
        'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      },
    },
  },
  knownIds: {parent.id},
);

Asset utxo(String ticker) => Asset(
  id: AssetId(
    id: ticker,
    name: ticker,
    symbol: AssetSymbol(assetConfigId: ticker),
    chainId: AssetChainId(chainId: 0, decimalsValue: 8),
    derivationPath: "m/44'/0'",
    subClass: CoinSubClass.utxo,
  ),
  protocol: UtxoProtocol.fromJson({
    'type': 'UTXO',
    'protocol': {'type': 'UTXO'},
    'is_testnet': true,
    'electrum': <Map<String, dynamic>>[],
  }),
  isWalletOnly: true,
  signMessagePrefix: null,
);

Map<String, dynamic> offline(String ticker, {int count = 11}) => {
  'mmrpc': '2.0',
  'result': [
    {
      'coin': ticker,
      'addresses': [
        for (var i = 0; i < count; i++)
          {
            'derivation_path': "m/44'/0'/0'/0/$i",
            'pubkey': 'synthetic-public',
            'address': 'synthetic-address-$i',
            'priv_key': 'synthetic-private-$i',
          },
      ],
    },
  ],
};

void main() {
  final trx = tron();
  final usdt = token(trx);
  final btc = utxo('BTC');
  late _Client client;
  late _Auth auth;
  late _Activation activation;
  late _Assets assets;
  late SecurityManager manager;
  late int generation;
  late KdfUser? user;
  late Map<AssetId, AssetActivationState> states;

  setUpAll(() {
    registerFallbackValue(trx.id);
  });
  setUp(() {
    generation = 1;
    user = const KdfUser(
      walletId: WalletId(
        name: 'fixture',
        pubkeyHash: 'verified-public-identity',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      ),
      isBip39Seed: true,
    );
    auth = _Auth();
    when(() => auth.isAuthTransitionInProgress).thenReturn(false);
    when(() => auth.authGeneration).thenAnswer((_) => generation);
    when(() => auth.currentUser).thenAnswer((_) async => user);
    states = {
      trx.id: AssetActivationState.active(trx.id),
      usdt.id: AssetActivationState.active(usdt.id),
    };
    activation = _Activation();
    when(() => activation.activationStates).thenAnswer((_) => states);
    assets = _Assets();
    final catalog = {
      for (final a in [trx, usdt, btc]) a.id: a,
    };
    when(
      () => assets.fromId(any()),
    ).thenAnswer((call) => catalog[call.positionalArguments[0]]);
    when(
      () => assets.getActivatedAssets(),
    ).thenAnswer((_) async => [btc, trx, usdt]);
    client = _Client();
    client.respond = (request) {
      switch (request['method']) {
        case 'get_private_keys':
          return offline((request['params'] as Map)['coins'][0] as String);
        default:
          throw StateError('Unexpected RPC');
      }
    };
    manager = SecurityManager(client, auth, assets, activation);
  });

  test(
    'mixed export keeps BTC and reports TRX and TRC20 unsupported',
    () async {
      final result = await manager.exportPrivateKeys();
      expect(result.isComplete, isFalse);
      expect(result.hasKeys, isTrue);
      expect(result.keysByAsset.keys, [btc.id]);
      expect(result.keysByAsset[btc.id], hasLength(11));
      expect(result.outcomes.map((outcome) => outcome.assetId), [
        btc.id,
        trx.id,
        usdt.id,
      ]);
      for (final outcome in result.outcomes.skip(1)) {
        expect(outcome.failure, PrivateKeyExportFailure.unsupportedProtocol);
        expect(outcome.keys, isEmpty);
        expect(outcome.coverage, isNull);
      }
      expect(client.requests.map((request) => request['method']), [
        'get_private_keys',
      ]);
      expect((client.requests.single['params'] as Map)['coins'], ['BTC']);
    },
  );

  for (final hdWallet in [true, false]) {
    for (final asset in [trx, usdt]) {
      test(
        '${asset.id.id} export is unsupported without RPC (HD=$hdWallet)',
        () async {
          if (!hdWallet) {
            user = const KdfUser(
              walletId: WalletId(
                name: 'fixture',
                pubkeyHash: 'verified-public-identity',
                authOptions: AuthOptions(
                  derivationMethod: DerivationMethod.iguana,
                ),
              ),
              isBip39Seed: true,
            );
          }
          final result = await manager.exportPrivateKeys(
            request: PrivateKeyExportRequest(assets: [asset.id]),
          );
          expect(result.hasKeys, isFalse);
          expect(
            result.outcomes.single.failure,
            PrivateKeyExportFailure.unsupportedProtocol,
          );
          expect(result.outcomes.single.coverage, isNull);
          await expectLater(
            manager.getPrivateKey(asset.id),
            throwsA(isA<UnsupportedError>()),
          );
          expect(client.requests, isEmpty);
          verifyNever(() => assets.getActivatedAssets());
          verifyNoMoreInteractions(activation);
        },
      );
    }
  }

  test(
    'TRON HD address 777 remains unsupported without scanning metadata',
    () async {
      final result = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(
          assets: [trx.id, usdt.id],
          startIndex: 777,
          endIndex: 777,
        ),
      );
      expect(result.hasKeys, isFalse);
      expect(
        result.outcomes.map((outcome) => outcome.failure),
        everyElement(PrivateKeyExportFailure.unsupportedProtocol),
      );
      await expectLater(
        manager.getPrivateKeys(
          assets: [trx.id, usdt.id],
          startIndex: 777,
          endIndex: 777,
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(client.requests, isEmpty);
      verifyNoMoreInteractions(activation);
    },
  );

  test('strict mixed export rejects TRON before deriving any keys', () async {
    for (final targets in [
      [btc.id, trx.id],
      [usdt.id, btc.id],
    ]) {
      await expectLater(
        manager.getPrivateKeys(assets: targets),
        throwsA(isA<UnsupportedError>()),
      );
    }
    expect(client.requests, isEmpty);
  });

  test(
    'TRON IDs remain unsupported when their catalog metadata is missing',
    () async {
      for (final asset in [trx, usdt]) {
        when(() => assets.fromId(asset.id)).thenReturn(null);
        final result = await manager.exportPrivateKeys(
          request: PrivateKeyExportRequest(assets: [asset.id]),
        );
        expect(
          result.outcomes.single.failure,
          PrivateKeyExportFailure.unsupportedProtocol,
        );
        await expectLater(
          manager.getPrivateKey(asset.id),
          throwsA(isA<UnsupportedError>()),
        );
      }
      expect(client.requests, isEmpty);
    },
  );

  test(
    'TRON protocol remains unsupported with a retained non-TRON ID',
    () async {
      for (final asset in [trx, usdt]) {
        final retained = asset.copyWith(
          id: asset.id.copyWith(subClass: CoinSubClass.utxo),
        );
        when(() => assets.fromId(retained.id)).thenReturn(retained);
        final result = await manager.exportPrivateKeys(
          request: PrivateKeyExportRequest(assets: [retained.id]),
        );
        expect(
          result.outcomes.single.failure,
          PrivateKeyExportFailure.unsupportedProtocol,
        );
        await expectLater(
          manager.getPrivateKey(retained.id),
          throwsA(isA<UnsupportedError>()),
        );
      }
      expect(client.requests, isEmpty);
    },
  );

  test('legacy BTC export remains available through both APIs', () async {
    user = const KdfUser(
      walletId: WalletId(
        name: 'fixture',
        pubkeyHash: 'verified-public-identity',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
      ),
      isBip39Seed: true,
    );
    client.respond = (_) => {
      'mmrpc': '2.0',
      'result': [
        {
          'coin': 'BTC',
          'pubkey': 'synthetic-public',
          'address': 'synthetic-address',
          'priv_key': 'synthetic-private',
        },
      ],
    };
    final result = await manager.exportPrivateKeys(
      request: PrivateKeyExportRequest(assets: [btc.id]),
    );
    expect(result.isComplete, isTrue);
    expect(
      result.outcomes.single.coverage!.kind,
      PrivateKeyExportCoverageKind.legacyWallet,
    );
    expect(result.keysByAsset[btc.id]!.single.hdInfo, isNull);
    final strict = await manager.getPrivateKey(btc.id);
    expect(strict[btc.id]!.single.privateKey, 'synthetic-private');
    expect(client.requests.map((request) => request['method']), [
      'get_private_keys',
      'get_private_keys',
    ]);
  });

  test('pending and failed TRON activation stays unsupported', () async {
    states[trx.id] = AssetActivationState.activating(trx.id);
    states[usdt.id] = AssetActivationState.failed(usdt.id);
    final result = await manager.exportPrivateKeys();
    expect(result.outcomes.first.isSuccess, isTrue);
    expect(
      result.outcomes.skip(1).map((outcome) => outcome.failure),
      everyElement(PrivateKeyExportFailure.unsupportedProtocol),
    );
    expect(client.requests.map((request) => request['method']), [
      'get_private_keys',
    ]);
  });

  test('default mode still validates malformed range before RPC', () async {
    await expectLater(
      manager.exportPrivateKeys(
        request: const PrivateKeyExportRequest(startIndex: 0, endIndex: 101),
      ),
      throwsArgumentError,
    );
    expect(client.requests, isEmpty);
  });

  test(
    'rejects a truncated offline response rather than claiming full range',
    () async {
      client.respond = (_) => offline('BTC', count: 1);
      final result = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(assets: [btc.id]),
      );
      expect(
        result.outcomes.single.failure,
        PrivateKeyExportFailure.invalidResponse,
      );
    },
  );

  test(
    'session transition while RPC pending discards every asset result',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      client.respond = (_) => pending.future;
      final operation = manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(assets: [btc.id]),
      );
      await Future<void>.delayed(Duration.zero);
      generation++; // Includes sign-out/sign-in to the same identity.
      pending.complete(offline('BTC'));
      await expectLater(
        operation,
        throwsA(isA<PrivateKeyExportSessionChangedException>()),
      );
    },
  );

  test('identity degradation with unchanged generation fails closed', () async {
    final session = await manager.captureExportSession();
    user = KdfUser(
      walletId: WalletId(
        name: 'fixture',
        authOptions: user!.walletId.authOptions,
      ),
      isBip39Seed: true,
    );
    await expectLater(
      manager.ensureExportSessionCurrent(session),
      throwsA(isA<PrivateKeyExportSessionChangedException>()),
    );
  });

  test(
    'diagnostics stay redacted while deliberate recovery JSON retains keys',
    () async {
      final result = await manager.exportPrivateKeys();
      const secret = 'synthetic-private-0';
      expect(result.toString(), isNot(contains(secret)));
      expect(result.outcomes.toString(), isNot(contains(secret)));
      expect(result.keysByAsset.toString(), isNot(contains(secret)));
      expect(jsonEncode(result.toJson()), contains(secret));
    },
  );
  test(
    'offline concurrency is bounded at two and requested order preserved',
    () async {
      final coins = [btc, utxo('KMD'), utxo('LTC'), utxo('DOGE')];
      for (final coin in coins) {
        when(() => assets.fromId(coin.id)).thenReturn(coin);
      }
      var current = 0;
      var maximum = 0;
      client.respond = (request) async {
        current++;
        if (current > maximum) maximum = current;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        current--;
        return offline((request['params'] as Map)['coins'][0] as String);
      };
      final result = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(
          assets: coins.map((coin) => coin.id).toList(),
        ),
      );
      expect(maximum, 2);
      expect(result.isComplete, isTrue);
      expect(
        result.outcomes.map((outcome) => outcome.assetId),
        coins.map((coin) => coin.id),
      );
    },
  );

  test(
    'shielded account preserves viewing key and alternate derivation metadata',
    () async {
      final shielded = Asset(
        id: btc.id.copyWith(id: 'ZEC', subClass: CoinSubClass.zhtlc),
        protocol: ZhtlcProtocol.fromJson({
          'type': 'ZHTLC',
          'protocol': {'type': 'ZHTLC'},
          'light_wallet_d_servers': <String>[],
        }),
        isWalletOnly: true,
        signMessagePrefix: null,
      );
      when(() => assets.fromId(shielded.id)).thenReturn(shielded);
      client.respond = (_) => {
        'mmrpc': '2.0',
        'result': [
          {
            'coin': 'ZEC',
            'addresses': [
              {
                'derivation_path': "m/44'/0'/0'",
                'z_derivation_path': "m/32'/133'/0'",
                'pubkey': '',
                'address': 'synthetic-shielded-address',
                'priv_key': 'synthetic-spending-key',
                'viewing_key': 'synthetic-viewing-key',
              },
            ],
          },
        ],
      };
      final result = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(assets: [shielded.id]),
      );
      expect(result.isComplete, isTrue);
      expect(
        result.outcomes.single.coverage!.kind,
        PrivateKeyExportCoverageKind.offlineAccount,
      );
      final exported = result.keysByAsset[shielded.id]!.single;
      expect(exported.viewingKey, 'synthetic-viewing-key');
      expect(exported.hdInfo!.zDerivationPath, "m/32'/133'/0'");
      expect(exported.toJson()['viewing_key'], 'synthetic-viewing-key');
      expect(exported.toString().contains('synthetic-viewing-key'), isFalse);
    },
  );
  for (final compatibility in [false, true]) {
    test(
      'snapshots asset selection before authentication await (compatibility=$compatibility)',
      () async {
        final read = Completer<KdfUser?>();
        var reads = 0;
        when(
          () => auth.currentUser,
        ).thenAnswer((_) => reads++ == 0 ? read.future : Future.value(user));
        final selected = [btc.id];
        final operation = compatibility
            ? manager.getPrivateKeys(assets: selected)
            : manager.exportPrivateKeys(
                request: PrivateKeyExportRequest(assets: selected),
              );
        selected.clear();
        selected.add(trx.id);
        read.complete(user);
        final result = await operation;
        final keys = compatibility
            ? result as Map<AssetId, List<PrivateKey>>
            : (result as PrivateKeyExportResult).keysByAsset;
        expect(keys.keys, [btc.id]);
        expect(client.requests.map((request) => request['method']), [
          'get_private_keys',
        ]);
      },
    );
  }

  test(
    'ERC20 offline export uses its own configured derivation path',
    () async {
      final asset = Asset(
        id: btc.id.copyWith(id: 'ERC20-FIXTURE', subClass: CoinSubClass.erc20),
        protocol: Erc20Protocol.fromJson({
          'type': 'ERC-20',
          'nodes': <Map<String, dynamic>>[],
          'fallback_swap_contract': '',
          'swap_contract_address': '0x0000000000000000000000000000000000000001',
          'derivation_path': "m/44'/60'",
          'decimals': 18,
          'protocol': {
            'type': 'ERC20',
            'protocol_data': {
              'platform': 'ETH',
              'contract_address': '0x0000000000000000000000000000000000000001',
            },
          },
        }),
        isWalletOnly: true,
        signMessagePrefix: null,
      );
      when(() => assets.fromId(asset.id)).thenReturn(asset);
      client.respond = (_) => {
        'mmrpc': '2.0',
        'result': [
          {
            'coin': asset.id.id,
            'addresses': [
              for (var i = 0; i < 11; i++)
                {
                  'derivation_path': "m/44'/60'/0'/0/$i",
                  'pubkey': 'public',
                  'address': 'synthetic-erc20-$i',
                  'priv_key': 'synthetic-erc20-secret-$i',
                },
            ],
          },
        ],
      };
      final result = await manager.exportPrivateKeys(
        request: PrivateKeyExportRequest(assets: [asset.id]),
      );
      expect(result.isComplete, isTrue);
      expect(
        result.outcomes.single.coverage!.kind,
        PrivateKeyExportCoverageKind.offlineHdRange,
      );
      expect(
        result.keysByAsset[asset.id]!.first.hdInfo!.derivationPath,
        "m/44'/60'/0'/0/0",
      );
    },
  );
  test('refuses a NEW capability during a pending auth transition', () async {
    when(() => auth.isAuthTransitionInProgress).thenReturn(true);
    await expectLater(
      manager.captureExportSession(),
      throwsA(isA<PrivateKeyExportSessionChangedException>()),
    );
    verifyNever(() => auth.currentUser);
    expect(client.requests, isEmpty);
  });

  test('rejects transition that starts during identity verification', () async {
    when(() => auth.currentUser).thenAnswer((_) async {
      when(() => auth.isAuthTransitionInProgress).thenReturn(true);
      return user;
    });
    await expectLater(
      manager.captureExportSession(),
      throwsA(isA<PrivateKeyExportSessionChangedException>()),
    );
  });
  test(
    'final synchronous guard rejects auth changes after asynchronous verification',
    () async {
      final session = await manager.captureExportSession();
      await manager.ensureExportSessionCurrent(session);
      generation++;
      expect(
        () => manager.ensureExportSessionCurrentSync(session),
        throwsA(isA<PrivateKeyExportSessionChangedException>()),
      );
    },
  );

  test(
    'manager disposal immediately revokes existing and new capabilities',
    () async {
      final session = await manager.captureExportSession();
      final disposal = manager.dispose();
      expect(
        () => manager.ensureExportSessionCurrentSync(session),
        throwsA(isA<PrivateKeyExportSessionChangedException>()),
      );
      await expectLater(
        manager.captureExportSession(),
        throwsA(isA<PrivateKeyExportSessionChangedException>()),
      );
      await disposal;
    },
  );
  test(
    'capabilities cannot cross managers with identical wallet and generation',
    () async {
      final session = await manager.captureExportSession();
      final separateAuth = _Auth();
      when(() => separateAuth.authGeneration).thenReturn(generation);
      when(() => separateAuth.isAuthTransitionInProgress).thenReturn(false);
      when(() => separateAuth.currentUser).thenAnswer((_) async => user);
      final other = SecurityManager(client, separateAuth, assets, activation);
      await expectLater(
        other.exportPrivateKeys(
          session: session,
          request: PrivateKeyExportRequest(assets: [btc.id]),
        ),
        throwsA(isA<PrivateKeyExportSessionChangedException>()),
      );
      verifyNever(() => separateAuth.currentUser);
      expect(client.requests, isEmpty);
    },
  );
}
