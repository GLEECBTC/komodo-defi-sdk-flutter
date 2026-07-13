import 'dart:async';
import 'dart:convert';
import 'dart:developer' show log;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show jsonFromString;
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Shared fee-estimation strategy classification used by withdrawal flows.
enum FeeEstimationSupport {
  /// Ethereum-style gas estimation.
  evmGas,

  /// UTXO fee-per-kilobyte estimation.
  utxoPerKbyte,

  /// Tendermint gas estimation.
  tendermint,

  /// QTUM gas estimation with UTXO fallback.
  qtum,

  /// ZHTLC fixed-fee estimation.
  zhtlc,

  /// No fee estimation support is available.
  unsupported,
}

/// Returns the fee-estimation support level for [protocol].
FeeEstimationSupport feeEstimationSupportForProtocol(ProtocolClass protocol) {
  return switch (protocol) {
    Erc20Protocol() => FeeEstimationSupport.evmGas,
    UtxoProtocol() => FeeEstimationSupport.utxoPerKbyte,
    TendermintProtocol() => FeeEstimationSupport.tendermint,
    QtumProtocol() => FeeEstimationSupport.qtum,
    ZhtlcProtocol() => FeeEstimationSupport.zhtlc,
    TrxProtocol() || Trc20Protocol() => FeeEstimationSupport.unsupported,
    _ => FeeEstimationSupport.unsupported,
  };
}

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
/// **Note:** Fee estimation features are currently disabled as the API
/// endpoints are not yet available. Set `_feeEstimationEnabled` to `true`
/// when the API endpoints become available.
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
    this._legacyManager, {
    GaslessCapabilityRegistry? gaslessCapabilities,
    PendingGaslessTransferRepository? pendingGaslessTransfers,
    TransactionHistoryManager? transactionHistoryManager,
    Future<WalletId?> Function()? walletIdResolver,
    Stream<KdfUser?>? authStateChanges,
    Duration gaslessPollInterval = const Duration(seconds: 3),
    Duration gaslessReconciliationInterval = const Duration(minutes: 1),
  }) : _gaslessCapabilities =
           gaslessCapabilities ??
           GaslessCapabilityRegistry(configuredAssetIds: const <String>[]),
       _pendingGaslessTransfers = pendingGaslessTransfers,
       _transactionHistoryManager = transactionHistoryManager,
       _walletIdResolver = walletIdResolver,
       _gaslessPollInterval = gaslessPollInterval,
       _gaslessReconciliationInterval = gaslessReconciliationInterval {
    _gaslessAuthSubscription = authStateChanges?.listen(
      _handleGaslessAuthStateChanged,
    );
  }

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
  final GaslessCapabilityRegistry _gaslessCapabilities;
  final PendingGaslessTransferRepository? _pendingGaslessTransfers;
  final TransactionHistoryManager? _transactionHistoryManager;
  final Future<WalletId?> Function()? _walletIdResolver;
  final Duration _gaslessPollInterval;
  final Duration _gaslessReconciliationInterval;
  final Map<String, WalletId> _pendingGaslessWallets = <String, WalletId>{};
  final math.Random _secureRandom = math.Random.secure();
  final _activeWithdrawals = <int, StreamController<WithdrawalProgress>>{};
  StreamSubscription<KdfUser?>? _gaslessAuthSubscription;
  StreamSubscription<WithdrawalProgress>? _gaslessReconciliationSubscription;
  Timer? _gaslessReconciliationTimer;
  bool _gaslessReconciliationStarting = false;
  WalletId? _currentWalletId;
  int _walletGeneration = 0;
  static const SdkErrorMapper _errorMapper = SdkErrorMapper();

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
    await stopGaslessReconciliation();
    await _gaslessAuthSubscription?.cancel();
    _gaslessAuthSubscription = null;
    final withdrawals = _activeWithdrawals.entries.toList();
    _activeWithdrawals.clear();

    for (final withdrawal in withdrawals) {
      await withdrawal.value.close();
      await cancelWithdrawal(withdrawal.key);
    }
  }

  /// Starts wallet-scoped, status-only recovery for unresolved GasFree sends.
  ///
  /// This operation never resubmits a signed payload. It resumes trace polling
  /// immediately and periodically so app restarts and network recovery do not
  /// strand an accepted relay.
  Future<void> startGaslessReconciliation() async {
    _gaslessReconciliationTimer?.cancel();
    await _runGaslessReconciliationCycle();
    _gaslessReconciliationTimer = Timer.periodic(
      _gaslessReconciliationInterval,
      (_) => unawaited(_runGaslessReconciliationCycle()),
    );
  }

  /// Stops polling while retaining the encrypted wallet-scoped journal.
  Future<void> stopGaslessReconciliation() async {
    _gaslessReconciliationTimer?.cancel();
    _gaslessReconciliationTimer = null;
    await _gaslessReconciliationSubscription?.cancel();
    _gaslessReconciliationSubscription = null;
  }

  void _handleGaslessAuthStateChanged(KdfUser? user) {
    final nextWallet = user?.walletId;
    if (!_sameOptionalWallet(_currentWalletId, nextWallet)) {
      _walletGeneration++;
      _currentWalletId = nextWallet;
    }
    unawaited(() async {
      await stopGaslessReconciliation();
      if (user != null) await startGaslessReconciliation();
    }());
  }

  bool _sameOptionalWallet(WalletId? left, WalletId? right) {
    if (left == null || right == null) return left == right;
    return isSameStableWallet(left, right);
  }

  Future<WalletOperationContext> _captureWalletContext() async {
    final wallet = await _walletIdResolver?.call();
    if (wallet == null) {
      throw StateError('GasFree requires an authenticated wallet');
    }
    final current = _currentWalletId;
    if (current == null) {
      _currentWalletId = wallet;
    } else if (!isSameStableWallet(current, wallet)) {
      _walletGeneration++;
      _currentWalletId = wallet;
    }
    return WalletOperationContext(
      walletId: wallet,
      generation: _walletGeneration,
    );
  }

  Future<bool> _isWalletContextCurrent(WalletOperationContext context) async {
    if (context.generation != _walletGeneration ||
        _currentWalletId == null ||
        !isSameStableWallet(context.walletId, _currentWalletId!)) {
      return false;
    }
    final current = await _walletIdResolver?.call();
    return current != null &&
        context.generation == _walletGeneration &&
        isSameStableWallet(context.walletId, current);
  }

  Future<void> _requireWalletContextCurrent(
    WalletOperationContext context,
  ) async {
    if (await _isWalletContextCurrent(context)) return;
    throw const WalletChangedDisconnectException(
      'Wallet changed during GasFree transfer',
    );
  }

  Future<void> _runGaslessReconciliationCycle() async {
    if (_gaslessReconciliationStarting ||
        _gaslessReconciliationSubscription != null ||
        await _walletIdResolver?.call() == null) {
      return;
    }
    _gaslessReconciliationStarting = true;
    try {
      final subscription = reconcilePendingGaslessTransfers().listen(
        (_) {},
        onError: (Object _, StackTrace __) {},
        onDone: () => _gaslessReconciliationSubscription = null,
      );
      _gaslessReconciliationSubscription = subscription;
    } finally {
      _gaslessReconciliationStarting = false;
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
      switch (feeEstimationSupportForProtocol(protocol)) {
        case FeeEstimationSupport.evmGas:
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

        case FeeEstimationSupport.utxoPerKbyte:
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

        case FeeEstimationSupport.tendermint:
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

        case FeeEstimationSupport.qtum:
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

        case FeeEstimationSupport.zhtlc:
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

        case FeeEstimationSupport.unsupported:
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
  /// Fetch the GasFree custody account status for a gasless-enabled TRC-20
  /// asset: the custody address, its on-chain balance, activation state, fees,
  /// and the maximum gaslessly-sendable amount.
  ///
  /// The GasFree custody address is where a gasless withdrawal settles from, so
  /// this is the balance a client should treat as spendable for a gasless TRC-20
  /// asset (the coin's `my_balance` reports the EOA balance instead).
  Future<GaslessAccountStatusResponse> gaslessAccountStatus(AssetId assetId) {
    if (!_gaslessCapabilities.isReady(assetId)) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.capabilityNotReady,
        message: 'Gas-free transfers are not ready for ${assetId.id}',
        retryable: true,
        terminal: false,
      );
    }
    return _client.rpc.withdraw.gaslessAccountStatus(coin: assetId.id);
  }

  /// Revalidates a legacy V1 GasFree receive address without granting relay
  /// submission readiness.
  ///
  /// The caller must use the canonical address currently rendered by the
  /// wallet as [expectedGasfreeAddress], then check
  /// `KomodoDefiSdk.canReceiveGaslessFromStatus` after this future completes.
  /// Bound-only integrations must continue to use [gaslessAccountStatus].
  Future<GaslessAccountStatusResponse> gaslessAccountStatusForReceive(
    AssetId assetId, {
    required String expectedGasfreeAddress,
  }) async {
    if (_gaslessCapabilities.canReceiveGasless(assetId)) {
      return gaslessAccountStatus(assetId);
    }
    if (!_gaslessCapabilities.canAttemptStatusReceiveAttestation(assetId)) {
      _gaslessCapabilities.invalidateStatusReceiveEvidence(
        assetId,
        reasonCode: 'runtime_restart_required',
      );
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.capabilityNotReady,
        message: 'Gas-free receive needs a wallet runtime restart',
        retryable: true,
        terminal: false,
      );
    }
    try {
      final status = await _client.rpc.withdraw.gaslessAccountStatus(
        coin: assetId.id,
      );
      _gaslessCapabilities.refreshStatusAttestation(
        assetId,
        status,
        expectedGasfreeAddress: expectedGasfreeAddress,
      );
      return status;
    } catch (error) {
      if (!_gaslessCapabilities.markAccountStatusError(assetId, error)) {
        _gaslessCapabilities.invalidateStatusReceiveEvidence(
          assetId,
          reasonCode: 'provider_unreachable',
        );
      }
      rethrow;
    }
  }

  Future<WithdrawalPreview> previewWithdrawal(
    WithdrawParameters parameters,
  ) async {
    try {
      final asset = _assetProvider
          .findAssetsByConfigId(parameters.asset)
          .single;
      final isGasless = parameters.feeMethod == WithdrawalFeeMethod.gasless;
      final walletContext = isGasless ? await _captureWalletContext() : null;
      if (isGasless) {
        _requireGaslessPreviewAllowed(asset.id);
      }
      _validateSiaSourceSelection(parameters, asset);
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
        throw _typedTaskError(lastStatus.details) ??
            WithdrawalException(
              lastStatus.details as String,
              WithdrawalException.mapErrorToCode(lastStatus.details as String),
            );
      }

      if (lastStatus.details is! WithdrawalPreview) {
        throw WithdrawalException(
          'Invalid preview response format',
          WithdrawalErrorCode.unknownError,
        );
      }

      final preview = lastStatus.details as WithdrawalPreview;
      if (isGasless) {
        await _requireWalletContextCurrent(walletContext!);
        _validateGaslessPreview(
          preview,
          asset,
          walletContext,
          allowLegacyPromotion: true,
        );
      }
      return preview;
    } catch (e) {
      throw _mapError(
        e,
        operation: 'withdrawal.preview',
        assetId: parameters.asset,
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
    WalletOperationContext? operationContext;
    PendingGaslessTransfer? operationPending;
    var relayInvocationBegan = false;
    try {
      final asset = _assetProvider.findAssetsByConfigId(assetId).single;
      final isGasless = _isGaslessPreview(preview);
      final walletContext = isGasless ? await _captureWalletContext() : null;
      operationContext = walletContext;
      final isTendermintProtocol = asset.protocol is TendermintProtocol;
      final isSiaProtocol = asset.protocol is SiaProtocol;

      // Tendermint assets are not yet supported by the task-based API
      if (isTendermintProtocol || isSiaProtocol) {
        yield* _legacyManager.executeWithdrawal(preview, assetId);
        return;
      }

      // Ensure asset is activated before broadcasting
      final activationResult = await _activationCoordinator.activateAsset(
        asset,
      );
      if (activationResult.isFailure) {
        throw _mapError(
          activationResult.errorMessage ?? activationResult.toString(),
          operation: 'withdrawal.activate',
          assetId: assetId,
        );
      }

      if (isGasless) {
        await _requireWalletContextCurrent(walletContext!);
        _requireGaslessReady(asset.id);
      }

      // Initial progress
      yield WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: isGasless
            ? 'Submitting gas-free transfer...'
            : 'Broadcasting signed transaction...',
        withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
      );

      // Persist a local request identity and authorization fingerprint before
      // invoking the relay. If secure persistence fails, do not submit.
      final validated = isGasless
          ? _validateGaslessPreview(preview, asset, walletContext!)
          : null;
      final prepared = validated == null
          ? null
          : await _prepareGaslessTransfer(
              preview,
              asset,
              validated,
              walletContext!,
            );
      operationPending = prepared;
      if (walletContext != null) {
        await _requireWalletContextCurrent(walletContext);
      }

      // Broadcast the pre-signed transaction (or relay the gas-free payload).
      final SendRawTransactionResponse response;
      try {
        relayInvocationBegan = true;
        response = await _client.rpc.withdraw.sendRawTransaction(
          coin: assetId,
          txHex: preview.txHex,
          txJson: preview.txJson,
        );
      } catch (error) {
        if (prepared == null) rethrow;
        final acceptedMismatch = _parseAcceptedRelayMismatch(error);
        if (acceptedMismatch != null) {
          final requestMatches =
              acceptedMismatch.requestId == prepared.requestId;
          final unknown = prepared.copyWith(
            traceId: requestMatches ? acceptedMismatch.traceId : null,
            state: GaslessTransferState.submittedUnknown,
            updatedAt: DateTime.now().toUtc(),
          );
          await _upsertPendingGaslessTransfer(unknown);
          if (!await _isWalletContextCurrent(walletContext!)) return;
          yield WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free relay response requires security review',
            withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
            taskId: requestMatches
                ? acceptedMismatch.traceId
                : prepared.requestId,
            sdkError: _mapError(
              GaslessTransferException(
                kind: GaslessTransferErrorKind.providerResponse,
                message: 'GasFree relay response identity mismatch',
                retryable: false,
                terminal: false,
                code: GaslessTransferErrorCode.responseMismatch,
                stage: GaslessTransferStage.submission,
                localizationKey: 'sdk_errors.gasless_response_invalid',
                traceId: requestMatches ? acceptedMismatch.traceId : null,
              ),
              operation: 'withdrawal.gasless.submit',
              assetId: assetId,
            ),
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: requestMatches
                ? WithdrawalSubmission.gaslessRelay(
                    traceId: acceptedMismatch.traceId,
                    requestId: prepared.requestId,
                  )
                : WithdrawalSubmission.gaslessUnknown(
                    requestId: prepared.requestId,
                  ),
          );
          return;
        }
        final rejected = _classifyPreRelayRejection(error);
        if (rejected != null) {
          await _removePendingGaslessTransfer(prepared.requestId);
          if (!await _isWalletContextCurrent(walletContext!)) return;
          yield WithdrawalProgress(
            status: WithdrawalStatus.error,
            message: 'Gas-free relay rejected the request before submission',
            withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
            taskId: prepared.requestId,
            sdkError: _mapError(
              rejected,
              operation: 'withdrawal.gasless.submit',
              assetId: assetId,
            ),
            gaslessTransferState: GaslessTransferState.rejectedBeforeRelay,
          );
          return;
        }
        final unknown = prepared.copyWith(
          state: GaslessTransferState.submittedUnknown,
          updatedAt: DateTime.now().toUtc(),
        );
        await _upsertPendingGaslessTransfer(unknown);
        if (!await _isWalletContextCurrent(walletContext!)) return;
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: 'Gas-free submission outcome is unknown',
          withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
          taskId: prepared.requestId,
          sdkError: _mapError(
            GaslessTransferException(
              kind: GaslessTransferErrorKind.traceUnavailable,
              message: 'GasFree submission outcome is unknown',
              retryable: false,
              terminal: false,
              code: GaslessTransferErrorCode.submissionOutcomeUnknown,
              stage: GaslessTransferStage.submission,
              localizationKey: 'sdk_errors.gasless_submission_unknown',
            ),
            operation: 'withdrawal.gasless.submit',
            assetId: assetId,
          ),
          gaslessTransferState: GaslessTransferState.submittedUnknown,
          submission: WithdrawalSubmission.gaslessUnknown(
            requestId: prepared.requestId,
          ),
        );
        return;
      }

      // A gas-free relay broadcast returns a trace handle, not a tx hash:
      // poll the relay status until the transfer confirms or fails.
      if (response.isGaslessRelay &&
          (response.traceId?.trim().isNotEmpty ?? false)) {
        final traceId = response.traceId!;
        final expected = prepared == null
            ? null
            : _expectedAuthorization(prepared);
        final hasAnyBoundResponseField =
            response.requestId != null ||
            response.expectedAuthorization != null;
        final responseMode = response.hasBoundRelayContext
            ? GaslessVerificationMode.boundRelay
            : hasAnyBoundResponseField
            ? null
            : GaslessVerificationMode.legacyOnChain;
        if (prepared == null ||
            responseMode != prepared.verificationMode ||
            (responseMode == GaslessVerificationMode.boundRelay &&
                (response.requestId != prepared.requestId ||
                    expected == null ||
                    response.expectedAuthorization != expected))) {
          final unknown = prepared?.copyWith(
            traceId: traceId,
            state: GaslessTransferState.submittedUnknown,
            updatedAt: DateTime.now().toUtc(),
          );
          if (unknown != null) {
            await _upsertPendingGaslessTransfer(unknown);
          }
          if (walletContext != null &&
              !await _isWalletContextCurrent(walletContext)) {
            return;
          }
          yield WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free relay identity could not be verified',
            withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
            taskId: traceId,
            sdkError: _mapError(
              GaslessTransferException(
                kind: GaslessTransferErrorKind.providerResponse,
                message: 'GasFree relay request identity mismatch',
                retryable: false,
                terminal: false,
                traceId: traceId,
              ),
              operation: 'withdrawal.gasless.submit',
              assetId: assetId,
            ),
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: prepared == null
                ? WithdrawalSubmission.gaslessRelay(
                    traceId: traceId,
                    requestId: response.requestId ?? traceId,
                  )
                : WithdrawalSubmission.gaslessRelay(
                    traceId: traceId,
                    requestId: prepared.requestId,
                  ),
          );
          return;
        }
        final pending = prepared.copyWith(
          traceId: traceId,
          fee: _applyFinalGaslessFee(preview.fee, null, traceId),
          state: GaslessTransferState.submittedPending,
          updatedAt: DateTime.now().toUtc(),
        );
        final persisted = await _persistAcceptedGaslessTransfer(pending);
        final GaslessTraceState initialState;
        try {
          initialState = GaslessTraceState.parse(response.state ?? '');
        } on FormatException {
          final unknown = pending.copyWith(
            state: GaslessTransferState.submittedUnknown,
            updatedAt: DateTime.now().toUtc(),
          );
          await _upsertPendingGaslessTransfer(unknown);
          if (walletContext != null &&
              !await _isWalletContextCurrent(walletContext)) {
            return;
          }
          yield WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free relay response requires security review',
            withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
            taskId: traceId,
            sdkError: _mapError(
              GaslessTransferException(
                kind: GaslessTransferErrorKind.providerResponse,
                message: 'GasFree relay returned an unknown state',
                retryable: false,
                terminal: false,
                code: GaslessTransferErrorCode.responseMismatch,
                stage: GaslessTransferStage.submission,
                localizationKey: 'sdk_errors.gasless_response_invalid',
                traceId: traceId,
              ),
              operation: 'withdrawal.gasless.submit',
              assetId: assetId,
            ),
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: WithdrawalSubmission.gaslessRelay(
              traceId: traceId,
              requestId: pending.requestId,
            ),
          );
          return;
        }

        if (walletContext != null &&
            !await _isWalletContextCurrent(walletContext)) {
          return;
        }

        // Surface relay identity before the first trace-status request. The app
        // can now persist/render a pending activity even when polling fails or
        // the process is terminated immediately after acceptance.
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: persisted
              ? 'Gas-free transfer submitted...'
              : 'Gas-free transfer submitted; status is temporarily unknown',
          gaslessState: initialState,
          gaslessTransferState: persisted
              ? GaslessTransferState.submittedPending
              : GaslessTransferState.submittedUnknown,
          taskId: traceId,
          submission: WithdrawalSubmission.gaslessRelay(
            traceId: traceId,
            requestId: pending.requestId,
          ),
          withdrawalResult: _withdrawalResultFromPreview(
            preview,
            assetId,
            fee: _applyFinalGaslessFee(preview.fee, null, traceId),
          ),
        );

        // An accepted trace must be durable before any polling can turn it
        // into a terminal UI state. Keep the visible outcome unknown when
        // secure storage cannot confirm the write.
        if (!persisted) return;

        yield* _pollGaslessTrace(
          assetId: assetId,
          traceId: traceId,
          withdrawalResult: _withdrawalResultFromPreview(
            preview,
            assetId,
            fee: _applyFinalGaslessFee(preview.fee, null, traceId),
          ),
          pending: pending,
        );
        return;
      }

      if (prepared != null) {
        final unknown = prepared.copyWith(
          state: GaslessTransferState.submittedUnknown,
          updatedAt: DateTime.now().toUtc(),
        );
        await _upsertPendingGaslessTransfer(unknown);
        if (walletContext != null &&
            !await _isWalletContextCurrent(walletContext)) {
          return;
        }
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: 'Gas-free relay returned an unexpected response',
          withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
          taskId: prepared.requestId,
          sdkError: _mapError(
            GaslessTransferException(
              kind: GaslessTransferErrorKind.providerResponse,
              message: 'GasFree relay response did not include a trace',
              retryable: false,
              terminal: false,
            ),
            operation: 'withdrawal.gasless.submit',
            assetId: assetId,
          ),
          gaslessTransferState: GaslessTransferState.submittedUnknown,
          submission: WithdrawalSubmission.gaslessUnknown(
            requestId: prepared.requestId,
          ),
        );
        return;
      }

      // Final success (standard broadcast)
      yield WithdrawalProgress(
        status: WithdrawalStatus.complete,
        message: 'Withdrawal complete',
        withdrawalResult: _withdrawalResultFromPreview(
          preview,
          assetId,
          txHash: response.txHash,
        ),
        submission: WithdrawalSubmission.onChain(txHash: response.txHash!),
      );
    } catch (e) {
      if (!relayInvocationBegan &&
          operationContext != null &&
          operationPending != null) {
        try {
          await _pendingGaslessTransfers?.remove(
            operationContext.walletId,
            operationPending.requestId,
          );
        } catch (_) {
          log('Failed to clear unsubmitted GasFree reservation');
        }
      }
      if (operationContext != null &&
          !await _isWalletContextCurrent(operationContext)) {
        return;
      }
      yield* Stream.error(
        _mapError(e, operation: 'withdrawal.execute', assetId: assetId),
      );
    }
  }

  /// Whether [preview] represents a gas-free (gasless) transfer that must be
  /// relayed (rather than directly broadcast) and then tracked.
  bool _isGaslessPreview(WithdrawalPreview preview) =>
      preview.fee is FeeInfoTronGasless ||
      preview.txJson?['relay_type'] == 'tron_gasfree';

  /// Builds a [WithdrawalResult] from a preview, optionally overriding the
  /// (on-chain) [txHash] and final [fee].
  WithdrawalResult _withdrawalResultFromPreview(
    WithdrawalPreview preview,
    String assetId, {
    String? txHash,
    FeeInfo? fee,
  }) {
    return WithdrawalResult(
      txHash: txHash ?? preview.txHash,
      balanceChanges: preview.balanceChanges,
      coin: assetId,
      toAddress: preview.to.isNotEmpty ? preview.to.first : '',
      fee: fee ?? preview.fee,
      kmdRewardsEligible:
          preview.kmdRewards != null &&
          Decimal.parse(preview.kmdRewards!.amount) > Decimal.zero,
      confirmationBlockHeight: preview.blockHeight > 0
          ? preview.blockHeight
          : null,
      confirmedAt: preview.timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              preview.timestamp * 1000,
              isUtc: true,
            )
          : null,
    );
  }

  /// Polls `gasless::trace_status` for a relayed gas-free transfer, emitting
  /// intermediate progress until the transfer reaches a terminal state.
  ///
  /// On `confirmed`, completes with the on-chain tx hash and final (token) fee.
  /// On `failed`, emits a stream error carrying the failure reason.
  Stream<WithdrawalProgress> _pollGaslessTrace({
    required String assetId,
    required String traceId,
    required WithdrawalResult withdrawalResult,
    required PendingGaslessTransfer pending,
    // Injectable so the polling/timeout paths are unit-testable.
    Duration? pollInterval,
    // Bound the loop so a stuck relay cannot poll forever (~5 minutes).
    int maxAttempts = 100,
  }) async* {
    final interval = pollInterval ?? _gaslessPollInterval;
    var current = pending;
    var consecutiveFailures = 0;
    var traceNotFoundFailures = 0;
    final expectedAuthorization =
        pending.verificationMode == GaslessVerificationMode.boundRelay
        ? _expectedAuthorization(pending)
        : null;
    if (pending.verificationMode == GaslessVerificationMode.boundRelay &&
        expectedAuthorization == null) {
      yield WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: 'Gas-free authorization context requires support review',
        withdrawalResult: withdrawalResult,
        taskId: traceId,
        sdkError: _mapError(
          GaslessTransferException(
            kind: GaslessTransferErrorKind.invalidTrace,
            message: 'GasFree authorization context is unavailable',
            retryable: false,
            terminal: false,
            code: GaslessTransferErrorCode.responseMismatch,
            stage: GaslessTransferStage.recovery,
            localizationKey: 'sdk_errors.gasless_recovery_context_missing',
            traceId: traceId,
          ),
          operation: 'withdrawal.gasless.recovery',
          assetId: assetId,
        ),
        gaslessTransferState: GaslessTransferState.submittedUnknown,
        submission: WithdrawalSubmission.gaslessRelay(
          traceId: traceId,
          requestId: pending.requestId,
        ),
      );
      return;
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!await _isPendingWalletCurrent(pending)) return;
      final GaslessTraceStatusResponse status;
      try {
        status = await _client.rpc.withdraw.gaslessTraceStatus(
          coin: assetId,
          traceId: traceId,
          expectedAuthorization: expectedAuthorization,
        );
      } catch (e) {
        if (!await _isPendingWalletCurrent(pending)) return;
        consecutiveFailures++;
        final classified = _classifyTraceFailure(e, traceId);
        if (e.toString().contains('TraceNotFound')) traceNotFoundFailures++;
        final shouldKeepPolling =
            classified.retryable && traceNotFoundFailures < 3;

        current = current.copyWith(
          state: GaslessTransferState.submittedUnknown,
          updatedAt: DateTime.now().toUtc(),
        );
        await _upsertPendingGaslessTransfer(current);
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: 'Gas-free transfer status is temporarily unavailable',
          withdrawalResult: withdrawalResult,
          taskId: traceId,
          sdkError: _mapError(
            classified,
            operation: 'withdrawal.gasless.trace',
            assetId: assetId,
          ),
          gaslessTransferState: GaslessTransferState.submittedUnknown,
          submission: WithdrawalSubmission.gaslessRelay(
            traceId: traceId,
            requestId: pending.requestId,
          ),
        );

        log('GasFree trace status unavailable (${classified.code.name})');
        if (!shouldKeepPolling) return;

        final multiplier = 1 << math.min(consecutiveFailures - 1, 4);
        final backoff = Duration(
          milliseconds: math.min(
            interval.inMilliseconds * multiplier,
            const Duration(seconds: 30).inMilliseconds,
          ),
        );
        await Future<void>.delayed(_withPollingJitter(backoff));
        continue;
      }

      if (!await _isPendingWalletCurrent(pending)) return;

      consecutiveFailures = 0;
      traceNotFoundFailures = 0;

      if (status.state.isConfirmed) {
        final finalFee = status.finalFee;
        if (finalFee == null) {
          current = current.copyWith(
            state: GaslessTransferState.confirming,
            updatedAt: DateTime.now().toUtc(),
          );
          await _upsertPendingGaslessTransfer(current);
          yield WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Verifying final gas-free fee...',
            withdrawalResult: withdrawalResult,
            taskId: traceId,
            gaslessState: status.state,
            gaslessTransferState: GaslessTransferState.confirming,
            submission: WithdrawalSubmission.gaslessRelay(
              traceId: traceId,
              requestId: pending.requestId,
            ),
          );
          await Future<void>.delayed(_withPollingJitter(interval));
          continue;
        }
        if (finalFee > pending.signedMaxFee) {
          current = current.copyWith(
            state: GaslessTransferState.submittedUnknown,
            updatedAt: DateTime.now().toUtc(),
          );
          await _upsertPendingGaslessTransfer(current);
          yield WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free transfer requires support review',
            withdrawalResult: withdrawalResult,
            taskId: traceId,
            sdkError: _mapError(
              GaslessTransferException(
                kind: GaslessTransferErrorKind.providerResponse,
                message: 'GasFree final fee exceeds the signed maximum',
                retryable: false,
                terminal: false,
                traceId: traceId,
              ),
              operation: 'withdrawal.gasless.trace',
              assetId: assetId,
            ),
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: WithdrawalSubmission.gaslessRelay(
              traceId: traceId,
              requestId: pending.requestId,
            ),
          );
          return;
        }

        final onChainHash = status.txHashOnChain;
        if (onChainHash != null && onChainHash.isNotEmpty) {
          if (pending.verificationMode ==
              GaslessVerificationMode.legacyOnChain) {
            final GaslessOnChainVerification verification;
            try {
              verification = await _verifyLegacyGaslessFinality(
                pending,
                onChainHash,
              );
              if (!await _isPendingWalletCurrent(pending)) return;
            } catch (_) {
              if (!await _isPendingWalletCurrent(pending)) return;
              current = current.copyWith(
                state: GaslessTransferState.submittedUnknown,
                updatedAt: DateTime.now().toUtc(),
              );
              await _upsertPendingGaslessTransfer(current);
              yield WithdrawalProgress(
                status: WithdrawalStatus.inProgress,
                message: 'Gas-free on-chain verification is unavailable',
                withdrawalResult: withdrawalResult,
                taskId: traceId,
                sdkError: _mapError(
                  GaslessTransferException(
                    kind: GaslessTransferErrorKind.traceUnavailable,
                    message: 'GasFree on-chain verification is unavailable',
                    retryable: false,
                    terminal: false,
                    code: GaslessTransferErrorCode.submissionOutcomeUnknown,
                    stage: GaslessTransferStage.finality,
                    localizationKey: 'sdk_errors.gasless_status_unavailable',
                    traceId: traceId,
                  ),
                  operation: 'withdrawal.gasless.finality',
                  assetId: assetId,
                ),
                gaslessTransferState: GaslessTransferState.submittedUnknown,
                submission: WithdrawalSubmission.gaslessRelay(
                  traceId: traceId,
                  requestId: pending.requestId,
                ),
              );
              return;
            }
            if (verification == GaslessOnChainVerification.mismatch) {
              current = current.copyWith(
                state: GaslessTransferState.submittedUnknown,
                updatedAt: DateTime.now().toUtc(),
              );
              await _upsertPendingGaslessTransfer(current);
              yield WithdrawalProgress(
                status: WithdrawalStatus.inProgress,
                message: 'Gas-free transfer requires support review',
                withdrawalResult: withdrawalResult,
                taskId: traceId,
                sdkError: _mapError(
                  GaslessTransferException(
                    kind: GaslessTransferErrorKind.providerResponse,
                    message: 'GasFree on-chain transaction does not match',
                    retryable: false,
                    terminal: false,
                    code: GaslessTransferErrorCode.responseMismatch,
                    stage: GaslessTransferStage.finality,
                    localizationKey: 'sdk_errors.gasless_response_invalid',
                    traceId: traceId,
                  ),
                  operation: 'withdrawal.gasless.finality',
                  assetId: assetId,
                ),
                gaslessTransferState: GaslessTransferState.submittedUnknown,
                submission: WithdrawalSubmission.gaslessRelay(
                  traceId: traceId,
                  requestId: pending.requestId,
                ),
              );
              return;
            }
            if (verification == GaslessOnChainVerification.pending) {
              current = current.copyWith(
                state: GaslessTransferState.confirming,
                updatedAt: DateTime.now().toUtc(),
              );
              await _upsertPendingGaslessTransfer(current);
              yield WithdrawalProgress(
                status: WithdrawalStatus.inProgress,
                message: 'Verifying gas-free transfer on chain...',
                withdrawalResult: withdrawalResult,
                taskId: traceId,
                gaslessState: status.state,
                gaslessTransferState: GaslessTransferState.confirming,
                submission: WithdrawalSubmission.gaslessRelay(
                  traceId: traceId,
                  requestId: pending.requestId,
                ),
              );
              await Future<void>.delayed(_withPollingJitter(interval));
              continue;
            }
          }
          await _removePendingGaslessTransfer(traceId);
          yield WithdrawalProgress(
            status: WithdrawalStatus.complete,
            message: 'Withdrawal complete',
            withdrawalResult: WithdrawalResult(
              txHash: onChainHash,
              balanceChanges: withdrawalResult.balanceChanges,
              coin: withdrawalResult.coin,
              toAddress: withdrawalResult.toAddress,
              fee: _applyFinalGaslessFee(
                withdrawalResult.fee,
                status.finalFee,
                traceId,
              ),
              kmdRewardsEligible: withdrawalResult.kmdRewardsEligible,
              confirmationBlockHeight: status.blockHeight,
              confirmedAt: status.confirmedAt == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      status.confirmedAt! * 1000,
                      isUtc: true,
                    ),
            ),
            taskId: traceId,
            gaslessState: status.state,
            gaslessTransferState: GaslessTransferState.confirmed,
            submission: WithdrawalSubmission.gaslessRelay(
              traceId: traceId,
              requestId: pending.requestId,
            ),
          );
          return;
        }
        // Confirmed but the on-chain hash has not propagated yet: keep polling
        // rather than completing with a blank, unlinkable tx hash.
        log('GasFree confirmation is awaiting its on-chain hash');
        current = current.copyWith(
          state: GaslessTransferState.confirming,
          updatedAt: DateTime.now().toUtc(),
        );
        await _upsertPendingGaslessTransfer(current);
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: 'Gas-free transfer confirmed; awaiting transaction hash',
          withdrawalResult: withdrawalResult,
          taskId: traceId,
          gaslessState: status.state,
          gaslessTransferState: GaslessTransferState.confirming,
          submission: WithdrawalSubmission.gaslessRelay(
            traceId: traceId,
            requestId: pending.requestId,
          ),
        );
      } else if (status.state.isFailed &&
          pending.verificationMode == GaslessVerificationMode.legacyOnChain) {
        current = current.copyWith(
          state: GaslessTransferState.submittedUnknown,
          updatedAt: DateTime.now().toUtc(),
        );
        await _upsertPendingGaslessTransfer(current);
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: 'Gas-free transfer requires support review',
          withdrawalResult: withdrawalResult,
          taskId: traceId,
          sdkError: _mapError(
            GaslessTransferException(
              kind: GaslessTransferErrorKind.providerResponse,
              message: 'Legacy GasFree relay reported failure',
              retryable: false,
              terminal: false,
              code: GaslessTransferErrorCode.submissionOutcomeUnknown,
              stage: GaslessTransferStage.finality,
              localizationKey: 'sdk_errors.gasless_submission_unknown',
              traceId: traceId,
            ),
            operation: 'withdrawal.gasless.finality',
            assetId: assetId,
          ),
          gaslessState: status.state,
          gaslessTransferState: GaslessTransferState.submittedUnknown,
          submission: WithdrawalSubmission.gaslessRelay(
            traceId: traceId,
            requestId: pending.requestId,
          ),
        );
        return;
      } else if (status.state.isFailed) {
        await _removePendingGaslessTransfer(traceId);
        yield WithdrawalProgress(
          status: WithdrawalStatus.error,
          message: 'Gas-free transfer failed',
          withdrawalResult: withdrawalResult,
          taskId: traceId,
          sdkError: _mapError(
            GaslessTransferException(
              kind: GaslessTransferErrorKind.finalFailure,
              message: 'GasFree relay reported a terminal failure',
              retryable: false,
              terminal: true,
              code: GaslessTransferErrorCode.relayFailedFinal,
              stage: GaslessTransferStage.finality,
              localizationKey: 'sdk_errors.gasless_final_failure',
              traceId: traceId,
            ),
            operation: 'withdrawal.gasless',
            assetId: assetId,
          ),
          gaslessState: status.state,
          gaslessTransferState: GaslessTransferState.failedFinal,
          submission: WithdrawalSubmission.gaslessRelay(
            traceId: traceId,
            requestId: pending.requestId,
          ),
        );
        return;
      } else {
        // Still in flight: surface the relay state to the UI, both as a
        // human-readable message and as the typed state so consumers can
        // localize.
        final transferState = status.state == GaslessTraceState.onChain
            ? GaslessTransferState.confirming
            : GaslessTransferState.submittedPending;
        current = current.copyWith(
          state: transferState,
          updatedAt: DateTime.now().toUtc(),
        );
        await _upsertPendingGaslessTransfer(current);
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: _gaslessStateMessage(status.state),
          gaslessState: status.state,
          taskId: traceId,
          withdrawalResult: withdrawalResult,
          gaslessTransferState: transferState,
          submission: WithdrawalSubmission.gaslessRelay(
            traceId: traceId,
            requestId: pending.requestId,
          ),
        );
      }

      await Future<void>.delayed(_withPollingJitter(interval));
    }

    current = current.copyWith(
      state: GaslessTransferState.submittedUnknown,
      updatedAt: DateTime.now().toUtc(),
    );
    await _upsertPendingGaslessTransfer(current);
    yield WithdrawalProgress(
      status: WithdrawalStatus.inProgress,
      message: 'Gas-free transfer is taking longer than expected',
      withdrawalResult: withdrawalResult,
      taskId: traceId,
      gaslessTransferState: GaslessTransferState.submittedUnknown,
      submission: WithdrawalSubmission.gaslessRelay(
        traceId: traceId,
        requestId: pending.requestId,
      ),
    );
  }

  /// Replaces the token total in a gasless fee with the authoritative
  /// `final_fee` reported by the relay, when available.
  FeeInfo _applyFinalGaslessFee(
    FeeInfo fee,
    Decimal? finalFee,
    String traceId,
  ) {
    if (fee is! FeeInfoTronGasless) {
      // Degenerate state: a gas-free transfer was relayed but the preview fee
      // is not gas-free-typed, so there is no gas-free fee structure to carry
      // the relay's authoritative `final_fee` into. This is unreachable on the
      // normal path (a gas-free preview always carries a FeeInfoTronGasless
      // fee); surface it rather than silently swallowing the final fee.
      if (finalFee != null) log('GasFree final fee type could not be applied');
      return fee;
    }
    return FeeInfo.tronGasless(
      coin: fee.coin,
      feeMethod: fee.feeMethod,
      providerName: fee.providerName,
      gasfreeAddress: fee.gasfreeAddress,
      transferFee: fee.transferFee,
      totalTokenFee: fee.totalTokenFee,
      activationFee: fee.activationFee,
      signedMaxFee: fee.signedMaxFee,
      finalFee: finalFee ?? fee.finalFee,
      providerAddress: fee.providerAddress,
      authorizationDeadline: fee.authorizationDeadline,
      requestId: fee.requestId,
      authorizationFingerprint: fee.authorizationFingerprint,
      traceId: traceId,
    );
  }

  String _gaslessStateMessage(GaslessTraceState state) => switch (state) {
    GaslessTraceState.pending => 'Awaiting gas-free relay...',
    GaslessTraceState.submitted => 'Gas-free transfer submitted...',
    GaslessTraceState.onChain => 'Confirming on chain...',
    GaslessTraceState.confirmed => 'Confirmed',
    GaslessTraceState.failed => 'Failed',
  };

  Duration _withPollingJitter(Duration duration) {
    if (duration <= Duration.zero) return Duration.zero;
    final factor = 0.8 + (_secureRandom.nextDouble() * 0.4);
    return Duration(
      milliseconds: math.max(1, (duration.inMilliseconds * factor).round()),
    );
  }

  /// Unresolved GasFree transfers for the currently signed-in wallet.
  Future<List<PendingGaslessTransfer>> listPendingGaslessTransfers() async {
    final repository = _pendingGaslessTransfers;
    final walletId = await _walletIdResolver?.call();
    if (repository == null || walletId == null) {
      return const <PendingGaslessTransfer>[];
    }
    final transfers = await repository.list(walletId);
    for (final transfer in transfers) {
      _pendingGaslessWallets[transfer.requestId] = walletId;
      final traceId = transfer.traceId;
      if (traceId != null) _pendingGaslessWallets[traceId] = walletId;
    }
    return transfers;
  }

  /// Wallet-scoped journal updates for app-wide pending activity surfaces.
  Stream<List<PendingGaslessTransfer>> watchPendingGaslessTransfers() async* {
    final repository = _pendingGaslessTransfers;
    final walletId = await _walletIdResolver?.call();
    if (repository == null || walletId == null) {
      yield const <PendingGaslessTransfer>[];
      return;
    }
    yield* repository.watch(walletId);
  }

  /// Resume authoritative trace reconciliation for an accepted GasFree relay.
  Stream<WithdrawalProgress> resumePendingGaslessTransfer(
    String identity,
  ) async* {
    final repository = _pendingGaslessTransfers;
    final walletId = await _walletIdResolver?.call();
    if (repository == null || walletId == null) {
      throw StateError('No signed-in wallet is available for reconciliation');
    }
    final pending = await repository.find(walletId, identity);
    if (pending == null) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.invalidTrace,
        message: 'Pending GasFree transfer was not found',
        retryable: false,
        terminal: false,
        traceId: identity,
      );
    }

    _pendingGaslessWallets[pending.requestId] = walletId;
    final traceId = pending.traceId;
    if (traceId == null) {
      yield WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: 'Gas-free submission outcome is still unknown',
        withdrawalResult: WithdrawalResult(
          txHash: null,
          balanceChanges: pending.balanceChanges,
          coin: pending.assetId,
          toAddress: pending.destinationAddress,
          fee: pending.fee,
        ),
        taskId: pending.requestId,
        sdkError: _mapError(
          GaslessTransferException(
            kind: GaslessTransferErrorKind.traceUnavailable,
            message: 'GasFree relay trace is not available',
            retryable: false,
            terminal: false,
          ),
          operation: 'withdrawal.gasless.recovery',
          assetId: pending.assetId,
        ),
        gaslessTransferState: GaslessTransferState.submittedUnknown,
        submission: WithdrawalSubmission.gaslessUnknown(
          requestId: pending.requestId,
        ),
      );
      return;
    }
    _pendingGaslessWallets[traceId] = walletId;
    final result = WithdrawalResult(
      txHash: null,
      balanceChanges: pending.balanceChanges,
      coin: pending.assetId,
      toAddress: pending.destinationAddress,
      fee: pending.fee,
    );
    yield WithdrawalProgress(
      status: WithdrawalStatus.inProgress,
      message: 'Checking gas-free transfer status...',
      withdrawalResult: result,
      taskId: traceId,
      gaslessTransferState: pending.state,
      submission: WithdrawalSubmission.gaslessRelay(
        traceId: traceId,
        requestId: pending.requestId,
      ),
    );
    yield* _pollGaslessTrace(
      assetId: pending.assetId,
      traceId: traceId,
      withdrawalResult: result,
      pending: pending,
    );
  }

  /// Reconcile every unresolved transfer for the current wallet in order.
  Stream<WithdrawalProgress> reconcilePendingGaslessTransfers() async* {
    final pending = await listPendingGaslessTransfers();
    for (final transfer in pending) {
      yield* resumePendingGaslessTransfer(
        transfer.traceId ?? transfer.requestId,
      );
    }
  }

  void _requireGaslessReady(AssetId assetId) {
    if (_gaslessCapabilities.isReady(assetId)) return;
    throw GaslessTransferException(
      kind: GaslessTransferErrorKind.capabilityNotReady,
      message: 'Gas-free transfers are not ready for ${assetId.id}',
      retryable: true,
      terminal: false,
    );
  }

  void _requireGaslessPreviewAllowed(AssetId assetId) {
    if (_gaslessCapabilities.canAttemptAuthoritativePreview(assetId)) return;
    throw GaslessTransferException(
      kind: GaslessTransferErrorKind.capabilityNotReady,
      message: 'Gas-free preview is not available for ${assetId.id}',
      retryable: true,
      terminal: false,
    );
  }

  PendingGaslessTransfer _pendingTransferFromPreview({
    required WithdrawalPreview preview,
    required String assetId,
    required String? traceId,
    required String requestId,
    required String authorizationFingerprint,
    required GaslessVerificationMode verificationMode,
    GaslessTransferState state = GaslessTransferState.submittedPending,
  }) {
    final txJson = preview.txJson ?? const <String, dynamic>{};
    final authorization = txJson['signed_authorization'];
    final auth = authorization is Map
        ? Map<String, dynamic>.from(authorization)
        : const <String, dynamic>{};
    final gaslessFee = preview.fee is FeeInfoTronGasless
        ? preview.fee as FeeInfoTronGasless
        : null;
    final now = DateTime.now().toUtc();
    return PendingGaslessTransfer(
      traceId: traceId,
      requestId: requestId,
      provider: auth['service_provider']?.toString(),
      tokenContract: auth['token']?.toString(),
      authorizationNonce: auth['nonce']?.toString(),
      authorizationVersion: auth['version']?.toString(),
      authorizationAmount: auth['value']?.toString(),
      authorizationMaxFee: auth['max_fee']?.toString(),
      assetId: assetId,
      network: txJson['chain_id']?.toString() ?? 'unknown',
      sourceAddress: txJson['from_address']?.toString() ?? '',
      custodyAddress:
          txJson['gasfree_address']?.toString() ??
          gaslessFee?.gasfreeAddress ??
          '',
      destinationAddress: preview.to.isEmpty ? '' : preview.to.first,
      // User-facing token units from the signed preview. The raw provider
      // integer remains separately bound in authorizationAmount.
      requestedAmount: preview.balanceChanges.totalAmount,
      signedMaxFee:
          gaslessFee?.signedMaxFee ?? gaslessFee?.totalTokenFee ?? Decimal.zero,
      authorizationDeadline:
          int.tryParse(auth['deadline']?.toString() ?? '') ?? 0,
      authorizationFingerprint: authorizationFingerprint,
      balanceChanges: preview.balanceChanges,
      fee: traceId == null
          ? preview.fee
          : _applyFinalGaslessFee(preview.fee, null, traceId),
      acceptedAt: now,
      updatedAt: now,
      state: state,
      verificationMode: verificationMode,
    );
  }

  _ValidatedGaslessPreview _validateGaslessPreview(
    WithdrawalPreview preview,
    Asset asset,
    WalletOperationContext walletContext, {
    bool allowLegacyPromotion = false,
  }) {
    final assetId = asset.id.id;
    final txJson = preview.txJson ?? const <String, dynamic>{};
    final boundRequestId = txJson['request_id']?.toString();
    final authorization = txJson['signed_authorization'];
    final hdFrom = txJson['hd_from'];
    final boundAuthorizationFingerprint = txJson['authorization_fingerprint']
        ?.toString();
    final hasBoundRequestId =
        boundRequestId != null && boundRequestId.isNotEmpty;
    final hasBoundFingerprint =
        boundAuthorizationFingerprint != null &&
        boundAuthorizationFingerprint.isNotEmpty;
    if (hasBoundRequestId != hasBoundFingerprint) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        message: 'GasFree signed preview has partial relay binding context',
        retryable: false,
        terminal: true,
        code: GaslessTransferErrorCode.invalidSignedPreview,
        stage: GaslessTransferStage.preview,
        localizationKey: 'sdk_errors.gasless_preview_invalid',
      );
    }
    final verificationMode = hasBoundRequestId
        ? GaslessVerificationMode.boundRelay
        : GaslessVerificationMode.legacyOnChain;
    final authorizationFingerprint =
        boundAuthorizationFingerprint ??
        _legacyGaslessPayloadFingerprint(txJson);
    final requiredAuthorizationFields = <String>{
      'token',
      'service_provider',
      'user',
      'receiver',
      'value',
      'max_fee',
      'deadline',
      'version',
      'nonce',
      'sig',
    };
    final isUuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(boundRequestId ?? '');
    final auth = authorization is Map
        ? Map<String, dynamic>.from(authorization)
        : const <String, dynamic>{};
    final signedFieldsPresent = requiredAuthorizationFields.every(
      (field) => (auth[field]?.toString().isNotEmpty ?? false),
    );
    final receiverMatches =
        preview.to.length == 1 && auth['receiver'] == preview.to.single;
    final gaslessFee = preview.fee is FeeInfoTronGasless
        ? preview.fee as FeeInfoTronGasless
        : null;
    final authorizationDeadline = int.tryParse(
      auth['deadline']?.toString() ?? '',
    );
    final authorizationMaxFee = Decimal.tryParse(
      _tokenBaseUnitsToDecimalString(
            auth['max_fee']?.toString(),
            asset.id.chainId.decimals,
          ) ??
          '',
    );
    final authorizationAmount = Decimal.tryParse(
      _tokenBaseUnitsToDecimalString(
            auth['value']?.toString(),
            asset.id.chainId.decimals,
          ) ??
          '',
    );
    final authorizationProvider = auth['service_provider']?.toString();
    final authorizationToken = auth['token']?.toString();
    final authorizationVersion = _parseUnsigned256(auth['version']?.toString());
    final authorizationNonce = _parseUnsigned256(auth['nonce']?.toString());
    final chainId = txJson['chain_id']?.toString();
    final sourceMatches =
        txJson['from_address']?.toString().isNotEmpty == true &&
        txJson['from_address']?.toString() == auth['user']?.toString() &&
        preview.from.length == 1 &&
        preview.from.single == auth['user']?.toString();
    final custodyMatches =
        txJson['gasfree_address']?.toString().isNotEmpty == true &&
        gaslessFee != null &&
        gaslessFee.gasfreeAddress == txJson['gasfree_address'];
    final amountMatches =
        authorizationAmount != null &&
        authorizationAmount > Decimal.zero &&
        authorizationAmount == preview.balanceChanges.totalAmount;
    final maxFeeMatches =
        gaslessFee != null &&
        gaslessFee.signedMaxFee != null &&
        authorizationMaxFee != null &&
        authorizationMaxFee > Decimal.zero &&
        gaslessFee.signedMaxFee! > Decimal.zero &&
        authorizationMaxFee == gaslessFee.signedMaxFee;
    final signatureFingerprint = _gaslessSignatureFingerprint(
      auth['sig']?.toString(),
    );
    final fingerprintMatchesSignature =
        verificationMode == GaslessVerificationMode.legacyOnChain
        ? signatureFingerprint != null
        : signatureFingerprint == authorizationFingerprint?.toLowerCase();
    final feeContextMatches =
        gaslessFee != null &&
        gaslessFee.coin == assetId &&
        gaslessFee.feeMethod.toLowerCase() == 'gasless' &&
        (verificationMode == GaslessVerificationMode.legacyOnChain
            ? (gaslessFee.providerAddress == null ||
                      gaslessFee.providerAddress == authorizationProvider) &&
                  (gaslessFee.authorizationDeadline == null ||
                      gaslessFee.authorizationDeadline ==
                          authorizationDeadline) &&
                  gaslessFee.requestId == null &&
                  gaslessFee.authorizationFingerprint == null
            : gaslessFee.providerAddress == authorizationProvider &&
                  gaslessFee.authorizationDeadline == authorizationDeadline &&
                  gaslessFee.requestId == boundRequestId &&
                  gaslessFee.authorizationFingerprint?.toLowerCase() ==
                      authorizationFingerprint?.toLowerCase());
    final walletPubkeyHash = walletContext.walletId.pubkeyHash?.trim();
    final capabilityContextMatches =
        chainId != null &&
        authorizationToken != null &&
        authorizationProvider != null &&
        walletPubkeyHash != null &&
        walletPubkeyHash.isNotEmpty &&
        (verificationMode == GaslessVerificationMode.legacyOnChain &&
                allowLegacyPromotion
            ? _gaslessCapabilities.matchesProvisionalAuthorizationContext(
                asset.id,
                chainId: chainId,
                tokenContract: authorizationToken,
                providerAddress: authorizationProvider,
                walletPubkeyHash: walletPubkeyHash,
              )
            : _gaslessCapabilities.matchesReadyAuthorizationContext(
                asset.id,
                chainId: chainId,
                tokenContract: authorizationToken,
                providerAddress: authorizationProvider,
                walletPubkeyHash: walletPubkeyHash,
                verificationMode: verificationMode,
              ));
    final authorizationFresh =
        authorizationDeadline != null &&
        authorizationDeadline >
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final isCanonicalSource = switch (hdFrom) {
      null => true,
      final Map<dynamic, dynamic> selector =>
        selector['account_id'] == 0 &&
            selector['address_id'] == 0 &&
            selector['chain']?.toString().toLowerCase() == 'external',
      _ => false,
    };
    final fingerprintValid =
        authorizationFingerprint != null &&
        RegExp(
          r'^[0-9a-f]{64}$',
          caseSensitive: false,
        ).hasMatch(authorizationFingerprint);
    if (txJson['relay_type'] != 'tron_gasfree' ||
        txJson['coin'] != assetId ||
        (hasBoundRequestId && !isUuidV4) ||
        !signedFieldsPresent ||
        !receiverMatches ||
        !sourceMatches ||
        !custodyMatches ||
        !amountMatches ||
        !maxFeeMatches ||
        !feeContextMatches ||
        !capabilityContextMatches ||
        authorizationDeadline == null ||
        authorizationVersion != BigInt.one ||
        authorizationNonce == null ||
        !isCanonicalSource ||
        !fingerprintValid ||
        !fingerprintMatchesSignature) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        message: 'GasFree signed preview is incomplete or inconsistent',
        retryable: false,
        terminal: true,
        code: GaslessTransferErrorCode.invalidSignedPreview,
        stage: GaslessTransferStage.preview,
        localizationKey: 'sdk_errors.gasless_preview_invalid',
      );
    }
    if (!authorizationFresh) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.configuration,
        message: 'GasFree authorization has expired',
        retryable: true,
        terminal: true,
        code: GaslessTransferErrorCode.authorizationExpired,
        stage: GaslessTransferStage.preview,
        localizationKey: 'sdk_errors.gasless_authorization_expired',
      );
    }
    if (verificationMode == GaslessVerificationMode.legacyOnChain &&
        allowLegacyPromotion &&
        !_gaslessCapabilities.proveLegacyReadyFromSignedPreview(
          asset.id,
          chainId: chainId,
          tokenContract: authorizationToken,
          providerAddress: authorizationProvider,
          walletPubkeyHash: walletPubkeyHash,
        )) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        message: 'GasFree signed preview identity could not be promoted',
        retryable: false,
        terminal: true,
        code: GaslessTransferErrorCode.invalidSignedPreview,
        stage: GaslessTransferStage.preview,
        localizationKey: 'sdk_errors.gasless_preview_invalid',
      );
    }
    return _ValidatedGaslessPreview(
      boundRequestId: boundRequestId,
      authorizationFingerprint: authorizationFingerprint,
      verificationMode: verificationMode,
    );
  }

  Future<PendingGaslessTransfer> _prepareGaslessTransfer(
    WithdrawalPreview preview,
    Asset asset,
    _ValidatedGaslessPreview validated,
    WalletOperationContext walletContext,
  ) async {
    final requestId = validated.boundRequestId ?? _newGaslessRequestId();
    final pending = _pendingTransferFromPreview(
      preview: preview,
      assetId: asset.id.id,
      traceId: null,
      requestId: requestId,
      authorizationFingerprint: validated.authorizationFingerprint,
      verificationMode: validated.verificationMode,
      state: GaslessTransferState.preparing,
    );
    final repository = _pendingGaslessTransfers;
    final walletId = walletContext.walletId;
    if (repository == null) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.persistenceUnavailable,
        message: 'GasFree transfer could not be stored securely',
        retryable: true,
        terminal: false,
        code: GaslessTransferErrorCode.securePersistenceUnavailable,
        stage: GaslessTransferStage.persistence,
        localizationKey: 'sdk_errors.gasless_storage_unavailable',
      );
    }
    final bool reserved;
    try {
      reserved = await repository.reserve(walletId, pending);
    } catch (_) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.persistenceUnavailable,
        message: 'GasFree transfer could not be stored securely',
        retryable: true,
        terminal: false,
        code: GaslessTransferErrorCode.securePersistenceUnavailable,
        stage: GaslessTransferStage.persistence,
        localizationKey: 'sdk_errors.gasless_storage_unavailable',
      );
    }
    if (!reserved) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.traceUnavailable,
        message: 'An unresolved GasFree transfer already exists',
        retryable: false,
        terminal: false,
        code: GaslessTransferErrorCode.submissionOutcomeUnknown,
        stage: GaslessTransferStage.recovery,
        localizationKey: 'sdk_errors.gasless_transfer_unresolved',
      );
    }
    if (!await _isWalletContextCurrent(walletContext)) {
      await repository.remove(walletId, pending.requestId);
      throw const WalletChangedDisconnectException(
        'Wallet changed before GasFree relay submission',
      );
    }
    _pendingGaslessWallets[pending.requestId] = walletId;
    return pending;
  }

  BigInt? _parseUnsigned256(String? raw) {
    if (raw == null ||
        raw.isEmpty ||
        raw.length > 78 ||
        !RegExp(r'^\d+$').hasMatch(raw)) {
      return null;
    }
    final value = BigInt.tryParse(raw);
    final max = (BigInt.one << 256) - BigInt.one;
    if (value == null || value < BigInt.zero || value > max) return null;
    return value;
  }

  String? _tokenBaseUnitsToDecimalString(String? raw, int? decimals) {
    if (decimals == null || decimals < 0 || decimals > 255) return null;
    final value = _parseUnsigned256(raw);
    if (value == null) return null;
    final digits = value.toString();
    if (decimals == 0) return digits;
    final padded = digits.padLeft(decimals + 1, '0');
    final split = padded.length - decimals;
    return '${padded.substring(0, split)}.${padded.substring(split)}';
  }

  String? _gaslessSignatureFingerprint(String? signature) {
    if (signature == null) return null;
    // KDF's TronSignature is an H520 serialized as exactly 65 bytes of hex,
    // with the protocol explicitly rejecting a `0x` prefix.
    if (signature.length != 130 ||
        !RegExp(r'^[0-9a-f]+$', caseSensitive: false).hasMatch(signature)) {
      return null;
    }
    final bytes = <int>[
      for (var offset = 0; offset < signature.length; offset += 2)
        int.parse(signature.substring(offset, offset + 2), radix: 16),
    ];
    return sha256.convert(bytes).toString();
  }

  String _newGaslessRequestId() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  String? _legacyGaslessPayloadFingerprint(Map<String, dynamic> txJson) {
    final authorization = txJson['signed_authorization'];
    if (authorization is! Map) return null;
    final auth = Map<String, dynamic>.from(authorization);
    final hdFrom = txJson['hd_from'];
    final hdIdentity = switch (hdFrom) {
      null => '',
      final Map<dynamic, dynamic> selector =>
        '${selector['account_id'] ?? ''}|${selector['chain'] ?? ''}|'
            '${selector['address_id'] ?? ''}',
      _ => null,
    };
    if (hdIdentity == null) return null;

    // Keep the sequence fixed. Each UTF-8 value is prefixed with a four-byte
    // big-endian length so concatenated fields cannot be reinterpreted.
    final values = <Object?>[
      'gleec.gasfree.legacy.v1',
      txJson['relay_type'],
      txJson['chain_id'],
      txJson['coin'],
      hdIdentity,
      txJson['from_address'],
      txJson['gasfree_address'],
      txJson['verifying_contract'],
      auth['token'],
      auth['service_provider'],
      auth['user'],
      auth['receiver'],
      auth['value'],
      auth['max_fee'],
      auth['deadline'],
      auth['version'],
      auth['nonce'],
      auth['sig'],
      txJson['created_at'],
    ];
    if (values.any((value) => value == null)) return null;

    final encoded = BytesBuilder(copy: false);
    for (final value in values) {
      final bytes = utf8.encode(value.toString());
      final length = ByteData(4)..setUint32(0, bytes.length, Endian.big);
      encoded
        ..add(length.buffer.asUint8List())
        ..add(bytes);
    }
    return sha256.convert(encoded.takeBytes()).toString();
  }

  Future<bool> _persistAcceptedGaslessTransfer(
    PendingGaslessTransfer transfer,
  ) async {
    final repository = _pendingGaslessTransfers;
    final walletId =
        _pendingGaslessWallets[transfer.requestId] ??
        await _walletIdResolver?.call();
    if (repository == null || walletId == null) return false;
    _pendingGaslessWallets[transfer.requestId] = walletId;
    final traceId = transfer.traceId;
    if (traceId != null) _pendingGaslessWallets[traceId] = walletId;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await repository.upsert(walletId, transfer);
        final stored = traceId == null
            ? await repository.findByRequestId(walletId, transfer.requestId)
            : await repository.findByTraceId(walletId, traceId);
        if (stored?.requestId == transfer.requestId &&
            stored?.traceId == transfer.traceId &&
            stored?.state == transfer.state &&
            stored?.custodyAddress == transfer.custodyAddress &&
            stored?.authorizationFingerprint ==
                transfer.authorizationFingerprint) {
          return true;
        }
      } catch (_) {
        // Retry the encrypted write and read-back as one durability unit.
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
      }
    }
    log('Failed to durably persist accepted GasFree relay');
    return false;
  }

  GaslessExpectedAuthorization? _expectedAuthorization(
    PendingGaslessTransfer transfer,
  ) {
    if (transfer.verificationMode != GaslessVerificationMode.boundRelay) {
      return null;
    }
    final amount = transfer.authorizationAmount;
    final maxFee = transfer.authorizationMaxFee;
    final provider = transfer.provider;
    final token = transfer.tokenContract;
    final nonce = transfer.authorizationNonce;
    final version = transfer.authorizationVersion;
    if (amount == null ||
        maxFee == null ||
        provider == null ||
        token == null ||
        nonce == null ||
        version == null ||
        transfer.authorizationFingerprint.isEmpty) {
      return null;
    }
    return GaslessExpectedAuthorization(
      requestId: transfer.requestId,
      account: transfer.sourceAddress,
      custodyAddress: transfer.custodyAddress,
      provider: provider,
      receiver: transfer.destinationAddress,
      token: token,
      amount: amount,
      maxFee: maxFee,
      deadline: transfer.authorizationDeadline.toString(),
      version: version,
      nonce: nonce,
      signatureFingerprint: transfer.authorizationFingerprint,
    );
  }

  Future<GaslessOnChainVerification> _verifyLegacyGaslessFinality(
    PendingGaslessTransfer pending,
    String transactionHash,
  ) async {
    final history = _transactionHistoryManager;
    if (history == null) return GaslessOnChainVerification.pending;
    final assets = _assetProvider.findAssetsByConfigId(pending.assetId);
    if (assets.length != 1) return GaslessOnChainVerification.mismatch;
    return history.verifyGaslessTransferOnChain(
      assets.single,
      pending,
      transactionHash,
    );
  }

  Future<bool> _isPendingWalletCurrent(PendingGaslessTransfer transfer) async {
    final original = _pendingGaslessWallets[transfer.requestId];
    final current = await _walletIdResolver?.call();
    if (original == null || current == null) return false;
    final originalStable = original.pubkeyHash?.trim();
    final currentStable = current.pubkeyHash?.trim();
    if (originalStable != null && currentStable != null) {
      return originalStable == currentStable;
    }
    return original.isSameAs(current);
  }

  Future<void> _upsertPendingGaslessTransfer(
    PendingGaslessTransfer transfer,
  ) async {
    final repository = _pendingGaslessTransfers;
    if (repository == null) return;
    final walletId =
        _pendingGaslessWallets[transfer.requestId] ??
        (transfer.traceId == null
            ? null
            : _pendingGaslessWallets[transfer.traceId]) ??
        await _walletIdResolver?.call();
    if (walletId == null) return;
    _pendingGaslessWallets[transfer.requestId] = walletId;
    final traceId = transfer.traceId;
    if (traceId != null) _pendingGaslessWallets[traceId] = walletId;
    try {
      await repository.upsert(walletId, transfer);
    } catch (_) {
      log('Failed to update pending GasFree relay');
    }
  }

  Future<void> _removePendingGaslessTransfer(String identity) async {
    final repository = _pendingGaslessTransfers;
    if (repository == null) return;
    final walletId =
        _pendingGaslessWallets[identity] ?? await _walletIdResolver?.call();
    if (walletId == null) return;
    try {
      final pending = await repository.find(walletId, identity);
      await repository.remove(walletId, identity);
      _pendingGaslessWallets.remove(identity);
      if (pending != null) {
        _pendingGaslessWallets.remove(pending.requestId);
        _pendingGaslessWallets.remove(pending.traceId);
      }
    } catch (_) {
      log('Failed to remove terminal GasFree relay');
    }
  }

  _AcceptedRelayMismatch? _parseAcceptedRelayMismatch(Object error) {
    final envelope = _gaslessRelayErrorEnvelope(error);
    if (envelope != null &&
        envelope.relayAccepted == true &&
        envelope.code == 'accepted_response_mismatch' &&
        envelope.requestId != null &&
        envelope.requestId!.isNotEmpty &&
        envelope.traceId != null &&
        envelope.traceId!.isNotEmpty) {
      return _AcceptedRelayMismatch(
        requestId: envelope.requestId!,
        traceId: envelope.traceId!,
      );
    }

    final descriptor = switch (error) {
      final GeneralErrorResponse response => [
        response.errorType,
        response.error,
        if (response.errorData is String) response.errorData as String,
      ].whereType<String>().join(' '),
      final MmRpcException exception => [
        exception.errorType,
        exception.message,
      ].whereType<String>().join(' '),
      _ => error.toString(),
    };
    final match = RegExp(
      r'GASFREE_RELAY_ACCEPTED_RESPONSE_MISMATCH\s+'
      r'request_id=([^\s]+)\s+trace_id=([^\s]+)\s+field=([^\s]+)',
      caseSensitive: false,
    ).firstMatch(descriptor);
    if (match == null) return null;
    final requestId = match.group(1);
    final traceId = match.group(2);
    if (requestId == null ||
        requestId.isEmpty ||
        traceId == null ||
        traceId.isEmpty) {
      return null;
    }
    return _AcceptedRelayMismatch(requestId: requestId, traceId: traceId);
  }

  GaslessTransferException? _classifyPreRelayRejection(Object error) {
    final envelope = _gaslessRelayErrorEnvelope(error);
    if (envelope != null) {
      // Only an explicit false is safe to retry. Missing/true means provider
      // acceptance is possible and the durable request reservation must stay.
      if (envelope.relayAccepted != false) return null;
      final code = _gaslessTransferErrorCode(envelope.code);
      final kind = switch (code) {
        GaslessTransferErrorCode.rateLimited ||
        GaslessTransferErrorCode.providerUnavailable ||
        GaslessTransferErrorCode.providerTimeout =>
          GaslessTransferErrorKind.traceUnavailable,
        GaslessTransferErrorCode.custodyAddressMismatch ||
        GaslessTransferErrorCode.signatureMismatch ||
        GaslessTransferErrorCode.walletOwnershipMismatch ||
        GaslessTransferErrorCode.responseMismatch =>
          GaslessTransferErrorKind.providerResponse,
        _ => GaslessTransferErrorKind.configuration,
      };
      return GaslessTransferException(
        kind: kind,
        message: 'GasFree request was rejected before relay acceptance',
        retryable: envelope.retryable,
        terminal: envelope.terminal,
        code: code,
        stage: GaslessTransferStage.submission,
        localizationKey: _gaslessPreRelayLocalizationKey(code),
      );
    }

    final errorType = switch (error) {
      final GeneralErrorResponse response => response.errorType ?? '',
      final MmRpcException exception => exception.errorType,
      _ => error.runtimeType.toString(),
    };
    final normalized = errorType.toLowerCase();
    final (GaslessTransferErrorCode, String)? classification =
        normalized.contains('unsupportedtoken') ||
            normalized.contains('tokennotsupported')
        ? (
            GaslessTransferErrorCode.unsupportedToken,
            'sdk_errors.gasless_token_unsupported',
          )
        : normalized.contains('authorizationexpired') ||
              normalized.contains('deadlineexpired')
        ? (
            GaslessTransferErrorCode.authorizationExpired,
            'sdk_errors.gasless_authorization_expired',
          )
        : normalized.contains('unauthorized') ||
              normalized.contains('authentication')
        ? (
            GaslessTransferErrorCode.authenticationRejected,
            'sdk_errors.gasless_authentication_rejected',
          )
        : normalized.contains('gaslessnotconfigured') ||
              normalized.contains('serviceprovidermismatch') ||
              normalized.contains('invalidsignature') ||
              normalized.contains('invalidrequest')
        ? (
            GaslessTransferErrorCode.relayRejected,
            'sdk_errors.gasless_rejected_before_relay',
          )
        : null;
    if (classification == null) return null;
    return GaslessTransferException(
      kind: GaslessTransferErrorKind.configuration,
      message: 'GasFree request was rejected before relay acceptance',
      retryable: true,
      terminal: true,
      code: classification.$1,
      stage: GaslessTransferStage.submission,
      localizationKey: classification.$2,
    );
  }

  _GaslessRelayErrorEnvelope? _gaslessRelayErrorEnvelope(Object error) {
    if (error is! GeneralErrorResponse ||
        error.errorType != 'GaslessRelaySubmission') {
      return null;
    }
    final data = error.errorData;
    if (data is! Map) return null;
    final code = data['code'];
    final relayAccepted = data['relay_accepted'];
    final retryable = data['retryable'];
    final terminal = data['terminal'];
    if (code is! String ||
        retryable is! bool ||
        terminal is! bool ||
        (relayAccepted != null && relayAccepted is! bool)) {
      return null;
    }
    return _GaslessRelayErrorEnvelope(
      code: code,
      relayAccepted: relayAccepted as bool?,
      retryable: retryable,
      terminal: terminal,
      requestId: data['request_id'] as String?,
      traceId: data['trace_id'] as String?,
    );
  }

  GaslessTransferErrorCode _gaslessTransferErrorCode(
    String code,
  ) => switch (code) {
    'invalid_payload' => GaslessTransferErrorCode.invalidPayload,
    'wrong_coin_type' => GaslessTransferErrorCode.wrongCoinType,
    'runtime_missing' => GaslessTransferErrorCode.runtimeMissing,
    'chain_id_mismatch' => GaslessTransferErrorCode.chainIdMismatch,
    'verifying_contract_mismatch' =>
      GaslessTransferErrorCode.verifyingContractMismatch,
    'service_provider_mismatch' =>
      GaslessTransferErrorCode.serviceProviderMismatch,
    'token_mismatch' => GaslessTransferErrorCode.tokenMismatch,
    'invalid_address' => GaslessTransferErrorCode.invalidAddress,
    'custody_address_mismatch' =>
      GaslessTransferErrorCode.custodyAddressMismatch,
    'signature_mismatch' => GaslessTransferErrorCode.signatureMismatch,
    'wallet_ownership_mismatch' =>
      GaslessTransferErrorCode.walletOwnershipMismatch,
    'authorization_expired' => GaslessTransferErrorCode.authorizationExpired,
    'pending_transfer' => GaslessTransferErrorCode.pendingTransfer,
    'provider_rejected' => GaslessTransferErrorCode.relayRejected,
    'authentication_rejected' =>
      GaslessTransferErrorCode.authenticationRejected,
    'rate_limited' => GaslessTransferErrorCode.rateLimited,
    'provider_unavailable' => GaslessTransferErrorCode.providerUnavailable,
    'provider_timeout' => GaslessTransferErrorCode.providerTimeout,
    'provider_response_mismatch' => GaslessTransferErrorCode.responseMismatch,
    _ => GaslessTransferErrorCode.relayRejected,
  };

  String _gaslessPreRelayLocalizationKey(GaslessTransferErrorCode code) =>
      switch (code) {
        GaslessTransferErrorCode.wrongCoinType ||
        GaslessTransferErrorCode.tokenMismatch ||
        GaslessTransferErrorCode.unsupportedToken =>
          'sdk_errors.gasless_token_unsupported',
        GaslessTransferErrorCode.authorizationExpired =>
          'sdk_errors.gasless_authorization_expired',
        GaslessTransferErrorCode.authenticationRejected =>
          'sdk_errors.gasless_authentication_rejected',
        GaslessTransferErrorCode.pendingTransfer =>
          'sdk_errors.gasless_transfer_unresolved',
        GaslessTransferErrorCode.rateLimited ||
        GaslessTransferErrorCode.providerUnavailable ||
        GaslessTransferErrorCode.providerTimeout =>
          'sdk_errors.gasless_status_unavailable',
        GaslessTransferErrorCode.custodyAddressMismatch ||
        GaslessTransferErrorCode.signatureMismatch ||
        GaslessTransferErrorCode.walletOwnershipMismatch ||
        GaslessTransferErrorCode.responseMismatch =>
          'sdk_errors.gasless_response_invalid',
        _ => 'sdk_errors.gasless_rejected_before_relay',
      };

  GaslessTransferException _classifyTraceFailure(Object error, String traceId) {
    if (error is GaslessTransferException) return error;
    if (error is FormatException) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.invalidTrace,
        message: 'GasFree trace response could not be verified',
        retryable: false,
        terminal: false,
        code: GaslessTransferErrorCode.responseMismatch,
        stage: GaslessTransferStage.status,
        localizationKey: 'sdk_errors.gasless_response_invalid',
        traceId: traceId,
      );
    }
    if (error is SdkError) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.traceUnavailable,
        message: 'GasFree transfer status is unavailable',
        retryable: error.retryable,
        terminal: false,
        traceId: traceId,
      );
    }

    final errorType = error is GeneralErrorResponse
        ? error.errorType ?? ''
        : error.toString();
    final deterministicConfiguration =
        errorType.contains('CoinNotFound') ||
        errorType.contains('NotEthCoin') ||
        errorType.contains('CoinNotSupported') ||
        errorType.contains('GaslessNotConfigured');
    final invalidTrace = errorType.contains('InvalidTraceId');
    final responseMismatch =
        errorType.contains('ResponseMismatch') ||
        errorType.contains('AuthorizationMismatch');
    final traceNotFound = errorType.contains('TraceNotFound');

    if (responseMismatch) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.invalidTrace,
        message: 'GasFree trace response could not be verified',
        retryable: false,
        terminal: false,
        code: GaslessTransferErrorCode.responseMismatch,
        stage: GaslessTransferStage.status,
        localizationKey: 'sdk_errors.gasless_response_invalid',
        traceId: traceId,
      );
    }
    if (invalidTrace) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.invalidTrace,
        message: 'GasFree trace identifier is invalid',
        retryable: false,
        terminal: false,
        code: GaslessTransferErrorCode.traceInvalid,
        stage: GaslessTransferStage.status,
        localizationKey: 'sdk_errors.gasless_trace_invalid',
        traceId: traceId,
      );
    }
    if (deterministicConfiguration) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.configuration,
        message: 'GasFree status configuration is unavailable',
        retryable: false,
        terminal: false,
        traceId: traceId,
      );
    }
    return GaslessTransferException(
      kind: GaslessTransferErrorKind.traceUnavailable,
      message: traceNotFound
          ? 'GasFree trace is not available yet'
          : 'GasFree transfer status is temporarily unavailable',
      retryable: true,
      terminal: false,
      traceId: traceId,
    );
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
      _validateSiaSourceSelection(parameters, asset);
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
        throw _mapError(
          activationResult.errorMessage ?? activationResult.toString(),
          operation: 'withdrawal.activate',
          assetId: parameters.asset,
        );
      }

      if (parameters.feeMethod == WithdrawalFeeMethod.gasless) {
        _requireGaslessReady(asset.id);
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
            _mapError(
              _typedTaskError(status.details) ?? status.details as String,
              operation: 'withdrawal.progress',
              assetId: parameters.asset,
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
        yield* executeWithdrawal(details, parameters.asset);
      }
    } catch (e, stackTrace) {
      // Log the error and stack trace for debugging purposes
      log('Error during withdrawal: $e');
      log('Stack trace: $stackTrace');
      yield* Stream.error(
        _mapError(
          e,
          operation: 'withdrawal.execute',
          assetId: parameters.asset,
        ),
      );
    } finally {
      await _activeWithdrawals[taskId]?.close();
      _activeWithdrawals.remove(taskId);
    }
  }

  SdkError _mapError(
    Object error, {
    required String operation,
    String? assetId,
  }) {
    return _errorMapper.map(
      error,
      context: SdkErrorContext(operation: operation, assetId: assetId),
    );
  }

  /// `task::withdraw` error details arrive as the full MmError JSON object
  /// (JSON-stringified by [WithdrawStatusResponse.parse]); resolve it to a
  /// typed exception when the registry recognizes the `error_type` so
  /// structured data (e.g. GasFree custody shortfall amounts) survives to the
  /// error mapper instead of collapsing into a display string.
  MmRpcException? _typedTaskError(dynamic details) {
    if (details is! String || !details.trimLeft().startsWith('{')) return null;
    try {
      return KdfErrorRegistry.tryParse(
        jsonFromString(details),
        rpcMethodHint: 'task::withdraw::status',
      );
    } catch (_) {
      return null;
    }
  }

  void _validateSiaSourceSelection(WithdrawParameters parameters, Asset asset) {
    if (asset.protocol is! SiaProtocol || parameters.from == null) {
      return;
    }

    throw SdkError(
      code: SdkErrorCode.notSupported,
      category: SdkErrorCategory.unsupported,
      messageKey: 'withdrawal.sia.source_not_supported',
      fallbackMessage:
          'SIA withdrawals do not support "from" derivation/account/index '
          'parameters.',
      context: SdkErrorContext(
        operation: 'withdrawal.validate',
        assetId: parameters.asset,
        extra: {'protocol': 'SIA', 'param': 'from'},
      ),
      retryable: false,
    );
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

      switch (feeEstimationSupportForProtocol(protocol)) {
        case FeeEstimationSupport.evmGas:
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

        case FeeEstimationSupport.utxoPerKbyte:
          // UTXO-based protocols use per-kbyte fee estimation
          final estimation = await _feeManager.getUtxoEstimatedFee(asset.id.id);
          final selectedLevel = _getUtxoFeeLevel(estimation, priority);
          fee = FeeInfo.utxoPerKbyte(
            coin: asset.id.id,
            amount: selectedLevel.feePerKbyte,
          );

        case FeeEstimationSupport.tendermint:
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

        case FeeEstimationSupport.qtum:
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

        case FeeEstimationSupport.zhtlc:
          // ZHTLC (Zcash) uses UTXO-style fees
          final estimation = await _feeManager.getUtxoEstimatedFee(asset.id.id);
          final selectedLevel = _getUtxoFeeLevel(estimation, priority);
          fee = FeeInfo.utxoFixed(
            coin: asset.id.id,
            amount:
                selectedLevel.feePerKbyte *
                Decimal.fromInt(250), // Assume ~250 bytes
          );

        case FeeEstimationSupport.unsupported:
          log(
            'No fee estimation available for protocol ${protocol.runtimeType}',
          );
          return params;
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
        expirationSeconds: params.expirationSeconds,
        isMax: params.isMax,
        feeMethod: params.feeMethod,
        gaslessOptions: params.gaslessOptions,
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
          confirmationBlockHeight: result.blockHeight > 0
              ? result.blockHeight
              : null,
          confirmedAt: result.timestamp > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  result.timestamp * 1000,
                  isUtc: true,
                )
              : null,
        ),
      );
    }

    return WithdrawalProgress(
      status: WithdrawalStatus.inProgress,
      message: status.details as String,
    );
  }
}

class _AcceptedRelayMismatch {
  const _AcceptedRelayMismatch({
    required this.requestId,
    required this.traceId,
  });

  final String requestId;
  final String traceId;
}

class _ValidatedGaslessPreview {
  const _ValidatedGaslessPreview({
    required this.boundRequestId,
    required this.authorizationFingerprint,
    required this.verificationMode,
  });

  final String? boundRequestId;
  final String authorizationFingerprint;
  final GaslessVerificationMode verificationMode;
}

class _GaslessRelayErrorEnvelope {
  const _GaslessRelayErrorEnvelope({
    required this.code,
    required this.relayAccepted,
    required this.retryable,
    required this.terminal,
    this.requestId,
    this.traceId,
  });

  final String code;
  final bool? relayAccepted;
  final bool retryable;
  final bool terminal;
  final String? requestId;
  final String? traceId;
}
