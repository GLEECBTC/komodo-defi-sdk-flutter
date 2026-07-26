import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _MemoryStorage
    implements GaslessTransferKeyValueStorage, GaslessTransferKeyDiscovery {
  final values = <String, String>{};
  String? failNextWriteFor;
  final unreadableKeys = <String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async =>
      unreadableKeys.contains(key) ? null : values[key];

  @override
  Future<Set<String>> keysWithPrefix(
    String prefix, {
    required int maxKeys,
  }) async {
    final keys = values.keys.where((key) => key.startsWith(prefix)).toSet();
    if (keys.length > maxKeys) {
      throw StateError('GasFree legacy journal discovery limit exceeded');
    }
    return keys;
  }

  @override
  Future<void> write(String key, String value) async {
    if (failNextWriteFor == key) {
      failNextWriteFor = null;
      throw StateError('simulated write interruption');
    }
    values[key] = value;
  }
}

const _wallet = WalletId(
  name: 'wallet',
  pubkeyHash: 'public-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);
const _renamedWallet = WalletId(
  name: 'renamed-wallet',
  pubkeyHash: 'public-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);
const _weakPasswordWallet = WalletId(
  name: 'wallet-restored-with-updated-password-policy',
  pubkeyHash: 'public-hash',
  authOptions: AuthOptions(
    derivationMethod: DerivationMethod.iguana,
    allowWeakPassword: true,
  ),
);
const _otherWallet = WalletId(
  name: 'other',
  pubkeyHash: 'other-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);
const _samePubkeyHdWallet = WalletId(
  name: 'wallet',
  pubkeyHash: 'public-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
);
const _renamedSamePubkeyHdWallet = WalletId(
  name: 'renamed-hd-wallet',
  pubkeyHash: 'public-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
);

PendingGaslessTransfer _transfer({
  String journalId = '123e4567-e89b-42d3-a456-426614174000',
  String? traceId = 'trace-1',
  String sourceAddress = 'TSource',
  String custodyAddress = 'TCustody',
  BigInt? authorizationDeadline,
  GaslessTransferState state = GaslessTransferState.submittedPending,
}) {
  final acceptedAt = DateTime.utc(2026, 7, 10, 12);
  return PendingGaslessTransfer(
    journalId: journalId,
    traceId: traceId,
    assetId: 'USDT-TRC20',
    network: '728126428',
    sourceAddress: sourceAddress,
    custodyAddress: custodyAddress,
    destinationAddress: 'TDestination',
    requestedAmount: Decimal.parse('5'),
    signedMaxFee: Decimal.parse('2'),
    authorizationDeadline: authorizationDeadline ?? BigInt.from(1783690000),
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse('-7'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.parse('7'),
      totalAmount: Decimal.parse('5'),
    ),
    fee: FeeInfo.tronGasless(
      coin: 'USDT-TRC20',
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: custodyAddress,
      transferFee: Decimal.one,
      totalTokenFee: Decimal.one,
      signedMaxFee: Decimal.parse('2'),
    ),
    acceptedAt: acceptedAt,
    updatedAt: acceptedAt,
    state: state,
  );
}

String _scopedKey(WalletId wallet) =>
    'gasless_pending_transfers_v3_${walletStorageNamespace(wallet)}';

String _legacyScopedNamespaceKey(WalletId wallet) =>
    'gasless_pending_transfers_v3_'
    '${legacyWalletStorageNamespaces(wallet).first}';

String _ambiguousPubkeyKey(WalletId wallet) {
  final hash = sha256.convert(utf8.encode(wallet.pubkeyHash!));
  return 'gasless_pending_transfers_v2_$hash';
}

String _legacyCompoundKey(WalletId wallet) {
  final hash = sha256.convert(utf8.encode(wallet.compoundId));
  return 'gasless_pending_transfers_v1_$hash';
}

String _ambiguousLegacyAliasKey(WalletId wallet) {
  final hash = sha256.convert(utf8.encode(wallet.pubkeyHash!));
  return 'gasless_pending_transfers_legacy_aliases_v1_$hash';
}

String _scopedLegacyAliasKey(WalletId wallet) =>
    'gasless_pending_transfers_legacy_aliases_v2_'
    '${walletStorageNamespace(wallet)}';

String _legacyScopedNamespaceAliasKey(WalletId wallet) =>
    'gasless_pending_transfers_legacy_aliases_v2_'
    '${legacyWalletStorageNamespaces(wallet).first}';

String _scopedLegacyResolutionKey(WalletId wallet) =>
    'gasless_pending_transfers_legacy_resolution_v1_'
    '${walletStorageNamespace(wallet)}';

String _ambiguousWalletFingerprint(WalletId wallet) =>
    sha256.convert(utf8.encode(wallet.pubkeyHash!)).toString();

Future<void> _resolveForWalletSource(
  PendingGaslessTransferRepository repository,
  WalletId wallet, {
  String sourceAddress = 'TSource',
}) {
  return repository.resolveAmbiguousLegacyTransfers(
    wallet,
    ownedSourceAddressesByAsset: {
      'USDT-TRC20': {sourceAddress},
    },
  );
}

void main() {
  test('persists only wallet-scoped non-replayable journal metadata', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final transfer = _transfer();

    await repository.upsert(_wallet, transfer);

    expect(await repository.list(_wallet), [transfer]);
    expect(await repository.list(_renamedWallet), [transfer]);
    expect(await repository.list(_otherWallet), isEmpty);

    final encoded = storage.values[_scopedKey(_wallet)]!;
    expect(encoded, contains('"version":4'));
    expect(encoded, contains('"journal_id"'));
    expect(encoded, contains('"authorization_deadline":"1783690000"'));
    expect(encoded, isNot(contains('"request_id"')));
    expect(encoded, isNot(contains('"signed_authorization"')));
    expect(encoded, isNot(contains('"sig"')));
    expect(encoded, isNot(contains('"authorization_fingerprint"')));
  });

  test(
    'same public key has isolated auth contexts and rename-stable scopes',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final iguana = _transfer(traceId: 'iguana-trace');
      final hd = _transfer(
        journalId: '223e4567-e89b-42d3-a456-426614174000',
        traceId: 'hd-trace',
        sourceAddress: 'THdSource',
      );

      await repository.upsert(_wallet, iguana);
      await repository.upsert(_samePubkeyHdWallet, hd);

      expect(_scopedKey(_wallet), isNot(_scopedKey(_samePubkeyHdWallet)));
      expect(await repository.list(_wallet), [iguana]);
      expect(await repository.list(_renamedWallet), [iguana]);
      expect(await repository.list(_samePubkeyHdWallet), [hd]);
      expect(await repository.list(_renamedSamePubkeyHdWallet), [hd]);
    },
  );

  test('public-key hash normalization preserves the scoped journal', () async {
    const uppercaseWallet = WalletId(
      name: 'uppercase-name',
      pubkeyHash: 'PUBLIC-HASH',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    );
    final repository = SecurePendingGaslessTransferRepository(
      storage: _MemoryStorage(),
    );
    final transfer = _transfer();

    await repository.upsert(_wallet, transfer);

    expect(await repository.list(uppercaseWallet), [transfer]);
  });

  test('weak-password policy cannot split one wallet journal', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final transfer = _transfer();

    expect(_scopedKey(_wallet), _scopedKey(_weakPasswordWallet));
    expect(walletStorageNamespace(_wallet), startsWith('v2:'));
    expect(legacyWalletStorageNamespaces(_wallet), {
      'v1:87b46bfa612551b1f8ef72ff9d01977e01b7a87e4d04a287c60358abe36e1827',
      'v1:cd20daab40b588ac9d3342be43a07e725cf032e856137e49169d32beffeb0a6b',
    });
    await repository.upsert(_wallet, transfer);

    expect(await repository.list(_weakPasswordWallet), [transfer]);
    expect(
      await repository.reserve(
        _weakPasswordWallet,
        _transfer(journalId: 'new-journal', traceId: null),
      ),
      isFalse,
    );
  });

  test('reserves only one unresolved send per custody source', () async {
    final repository = SecurePendingGaslessTransferRepository(
      storage: _MemoryStorage(),
    );
    final first = _transfer(traceId: null);
    final duplicate = _transfer(
      journalId: '223e4567-e89b-42d3-a456-426614174000',
      traceId: null,
    );
    final otherCustody = _transfer(
      journalId: '323e4567-e89b-42d3-a456-426614174000',
      traceId: null,
      custodyAddress: 'TOtherCustody',
    );

    final reservations = await Future.wait([
      repository.reserve(_wallet, first),
      repository.reserve(_wallet, duplicate),
    ]);

    expect(reservations.where((reserved) => reserved), hasLength(1));
    expect(await repository.reserve(_wallet, otherCustody), isTrue);
    expect(await repository.list(_wallet), hasLength(2));
  });

  test('reservation is atomic across repository instances', () async {
    final storage = _MemoryStorage();
    final firstRepository = SecurePendingGaslessTransferRepository(
      storage: storage,
    );
    final secondRepository = SecurePendingGaslessTransferRepository(
      storage: storage,
    );
    final first = _transfer(traceId: null);
    final duplicate = _transfer(
      journalId: '223e4567-e89b-42d3-a456-426614174000',
      traceId: null,
    );

    final reservations = await Future.wait([
      firstRepository.reserve(_wallet, first),
      secondRepository.reserve(_wallet, duplicate),
    ]);

    expect(reservations.where((reserved) => reserved), hasLength(1));
    expect(await firstRepository.list(_wallet), hasLength(1));
  });

  test('watch cannot lose a write racing its initial snapshot', () async {
    final repository = SecurePendingGaslessTransferRepository(
      storage: _MemoryStorage(),
    );
    final iterator = StreamIterator(repository.watch(_wallet));
    final firstSnapshot = iterator.moveNext();
    final transfer = _transfer();

    await repository.upsert(_wallet, transfer);
    expect(await firstSnapshot, isTrue);
    if (iterator.current.isEmpty) {
      expect(await iterator.moveNext(), isTrue);
    }
    expect(iterator.current, [transfer]);
    await iterator.cancel();
  });

  test('watch observes writes from another repository instance', () async {
    final storage = _MemoryStorage();
    final watchingRepository = SecurePendingGaslessTransferRepository(
      storage: storage,
    );
    final writingRepository = SecurePendingGaslessTransferRepository(
      storage: storage,
    );
    final iterator = StreamIterator(watchingRepository.watch(_wallet));
    final transfer = _transfer();

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isEmpty);

    await writingRepository.upsert(_wallet, transfer);

    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 1)),
      isTrue,
    );
    expect(iterator.current, [transfer]);
    await iterator.cancel();
  });

  test('accepted trace atomically replaces its journal reservation', () async {
    final repository = SecurePendingGaslessTransferRepository(
      storage: _MemoryStorage(),
    );
    final reserved = _transfer(traceId: null);
    final accepted = _transfer(traceId: 'trace-accepted');

    expect(await repository.reserve(_wallet, reserved), isTrue);
    await repository.upsert(_wallet, accepted);

    expect(await repository.list(_wallet), [accepted]);
    expect(
      await repository.findByJournalId(_wallet, accepted.journalId),
      accepted,
    );
    expect(await repository.findByTraceId(_wallet, 'trace-accepted'), accepted);
  });

  test(
    'ambiguous legacy data blocks normal reads and reservations before proof',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final legacy = _transfer(traceId: 'legacy-trace');
      storage.values[_ambiguousPubkeyKey(_wallet)] = jsonEncode({
        'version': 3,
        'transfers': [legacy.toJson()],
      });

      expect(await repository.listAmbiguousLegacyTransfers(_wallet), [legacy]);
      await expectLater(
        repository.list(_wallet),
        throwsA(isA<GaslessTransferLegacyResolutionException>()),
      );
      await expectLater(
        repository.reserve(
          _wallet,
          _transfer(journalId: 'new-journal', traceId: null),
        ),
        throwsA(isA<GaslessTransferLegacyResolutionException>()),
      );
    },
  );

  test(
    'authoritative scoped trace progress supersedes claimed legacy state',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      await repository.upsert(
        _wallet,
        _transfer(state: GaslessTransferState.confirming),
      );
      storage.values[_legacyCompoundKey(_wallet)] = jsonEncode({
        'version': 1,
        'transfers': [
          _transfer(state: GaslessTransferState.submittedUnknown).toJson(),
        ],
      });

      await _resolveForWalletSource(repository, _wallet);
      final recovered = (await repository.list(_wallet)).single;

      expect(recovered.traceId, 'trace-1');
      expect(recovered.state, GaslessTransferState.confirming);
    },
  );

  test('legacy accepted record migrates into trace recovery', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final legacy = _transfer(traceId: 'legacy-trace').toJson()
      ..remove('journal_id')
      ..['request_id'] = 'legacy-local-id'
      ..['signed_authorization'] = {
        'sig': 'replayable-signature',
        'max_fee': '2000000',
      }
      ..['authorization_fingerprint'] = 'obsolete-fingerprint';
    final ambiguousEncoded = jsonEncode({
      'version': 2,
      'transfers': [legacy],
    });
    storage.values[_ambiguousPubkeyKey(_wallet)] = ambiguousEncoded;

    await expectLater(
      repository.list(_wallet),
      throwsA(isA<GaslessTransferLegacyResolutionException>()),
    );
    await _resolveForWalletSource(repository, _wallet);
    final migrated = (await repository.list(_wallet)).single;

    expect(migrated.journalId, 'legacy-local-id');
    expect(migrated.traceId, 'legacy-trace');
    expect(await repository.findByTraceId(_wallet, 'legacy-trace'), migrated);
    final rewritten = storage.values[_scopedKey(_wallet)]!;
    expect(rewritten, contains('"version":4'));
    expect(rewritten, contains('"journal_id":"legacy-local-id"'));
    expect(rewritten, isNot(contains('"request_id"')));
    expect(rewritten, isNot(contains('replayable-signature')));
    expect(rewritten, isNot(contains('obsolete-fingerprint')));
    final retainedLegacy =
        jsonDecode(storage.values[_ambiguousPubkeyKey(_wallet)]!)
            as Map<String, dynamic>;
    final retainedTransfer =
        (retainedLegacy['transfers']! as List).single as Map<String, dynamic>;
    expect(retainedLegacy['version'], 4);
    expect(retainedTransfer['journal_id'], 'legacy-local-id');
    expect(retainedTransfer['trace_id'], 'legacy-trace');
    expect(retainedTransfer, isNot(contains('request_id')));
    expect(retainedTransfer, isNot(contains('signed_authorization')));
    expect(retainedTransfer, isNot(contains('authorization_fingerprint')));
    expect(storage.values, contains(_scopedLegacyResolutionKey(_wallet)));
  });

  test('previous auth-options namespace remains safely recoverable', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final legacy = _transfer(traceId: 'previous-namespace-trace');
    final oldKey = _legacyScopedNamespaceKey(_wallet);
    storage.values[oldKey] = jsonEncode({
      'version': 4,
      'transfers': [legacy.toJson()],
    });

    expect(await repository.listAmbiguousLegacyTransfers(_weakPasswordWallet), [
      legacy,
    ]);
    await expectLater(
      repository.list(_weakPasswordWallet),
      throwsA(isA<GaslessTransferLegacyResolutionException>()),
    );

    await _resolveForWalletSource(repository, _weakPasswordWallet);

    expect(await repository.list(_weakPasswordWallet), [legacy]);
    expect(storage.values, contains(_scopedKey(_wallet)));
    expect(storage.values, contains(oldKey));
    expect(
      storage.values,
      contains(_scopedLegacyResolutionKey(_weakPasswordWallet)),
    );
  });

  test(
    'previous namespace alias preserves pre-claim rename recovery',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final legacyKey = _legacyCompoundKey(_wallet);
      final legacy = _transfer(traceId: 'previous-alias-trace');
      final oldNamespace = legacyWalletStorageNamespaces(_wallet).first;
      storage.values[legacyKey] = jsonEncode({
        'version': 4,
        'transfers': [legacy.toJson()],
      });
      storage.values[_legacyScopedNamespaceAliasKey(_wallet)] = jsonEncode({
        'version': 2,
        'wallet_namespace': oldNamespace,
        'legacy_keys': [legacyKey],
      });

      expect(
        await repository.listAmbiguousLegacyTransfers(_weakPasswordWallet),
        [legacy],
      );
      await _resolveForWalletSource(repository, _weakPasswordWallet);

      expect(await repository.list(_weakPasswordWallet), [legacy]);
      expect(
        storage.values[_scopedLegacyAliasKey(_weakPasswordWallet)],
        contains(legacyKey),
      );
      expect(storage.values, contains(_legacyScopedNamespaceAliasKey(_wallet)));
    },
  );

  test('legacy sanitization is atomic and fails closed', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final oldKey = _ambiguousPubkeyKey(_wallet);
    final legacy = _transfer(traceId: 'legacy-trace').toJson()
      ..['signed_authorization'] = {'sig': 'replayable-signature'};
    final unsafeEncoded = jsonEncode({
      'version': 2,
      'transfers': [legacy],
    });
    storage.values[oldKey] = unsafeEncoded;
    storage.failNextWriteFor = oldKey;

    await expectLater(
      repository.listAmbiguousLegacyTransfers(_wallet),
      throwsStateError,
    );

    expect(storage.values[oldKey], unsafeEncoded);
    expect(storage.values, isNot(contains(_scopedKey(_wallet))));
    expect(
      storage.values,
      isNot(contains(_scopedLegacyResolutionKey(_wallet))),
    );
  });

  test(
    'legacy record without trace stays unknown and non-resubmittable',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final legacy =
          _transfer(
              traceId: null,
              state: GaslessTransferState.preparing,
            ).toJson()
            ..remove('journal_id')
            ..['request_id'] = 'unknown-outcome'
            ..['signed_authorization'] = {'sig': 'must-be-removed'};
      storage.values[_ambiguousPubkeyKey(_wallet)] = jsonEncode({
        'version': 2,
        'transfers': [legacy],
      });

      await _resolveForWalletSource(repository, _wallet);
      final migrated = (await repository.list(_wallet)).single;

      expect(migrated.journalId, 'unknown-outcome');
      expect(migrated.traceId, isNull);
      expect(migrated.state, GaslessTransferState.submittedUnknown);
      expect(
        await repository.reserve(
          _wallet,
          _transfer(journalId: 'new-journal', traceId: null),
        ),
        isFalse,
      );
      expect(
        storage.values[_scopedKey(_wallet)],
        isNot(contains('must-be-removed')),
      );
    },
  );

  test(
    'different auth context retains sanitized non-owned legacy evidence',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final encoded = jsonEncode({
        'version': 3,
        'transfers': [_transfer(traceId: 'iguana-only').toJson()],
      });
      storage.values[_ambiguousPubkeyKey(_wallet)] = encoded;

      await _resolveForWalletSource(
        repository,
        _samePubkeyHdWallet,
        sourceAddress: 'THdSource',
      );

      expect(await repository.list(_samePubkeyHdWallet), isEmpty);
      expect(await repository.list(_renamedSamePubkeyHdWallet), isEmpty);
      final retained =
          jsonDecode(storage.values[_ambiguousPubkeyKey(_wallet)]!)
              as Map<String, dynamic>;
      expect(retained['version'], 4);
      expect(retained['transfers'] as List, hasLength(1));
      expect(
        (retained['transfers'] as List).single,
        isNot(contains('signed_authorization')),
      );
      await expectLater(
        repository.list(_wallet),
        throwsA(isA<GaslessTransferLegacyResolutionException>()),
      );
    },
  );

  test('failed or incomplete source proof leaves legacy blocked', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    storage.values[_ambiguousPubkeyKey(_wallet)] = jsonEncode({
      'version': 3,
      'transfers': [_transfer(traceId: 'blocked-trace').toJson()],
    });

    await repository.resolveAmbiguousLegacyTransfers(
      _wallet,
      ownedSourceAddressesByAsset: const {},
    );
    await expectLater(
      repository.resolveAmbiguousLegacyTransfers(
        _wallet,
        ownedSourceAddressesByAsset: const {'USDT-TRC20': <String>{}},
      ),
      throwsArgumentError,
    );

    expect(
      await repository.listAmbiguousLegacyTransfers(_wallet),
      hasLength(1),
    );
    await expectLater(
      repository.list(_wallet),
      throwsA(isA<GaslessTransferLegacyResolutionException>()),
    );
    expect(storage.values, isNot(contains(_scopedKey(_wallet))));
    expect(
      storage.values,
      isNot(contains(_scopedLegacyResolutionKey(_wallet))),
    );
  });

  test('legacy record without a provable source fails closed', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final malformed = _transfer().toJson()..['source_address'] = '';
    storage.values[_ambiguousPubkeyKey(_wallet)] = jsonEncode({
      'version': 3,
      'transfers': [malformed],
    });

    await expectLater(
      repository.listAmbiguousLegacyTransfers(_wallet),
      throwsA(isA<GaslessTransferStorageFormatException>()),
    );
    await expectLater(
      _resolveForWalletSource(repository, _wallet),
      throwsA(isA<GaslessTransferStorageFormatException>()),
    );
    expect(storage.values, isNot(contains(_scopedKey(_wallet))));
    expect(
      storage.values,
      isNot(contains(_scopedLegacyResolutionKey(_wallet))),
    );
  });

  test('old pubkey alias can discover a renamed compound-key record', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final legacyKey = _legacyCompoundKey(_wallet);
    storage.values[legacyKey] = jsonEncode({
      'version': 1,
      'transfers': [_transfer(traceId: 'renamed-legacy-trace').toJson()],
    });
    storage.values[_ambiguousLegacyAliasKey(_wallet)] = jsonEncode({
      'version': 1,
      'wallet_fingerprint': _ambiguousWalletFingerprint(_wallet),
      'legacy_keys': [legacyKey],
    });

    expect(
      await repository.listAmbiguousLegacyTransfers(_renamedWallet),
      hasLength(1),
    );
    await _resolveForWalletSource(repository, _renamedWallet);

    expect(
      await repository.findByTraceId(_renamedWallet, 'renamed-legacy-trace'),
      isNotNull,
    );
  });

  test(
    'prefix discovery recovers a V1 journal renamed before first discovery',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final legacyKey = _legacyCompoundKey(_wallet);
      final legacy = _transfer(traceId: 'undiscovered-renamed-trace').toJson()
        ..['signed_authorization'] = {
          'sig': 'must-be-sanitized-before-classification',
        };
      storage.values[legacyKey] = jsonEncode({
        'version': 1,
        'transfers': [legacy],
      });

      expect(
        await repository.listAmbiguousLegacyTransfers(_renamedWallet),
        hasLength(1),
      );
      expect(
        storage.values[legacyKey],
        isNot(contains('must-be-sanitized-before-classification')),
      );
      await _resolveForWalletSource(repository, _renamedWallet);

      expect(
        await repository.findByTraceId(
          _renamedWallet,
          'undiscovered-renamed-trace',
        ),
        isNotNull,
      );
      expect(storage.values, contains(legacyKey));
      expect(
        storage.values[_scopedLegacyAliasKey(_renamedWallet)],
        contains(legacyKey),
      );
    },
  );

  test(
    'interrupted V1 claim remains discoverable and recoverable after rename',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final legacyKey = _legacyCompoundKey(_wallet);
      storage.values[legacyKey] = jsonEncode({
        'version': 1,
        'transfers': [_transfer(traceId: 'restart-trace').toJson()],
      });
      storage.failNextWriteFor = _scopedKey(_wallet);

      await expectLater(
        _resolveForWalletSource(repository, _wallet),
        throwsStateError,
      );

      final alias = storage.values[_scopedLegacyAliasKey(_wallet)]!;
      expect(alias, contains(legacyKey));
      expect(alias, contains(walletStorageNamespace(_wallet)));
      expect(alias, isNot(contains(_wallet.pubkeyHash)));
      expect(storage.values, contains(legacyKey));
      expect(storage.values, isNot(contains(_scopedKey(_wallet))));

      await _resolveForWalletSource(repository, _renamedWallet);
      final recovered = await repository.findByTraceId(
        _renamedWallet,
        'restart-trace',
      );
      expect(recovered?.traceId, 'restart-trace');
      expect(storage.values, contains(_scopedKey(_wallet)));
      expect(storage.values, contains(legacyKey));
      expect(storage.values, contains(_scopedLegacyAliasKey(_wallet)));
      expect(
        await repository.listAmbiguousLegacyTransfers(_otherWallet),
        hasLength(1),
      );
      await expectLater(
        repository.list(_otherWallet),
        throwsA(isA<GaslessTransferLegacyResolutionException>()),
      );
    },
  );

  test('scoped legacy alias ownership cannot cross auth contexts', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    storage.values[_scopedLegacyAliasKey(_samePubkeyHdWallet)] = jsonEncode({
      'version': 2,
      'wallet_namespace': walletStorageNamespace(_wallet),
      'legacy_keys': [_legacyCompoundKey(_wallet)],
    });

    await expectLater(
      repository.listAmbiguousLegacyTransfers(_samePubkeyHdWallet),
      throwsStateError,
    );
  });

  test('terminal state removes the durable correlation', () async {
    final repository = SecurePendingGaslessTransferRepository(
      storage: _MemoryStorage(),
    );
    await repository.upsert(_wallet, _transfer());

    await repository.upsert(
      _wallet,
      _transfer(state: GaslessTransferState.confirmed),
    );

    expect(await repository.list(_wallet), isEmpty);
  });

  test('claimed terminal legacy record is never re-imported', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final legacy = _transfer(traceId: 'terminal-trace');
    final encoded = jsonEncode({
      'version': 3,
      'transfers': [legacy.toJson()],
    });
    storage.values[_ambiguousPubkeyKey(_wallet)] = encoded;

    await _resolveForWalletSource(repository, _wallet);
    await repository.upsert(
      _wallet,
      legacy.copyWith(state: GaslessTransferState.confirmed),
    );

    expect(await repository.list(_wallet), isEmpty);
    expect(await repository.listAmbiguousLegacyTransfers(_wallet), isEmpty);
    final retained =
        jsonDecode(storage.values[_ambiguousPubkeyKey(_wallet)]!)
            as Map<String, dynamic>;
    expect(retained['version'], 4);
    expect(retained['transfers'] as List, hasLength(1));
    expect(
      (retained['transfers'] as List).single,
      isNot(contains('signed_authorization')),
    );
    expect(storage.values, contains(_scopedLegacyResolutionKey(_wallet)));
  });

  test('V3 numeric deadline migrates to a V4 decimal string', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final legacy = _transfer().toJson()
      ..['authorization_deadline'] = 1783690000;
    storage.values[_scopedKey(_wallet)] = jsonEncode({
      'version': 3,
      'transfers': [legacy],
    });

    final migrated = (await repository.list(_wallet)).single;

    expect(migrated.authorizationDeadline, BigInt.from(1783690000));
    expect(
      storage.values[_scopedKey(_wallet)],
      contains('"authorization_deadline":"1783690000"'),
    );
    expect(storage.values[_scopedKey(_wallet)], contains('"version":4'));
  });

  test('maximum U256 deadline round trips exactly', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final maxU256 = (BigInt.one << 256) - BigInt.one;
    final transfer = _transfer(authorizationDeadline: maxU256);

    await repository.upsert(_wallet, transfer);
    final restored = (await repository.list(_wallet)).single;

    expect(restored.authorizationDeadline, maxU256);
    expect(
      storage.values[_scopedKey(_wallet)],
      contains('"authorization_deadline":"$maxU256"'),
    );
  });

  test('future storage schema fails closed without rewriting it', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final encoded = jsonEncode({
      'version': 999,
      'transfers': [_transfer().toJson()],
    });
    storage.values[_scopedKey(_wallet)] = encoded;

    await expectLater(repository.list(_wallet), throwsStateError);
    expect(storage.values[_scopedKey(_wallet)], encoded);
  });

  test(
    'present but unreadable journal fails closed without rewriting it',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      final key = _scopedKey(_wallet);
      const ciphertext = 'encrypted-but-unreadable';
      storage.values[key] = ciphertext;
      storage.unreadableKeys.add(key);

      await expectLater(
        repository.list(_wallet),
        throwsA(isA<GaslessTransferStorageReadException>()),
      );
      await expectLater(
        repository.reserve(
          _wallet,
          _transfer(journalId: 'new-journal', traceId: null),
        ),
        throwsA(isA<GaslessTransferStorageReadException>()),
      );

      expect(storage.values[key], ciphertext);
    },
  );

  test(
    'malformed journal failure never retains decrypted source text',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      const privateSentinel = 'TSensitiveDestination-amount-123.45';
      storage.values[_scopedKey(_wallet)] = '{"transfers":["$privateSentinel"';

      Object? thrown;
      try {
        await repository.list(_wallet);
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<GaslessTransferStorageFormatException>());
      expect(thrown.toString(), isNot(contains(privateSentinel)));
      expect(storage.values[_scopedKey(_wallet)], contains(privateSentinel));
    },
  );

  test(
    'well-formed invalid state failure never exposes decrypted source text',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      const privateSentinel = 'private-state-TSensitive-amount-123.45';
      final malformed = _transfer().toJson()..['state'] = privateSentinel;
      storage.values[_scopedKey(_wallet)] = jsonEncode({
        'version': 4,
        'transfers': [malformed],
      });

      Object? thrown;
      try {
        await repository.list(_wallet);
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<GaslessTransferStorageFormatException>());
      expect(thrown.toString(), isNot(contains(privateSentinel)));
      expect(storage.values[_scopedKey(_wallet)], contains(privateSentinel));
    },
  );
}
