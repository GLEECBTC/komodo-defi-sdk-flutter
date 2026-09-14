@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_transfer_lock.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

class _MockApiClient extends Mock implements ApiClient {}

class _MockAssetProvider extends Mock implements IAssetProvider {}

class _MockFeeManager extends Mock implements FeeManager {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockLegacyWithdrawalManager extends Mock
    implements LegacyWithdrawalManager {}

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final _values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

const _wallet = WalletId(
  name: 'web-submission-wallet',
  pubkeyHash: 'web-submission-wallet-hash',
  authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
);

PendingGaslessTransfer _pending() {
  final acceptedAt = DateTime.utc(2026, 7, 10, 12);
  return PendingGaslessTransfer(
    journalId: 'web-live-submission',
    assetId: 'USDT-TRC20',
    network: '728126428',
    sourceAddress: 'TWebSource',
    custodyAddress: 'TWebCustody',
    destinationAddress: 'TWebDestination',
    requestedAmount: Decimal.one,
    signedMaxFee: Decimal.one,
    authorizationDeadline: BigInt.from(1783690000),
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
      gasfreeAddress: 'TWebCustody',
      transferFee: Decimal.one,
      totalTokenFee: Decimal.one,
      signedMaxFee: Decimal.one,
    ),
    acceptedAt: acceptedAt,
    updatedAt: acceptedAt,
    state: GaslessTransferState.submittedUnknown,
  );
}

WithdrawalManager _manager(PendingGaslessTransferRepository repository) =>
    WithdrawalManager(
      _MockApiClient(),
      _MockAssetProvider(),
      _MockFeeManager(),
      _MockActivationCoordinator(),
      _MockLegacyWithdrawalManager(),
      pendingGaslessTransfers: repository,
      walletIdResolver: () async => _wallet,
    );

void main() {
  test(
    'discard refuses an external Web Lock until its owner releases',
    () async {
      final repository = SecurePendingGaslessTransferRepository(
        storage: _MemoryStorage(),
      );
      final pending = _pending();
      await repository.upsert(_wallet, pending);
      final lockName = gaslessSubmissionLockName(
        walletStorageNamespace(_wallet),
        pending.journalId,
      );
      final acquired = Completer<void>();
      final release = Completer<JSAny?>();
      // Acquire the browser lock directly. No SDK lease registry is touched,
      // matching a competing same-origin tab or worker's ownership.
      final request = web.window.navigator.locks
          .request(
            lockName,
            Zone.current.bindUnaryCallback((web.Lock? lock) {
              expect(lock, isNotNull);
              acquired.complete();
              return release.future.toJS;
            }).toJS,
          )
          .toDart;
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await request;
      });
      await acquired.future;
      final manager = _manager(repository);
      addTearDown(manager.dispose);

      await expectLater(
        manager
            .discardPendingGaslessTransfer(pending.journalId)
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<GaslessTransferException>().having(
            (error) => error.code,
            'code',
            GaslessTransferErrorCode.capabilityNotReady,
          ),
        ),
      );
      expect(await repository.find(_wallet, pending.journalId), isNotNull);
      release.complete();
      await request;

      expect(
        await manager.discardPendingGaslessTransfer(pending.journalId),
        isTrue,
      );
      expect(await repository.list(_wallet), isEmpty);
    },
  );

  test(
    'destroying the owning browser context releases an abandoned lease',
    () async {
      final pending = _pending();
      final namespace = walletStorageNamespace(_wallet);
      final frame = web.HTMLIFrameElement();
      web.document.body!.appendChild(frame);
      // External JS interop methods cannot be torn off.
      // ignore: unnecessary_lambdas
      addTearDown(() => frame.remove());
      final acquired = Completer<void>();
      final held = Completer<JSAny?>();
      final request = frame.contentWindow!.navigator.locks
          .request(
            gaslessSubmissionLockName(namespace, pending.journalId),
            Zone.current.bindUnaryCallback((web.Lock? lock) {
              acquired.complete();
              return held.future.toJS;
            }).toJS,
          )
          .toDart;
      // A destroyed context can leave its own promise unresolved. Attach an
      // error handler without waiting for that context during test cleanup.
      unawaited(request.then<void>((_) {}, onError: (Object _) {}));
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });
      await acquired.future;
      expect(
        await tryAcquireGaslessSubmissionLease(namespace, pending.journalId),
        isNull,
      );

      frame.remove();
      final recovered = await tryAcquireGaslessSubmissionLease(
        namespace,
        pending.journalId,
      );
      expect(recovered, isNotNull);
      await recovered!.release();
    },
  );

  test(
    'submission lease holds a real Web Lock without blocking journal IO',
    () async {
      final pending = _pending();
      final namespace = walletStorageNamespace(_wallet);
      final lease = await tryAcquireGaslessSubmissionLease(
        namespace,
        pending.journalId,
      );
      expect(lease, isNotNull);
      addTearDown(lease!.release);
      final repository = SecurePendingGaslessTransferRepository(
        storage: _MemoryStorage(),
      );
      expect(
        await repository
            .reserve(_wallet, pending)
            .timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect(await repository.list(_wallet), hasLength(1));

      Future<bool> competingBrowserRequest() async {
        var granted = false;
        await web.window.navigator.locks
            .request(
              gaslessSubmissionLockName(namespace, pending.journalId),
              web.LockOptions(ifAvailable: true),
              Zone.current.bindUnaryCallback((web.Lock? lock) {
                granted = lock != null;
                return null;
              }).toJS,
            )
            .toDart;
        return granted;
      }

      expect(await competingBrowserRequest(), isFalse);
      final independentLease = await tryAcquireGaslessSubmissionLease(
        'different-wallet-namespace',
        pending.journalId,
      );
      expect(independentLease, isNotNull);
      await independentLease!.release();
      await lease.release();
      await lease.release();
      expect(await competingBrowserRequest(), isTrue);
    },
  );
}
