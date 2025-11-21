import 'dart:async';
import 'dart:developer' show log;

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Manages cryptocurrency asset withdrawals to external addresses.
///
/// The [WithdrawalManager] provides functionality for:
/// - Creating withdrawal previews to check fees and expected results
/// - Executing withdrawals with progress tracking
/// - Managing and canceling active withdrawal operations
///
/// It supports both task-based API operations for most chains and falls back to
/// legacy implementation for protocols that don't yet support tasks
/// (e.g., Tendermint).
///
/// The manager ensures proper fee estimation when not provided explicitly
/// and handles the full lifecycle of a withdrawal transaction:
/// 1. Asset activation (if needed)
/// 2. Transaction creation
/// 3. Broadcasting to the network
/// 4. Status tracking
///
/// **Note:** Fee estimation features are currently disabled as the API endpoints
/// are not yet available. Set `_feeEstimationEnabled` to `true` when the API
/// endpoints become available.
///
/// Usage example:
/// ```dart
/// final manager = WithdrawalManager(...);
///
/// // Get fee options for UI selection
/// final feeOptions = await manager.getFeeOptions('BTC');
/// if (feeOptions != null) {
///   print('Low: ${feeOptions.low.estimatedFeeAmount} BTC');
///   print('Medium: ${feeOptions.medium.estimatedFeeAmount} BTC');
///   print('High: ${feeOptions.high.estimatedFeeAmount} BTC');
/// }
///
/// // Preview a withdrawal
/// final preview = await manager.previewWithdrawal(
///   WithdrawParameters(
///     asset: 'BTC',
///     toAddress: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
///     amount: Decimal.parse('0.001'),
///   ),
/// );
///
/// // Execute a withdrawal with priority selection
/// final progressStream = manager.withdraw(
///   WithdrawParameters(
///     asset: 'BTC',
///     toAddress: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
///     amount: Decimal.parse('0.001'),
///     feePriority: WithdrawalFeeLevel.high, // Fast confirmation
///   ),
/// );
///
/// await for (final progress in progressStream) {
///   print('Status: ${progress.status}, Message: ${progress.message}');
///   if (progress.withdrawalResult != null) {
///     print('Tx hash: ${progress.withdrawalResult!.txHash}');
///   }
/// }
/// ```
class WithdrawalManager {
  /// Creates a new [WithdrawalManager] instance.
  ///
  /// Requires:
  /// - [_client] - API client for making RPC calls
  /// - [_assetProvider] - Provider for looking up asset information
  /// - [_feeManager] - Manager for fee estimation and management
  WithdrawalManager(
    this._client,
    this._assetProvider,
    this._feeManager,
    this._activationCoordinator,
    this._legacyManager,
  );

  /// Flag to enable/disable fee estimation features.
  ///
  /// TODO: Set to true when the fee estimation API endpoints become available.
  /// Currently disabled as the endpoints are not yet implemented in the API.
  static const bool _feeEstimationEnabled = false;

  /// Default gas limit for basic ETH transactions.
  ///
  /// This is used when no specific gas limit is provided in the withdrawal
  /// parameters. For standard ETH transfers, 21000 gas is the standard amount
  /// required.
  static const int _defaultEthGasLimit = 21000;

  final ApiClient _client;
  final IAssetProvider _assetProvider;
  final SharedActivationCoordinator _activationCoordinator;
  final FeeManager _feeManager;
  final LegacyWithdrawalManager _legacyManager;
  final _activeWithdrawals = <int, StreamController<WithdrawalProgress>>{};

  /// Cancels an active withdrawal task.
  ///
  /// This method attempts to cancel a withdrawal task that is currently in
  /// progress. It's useful when a user wants to abort an ongoing withdrawal
  /// operation.
  ///
  /// Parameters:
  /// - [taskId] - The ID of the task to cancel
  ///
  /// Returns a [Future<bool>] that completes with:
  /// - `true` if the cancellation was successful
  /// - `false` if the cancellation failed
  ///
  /// The method will also clean up any resources associated with the task,
  /// regardless of whether the cancellation was successful.
  ///
  /// Example:
  /// ```dart
  /// final success = await withdrawalManager.cancelWithdrawal(taskId);
  /// if (success) {
  ///   print('Withdrawal canceled successfully');
  /// } else {
  ///   print('Failed to cancel withdrawal');
  /// }
  /// ```
  Future<bool> cancelWithdrawal(int taskId) async {
    try {
      final response = await _client.rpc.withdraw.cancel(taskId);
      return response.result == 'success';
    } catch (e, stackTrace) {
      // Log the error and stack trace for debugging purposes
      log('Error while canceling withdrawal: $e');
      log('Stack trace: $stackTrace');
      return false;
    } finally {
      await _activeWithdrawals[taskId]?.close();
      _activeWithdrawals.remove(taskId);
    }
  }

