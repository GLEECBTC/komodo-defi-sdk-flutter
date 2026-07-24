import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final values = <String, String>{};
  String? failNextWriteFor;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

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
const _otherWallet = WalletId(
  name: 'other',
  pubkeyHash: 'other-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);

PendingGaslessTransfer _transfer({
  String journalId = '123e4567-e89b-42d3-a456-426614174000',
  String? traceId = 'trace-1',
  String custodyAddress = 'TCustody',
  GaslessTransferState state = GaslessTransferState.submittedPending,
}) {
  final acceptedAt = DateTime.utc(2026, 7, 10, 12);
  return PendingGaslessTransfer(
    journalId: journalId,
    traceId: traceId,
    assetId: 'USDT-TRC20',
    network: '728126428',
    sourceAddress: 'TSource',
    custodyAddress: custodyAddress,
    destinationAddress: 'TDestination',
    requestedAmount: Decimal.parse('5'),
    signedMaxFee: Decimal.parse('2'),
    authorizationDeadline: 1783690000,
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

String _stableKey(WalletId wallet) {
  final hash = sha256.convert(utf8.encode(wallet.pubkeyHash!));
  return 'gasless_pending_transfers_v2_$hash';
}

String _legacyKey(WalletId wallet) {
  final hash = sha256.convert(utf8.encode(wallet.compoundId));
  return 'gasless_pending_transfers_v1_$hash';
}

String _legacyAliasKey(WalletId wallet) {
  final hash = sha256.convert(utf8.encode(wallet.pubkeyHash!));
  return 'gasless_pending_transfers_legacy_aliases_v1_$hash';
}

String _walletFingerprint(WalletId wallet) =>
    sha256.convert(utf8.encode(wallet.pubkeyHash!)).toString();

void main() {
  test('persists only wallet-scoped non-replayable journal metadata', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final transfer = _transfer();

    await repository.upsert(_wallet, transfer);

    expect(await repository.list(_wallet), [transfer]);
    expect(await repository.list(_renamedWallet), [transfer]);
    expect(await repository.list(_otherWallet), isEmpty);

    final encoded = storage.values[_stableKey(_wallet)]!;
    expect(encoded, contains('"journal_id"'));
    expect(encoded, isNot(contains('"request_id"')));
    expect(encoded, isNot(contains('"signed_authorization"')));
    expect(encoded, isNot(contains('"sig"')));
    expect(encoded, isNot(contains('"authorization_fingerprint"')));
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
    'authoritative trace progress supersedes correlated unknown state',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      await repository.upsert(
        _wallet,
        _transfer(state: GaslessTransferState.confirming),
      );
      storage.values[_legacyKey(_wallet)] = jsonEncode({
        'version': 1,
        'transfers': [
          _transfer(state: GaslessTransferState.submittedUnknown).toJson(),
        ],
      });

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
    storage.values[_stableKey(_wallet)] = jsonEncode({
      'version': 2,
      'transfers': [legacy],
    });

    final migrated = (await repository.list(_wallet)).single;

    expect(migrated.journalId, 'legacy-local-id');
    expect(migrated.traceId, 'legacy-trace');
    expect(await repository.findByTraceId(_wallet, 'legacy-trace'), migrated);
    final rewritten = storage.values[_stableKey(_wallet)]!;
    expect(rewritten, contains('"version":3'));
    expect(rewritten, contains('"journal_id":"legacy-local-id"'));
    expect(rewritten, isNot(contains('"request_id"')));
    expect(rewritten, isNot(contains('replayable-signature')));
    expect(rewritten, isNot(contains('obsolete-fingerprint')));
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
      storage.values[_stableKey(_wallet)] = jsonEncode({
        'version': 2,
        'transfers': [legacy],
      });

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
        storage.values[_stableKey(_wallet)],
        isNot(contains('must-be-removed')),
      );
    },
  );

  test(
    'interrupted V1 migration remains owned and recoverable after rename',
    () async {
      final storage = _MemoryStorage();
      final repository = SecurePendingGaslessTransferRepository(
        storage: storage,
      );
      storage.values[_legacyKey(_wallet)] = jsonEncode({
        'version': 1,
        'transfers': [_transfer(traceId: 'restart-trace').toJson()],
      });
      storage.failNextWriteFor = _stableKey(_wallet);

      await expectLater(repository.list(_wallet), throwsStateError);

      final alias = storage.values[_legacyAliasKey(_wallet)]!;
      expect(alias, contains(_legacyKey(_wallet)));
      expect(alias, isNot(contains(_wallet.pubkeyHash)));
      expect(storage.values, contains(_legacyKey(_wallet)));
      expect(storage.values, isNot(contains(_stableKey(_wallet))));
      expect(await repository.list(_otherWallet), isEmpty);

      final recovered = await repository.findByTraceId(
        _renamedWallet,
        'restart-trace',
      );

      expect(recovered?.traceId, 'restart-trace');
      expect(storage.values, contains(_stableKey(_wallet)));
      expect(storage.values, isNot(contains(_legacyKey(_wallet))));
      expect(storage.values, isNot(contains(_legacyAliasKey(_wallet))));
      expect(await repository.list(_otherWallet), isEmpty);
    },
  );

  test('legacy alias ownership cannot be replayed across wallets', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    storage.values[_legacyKey(_wallet)] = jsonEncode({
      'version': 1,
      'transfers': [_transfer(traceId: 'wallet-owned-trace').toJson()],
    });
    storage.values[_legacyAliasKey(_otherWallet)] = jsonEncode({
      'version': 1,
      'wallet_fingerprint': _walletFingerprint(_wallet),
      'legacy_keys': [_legacyKey(_wallet)],
    });

    await expectLater(repository.list(_otherWallet), throwsStateError);

    expect(storage.values, contains(_legacyKey(_wallet)));
    expect(storage.values, isNot(contains(_stableKey(_otherWallet))));
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

  test('future storage schema fails closed without rewriting it', () async {
    final storage = _MemoryStorage();
    final repository = SecurePendingGaslessTransferRepository(storage: storage);
    final encoded = jsonEncode({
      'version': 999,
      'transfers': [_transfer().toJson()],
    });
    storage.values[_stableKey(_wallet)] = encoded;

    await expectLater(repository.list(_wallet), throwsStateError);
    expect(storage.values[_stableKey(_wallet)], encoded);
  });
}
