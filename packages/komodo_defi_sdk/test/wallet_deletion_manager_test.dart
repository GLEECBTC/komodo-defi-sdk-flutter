import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_transfer_lock.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

class _Storage
    implements GaslessTransferKeyValueStorage, GaslessTransferKeyDiscovery {
  final values = <String, String>{};
  bool unreadable = false;
  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
  @override
  Future<String?> read(String key) async {
    if (unreadable) throw StateError('locked');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<Set<String>> keysWithPrefix(
    String prefix, {
    required int maxKeys,
  }) async => values.keys.where((key) => key.startsWith(prefix)).toSet();
}

const _wallet = WalletId(
  name: 'inactive-wallet',
  pubkeyHash: 'deletion-test-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);

KdfUser _user({String entry = 'entry-1', WalletId wallet = _wallet}) => KdfUser(
  walletId: wallet,
  isBip39Seed: true,
  metadata: {walletEntryIdMetadataKey: entry},
);

PendingGaslessTransfer _pending({String id = 'request-1', String? trace}) {
  final at = DateTime.utc(2026, 9, 15);
  return PendingGaslessTransfer(
    journalId: id,
    traceId: trace,
    assetId: 'USDT-TRC20',
    network: '728126428',
    sourceAddress: 'TSource',
    custodyAddress: 'TCustody',
    destinationAddress: 'TDestination',
    requestedAmount: Decimal.one,
    signedMaxFee: Decimal.one,
    authorizationDeadline: BigInt.from(1790000000),
    balanceChanges: BalanceChanges(
      netChange: -Decimal.fromInt(2),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.fromInt(2),
      totalAmount: Decimal.one,
    ),
    fee: FeeInfo.tronGasless(
      coin: 'USDT-TRC20',
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: 'TCustody',
      transferFee: Decimal.one,
      totalTokenFee: Decimal.one,
      signedMaxFee: Decimal.one,
    ),
    acceptedAt: at,
    updatedAt: at,
    state: GaslessTransferState.submittedUnknown,
  );
}

void main() {
  group('Reviewed wallet deletion', () {
    late _Storage storage;
    late SecurePendingGaslessTransferRepository journal;
    late KdfUser target;
    late WalletDeletionManager manager;
    var deleted = false;
    Future<void> Function()? beforeValidation;
    Future<void> Function()? afterValidation;

    setUp(() {
      storage = _Storage();
      journal = SecurePendingGaslessTransferRepository(storage: storage);
      target = _user();
      deleted = false;
      beforeValidation = null;
      afterValidation = null;
      manager = WalletDeletionManager(
        readWallets: () async => deleted ? [] : [target],
        pendingTransfers: journal,
        deleteWallet:
            ({
              required walletName,
              required password,
              required validateTarget,
            }) async {
              await beforeValidation?.call();
              await validateTarget(target);
              if (password != 'correct') {
                throw AuthException(
                  'Incorrect password',
                  type: AuthExceptionType.incorrectPassword,
                );
              }
              await afterValidation?.call();
              deleted = true;
            },
      );
    });

    test('deletes an inactive wallet with no pending transfers', () async {
      final review = await manager.prepare(_wallet.name);
      expect(review.recoveryStatus, WalletDeletionRecoveryStatus.none);
      expect(
        (await manager.delete(
          acknowledgedReview: review,
          password: 'correct',
        )).status,
        WalletDeletionStatus.deleted,
      );
      expect(deleted, isTrue);
    });

    for (final trace in [null, 'trace-1']) {
      test('retains ${trace == null ? 'untraced' : 'traced'} recovery '
          'after deletion and renamed reimport', () async {
        await journal.upsert(_wallet, _pending(trace: trace));
        final review = await manager.prepare(_wallet.name);
        expect(review.recoveryStatus, WalletDeletionRecoveryStatus.pending);
        expect(
          (await manager.delete(
            acknowledgedReview: review,
            password: 'correct',
          )).status,
          WalletDeletionStatus.deleted,
        );
        const reimported = WalletId(
          name: 'renamed',
          pubkeyHash: 'deletion-test-hash',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
        );
        expect((await journal.list(reimported)).single.journalId, 'request-1');
      });
    }

    test(
      'unreadable journal permits the explicit uncertainty warning',
      () async {
        await journal.upsert(_wallet, _pending());
        final stored = Map.of(storage.values);
        storage.unreadable = true;
        final review = await manager.prepare(_wallet.name);
        expect(review.recoveryStatus, WalletDeletionRecoveryStatus.unavailable);
        expect(
          (await manager.delete(
            acknowledgedReview: review,
            password: 'correct',
          )).status,
          WalletDeletionStatus.deleted,
        );
        expect(storage.values, stored);
      },
    );

    test('a newly unreadable journal requires an updated warning', () async {
      final review = await manager.prepare(_wallet.name);
      storage.unreadable = true;
      final result = await manager.delete(
        acknowledgedReview: review,
        password: 'correct',
      );
      expect(result.status, WalletDeletionStatus.reviewChanged);
      expect(
        result.review!.recoveryStatus,
        WalletDeletionRecoveryStatus.unavailable,
      );
      expect(deleted, isFalse);
    });

    test(
      'a new reservation after preparation requires renewed confirmation',
      () async {
        final review = await manager.prepare(_wallet.name);
        await journal.upsert(_wallet, _pending());
        final result = await manager.delete(
          acknowledgedReview: review,
          password: 'correct',
        );
        expect(result.status, WalletDeletionStatus.reviewChanged);
        expect(
          result.review!.transfers.single.destinationAddress,
          'TDestination',
        );
        expect(deleted, isFalse);
      },
    );

    test('progress and completed records preserve acknowledgement', () async {
      final pending = _pending(trace: 'trace-1');
      await journal.upsert(_wallet, pending);
      final review = await manager.prepare(_wallet.name);
      await journal.upsert(
        _wallet,
        pending.copyWith(updatedAt: DateTime.utc(2026, 9, 16)),
      );
      await journal.remove(_wallet, pending.journalId);
      expect(
        (await manager.delete(
          acknowledgedReview: review,
          password: 'correct',
        )).status,
        WalletDeletionStatus.deleted,
      );
    });

    test(
      'same-name same-seed replacement under catalog lock cannot be deleted',
      () async {
        final review = await manager.prepare(_wallet.name);
        beforeValidation = () async => target = _user(entry: 'entry-2');
        expect(
          (await manager.delete(
            acknowledgedReview: review,
            password: 'correct',
          )).status,
          WalletDeletionStatus.targetChanged,
        );
        expect(deleted, isFalse);
      },
    );

    test(
      'live submission is busy only until its local outcome is stored',
      () async {
        final review = await manager.prepare(_wallet.name);
        final lease = await tryAcquireGaslessWalletLease(
          walletStorageNamespace(_wallet),
        );
        expect(lease, isNotNull);
        expect(
          (await manager.delete(
            acknowledgedReview: review,
            password: 'correct',
          )).status,
          WalletDeletionStatus.busy,
        );
        await lease!.release();
        expect(
          (await manager.delete(
            acknowledgedReview: review,
            password: 'correct',
          )).status,
          WalletDeletionStatus.deleted,
        );
      },
    );

    test('new submission is blocked while deletion owns the lease', () async {
      final review = await manager.prepare(_wallet.name);
      afterValidation = () async {
        expect(
          await tryAcquireGaslessWalletLease(walletStorageNamespace(_wallet)),
          isNull,
        );
      };
      await manager.delete(acknowledgedReview: review, password: 'correct');
      final available = await tryAcquireGaslessWalletLease(
        walletStorageNamespace(_wallet),
      );
      expect(available, isNotNull);
      await available!.release();
    });

    test(
      'wrong password preserves wallet and recovery and releases the lease',
      () async {
        await journal.upsert(_wallet, _pending());
        final review = await manager.prepare(_wallet.name);
        await expectLater(
          manager.delete(acknowledgedReview: review, password: 'wrong'),
          throwsA(isA<AuthException>()),
        );
        expect(deleted, isFalse);
        expect(await journal.list(_wallet), hasLength(1));
        final available = await tryAcquireGaslessWalletLease(
          walletStorageNamespace(_wallet),
        );
        expect(available, isNotNull);
        await available!.release();
      },
    );

    test('foreign SDK reviews cannot authorize deletion', () async {
      final foreign = WalletDeletionManager(
        readWallets: () async => [target],
        pendingTransfers: journal,
        deleteWallet:
            ({
              required walletName,
              required password,
              required validateTarget,
            }) async {},
      );
      final review = await foreign.prepare(_wallet.name);
      await expectLater(
        manager.delete(acknowledgedReview: review, password: 'correct'),
        throwsA(isA<WalletDeletionReviewRequiredException>()),
      );
      expect(deleted, isFalse);
    });

    test('name-only target warns and uses global submission scope', () async {
      target = _user(
        wallet: WalletId.fromName(
          'legacy',
          const AuthOptions(derivationMethod: DerivationMethod.iguana),
        ),
      );
      final review = await manager.prepare('legacy');
      expect(review.recoveryStatus, WalletDeletionRecoveryStatus.unavailable);
      final lease = await tryAcquireGaslessWalletLease('*');
      expect(
        (await manager.delete(
          acknowledgedReview: review,
          password: 'correct',
        )).status,
        WalletDeletionStatus.busy,
      );
      await lease!.release();
      expect(
        (await manager.delete(
          acknowledgedReview: review,
          password: 'correct',
        )).status,
        WalletDeletionStatus.deleted,
      );
    });
  });
}
