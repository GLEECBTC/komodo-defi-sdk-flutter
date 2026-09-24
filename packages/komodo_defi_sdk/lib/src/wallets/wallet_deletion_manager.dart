import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/storage/wallet_storage_namespace.dart';
import 'package:komodo_defi_sdk/src/withdrawals/gasless_transfer_lock.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Whether the SDK could inspect unresolved recovery records.
enum WalletDeletionRecoveryStatus {
  /// Inspection succeeded and no unresolved records remain.
  none,

  /// Inspection succeeded and unresolved records remain.
  pending,

  /// Ownership or storage could not be verified; preserve every record.
  unavailable,
}

/// Outcome of confirming a reviewed deletion.
enum WalletDeletionStatus {
  /// The selected wallet was deleted. Cache cleanup was attempted.
  deleted,

  /// A submission is recording its outcome; retry after it releases its lease.
  busy,

  /// Present the returned warning and ask the user to confirm again.
  reviewChanged,

  /// Return to wallet selection because the catalog entry changed.
  targetChanged,
}

/// Typed deletion outcome and, when needed, its replacement warning.
final class WalletDeletionResult {
  /// Creates an outcome with an optional refreshed review.
  const WalletDeletionResult(this.status, {this.review});

  /// Whether deletion completed or needs another user action.
  final WalletDeletionStatus status;

  /// Updated warning for [WalletDeletionStatus.reviewChanged].
  final WalletDeletionReview? review;
}

/// Payment details safe to display in a deletion warning.
final class WalletDeletionTransferSummary {
  WalletDeletionTransferSummary._(PendingGaslessTransfer transfer)
    : assetId = transfer.assetId,
      requestedAmount = transfer.requestedAmount,
      destinationAddress = transfer.destinationAddress,
      acceptedAt = transfer.acceptedAt;

  /// Asset the user requested to send.
  final String assetId;

  /// Requested recipient amount, excluding fees.
  final Decimal requestedAmount;

  /// Requested recipient address.
  final String destinationAddress;

  /// Time the SDK reserved the request locally.
  final DateTime acceptedAt;
}

/// An SDK-issued snapshot of the wallet and the warning the user reviewed.
final class WalletDeletionReview {
  WalletDeletionReview._({
    required Object issuer,
    required this.walletId,
    required String entryId,
    required this.recoveryStatus,
    required List<PendingGaslessTransfer> transfers,
    required Set<String> requestIdentities,
  }) : _issuer = issuer,
       _entryId = entryId,
       _requestIdentities = Set.unmodifiable(requestIdentities),
       transfers = List.unmodifiable(
         transfers.map(WalletDeletionTransferSummary._),
       );

  final Object _issuer;
  final String _entryId;
  final Set<String> _requestIdentities;

  /// Selected catalog identity; preparation does not sign it in.
  final WalletId walletId;

  /// Inspection result that must be included in the user's warning.
  final WalletDeletionRecoveryStatus recoveryStatus;

  /// Unresolved requests without internal authorization or trace data.
  final List<WalletDeletionTransferSummary> transfers;
}

/// Auth catalog transaction that validates the target before deleting it.
typedef DeleteReviewedWallet =
    Future<void> Function({
      required String walletName,
      required String password,
      required Future<void> Function(KdfUser target) validateTarget,
    });

/// Coordinates deletion with the durable transfer journal and live submissions.
///
/// Authentication supplies the fresh catalog and invokes the target validator
/// inside its catalog transaction through [DeleteReviewedWallet]. Recovery
/// records remain: removing a local wallet cannot cancel a submitted
/// transaction.
class WalletDeletionManager {
  /// Connects deletion to the SDK-owned catalog and recovery journal.
  WalletDeletionManager({
    required Future<List<KdfUser>> Function() readWallets,
    required DeleteReviewedWallet deleteWallet,
    required PendingGaslessTransferRepository pendingTransfers,
  }) : _readWallets = readWallets,
       _deleteWallet = deleteWallet,
       _pendingTransfers = pendingTransfers;

  final Future<List<KdfUser>> Function() _readWallets;
  final DeleteReviewedWallet _deleteWallet;
  final PendingGaslessTransferRepository _pendingTransfers;
  final Object _issuer = Object();

