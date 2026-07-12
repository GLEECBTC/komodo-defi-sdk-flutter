import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

PendingGaslessTransfer _transfer({
  String? traceId = 'trace-1',
  String requestId = '123e4567-e89b-42d3-a456-426614174000',
  String assetId = 'USDT-TRC20',
  String custodyAddress = 'TCustody',
  GaslessTransferState state = GaslessTransferState.submittedPending,
}) {
  final acceptedAt = DateTime.utc(2026, 7, 10, 12);
  return PendingGaslessTransfer(
    traceId: traceId,
    requestId: requestId,
    assetId: assetId,
    network: '728126428',
    sourceAddress: 'TSource',
    custodyAddress: custodyAddress,
    destinationAddress: 'TDestination',
    requestedAmount: Decimal.parse('5'),
    signedMaxFee: Decimal.parse('2'),
    authorizationDeadline: 1783690000,
    authorizationFingerprint: 'safe-fingerprint',
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse('-5'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.parse('5'),
      totalAmount: Decimal.parse('5'),
    ),
    fee: FeeInfo.tronGasless(
      coin: assetId,
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: custodyAddress,
      transferFee: Decimal.one,
      totalTokenFee: Decimal.one,
      signedMaxFee: Decimal.parse('2'),
      traceId: traceId,
    ),
    acceptedAt: acceptedAt,
    updatedAt: acceptedAt,
    state: state,
    provider: 'TProvider',
    tokenContract: 'TToken',
    authorizationNonce: '9',
    authorizationVersion: '1',
    authorizationAmount: '5000000',
    authorizationMaxFee: '2000000',
  );
}

