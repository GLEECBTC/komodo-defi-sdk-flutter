import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_transfer_lock.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_journal.dart';
import 'package:komodo_defi_sdk/src/withdrawals/solana_withdrawal_support.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Refreshes Solana's short-lived signed transactions at explicit confirmation.
///
/// A preview is bound to its original parameters and wallet session. Only its
/// user-visible values may authorize a freshly signed transaction. A lost
/// broadcast response keeps the signature in encrypted wallet storage and
/// locks that intent across sessions, without automatic sign-and-send retries.
final class SolanaWithdrawalCoordinator {
  /// Uses the existing RPC and authentication dispatch protections.
  SolanaWithdrawalCoordinator({
    required this.capabilities,
    required this.createPreview,
    required this.broadcast,
    required this.captureWallet,
    required this.requireWalletCurrent,
    required this.ensureSessionCurrent,
    required this.ensureAllowed,
    required this.runWithSession,
    this.journal,
  });

  /// Release capabilities for this engine build.
  final SolanaCapabilities capabilities;

  /// Builds a signed transaction using ordinary withdraw.
  final Future<WithdrawalPreview> Function(WithdrawParameters) createPreview;

  /// Dispatches send_raw_transaction without retries.
  final Future<SendRawTransactionResponse> Function(String, String) broadcast;

  /// Captures a verified authentication session.
  final Future<WalletOperationContext> Function() captureWallet;

  /// Checks wallet identity after asynchronous work.
  final Future<void> Function(WalletOperationContext) requireWalletCurrent;

  /// Checks synchronous session revocation.
  final void Function(WalletOperationContext) ensureSessionCurrent;

  /// Rechecks catalog and activation policy.
  final void Function(Asset) ensureAllowed;

  /// Leases one RPC in the same engine session, excluding identity and storage.
  final Future<T> Function<T>(WalletOperationContext, Future<T> Function())
  runWithSession;

  /// Durable reservation storage, required before submitting.
  final SolanaWithdrawalJournal? journal;
  Expando<_PreparedWithdrawal> _previews = Expando();
  final Map<(Object, String), _PreparedWithdrawal> _submissions = {};

  /// Drops signed previews and transient reservations when the session ends.
  /// Durable unknown-submission records remain available for reconciliation.
  void clearSession() {
    _previews = Expando();
    _submissions.clear();
  }

  Future<WithdrawalPreview> _create(
    WithdrawParameters parameters,
    Asset asset,
  ) async {
    try {
      return contextualizeSolanaWithdrawal(
        await createPreview(parameters),
        asset,
      );
    } on Object catch (error) {
      final contextual = contextualizeSolanaWithdrawalError(error, asset);
      if (contextual != null) throw contextual;
      rethrow;
    }
  }

  /// Creates a review bound to the original intent and authenticated session.
  Future<WithdrawalPreview> previewWithdrawal(
    WithdrawParameters parameters,
    Asset asset,
  ) async {
    validateSolanaWithdrawal(parameters, asset, capabilities);
    final wallet = await captureWallet();
    if (wallet.walletId.authOptions.privKeyPolicy !=
        const PrivateKeyPolicy.contextPrivKey()) {
      throw UnsupportedError('Solana requires an active software wallet');
    }
    final persisted = await journal?.find(wallet.walletId, parameters);
    await requireWalletCurrent(wallet);
    ensureSessionCurrent(wallet);
    if (persisted != null) throw SolanaWithdrawalSubmissionUnknown(persisted);
    final pending =
        _submissions[(wallet.session, solanaWithdrawalIntentKey(parameters))];
    if (pending?.submittedPreview case final WithdrawalPreview previous) {
      throw SolanaWithdrawalSubmissionUnknown(previous);
    }
    ensureAllowed(asset);
    final preview = await runWithSession(
      wallet,
      () => RpcDispatchGuard.run(
        () {
          ensureSessionCurrent(wallet);
          ensureAllowed(asset);
        },
        () => _create(parameters, asset),
        methods: const {'withdraw'},
      ),
    );
    await requireWalletCurrent(wallet);
    ensureSessionCurrent(wallet);
    _previews[preview] = _PreparedWithdrawal(parameters, wallet, preview);
    return preview;
  }

