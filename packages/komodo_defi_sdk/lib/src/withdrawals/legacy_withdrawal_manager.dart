import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Implementation of withdrawal manager using non-task-based withdrawal methods
class LegacyWithdrawalManager implements WithdrawalManager {
  LegacyWithdrawalManager(this._client);

  final ApiClient _client;

  /// Creates a preview and immediately executes the withdrawal.
  ///
  /// **DEPRECATED:** Use [previewWithdrawal] followed by [executeWithdrawal]
  /// instead to ensure users can review transaction details before broadcasting.
  @Deprecated(
    'Use previewWithdrawal() followed by executeWithdrawal() instead.',
  )
  @override
  Stream<WithdrawalProgress> withdraw(WithdrawParameters parameters) async* {
    try {
      // Initial progress update
      yield const WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: 'Initiating withdrawal...',
      );

      // Execute withdrawal request
      final response = await _client.rpc.withdraw.withdraw(parameters);

      if (response.status == 'Error') {
        yield* Stream.error(
          WithdrawalException(
            response.details as String,
            WithdrawalException.mapErrorToCode(response.details as String),
          ),
        );
        return;
      }

      final result = response.details as WithdrawResult;

      // Progress update for successful generation
      yield WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: 'Transaction generated. Broadcasting to network...',
        withdrawalResult: WithdrawalResult(
          txHash: result.txHash,
          balanceChanges: result.balanceChanges,
          coin: result.coin,
          toAddress: result.to.first,
          fee: result.fee,
          kmdRewardsEligible:
              result.kmdRewards != null &&
              Decimal.parse(result.kmdRewards!.amount) > Decimal.zero,
        ),
      );

      // Broadcast the transaction to the blockchain
      try {
        final broadcastResponse = await _client.rpc.withdraw.sendRawTransaction(
          coin: parameters.asset,
          txHex: result.txHex,
          txJson: result.txJson,
        );

        // Final success update with actual broadcast transaction hash
        yield WithdrawalProgress(
          status: WithdrawalStatus.complete,
          message: 'Withdrawal completed successfully',
          withdrawalResult: WithdrawalResult(
            txHash: broadcastResponse.txHash,
            balanceChanges: result.balanceChanges,
            coin: result.coin,
            toAddress: result.to.first,
            fee: result.fee,
            kmdRewardsEligible:
                result.kmdRewards != null &&
                Decimal.parse(result.kmdRewards!.amount) > Decimal.zero,
          ),
        );
      } catch (e) {
        yield* Stream.error(
          WithdrawalException(
            'Failed to broadcast transaction: $e',
            WithdrawalErrorCode.networkError,
          ),
        );
      }
    } catch (e) {
      yield* Stream.error(
        WithdrawalException(
          'Withdrawal failed: $e',
          WithdrawalErrorCode.unknownError,
        ),
      );
    }
  }

  /// Preview a withdrawal operation without executing it
  @override
  Future<WithdrawalPreview> previewWithdrawal(
    WithdrawParameters parameters,
  ) async {
    try {
      final response = await _client.rpc.withdraw.withdraw(parameters);

      if (response.status == 'Error') {
        throw WithdrawalException(
          response.details as String,
          WithdrawalException.mapErrorToCode(response.details as String),
        );
      }

      if (response.details is! WithdrawResult) {
        throw WithdrawalException(
          'Invalid preview response format',
          WithdrawalErrorCode.unknownError,
        );
      }

      return response.details as WithdrawResult;
    } catch (e) {
      if (e is WithdrawalException) {
        rethrow;
      }
      throw WithdrawalException(
        'Preview failed: $e',
        WithdrawalErrorCode.unknownError,
      );
    }
  }

  /// Execute a withdrawal from a previously generated preview.
  ///
  /// This method broadcasts the pre-signed transaction from the preview,
  /// avoiding the need to sign the transaction again. This is the ONLY
  /// recommended way to execute withdrawals for Tendermint assets.
  ///
  /// Parameters:
  /// - [preview] - The preview result from [previewWithdrawal]
  /// - [assetId] - The asset identifier (coin symbol)
  ///
  /// Returns a [Stream<WithdrawalProgress>] that emits progress updates.
  @override
  Stream<WithdrawalProgress> executeWithdrawal(
    WithdrawalPreview preview,
    String assetId,
  ) async* {
    try {
      // Initial progress update
      yield WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: 'Broadcasting signed transaction...',
        withdrawalResult: WithdrawalResult(
          txHash: preview.txHash,
          balanceChanges: preview.balanceChanges,
          coin: assetId,
          toAddress: preview.to.first,
          fee: preview.fee,
          kmdRewardsEligible:
              preview.kmdRewards != null &&
              Decimal.parse(preview.kmdRewards!.amount) > Decimal.zero,
        ),
      );

      // Broadcast the pre-signed transaction
      final broadcastResponse = await _client.rpc.withdraw.sendRawTransaction(
        coin: assetId,
        txHex: preview.txHex,
        txJson: preview.txJson,
      );

      // Final success update with actual broadcast transaction hash
      yield WithdrawalProgress(
        status: WithdrawalStatus.complete,
        message: 'Withdrawal completed successfully',
        withdrawalResult: WithdrawalResult(
          txHash: broadcastResponse.txHash,
          balanceChanges: preview.balanceChanges,
          coin: assetId,
          toAddress: preview.to.first,
          fee: preview.fee,
          kmdRewardsEligible:
              preview.kmdRewards != null &&
              Decimal.parse(preview.kmdRewards!.amount) > Decimal.zero,
        ),
      );
    } catch (e) {
      yield* Stream.error(
        WithdrawalException(
          'Failed to broadcast transaction: $e',
          WithdrawalErrorCode.networkError,
        ),
      );
    }
  }

  /// No-op for legacy implementation since there's no task to cancel
  @override
  Future<bool> cancelWithdrawal(int taskId) async => false;

  /// No cleanup needed for legacy implementation
  @override
  Future<void> dispose() async {
    // Do any cleanup here
  }

  /// Legacy implementation doesn't support priority-based fee options
  @override
  Future<WithdrawalFeeOptions?> getFeeOptions(String assetId) async {
    // Legacy implementation doesn't support priority-based fees
    return null;
  }
}