  /// Inspects a saved wallet without requiring it to be signed in.
  Future<WalletDeletionReview> prepare(String walletName) async {
    final users = await _readWallets();
    final target = users
        .where((user) => user.walletId.name == walletName)
        .firstOrNull;
    if (target == null) throw AuthException.notFound();
    return _review(target);
  }

  Future<WalletDeletionReview> _review(KdfUser target) async {
    final entryId = target.metadata[walletEntryIdMetadataKey];
    if (entryId is! String || entryId.isEmpty) {
      throw StateError('Wallet catalog identity is unavailable');
    }
    List<PendingGaslessTransfer> transfers = const [];
    var status = WalletDeletionRecoveryStatus.unavailable;
    // A name-only identity cannot prove recovery ownership. Preserve records
    // and show an uncertainty warning without signing in.
    if (target.walletId.pubkeyHash?.trim().isNotEmpty == true) {
      try {
        transfers = await _pendingTransfers
            .list(target.walletId)
            .timeout(const Duration(seconds: 10));
        status = transfers.isEmpty
            ? WalletDeletionRecoveryStatus.none
            : WalletDeletionRecoveryStatus.pending;
      } on Object {
        // Includes legacy ownership and encrypted-storage read failures.
        // Neither means an empty journal, and neither authorizes deleting it.
      }
    }
    return WalletDeletionReview._(
      issuer: _issuer,
      walletId: target.walletId,
      entryId: entryId,
      recoveryStatus: status,
      transfers: transfers,
      requestIdentities: transfers.map(_requestIdentity).toSet(),
    );
  }

  /// Revalidates an SDK-issued review under the wallet submission lease.
  Future<WalletDeletionResult> delete({
    required WalletDeletionReview acknowledgedReview,
    required String password,
  }) async {
    if (!identical(acknowledgedReview._issuer, _issuer)) {
      throw const WalletDeletionReviewRequiredException();
    }
    final identity = acknowledgedReview.walletId;
    final namespace = identity.pubkeyHash?.trim().isNotEmpty == true
        ? walletStorageNamespace(identity)
        : '*';
    final lease = await tryAcquireGaslessWalletLease(
      namespace,
      exclusive: true,
    );
    if (lease == null) {
      return const WalletDeletionResult(WalletDeletionStatus.busy);
    }
    try {
      await _deleteWallet(
        walletName: identity.name,
        password: password,
        validateTarget: (target) async {
          if (target.metadata[walletEntryIdMetadataKey] !=
                  acknowledgedReview._entryId ||
              target.walletId != identity) {
            throw const _DeletionChanged(
              WalletDeletionResult(WalletDeletionStatus.targetChanged),
            );
          }
          final current = await _review(target);
          if (!_covers(acknowledgedReview, current)) {
            throw _DeletionChanged(
              WalletDeletionResult(
                WalletDeletionStatus.reviewChanged,
                review: current,
              ),
            );
          }
        },
      );
      return const WalletDeletionResult(WalletDeletionStatus.deleted);
    } on _DeletionChanged catch (changed) {
      return changed.result;
    } on AuthException catch (error) {
      if (error.type == AuthExceptionType.walletNotFound) {
        return const WalletDeletionResult(WalletDeletionStatus.targetChanged);
      }
      rethrow;
    } finally {
      await lease.release();
    }
  }

  bool _covers(WalletDeletionReview accepted, WalletDeletionReview current) {
    if (accepted.recoveryStatus == WalletDeletionRecoveryStatus.unavailable ||
        current.recoveryStatus == WalletDeletionRecoveryStatus.unavailable) {
      return accepted.recoveryStatus == current.recoveryStatus;
    }
    // Reconciliation may reduce the acknowledged set. Progress polling does
    // not change the warning, but a new request or changed payment details do.
    return accepted._requestIdentities.containsAll(current._requestIdentities);
  }

  String _requestIdentity(PendingGaslessTransfer transfer) => jsonEncode([
    transfer.journalId,
    transfer.assetId,
    transfer.network,
    transfer.sourceAddress,
    transfer.custodyAddress,
    transfer.destinationAddress,
    transfer.requestedAmount.toString(),
    transfer.signedMaxFee.toString(),
    transfer.authorizationDeadline.toString(),
    transfer.acceptedAt.toIso8601String(),
  ]);
}

final class _DeletionChanged implements Exception {
  const _DeletionChanged(this.result);
  final WalletDeletionResult result;
}