  /// Cleans up all active withdrawals and releases resources.
  ///
  /// This method should be called when the manager is no longer needed,
  /// typically when the application is shutting down or the user is
  /// logging out. It attempts to cancel all active withdrawal tasks and
  /// releases associated resources.
  ///
  /// Example:
  /// ```dart
  /// // When done with the withdrawal manager
  /// await withdrawalManager.dispose();
  /// ```
  Future<void> dispose() async {
    final withdrawals = _activeWithdrawals.entries.toList();
    _activeWithdrawals.clear();

    for (final withdrawal in withdrawals) {
      await withdrawal.value.close();
      await cancelWithdrawal(withdrawal.key);
    }
  }

  /// Retrieves fee options with different priority levels for the specified asset.
  ///
  /// This method provides fee estimates at multiple priority levels, allowing
  /// the UI to present users with options ranging from low-cost/slow confirmation
  /// to high-cost/fast confirmation.
  ///
  /// **Note:** This feature is currently disabled as the API endpoints are not yet available.
  /// TODO: Enable when the fee estimation API endpoints become available.
  ///
  /// Parameters:
  /// - [assetId] - The asset identifier (e.g., 'BTC', 'ETH', 'ATOM')
  ///
  /// Returns a [Future<WithdrawalFeeOptions?>] containing fee estimates for
  /// different priority levels. Returns `null` if fee estimation is not
  /// supported for the asset, if the asset is not found, or if fee estimation
  /// is disabled.
  ///
  /// The returned options include:
  /// - Low priority: Lowest cost, slowest confirmation
  /// - Medium priority: Balanced cost and confirmation time
  /// - High priority: Highest cost, fastest confirmation
  ///
  /// Example:
  /// ```dart
  /// final feeOptions = await withdrawalManager.getFeeOptions('BTC');
  /// if (feeOptions != null) {
  ///   print('Low priority: ${feeOptions.low.estimatedFeeAmount} BTC');
  ///   print('Medium priority: ${feeOptions.medium.estimatedFeeAmount} BTC');
  ///   print('High priority: ${feeOptions.high.estimatedFeeAmount} BTC');
  /// }
  /// ```
  Future<WithdrawalFeeOptions?> getFeeOptions(String assetId) async {
    // Return null if fee estimation is disabled
    if (!_feeEstimationEnabled) {
      return null;
    }
    try {
      final asset = _assetProvider.findAssetsByConfigId(assetId).single;
      final protocol = asset.protocol;

      // Handle different protocol types
      switch (protocol.runtimeType) {
        case Erc20Protocol:
          // Ethereum-based protocols use gas estimation
          final estimation = await _feeManager.getEthEstimatedFeePerGas(
            assetId,
          );
          return WithdrawalFeeOptions(
            coin: assetId,
            low: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.low,
              feeInfo: FeeInfo.ethGasEip1559(
                coin: assetId,
                maxFeePerGas: estimation.low.maxFeePerGas,
                maxPriorityFeePerGas: estimation.low.maxPriorityFeePerGas,
                gas: _defaultEthGasLimit,
              ),
              estimatedTime: _getEthEstimatedTime(WithdrawalFeeLevel.low),
            ),
            medium: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.medium,
              feeInfo: FeeInfo.ethGasEip1559(
                coin: assetId,
                maxFeePerGas: estimation.medium.maxFeePerGas,
                maxPriorityFeePerGas: estimation.medium.maxPriorityFeePerGas,
                gas: _defaultEthGasLimit,
              ),
              estimatedTime: _getEthEstimatedTime(WithdrawalFeeLevel.medium),
            ),
            high: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.high,
              feeInfo: FeeInfo.ethGasEip1559(
                coin: assetId,
                maxFeePerGas: estimation.high.maxFeePerGas,
                maxPriorityFeePerGas: estimation.high.maxPriorityFeePerGas,
                gas: _defaultEthGasLimit,
              ),
              estimatedTime: _getEthEstimatedTime(WithdrawalFeeLevel.high),
            ),
          );