  /// Refreshes once after explicit confirmation, then broadcasts at most once.
  ///
  /// [beforeBroadcast] checks the caller's authorization at both signing and
  /// broadcast dispatch, including after asynchronous transport preparation.
  /// It supplements the wallet-session and catalog guards.
  Stream<WithdrawalProgress> executeWithdrawal(
    WithdrawalPreview preview,
    Asset asset, {
    void Function()? beforeBroadcast,
  }) async* {
    final prepared = _previews[preview];
    if (prepared == null || !prepared.review.matches(preview)) {
      throw const FormatException(
        'Solana withdrawal requires an unchanged preview from this session',
      );
    }
    validateSolanaWithdrawal(prepared.parameters, asset, capabilities);
    final journal = this.journal;
    if (journal == null) {
      throw StateError('Solana sends require durable submission storage');
    }
    await requireWalletCurrent(prepared.wallet);
    ensureSessionCurrent(prepared.wallet);
    if (prepared.submittedPreview case final WithdrawalPreview previous) {
      throw SolanaWithdrawalSubmissionUnknown(previous);
    }
    if (prepared.replacement case final WithdrawalPreview replacement) {
      throw SolanaWithdrawalReviewChanged(replacement);
    }
    final key = (
      prepared.wallet.session as Object,
      solanaWithdrawalIntentKey(prepared.parameters),
    );
    final pending = _submissions[key];
    if (pending?.submittedPreview case final WithdrawalPreview previous) {
      throw SolanaWithdrawalSubmissionUnknown(previous);
    }
    if (pending != null) {
      throw StateError('This Solana withdrawal is already being confirmed');
    }
    _submissions[key] = prepared;
    GaslessSubmissionLease? intentLease;
    try {
      // Hold one live intent across refresh and submission. A journal record
      // alone cannot exclude a second manager whose refresh finishes after
      // our successful broadcast has already cleared that record.
      intentLease = await tryAcquireGaslessSubmissionLease(
        walletStorageNamespace(prepared.wallet.walletId),
        'solana:${key.$2}',
      );
      if (intentLease == null) {
        throw StateError('This Solana withdrawal is already being confirmed');
      }
      void ensureCurrent() {
        ensureSessionCurrent(prepared.wallet);
        ensureAllowed(asset);
        beforeBroadcast?.call();
      }

      ensureCurrent();
      // Emit before refreshing: consumers can suspend between progress events.
      // There must be no user-controlled pause after the fresh blockhash.
      yield const WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: 'Refreshing Solana transfer details...',
      );
      ensureCurrent();
      final fresh = contextualizeSolanaWithdrawal(
        await RpcDispatchGuard.run(
          ensureCurrent,
          () => runWithSession(
            prepared.wallet,
            () => _create(prepared.parameters, asset),
          ),
          methods: const {'withdraw'},
        ),
        asset,
      );
      await requireWalletCurrent(prepared.wallet);
      ensureCurrent();
      if (!prepared.review.matches(fresh)) {
        _previews[fresh] = _PreparedWithdrawal(
          prepared.parameters,
          prepared.wallet,
          fresh,
        );
        prepared.replacement = fresh;
        throw SolanaWithdrawalReviewChanged(fresh);
      }

      final SendRawTransactionResponse response;
      final existing = await journal.reserve(
        prepared.wallet.walletId,
        prepared.parameters,
        fresh,
      );
      if (existing != null) {
        prepared.submittedPreview = existing;
        await requireWalletCurrent(prepared.wallet);
        ensureSessionCurrent(prepared.wallet);
        throw SolanaWithdrawalSubmissionUnknown(existing);
      }
      // This check is provably before dispatch; a local refusal may release
      // the reservation without describing it as a network submission.
      try {
        ensureCurrent();
      } on Object {
        await journal.clear(
          prepared.wallet.walletId,
          prepared.parameters,
          fresh.txHash!,
        );
        rethrow;
      }
      prepared.submittedPreview = fresh;
      try {
        var dispatchStarted = false;
        try {
          response = await RpcDispatchGuard.run(
            ensureCurrent,
            () => runWithSession(prepared.wallet, () {
              dispatchStarted = true;
              return broadcast(asset.id.id, fresh.txHex!);
            }),
            methods: const {'send_raw_transaction'},
          );
        } on Object catch (error) {
          // A refused engine lease never entered the broadcast callback.
          if (!dispatchStarted && error is! RpcDispatchRejected) {
            throw RpcDispatchRejected(error);
          }
          rethrow;
        }
        if (response.isGaslessRelay || response.txHash != fresh.txHash) {
          throw const FormatException('Unexpected Solana broadcast response');
        }
      } on RpcDispatchRejected {
        // The transport proved it never dispatched the request.
        await journal.clear(
          prepared.wallet.walletId,
          prepared.parameters,
          fresh.txHash!,
        );
        prepared.submittedPreview = null;
        rethrow;
      } on Object {
        await requireWalletCurrent(prepared.wallet);
        ensureSessionCurrent(prepared.wallet);
        throw SolanaWithdrawalSubmissionUnknown(fresh);
      }
      // Keep the durable reservation if the active wallet changed.
      await requireWalletCurrent(prepared.wallet);
      try {
        await journal.clear(
          prepared.wallet.walletId,
          prepared.parameters,
          fresh.txHash!,
        );
      } on Object {
        await requireWalletCurrent(prepared.wallet);
        ensureSessionCurrent(prepared.wallet);
        throw SolanaWithdrawalSubmissionUnknown(fresh);
      }
      await requireWalletCurrent(prepared.wallet);
      ensureSessionCurrent(prepared.wallet);
      _submissions.remove(key);
      yield WithdrawalProgress(
        status: WithdrawalStatus.complete,
        message: 'Solana transfer submitted',
        withdrawalResult: WithdrawalResult(
          txHash: response.txHash,
          balanceChanges: fresh.balanceChanges,
          coin: fresh.coin,
          toAddress: fresh.to.single,
          fee: fresh.fee,
        ),
        submission: WithdrawalSubmission.onChain(txHash: response.txHash),
      );
    } finally {
      if (prepared.submittedPreview == null) _submissions.remove(key);
      await intentLease?.release();
    }
  }
}

final class _PreparedWithdrawal {
  _PreparedWithdrawal(this.parameters, this.wallet, WithdrawalPreview preview)
    : review = SolanaWithdrawalReview(preview);

  final WithdrawParameters parameters;
  final WalletOperationContext wallet;
  final SolanaWithdrawalReview review;
  WithdrawalPreview? replacement;
  WithdrawalPreview? submittedPreview;
}