void main() {
  const wallet = WalletId(
    name: 'wallet',
    pubkeyHash: 'public-hash',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  );
  const otherWallet = WalletId(
    name: 'other',
    pubkeyHash: 'other-hash',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  );
  const renamedWallet = WalletId(
    name: 'renamed-wallet',
    pubkeyHash: 'public-hash',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  );

  test(
    'persists unresolved transfers wallet-scoped and round-trips fields',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final transfer = _transfer();

      await repository.upsert(wallet, transfer);

      expect(await repository.list(wallet), [transfer]);
      expect(await repository.list(renamedWallet), [transfer]);
      expect(await repository.list(otherWallet), isEmpty);
      expect(storage.values.keys.single, isNot(contains('wallet')));
      expect(
        storage.values.values.single,
        isNot(contains('replayable-signature')),
      );
      expect(
        (await repository.list(wallet)).single.authorization.provider,
        'TProvider',
      );
    },
  );

  test(
    'atomically reserves only one unresolved send per custody source',
    () async {
      final repository = SecurePendingGaslessTransferRepository(
        storage: _MemoryStorage(),
      );
      final first = _transfer(traceId: null);
      final duplicate = _transfer(
        traceId: null,
        requestId: '223e4567-e89b-42d3-a456-426614174000',
      );
      final otherSource = _transfer(
        traceId: null,
        requestId: '323e4567-e89b-42d3-a456-426614174000',
        custodyAddress: 'TOtherCustody',
      );

      final results = await Future.wait([
        repository.reserve(wallet, first),
        repository.reserve(wallet, duplicate),
      ]);

      expect(results.where((reserved) => reserved), hasLength(1));
      expect(await repository.reserve(wallet, otherSource), isTrue);
      expect(await repository.list(wallet), hasLength(2));
    },
  );

  test('watch emits wallet-scoped journal updates', () async {
    final repository = SecurePendingGaslessTransferRepository(
      storage: _MemoryStorage(),
    );
    final updates = repository.watch(wallet).take(2).toList();
    await Future<void>.delayed(Duration.zero);

    expect(await repository.reserve(wallet, _transfer(traceId: null)), isTrue);

    final values = await updates;
    expect(values.first, isEmpty);
    expect(values.last.single.requestId, _transfer().requestId);
  });

  test('keeps unknown transfers and clears only terminal states', () async {
    final repository = SecurePendingGaslessTransferRepository(
      storage: _MemoryStorage(),
    );

    await repository.upsert(
      wallet,
      _transfer(state: GaslessTransferState.submittedUnknown),
    );
    expect(await repository.list(wallet), hasLength(1));

    await repository.upsert(
      wallet,
      _transfer(state: GaslessTransferState.confirmed),
    );
    expect(await repository.list(wallet), isEmpty);
  });

  test(
    'accepted upsert atomically coalesces request-only and trace matches',
    () async {
      final repository = SecurePendingGaslessTransferRepository(
        storage: _MemoryStorage(),
      );
      final requestOnly = _transfer(traceId: null);
      final traceOnlyCorrelation = _transfer(
        requestId: '223e4567-e89b-42d3-a456-426614174000',
        traceId: 'trace-accepted',
        custodyAddress: 'TOtherCustody',
      );
      final accepted = _transfer(traceId: 'trace-accepted');

      await repository.upsert(wallet, traceOnlyCorrelation);
      await repository.upsert(wallet, requestOnly);
      await repository.upsert(wallet, accepted);

      expect(await repository.list(wallet), [accepted]);
    },
  );

  test(
    'removing an accepted trace also clears its stale request-only reservation',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final requestOnly = _transfer(traceId: null);
      final accepted = _transfer(traceId: 'trace-accepted');
      await repository.upsert(wallet, accepted);
      final key = storage.values.keys.single;
      storage.values[key] = jsonEncode({
        'version': 1,
        'transfers': [requestOnly.toJson(), accepted.toJson()],
      });

      await repository.remove(wallet, 'trace-accepted');

      expect(await repository.list(wallet), isEmpty);
      expect(
        await repository.reserve(
          wallet,
          _transfer(
            traceId: null,
            requestId: '323e4567-e89b-42d3-a456-426614174000',
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'terminal upsert clears both request and trace correlation rows',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final requestOnly = _transfer(traceId: null);
      final accepted = _transfer(traceId: 'trace-accepted');
      await repository.upsert(wallet, accepted);
      final key = storage.values.keys.single;
      storage.values[key] = jsonEncode({
        'version': 1,
        'transfers': [requestOnly.toJson(), accepted.toJson()],
      });

      await repository.upsert(
        wallet,
        _transfer(
          traceId: 'trace-accepted',
          state: GaslessTransferState.confirmed,
        ),
      );

      expect(await repository.list(wallet), isEmpty);
    },
  );

  test(
    'migrates an unversioned unresolved list without discarding it',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final transfer = _transfer(state: GaslessTransferState.submittedUnknown);
      await repository.upsert(wallet, transfer);
      final key = storage.values.keys.single;
      storage.values[key] = jsonEncode([transfer.toJson()]);

      expect(await repository.list(wallet), [transfer]);
      final migrated = jsonDecode(storage.values[key]!) as Map<String, dynamic>;
      expect(migrated['version'], 2);
      expect(migrated['transfers'], hasLength(1));
    },
  );

  test('migrates v1 records to conservative legacy verification', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final transfer = _transfer(state: GaslessTransferState.submittedUnknown);
    await repository.upsert(wallet, transfer);
    final key = storage.values.keys.single;
    final legacyJson = transfer.toJson()..remove('verification_mode');
    storage.values[key] = jsonEncode({
      'version': 1,
      'transfers': [legacyJson],
    });

    final migrated = await repository.list(wallet);

    expect(
      migrated.single.verificationMode,
      GaslessVerificationMode.legacyOnChain,
    );
    final encoded = jsonDecode(storage.values[key]!) as Map<String, dynamic>;
    expect(encoded['version'], 2);
  });

  test('merges simultaneous v1 and v2 journals without losing trace', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final requestOnly = _transfer(traceId: null);
    await repository.upsert(wallet, requestOnly);
    final v2Key = storage.values.keys.single;
    final acceptedJson = _transfer(traceId: 'accepted-trace').toJson()
      ..remove('verification_mode');
    final legacyHash = sha256.convert(utf8.encode(wallet.compoundId));
    final v1Key = 'gasless_pending_transfers_v1_$legacyHash';
    storage.values[v1Key] = jsonEncode({
      'version': 1,
      'transfers': [acceptedJson],
    });

    final merged = await repository.list(wallet);

    expect(merged, hasLength(1));
    expect(merged.single.traceId, 'accepted-trace');
    expect(
      merged.single.verificationMode,
      GaslessVerificationMode.legacyOnChain,
    );
    expect(storage.values.containsKey(v1Key), isFalse);
    expect(storage.values.containsKey(v2Key), isTrue);
  });

  test('preserves conflicting accepted traces for the same request', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    await repository.upsert(wallet, _transfer(traceId: 'trace-a'));
    final legacyHash = sha256.convert(utf8.encode(wallet.compoundId));
    final v1Key = 'gasless_pending_transfers_v1_$legacyHash';
    storage.values[v1Key] = jsonEncode({
      'version': 1,
      'transfers': [_transfer(traceId: 'trace-b').toJson()],
    });

    final merged = await repository.list(wallet);

    expect(
      merged.map((item) => item.traceId),
      containsAll(['trace-a', 'trace-b']),
    );
  });

  test(
    'merges complementary metadata with conservative lifecycle state',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final current = _transfer(traceId: 'shared-trace');
      await repository.upsert(wallet, current);
      final legacyHash = sha256.convert(utf8.encode(wallet.compoundId));
      final v1Key = 'gasless_pending_transfers_v1_$legacyHash';
      final legacy =
          _transfer(
              traceId: 'shared-trace',
              state: GaslessTransferState.submittedUnknown,
            ).toJson()
            ..remove('provider')
            ..remove('verification_mode');
      storage.values[v1Key] = jsonEncode({
        'version': 1,
        'transfers': [legacy],
      });

      final merged = await repository.list(wallet);

      expect(merged, hasLength(1));
      expect(merged.single.provider, 'TProvider');
      expect(merged.single.state, GaslessTransferState.submittedUnknown);
    },
  );

  test(
    'future schema remains stored and surfaces a migration blocker',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      await repository.upsert(wallet, _transfer());
      final key = storage.values.keys.single;
      final unsupported = jsonEncode({
        'version': 99,
        'transfers': <Map<String, dynamic>>[],
      });
      storage.values[key] = unsupported;

      await expectLater(repository.list(wallet), throwsStateError);
      expect(storage.values[key], unsupported);
    },
  );
}