        case UtxoProtocol:
          // UTXO-based protocols use per-kbyte fee estimation
          final estimation = await _feeManager.getUtxoEstimatedFee(assetId);
          return WithdrawalFeeOptions(
            coin: assetId,
            low: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.low,
              feeInfo: FeeInfo.utxoPerKbyte(
                coin: assetId,
                amount: estimation.low.feePerKbyte,
              ),
              estimatedTime: estimation.low.estimatedTime,
            ),
            medium: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.medium,
              feeInfo: FeeInfo.utxoPerKbyte(
                coin: assetId,
                amount: estimation.medium.feePerKbyte,
              ),
              estimatedTime: estimation.medium.estimatedTime,
            ),
            high: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.high,
              feeInfo: FeeInfo.utxoPerKbyte(
                coin: assetId,
                amount: estimation.high.feePerKbyte,
              ),
              estimatedTime: estimation.high.estimatedTime,
            ),
          );

        case TendermintProtocol:
          // Tendermint/Cosmos protocols use gas price and gas limit
          final estimation = await _feeManager.getTendermintEstimatedFee(
            assetId,
          );
          return WithdrawalFeeOptions(
            coin: assetId,
            low: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.low,
              feeInfo: FeeInfo.tendermint(
                coin: assetId,
                amount: estimation.low.totalFee,
                gasLimit: estimation.low.gasLimit,
              ),
              estimatedTime: estimation.low.estimatedTime,
            ),
            medium: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.medium,
              feeInfo: FeeInfo.tendermint(
                coin: assetId,
                amount: estimation.medium.totalFee,
                gasLimit: estimation.medium.gasLimit,
              ),
              estimatedTime: estimation.medium.estimatedTime,
            ),
            high: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.high,
              feeInfo: FeeInfo.tendermint(
                coin: assetId,
                amount: estimation.high.totalFee,
                gasLimit: estimation.high.gasLimit,
              ),
              estimatedTime: estimation.high.estimatedTime,
            ),
          );

        case QtumProtocol:
          // QTUM uses similar gas model to Ethereum but with different fee structure
          try {
            final estimation = await _feeManager.getEthEstimatedFeePerGas(
              assetId,
            );
            return WithdrawalFeeOptions(
              coin: assetId,
              low: WithdrawalFeeOption(
                priority: WithdrawalFeeLevel.low,
                feeInfo: FeeInfo.qrc20Gas(
                  coin: assetId,
                  gasPrice: estimation.low.maxFeePerGas,
                  gasLimit: _defaultEthGasLimit,
                ),
                estimatedTime: _getEthEstimatedTime(WithdrawalFeeLevel.low),
              ),
              medium: WithdrawalFeeOption(
                priority: WithdrawalFeeLevel.medium,
                feeInfo: FeeInfo.qrc20Gas(
                  coin: assetId,
                  gasPrice: estimation.medium.maxFeePerGas,
                  gasLimit: _defaultEthGasLimit,
                ),
                estimatedTime: _getEthEstimatedTime(WithdrawalFeeLevel.medium),
              ),
              high: WithdrawalFeeOption(
                priority: WithdrawalFeeLevel.high,
                feeInfo: FeeInfo.qrc20Gas(
                  coin: assetId,
                  gasPrice: estimation.high.maxFeePerGas,
                  gasLimit: _defaultEthGasLimit,
                ),
                estimatedTime: _getEthEstimatedTime(WithdrawalFeeLevel.high),
              ),
            );
          } catch (e) {
            // Fallback to UTXO-style estimation if ETH estimation fails
            final estimation = await _feeManager.getUtxoEstimatedFee(assetId);
            return WithdrawalFeeOptions(
              coin: assetId,
              low: WithdrawalFeeOption(
                priority: WithdrawalFeeLevel.low,
                feeInfo: FeeInfo.utxoPerKbyte(
                  coin: assetId,
                  amount: estimation.low.feePerKbyte,
                ),
                estimatedTime: estimation.low.estimatedTime,
              ),
              medium: WithdrawalFeeOption(
                priority: WithdrawalFeeLevel.medium,
                feeInfo: FeeInfo.utxoPerKbyte(
                  coin: assetId,
                  amount: estimation.medium.feePerKbyte,
                ),
                estimatedTime: estimation.medium.estimatedTime,
              ),
              high: WithdrawalFeeOption(
                priority: WithdrawalFeeLevel.high,
                feeInfo: FeeInfo.utxoPerKbyte(
                  coin: assetId,
                  amount: estimation.high.feePerKbyte,
                ),
                estimatedTime: estimation.high.estimatedTime,
              ),
            );
          }

        case ZhtlcProtocol:
          // ZHTLC (Zcash) uses UTXO-style fees
          final estimation = await _feeManager.getUtxoEstimatedFee(assetId);
          return WithdrawalFeeOptions(
            coin: assetId,
            low: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.low,
              feeInfo: FeeInfo.utxoFixed(
                coin: assetId,
                amount: estimation.low.feePerKbyte * Decimal.fromInt(250),
              ),
              estimatedTime: estimation.low.estimatedTime,
            ),
            medium: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.medium,
              feeInfo: FeeInfo.utxoFixed(
                coin: assetId,
                amount: estimation.medium.feePerKbyte * Decimal.fromInt(250),
              ),
              estimatedTime: estimation.medium.estimatedTime,
            ),
            high: WithdrawalFeeOption(
              priority: WithdrawalFeeLevel.high,
              feeInfo: FeeInfo.utxoFixed(
                coin: assetId,
                amount: estimation.high.feePerKbyte * Decimal.fromInt(250),
              ),
              estimatedTime: estimation.high.estimatedTime,
            ),
          );

        default:
          // For unknown protocols, return null to indicate unsupported
          log('Fee options not supported for protocol ${protocol.runtimeType}');
          return null;
      }
    } catch (e, stackTrace) {
      // Log the error and stack trace for debugging purposes
      log('Error while getting fee options for $assetId: $e');
      log('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Creates a preview of a withdrawal operation without executing it.
  ///
  /// This method allows users to see what would happen if they executed the
  /// withdrawal, including fees, balance changes, and other transaction
  /// details, before committing to it.
  ///
  /// **Note:** Fee estimation is currently disabled as the API endpoints are not yet available.
  /// When fee estimation is disabled, withdrawals will proceed without automatic fee estimation.
  /// TODO: Enable when the fee estimation API endpoints become available.
  ///
  /// Parameters:
  /// - [parameters] - The withdrawal parameters defining the asset, amount,
  ///   destination, and optional fee priority
  ///
  /// Returns a [Future<WithdrawalPreview>] containing the estimated transaction
  /// details.
  ///
  /// Fee Priority:
  /// - If no fee is specified, the method will estimate fees based on the
  ///   feePriority parameter (defaults to medium) when fee estimation is enabled
  /// - Low: Lowest cost, slowest confirmation
  /// - Medium: Balanced cost and confirmation time
  /// - High: Highest cost, fastest confirmation
  ///
  /// Throws:
  /// - [WithdrawalException] if the preview fails, with appropriate error code
  ///
  /// Note: For Tendermint-based assets, this method falls back to the legacy
  /// implementation since task-based API is not yet supported for these assets.
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   // Preview with default (medium) priority
  ///   final preview = await withdrawalManager.previewWithdrawal(
  ///     WithdrawParameters(
  ///       asset: 'ETH',
  ///       toAddress: '0x1234...',
  ///       amount: Decimal.parse('0.1'),
  ///     ),
  ///   );
  ///
  ///   // Preview with low priority for cost estimation
  ///   final lowFeePreview = await withdrawalManager.previewWithdrawal(
  ///     WithdrawParameters(
  ///       asset: 'ETH',
  ///       toAddress: '0x1234...',
  ///       amount: Decimal.parse('0.1'),
  ///       feePriority: WithdrawalFeeLevel.low,
  ///     ),
  ///   );
  ///
  ///   print('Estimated fee: ${preview.fee}');
  ///   print('Balance change: ${preview.balanceChanges.netChange}');
  /// } catch (e) {
  ///   print('Preview failed: $e');
  /// }
  /// ```
  Future<WithdrawalPreview> previewWithdrawal(
    WithdrawParameters parameters,
  ) async {
    try {
      final asset = _assetProvider
          .findAssetsByConfigId(parameters.asset)
          .single;

      // TODO: refactor into strategy pattern or add a getter to the protocol
      // class to check if the protocol requires the legacy withdrawals
      final isTendermintProtocol = asset.protocol is TendermintProtocol;
      final isSiaProtocol = asset.protocol is SiaProtocol;

      // Tendermint assets are not yet supported by the task-based API
      // and require a legacy implementation
      if (isTendermintProtocol || isSiaProtocol) {
        return await _legacyManager.previewWithdrawal(parameters);
      }

      final paramsWithFee = await _ensureFee(parameters, asset);

      // Use task-based approach for non-Tendermint assets
      final stream = (await _client.rpc.withdraw.init(paramsWithFee))
          .watch<WithdrawStatusResponse>(
            getTaskStatus: (int taskId) =>
                _client.rpc.withdraw.status(taskId, forgetIfFinished: false),
            isTaskComplete: (WithdrawStatusResponse status) =>
                status.status != 'InProgress',
          );

      final lastStatus = await stream.last;

      if (lastStatus.status.toLowerCase() == 'error') {
        throw WithdrawalException(
          lastStatus.details as String,
          _mapErrorToCode(lastStatus.details as String),
        );
      }

      if (lastStatus.details is! WithdrawalPreview) {
        throw WithdrawalException(
          'Invalid preview response format',
          WithdrawalErrorCode.unknownError,
        );
      }

      return lastStatus.details as WithdrawalPreview;
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

  /// Executes a withdrawal from a previously generated preview.
  ///
  /// This method broadcasts a transaction that was already signed during the
  /// preview phase. This is the ONLY recommended way to execute withdrawals,
  /// as it ensures:
  /// - The transaction is signed only once
  /// - The user sees and confirms the exact transaction that will be broadcast
  /// - No risk of parameters changing between preview and execution
  ///
  /// **Workflow:**
  /// 1. Call [previewWithdrawal] to generate and sign the transaction
  /// 2. Show the preview to the user for confirmation
  /// 3. Call [executeWithdrawal] to broadcast the signed transaction
  ///
  /// Parameters:
  /// - [preview] - The preview result from [previewWithdrawal]
  /// - [assetId] - The asset identifier (coin symbol)
  ///
  /// Returns a [Stream<WithdrawalProgress>] that emits progress updates.
  ///
  /// Example:
  /// ```dart
  /// // 1. Preview the withdrawal
  /// final preview = await withdrawalManager.previewWithdrawal(
  ///   WithdrawParameters(
  ///     asset: 'BTC',
  ///     toAddress: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
  ///     amount: Decimal.parse('0.001'),
  ///   ),
  /// );
  ///
  /// // 2. Show preview to user, get confirmation...
  ///
  /// // 3. Execute the previewed transaction
  /// await for (final progress in withdrawalManager.executeWithdrawal(
  ///   preview,
  ///   'BTC',
  /// )) {
  ///   print('Status: ${progress.status}');
  /// }
  /// ```
  Stream<WithdrawalProgress> executeWithdrawal(
    WithdrawalPreview preview,
    String assetId,
  ) async* {
    try {
      final asset = _assetProvider.findAssetsByConfigId(assetId).single;

      // TODO: refactor into strategy pattern or add a getter to the protocol
      // class to check if the protocol requires the legacy withdrawals
      final isTendermintProtocol = asset.protocol is TendermintProtocol;
      final isSiaProtocol = asset.protocol is SiaProtocol;

      // Tendermint assets are not yet supported by the task-based API
      // and require a legacy implementation
      if (isTendermintProtocol || isSiaProtocol) {
        yield* _legacyManager.executeWithdrawal(preview, assetId);
        return;
      }

      // Ensure asset is activated before broadcasting
      final activationResult = await _activationCoordinator.activateAsset(
        asset,
      );
      if (activationResult.isFailure) {
        throw WithdrawalException(
          'Failed to activate asset $assetId: ${activationResult.errorMessage ?? activationResult.toString()}',
          WithdrawalErrorCode.unknownError,
        );
      }

      // Initial progress
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
      final response = await _client.rpc.withdraw.sendRawTransaction(
        coin: assetId,
        txHex: preview.txHex,
        txJson: preview.txJson,
      );

      // Final success
      yield WithdrawalProgress(
        status: WithdrawalStatus.complete,
        message: 'Withdrawal complete',
        withdrawalResult: WithdrawalResult(
          txHash: response.txHash,
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

  /// Creates a preview and immediately executes the withdrawal.
  ///
  /// **DEPRECATED:** This method is provided for convenience but is NOT the
  /// recommended approach. It's better to use the two-step process:
  /// 1. [previewWithdrawal] - Generate and show preview to user
  /// 2. [executeWithdrawal] - Execute after user confirmation
  ///
  /// This ensures users can review the transaction details (fees, amounts)
  /// before broadcasting.
  ///
  /// This method performs the full withdrawal process:
  /// 1. Ensures the asset is activated
  /// 2. Creates and signs the transaction
  /// 3. Broadcasts it to the network
  /// 4. Tracks and reports progress
  ///
  /// Parameters:
  /// - [parameters] - The withdrawal parameters defining the asset, amount,
  ///   destination, and optional fee priority
  ///
  /// Returns a [Stream<WithdrawalProgress>] that emits progress updates.
  ///
  /// **Recommended alternative:**
  /// ```dart
  /// // Instead of this:
  /// await for (final progress in manager.withdraw(params)) { }
  ///
  /// // Do this:
  /// final preview = await manager.previewWithdrawal(params);
  /// // Show preview to user...
  /// await for (final progress in manager.executeWithdrawal(preview, assetId)) { }
  /// ```
  @Deprecated(
    'Use previewWithdrawal() followed by executeWithdrawal() instead. '
    'This ensures users can review transaction details before broadcasting.',
  )
  Stream<WithdrawalProgress> withdraw(WithdrawParameters parameters) async* {
    int? taskId;
    try {
      final asset = _assetProvider
          .findAssetsByConfigId(parameters.asset)
          .single;
      final isTendermintProtocol = asset.protocol is TendermintProtocol;
      final isSiaProtocol = asset.protocol is SiaProtocol;

      // Tendermint assets are not yet supported by the task-based API
      // and require a legacy implementation
      if (isTendermintProtocol || isSiaProtocol) {
        yield* _legacyManager.withdraw(parameters);
        return;
      }

      final activationResult = await _activationCoordinator.activateAsset(
        asset,
      );

      if (activationResult.isFailure) {
        throw WithdrawalException(
          'Failed to activate asset ${parameters.asset}',
          WithdrawalErrorCode.unknownError,
        );
      }

      final paramsWithFee = await _ensureFee(parameters, asset);

      // Initialize withdrawal task
      final initResponse = await _client.rpc.withdraw.init(paramsWithFee);
      taskId = initResponse.taskId;
      WithdrawStatusResponse? lastProgress;

      await for (final status in initResponse.watch<WithdrawStatusResponse>(
        getTaskStatus: (int taskId) async => lastProgress = await _client
            .rpc
            .withdraw
            .status(taskId, forgetIfFinished: false),
        isTaskComplete: (WithdrawStatusResponse status) =>
            status.status != 'InProgress',
      )) {
        if (status.status == 'Error') {
          yield* Stream.error(
            WithdrawalException(
              status.details as String,
              _mapErrorToCode(status.details as String),
            ),
          );
          return;
        }
        yield _mapStatusToProgress(status);
        // Break if we have a successful result to handle tx broadcast
        if (status.status == 'Ok' && status.details is WithdrawResult) {
          break;
        }
      }

      // Send the raw transaction to the network if successful
      if (lastProgress?.status == 'Ok' &&
          lastProgress?.details is WithdrawResult) {
        final details = lastProgress!.details as WithdrawResult;
        try {
          final response = await _client.rpc.withdraw.sendRawTransaction(
            coin: parameters.asset,
            txHex: details.txHex,
            txJson: details.txJson,
          );
          yield WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'Withdrawal complete',
            withdrawalResult: WithdrawalResult(
              txHash: response.txHash,
              balanceChanges: details.balanceChanges,
              coin: parameters.asset,
              toAddress: parameters.toAddress,
              fee: details.fee,
              kmdRewardsEligible:
                  details.kmdRewards != null &&
                  Decimal.parse(details.kmdRewards!.amount) > Decimal.zero,
            ),
          );
        } catch (e, stackTrace) {
          // Log the error and stack trace for debugging purposes
          log('Error while broadcasting transaction: $e');
          log('Stack trace: $stackTrace');
          yield* Stream.error(
            WithdrawalException(
              'Failed to broadcast transaction: $e',
              WithdrawalErrorCode.networkError,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      // Log the error and stack trace for debugging purposes
      log('Error during withdrawal: $e');
      log('Stack trace: $stackTrace');
      yield* Stream.error(
        WithdrawalException(
          'Withdrawal failed: $e',
          WithdrawalErrorCode.unknownError,
        ),
      );
    } finally {
      await _activeWithdrawals[taskId]?.close();
      _activeWithdrawals.remove(taskId);
    }
  }

  /// Maps error messages to withdrawal error codes.
  ///
  /// This helper method analyzes error messages from the API and maps them
  /// to appropriate [WithdrawalErrorCode] values for consistent error
  /// handling.
  ///
  /// Parameters:
  /// - [error] - The error message to analyze
  ///
  /// Returns the appropriate [WithdrawalErrorCode] based on the error content.
  WithdrawalErrorCode _mapErrorToCode(String error) {
    final errorLower = error.toLowerCase();

    if (errorLower.contains('insufficient funds') ||
        errorLower.contains('not enough funds')) {
      return WithdrawalErrorCode.insufficientFunds;
    }

    if (errorLower.contains('invalid address')) {
      return WithdrawalErrorCode.invalidAddress;
    }

    if (errorLower.contains('fee')) {
      return WithdrawalErrorCode.networkError;
    }

    return WithdrawalErrorCode.unknownError;
  }

  /// Provides estimated confirmation times for Ethereum-based transactions.
  ///
  /// Returns user-friendly estimated confirmation times based on the fee priority level.
  ///
  /// Parameters:
  /// - [priority] - The fee priority level
  ///
  /// Returns a string representing the estimated confirmation time.
  String _getEthEstimatedTime(WithdrawalFeeLevel priority) {
    switch (priority) {
      case WithdrawalFeeLevel.low:
        return '~10-15 min';
      case WithdrawalFeeLevel.medium:
        return '~2-5 min';
      case WithdrawalFeeLevel.high:
        return '~30 sec';
    }
  }

  /// Selects the appropriate Ethereum fee level based on priority.
  ///
  /// Maps withdrawal priority levels to corresponding Ethereum fee estimation levels.
  ///
  /// Parameters:
  /// - [estimation] - The fee estimation response
  /// - [priority] - The desired priority level
  ///
  /// Returns the selected [EthFeeLevel].
  EthFeeLevel _getEthFeeLevel(
    EthEstimatedFeePerGas estimation,
    WithdrawalFeeLevel priority,
  ) {
    switch (priority) {
      case WithdrawalFeeLevel.low:
        return estimation.low;
      case WithdrawalFeeLevel.medium:
        return estimation.medium;
      case WithdrawalFeeLevel.high:
        return estimation.high;
    }
  }

  /// Selects the appropriate UTXO fee level based on priority.
  ///
  /// Maps withdrawal priority levels to corresponding UTXO fee estimation levels.
  ///
  /// Parameters:
  /// - [estimation] - The fee estimation response
  /// - [priority] - The desired priority level
  ///
  /// Returns the selected [UtxoFeeLevel].
  UtxoFeeLevel _getUtxoFeeLevel(
    UtxoEstimatedFee estimation,
    WithdrawalFeeLevel priority,
  ) {
    switch (priority) {
      case WithdrawalFeeLevel.low:
        return estimation.low;
      case WithdrawalFeeLevel.medium:
        return estimation.medium;
      case WithdrawalFeeLevel.high:
        return estimation.high;
    }
  }

  /// Selects the appropriate Tendermint fee level based on priority.
  ///
  /// Maps withdrawal priority levels to corresponding Tendermint fee estimation levels.
  ///
  /// Parameters:
  /// - [estimation] - The fee estimation response
  /// - [priority] - The desired priority level
  ///
  /// Returns the selected [TendermintFeeLevel].
  TendermintFeeLevel _getTendermintFeeLevel(
    TendermintEstimatedFee estimation,
    WithdrawalFeeLevel priority,
  ) {
    switch (priority) {
      case WithdrawalFeeLevel.low:
        return estimation.low;
      case WithdrawalFeeLevel.medium:
        return estimation.medium;
      case WithdrawalFeeLevel.high:
        return estimation.high;
    }
  }

  /// Ensures that withdrawal parameters have appropriate fee information.
  ///
  /// If the parameters already include fee information, they are returned unchanged.
  /// Otherwise, the method attempts to estimate an appropriate fee based on the
  /// asset's protocol type, current network conditions, and the specified priority level.
  ///
  /// **Note:** Fee estimation is currently disabled as the API endpoints are not yet available.
  /// TODO: Enable when the fee estimation API endpoints become available.
  ///
  /// Parameters:
  /// - [params] - The withdrawal parameters
  /// - [asset] - The asset being withdrawn
  ///
  /// Returns updated [WithdrawParameters] with fee information.
  Future<WithdrawParameters> _ensureFee(
    WithdrawParameters params,
    Asset asset,
  ) async {
    if (params.fee != null) return params;

    // If fee estimation is disabled, return parameters without fee
    if (!_feeEstimationEnabled) {
      return params;
    }

    try {
      final protocol = asset.protocol;
      final priority = params.feePriority ?? WithdrawalFeeLevel.medium;
      FeeInfo? fee;

      switch (protocol.runtimeType) {
        case Erc20Protocol:
          // Ethereum-based protocols (ETH, ERC20 tokens) use gas estimation
          final estimation = await _feeManager.getEthEstimatedFeePerGas(
            asset.id.id,
          );
          final selectedLevel = _getEthFeeLevel(estimation, priority);
          fee = FeeInfo.ethGasEip1559(
            coin: asset.id.id,
            maxFeePerGas: selectedLevel.maxFeePerGas,
            maxPriorityFeePerGas: selectedLevel.maxPriorityFeePerGas,
            gas: _defaultEthGasLimit,
          );

        case UtxoProtocol:
          // UTXO-based protocols use per-kbyte fee estimation
          final estimation = await _feeManager.getUtxoEstimatedFee(asset.id.id);
          final selectedLevel = _getUtxoFeeLevel(estimation, priority);
          fee = FeeInfo.utxoPerKbyte(
            coin: asset.id.id,
            amount: selectedLevel.feePerKbyte,
          );

        case TendermintProtocol:
          // Tendermint/Cosmos protocols use gas price and gas limit
          final estimation = await _feeManager.getTendermintEstimatedFee(
            asset.id.id,
          );
          final selectedLevel = _getTendermintFeeLevel(estimation, priority);
          fee = FeeInfo.tendermint(
            coin: asset.id.id,
            amount: selectedLevel.totalFee,
            gasLimit: selectedLevel.gasLimit,
          );

        case QtumProtocol:
          // QTUM uses similar gas model to Ethereum but different fee structure
          try {
            final estimation = await _feeManager.getEthEstimatedFeePerGas(
              asset.id.id,
            );
            final selectedLevel = _getEthFeeLevel(estimation, priority);
            fee = FeeInfo.qrc20Gas(
              coin: asset.id.id,
              gasPrice: selectedLevel.maxFeePerGas,
              gasLimit: _defaultEthGasLimit,
            );
          } catch (e) {
            // Fallback to UTXO-style estimation if ETH estimation fails
            final estimation = await _feeManager.getUtxoEstimatedFee(
              asset.id.id,
            );
            final selectedLevel = _getUtxoFeeLevel(estimation, priority);
            fee = FeeInfo.utxoPerKbyte(
              coin: asset.id.id,
              amount: selectedLevel.feePerKbyte,
            );
          }

        case ZhtlcProtocol:
          // ZHTLC (Zcash) uses UTXO-style fees
          final estimation = await _feeManager.getUtxoEstimatedFee(asset.id.id);
          final selectedLevel = _getUtxoFeeLevel(estimation, priority);
          fee = FeeInfo.utxoFixed(
            coin: asset.id.id,
            amount:
                selectedLevel.feePerKbyte *
                Decimal.fromInt(250), // Assume ~250 bytes
          );

        default:
          // For unknown protocols, attempt ETH estimation as fallback
          try {
            final estimation = await _feeManager.getEthEstimatedFeePerGas(
              asset.id.id,
            );
            final selectedLevel = _getEthFeeLevel(estimation, priority);
            fee = FeeInfo.ethGasEip1559(
              coin: asset.id.id,
              maxFeePerGas: selectedLevel.maxFeePerGas,
              maxPriorityFeePerGas: selectedLevel.maxPriorityFeePerGas,
              gas: _defaultEthGasLimit,
            );
          } catch (e) {
            log(
              'No fee estimation available for protocol ${protocol.runtimeType}',
            );
            // Return original parameters without fee
            return params;
          }
      }

      return WithdrawParameters(
        asset: params.asset,
        toAddress: params.toAddress,
        amount: params.amount,
        fee: fee,
        feePriority: params.feePriority,
        from: params.from,
        memo: params.memo,
        ibcTransfer: params.ibcTransfer,
        ibcSourceChannel: params.ibcSourceChannel,
        isMax: params.isMax,
      );
    } catch (e, stackTrace) {
      // Log the error and stack trace for debugging purposes
      log('Error while estimating fee for ${asset.id.id}: $e');
      log('Stack trace: $stackTrace');
      return params;
    }
  }

  /// Maps API status response to domain progress model.
  ///
  /// Converts the raw API status response into a user-friendly progress object
  /// that can be consumed by the application.
  ///
  /// Parameters:
  /// - [status] - The API status response
  ///
  /// Returns a [WithdrawalProgress] object representing the current state.
  WithdrawalProgress _mapStatusToProgress(WithdrawStatusResponse status) {
    if (status.status == 'Ok') {
      final result = status.details as WithdrawResult;
      return WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: 'Withdrawal generated. Sending transaction...',
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
    }

    return WithdrawalProgress(
      status: WithdrawalStatus.inProgress,
      message: status.details as String,
    );
  }
}
