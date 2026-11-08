@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_transfer_lock.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_coordinator.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_journal.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_support.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../helpers/withdrawal_auth_fixture.dart';
import '../solana/solana_fixtures.dart';

class _MemoryStorage implements GaslessTransferKeyValueStorage {
  final values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

WithdrawalPreview _preview() => WithdrawResult(
  coin: 'SOL-DEV',
  txHash: 'FreshSignature',
  txHex: 'aabb',
  from: ['sender'],
  to: ['recipient'],
  balanceChanges: BalanceChanges(
    netChange: -Decimal.one,
    receivedByMe: Decimal.zero,
    spentByMe: Decimal.one,
    totalAmount: Decimal.one,
  ),
  fee: FeeInfo.solana(
    coin: 'SOL-DEV',
    feeAmount: Decimal.parse('0.000005'),
    rentAmount: Decimal.zero,
    totalAmount: Decimal.parse('0.000005'),
  ),
  blockHeight: 0,
  timestamp: 123,
);

void main() {
  test(
    'Solana confirmation owns a cross-context lock through broadcast',
    () async {
      const walletId = WalletId(
        name: 'solana-web-lock',
        pubkeyHash: 'solana-web-lock-verified',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      );
      final auth = WithdrawalAuthFixture(walletResolver: () async => walletId);
      final wallet = WalletOperationContext(
        walletId: walletId,
        generation: 0,
        session: await auth.captureSessionContext(),
      );
      final asset = solanaAsset();
      final parameters = WithdrawParameters(
        asset: asset.id.id,
        toAddress: 'recipient',
        amount: Decimal.one,
      );
      final lockName = gaslessSubmissionLockName(
        walletStorageNamespace(walletId),
        'solana:${solanaWithdrawalIntentKey(parameters)}',
      );
      final frame = web.HTMLIFrameElement();
      web.document.body!.appendChild(frame);
      // External JS interop methods cannot be torn off by the Wasm compiler.
      // ignore: unnecessary_lambdas
      addTearDown(() => frame.remove());
      final acquired = Completer<void>();
      final release = Completer<JSAny?>();
      final externalLock = frame.contentWindow!.navigator.locks
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
        await externalLock;
      });
      await acquired.future;

      var signed = 0;
      var submitted = 0;
      final refreshing = Completer<void>();
      final refreshed = Completer<WithdrawalPreview>();
      final broadcasting = Completer<void>();
      final broadcast = Completer<SendRawTransactionResponse>();
      final coordinator = SolanaWithdrawalCoordinator(
        capabilities: const SolanaCapabilities(enabled: true),
        journal: SecureSolanaWithdrawalJournal(storage: _MemoryStorage()),
        captureWallet: () async => wallet,
        requireWalletCurrent: (context) async =>
            auth.ensureSessionContextCurrent(context.session),
        ensureSessionCurrent: (context) =>
            auth.ensureSessionContextCurrent(context.session),
        ensureAllowed: (_) {},
        runWithSession: <T>(context, dispatch) =>
            auth.runWithSession<T>(context.session, dispatch),
        createPreview: (_) async {
          if (++signed == 1) return _preview();
          refreshing.complete();
          return refreshed.future;
        },
        broadcast: (_, __) {
          submitted++;
          broadcasting.complete();
          return broadcast.future;
        },
      );
      final preview = await coordinator.previewWithdrawal(parameters, asset);
      await expectLater(
        coordinator.executeWithdrawal(preview, asset).toList(),
        throwsStateError,
      );
      expect(signed, 1);
      expect(submitted, 0);
      release.complete();
      await externalLock;

      Future<bool> competingContextCanConfirm() async {
        var granted = false;
        await frame.contentWindow!.navigator.locks
            .request(
              lockName,
              web.LockOptions(ifAvailable: true),
              Zone.current.bindUnaryCallback((web.Lock? lock) {
                granted = lock != null;
                return null;
              }).toJS,
            )
            .toDart;
        return granted;
      }

      final confirmation = coordinator
          .executeWithdrawal(preview, asset)
          .toList();
      await refreshing.future;
      expect(await competingContextCanConfirm(), isFalse);
      refreshed.complete(_preview());
      await broadcasting.future;
      expect(await competingContextCanConfirm(), isFalse);
      broadcast.complete(
        SendRawTransactionResponse(mmrpc: '2.0', txHash: 'FreshSignature'),
      );
      expect((await confirmation).last.status, WithdrawalStatus.complete);
      expect(signed, 2);
      expect(submitted, 1);
      expect(await competingContextCanConfirm(), isTrue);
    },
  );
}
