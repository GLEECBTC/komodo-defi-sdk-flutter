import 'dart:async';
import 'dart:developer' show log;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show
        GaslessTraceErrorEvent,
        GaslessTraceEvent,
        GaslessTraceEventState,
        KdfEvent;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/pending_gasless_transfer_repository.dart';
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
    EventStreamingManager? eventStreamingManager,
    Future<Set<String>> Function(Asset asset)? freshSourceAddressResolver,
    Future<WalletId?> Function()? walletIdResolver,
    Stream<KdfUser?>? authStateChanges,
  }) : _gaslessCapabilities =
           gaslessCapabilities ?? GaslessCapabilityRegistry(),
       _pendingGaslessTransfers = pendingGaslessTransfers,
       _eventStreamingManager = eventStreamingManager,
       _freshSourceAddressResolver = freshSourceAddressResolver,
       _walletIdResolver = walletIdResolver {
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

  /// KDF defaults GasFree permits to five minutes when the request omits a
  /// deadline. KDF only requires an explicitly supplied value to be positive;
  /// the SDK must not invent a smaller provider maximum.
  static const int _defaultGaslessDeadlineSeconds = 300;
  static const int _gaslessDeadlineClockSkewSeconds = 5;

  final ApiClient _client;
  final IAssetProvider _assetProvider;
  final SharedActivationCoordinator _activationCoordinator;
  final FeeManager _feeManager;
  final LegacyWithdrawalManager _legacyManager;
  final GaslessCapabilityRegistry _gaslessCapabilities;
  final PendingGaslessTransferRepository? _pendingGaslessTransfers;
  final EventStreamingManager? _eventStreamingManager;
  final Future<Set<String>> Function(Asset asset)? _freshSourceAddressResolver;
  final Future<WalletId?> Function()? _walletIdResolver;
  final Map<String, WalletId> _pendingGaslessWallets = <String, WalletId>{};
  final math.Random _secureRandom = math.Random.secure();
  final _activeWithdrawals = <int, StreamController<WithdrawalProgress>>{};
  StreamSubscription<KdfUser?>? _gaslessAuthSubscription;
  final StreamController<int> _walletGenerationChanges =
      StreamController<int>.broadcast(sync: true);
  StreamSubscription<WithdrawalProgress>? _gaslessReconciliationSubscription;
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
    await _walletGenerationChanges.close();
    final withdrawals = _activeWithdrawals.entries.toList();
    _activeWithdrawals.clear();

    for (final withdrawal in withdrawals) {
      await withdrawal.value.close();
      await cancelWithdrawal(withdrawal.key);
    }
  }

  /// Starts wallet-scoped, status-only recovery for unresolved GasFree sends.
  ///
  /// This operation never resubmits a signed payload. Existing traces receive
  /// one authoritative `gasless::trace_status` reconciliation; KDF stream
  /// registration is intentionally not assumed to survive a process restart.
  Future<void> startGaslessReconciliation() async {
    await _runGaslessReconciliationCycle();
  }

  /// Stops an active recovery cycle while retaining the encrypted journal.
  Future<void> stopGaslessReconciliation() async {
    await _gaslessReconciliationSubscription?.cancel();
    _gaslessReconciliationSubscription = null;
  }

  void _handleGaslessAuthStateChanged(KdfUser? user) {
    final nextWallet = user?.walletId;
    final hasStableIdentity =
        nextWallet?.pubkeyHash?.trim().isNotEmpty ?? false;
    _gaslessCapabilities.ensureWalletSession(nextWallet?.pubkeyHash);
    if (!_sameOptionalWallet(_currentWalletId, nextWallet)) {
      _walletGeneration++;
      _currentWalletId = nextWallet;
      if (!_walletGenerationChanges.isClosed) {
        _walletGenerationChanges.add(_walletGeneration);
      }
    } else if (_currentWalletId != null && nextWallet != null) {
      _currentWalletId = preferEnrichedWalletIdentity(
        _currentWalletId!,
        nextWallet,
      );
    }
    unawaited(() async {
      await stopGaslessReconciliation();
      // A name-only auth fallback is sufficient for Standard wallet access,
      // but cannot decrypt or own a GasFree journal. Wait for enrichment
      // instead of surfacing a storage failure or touching unresolved work.
      if (hasStableIdentity) await startGaslessReconciliation();
    }());
  }

  bool _sameOptionalWallet(WalletId? previous, WalletId? current) {
    if (previous == null || current == null) return previous == current;
    return isSameStableWallet(previous, current);
  }

  Future<WalletOperationContext> _captureWalletContext() async {
    final wallet = await _walletIdResolver?.call();
    if (wallet == null) {
      throw StateError('GasFree requires an authenticated wallet');
    }
    // Only bind on a real hash. A name-only WalletId means the identity RPC was
    // momentarily unavailable, not that a different wallet is present - and
    // this runs on the withdraw path, so passing the null through resets the
    // capability session mid-money-flow and arms the securityMismatch latch.
    // `_requireVerifiedGaslessJournalIdentity` is what enforces the real
    // identity requirement before anything touches the journal.
    final pubkeyHash = wallet.pubkeyHash?.trim();
    if (pubkeyHash != null && pubkeyHash.isNotEmpty) {
      _gaslessCapabilities.ensureWalletSession(pubkeyHash);
    }
    final current = _currentWalletId;
    if (current == null) {
      _currentWalletId = wallet;
    } else if (!isSameStableWallet(current, wallet)) {
      _walletGeneration++;
      _currentWalletId = wallet;
      if (!_walletGenerationChanges.isClosed) {
        _walletGenerationChanges.add(_walletGeneration);
      }
    } else {
      _currentWalletId = preferEnrichedWalletIdentity(current, wallet);
    }
    return WalletOperationContext(
      walletId: wallet,
      generation: _walletGeneration,
    );
  }

  void _requireVerifiedGaslessJournalIdentity(WalletId walletId) {
    if (walletId.pubkeyHash?.trim().isNotEmpty ?? false) return;
    throw GaslessTransferException(
      kind: GaslessTransferErrorKind.capabilityNotReady,
      code: GaslessTransferErrorCode.capabilityNotReady,
      stage: GaslessTransferStage.recovery,
      message:
          'GasFree journal access requires a verified wallet public-key hash',
      retryable: true,
      terminal: false,
      localizationKey: 'sdk_errors.gasless_capability_not_ready',
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

  Future<void> _requireGaslessStatusContextCurrent(
    WalletOperationContext context,
    int capabilityGeneration,
  ) async {
    if (capabilityGeneration != _gaslessCapabilities.sessionGeneration) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree account status',
      );
    }
    await _requireWalletContextCurrent(context);
    if (capabilityGeneration != _gaslessCapabilities.sessionGeneration) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree account status',
      );
    }
  }

  void _requireAccountStatusProbeCurrent(AssetId assetId, int epoch) {
    if (_gaslessCapabilities.isCurrentAccountStatusProbe(assetId, epoch)) {
      return;
    }
    throw GaslessTransferException(
      kind: GaslessTransferErrorKind.capabilityNotReady,
      stage: GaslessTransferStage.status,
      message: 'Gas-free account status was superseded by a newer check',
      retryable: true,
      terminal: false,
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
  /// Fetches and validates KDF's typed GasFree account-status snapshot.
  ///
  /// Provider availability and custody-total freshness are deliberately
  /// independent: a provider outage may still carry a fresh on-chain custody
  /// balance, but it never grants GasFree spend authority.
  Future<GaslessAccountStatusResponse> gaslessAccountStatus(
    AssetId assetId,
  ) async {
    final asset = _assetProvider.findAssetsByConfigId(assetId.id).single;
    final walletContext = await _captureWalletContext();
    final capabilityGeneration = _gaslessCapabilities.sessionGeneration;
    if (!_gaslessCapabilities.isConfigured(asset)) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.capabilityNotReady,
        message: 'Gas-free transfers are not configured for ${assetId.id}',
        retryable: false,
        terminal: false,
      );
    }
    final statusEpoch = _gaslessCapabilities.beginAccountStatusProbe(assetId);
    try {
      await _requireGaslessStatusContextCurrent(
        walletContext,
        capabilityGeneration,
      );
      final status = await _client.rpc.withdraw.gaslessAccountStatus(
        coin: assetId.id,
      );
      await _requireGaslessStatusContextCurrent(
        walletContext,
        capabilityGeneration,
      );
      _requireAccountStatusProbeCurrent(assetId, statusEpoch);
      if (!_gaslessCapabilities.refreshAccountStatus(asset, status)) {
        throw GaslessTransferException(
          kind: GaslessTransferErrorKind.providerResponse,
          stage: GaslessTransferStage.status,
          message: 'Gas-free account status failed validation',
          retryable: false,
          terminal: true,
        );
      }
      return status;
    } catch (error) {
      await _requireGaslessStatusContextCurrent(
        walletContext,
        capabilityGeneration,
      );
      _requireAccountStatusProbeCurrent(assetId, statusEpoch);
      _gaslessCapabilities.markAccountStatusError(assetId, error);
      throw _mapGaslessAccountStatusError(error);
    }
  }

  GaslessTransferException _mapGaslessAccountStatusError(Object error) {
    if (error is GaslessTransferException) return error;
    if (error is FormatException || error is ArgumentError) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        code: GaslessTransferErrorCode.responseMismatch,
        stage: GaslessTransferStage.status,
        message: 'GasFree account status has an invalid response shape',
        retryable: false,
        terminal: true,
        localizationKey: 'sdk_errors.gasless_response_invalid',
      );
    }
    final (
      GaslessTransferErrorKind,
      GaslessTransferErrorCode,
      String,
      bool,
      String,
    )
    mapping = switch (error) {
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.providerIdentityMismatch,
      ) =>
        (
          GaslessTransferErrorKind.providerResponse,
          GaslessTransferErrorCode.serviceProviderMismatch,
          'GasFree provider identity does not match the configured pin',
          false,
          'sdk_errors.gasless_response_invalid',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.gasfreeAddressMismatch,
      ) =>
        (
          GaslessTransferErrorKind.providerResponse,
          GaslessTransferErrorCode.custodyAddressMismatch,
          'GasFree custody address does not match the wallet',
          false,
          'sdk_errors.gasless_response_invalid',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.tokenDecimalMismatch,
      ) =>
        (
          GaslessTransferErrorKind.providerResponse,
          GaslessTransferErrorCode.tokenDecimalMismatch,
          'GasFree token decimals do not match the activated asset',
          false,
          'sdk_errors.gasless_response_invalid',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.coinNotSupported,
      ) =>
        (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.coinNotSupported,
          'GasFree is not supported for this asset',
          false,
          'sdk_errors.gasless_token_unsupported',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.notEthCoin,
      ) =>
        (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.notEthCoin,
          'GasFree account status requires an EVM/TRON asset',
          false,
          'sdk_errors.gasless_capability_not_ready',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.gaslessNotConfigured,
      ) =>
        (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.gaslessNotConfigured,
          'GasFree requires the asset to be reactivated with provider settings',
          false,
          'sdk_errors.gasless_capability_not_ready',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.coinNotFound,
      ) =>
        (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.coinNotFound,
          'GasFree account status asset is not activated',
          false,
          'sdk_errors.gasless_capability_not_ready',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.tronRpcUnavailable,
      ) =>
        (
          GaslessTransferErrorKind.traceUnavailable,
          GaslessTransferErrorCode.tronRpcUnavailable,
          'The TRON RPC client is unavailable for GasFree account status',
          true,
          'sdk_errors.gasless_status_unavailable',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.providerError,
      ) =>
        (
          GaslessTransferErrorKind.traceUnavailable,
          GaslessTransferErrorCode.providerError,
          'The GasFree provider could not return account status',
          true,
          'sdk_errors.gasless_status_unavailable',
        ),
      GaslessAccountStatusException(
        type: GaslessAccountStatusErrorType.internalError,
      ) =>
        (
          GaslessTransferErrorKind.traceUnavailable,
          GaslessTransferErrorCode.internalError,
          'KDF could not process GasFree account status',
          false,
          'sdk_errors.gasless_status_unavailable',
        ),
      _ => (
        GaslessTransferErrorKind.traceUnavailable,
        GaslessTransferErrorCode.providerUnavailable,
        'GasFree account status is temporarily unavailable',
        true,
        'sdk_errors.gasless_status_unavailable',
      ),
    };
    return GaslessTransferException(
      kind: mapping.$1,
      code: mapping.$2,
      stage: GaslessTransferStage.status,
      message: mapping.$3,
      retryable: mapping.$4,
      terminal: !mapping.$4,
      localizationKey: mapping.$5,
    );
  }

  Future<WithdrawalPreview> previewWithdrawal(
    WithdrawParameters parameters,
  ) async {
    try {
      final asset = _assetProvider
          .findAssetsByConfigId(parameters.asset)
          .single;
      final isGasless = parameters.feeMethod == WithdrawalFeeMethod.gasless;
      if (isGasless) _validateGaslessRequestOptions(parameters);
      final walletContext = isGasless ? await _captureWalletContext() : null;
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
        if (lastStatus.details case final Exception error) {
          throw error;
        }
        final message = lastStatus.details.toString();
        throw WithdrawalException(
          isGasless ? 'GasFree withdrawal preview failed' : message,
          isGasless
              ? WithdrawalErrorCode.unknownError
              : WithdrawalException.mapErrorToCode(message),
        );
      }

      if (lastStatus.details is! WithdrawalPreview) {
        throw WithdrawalException(
          'Invalid preview response format',
          WithdrawalErrorCode.unknownError,
        );
      }

      final preview = lastStatus.details as WithdrawalPreview;
      _rejectInconsistentGaslessRailShape(preview);
      final responseIsGasless = _isGaslessPreview(preview);
      if (isGasless) {
        await _requireWalletContextCurrent(walletContext!);
        if (!responseIsGasless) {
          if (parameters.gaslessOptions?.fallbackToNative == true) {
            return preview;
          }
          throw GaslessTransferException(
            kind: GaslessTransferErrorKind.providerResponse,
            message: 'KDF returned the native rail when fallback was disabled',
            retryable: false,
            terminal: true,
            code: GaslessTransferErrorCode.responseMismatch,
            stage: GaslessTransferStage.preview,
            localizationKey: 'sdk_errors.gasless_response_invalid',
          );
        }
        _validateGaslessPreview(
          preview,
          asset,
          walletContext,
          requestedParameters: parameters,
        );
      } else if (responseIsGasless) {
        throw GaslessTransferException(
          kind: GaslessTransferErrorKind.providerResponse,
          message: 'KDF returned the GasFree rail for a Standard withdrawal',
          retryable: false,
          terminal: true,
          code: GaslessTransferErrorCode.responseMismatch,
          stage: GaslessTransferStage.preview,
          localizationKey: 'sdk_errors.gasless_response_invalid',
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
    _GaslessTraceStreamSession? traceStreamSession;
    var relayInvocationBegan = false;
    try {
      final asset = _assetProvider.findAssetsByConfigId(assetId).single;
      _rejectInconsistentGaslessRailShape(preview);
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
      }

      // Initial progress
      yield WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: isGasless
            ? 'Submitting gas-free transfer...'
            : 'Broadcasting signed transaction...',
        withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
      );

      // Persist a local journal reservation before invoking the relay. The
      // journal id and signed authorization never become KDF wire fields, and
      // the authorization itself is never written to storage.
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

      // KDF only registers traces with a streamer that exists when the relay
      // is submitted. Attach first and buffer coin events until the response
      // supplies the trace id.
      final streamingManager = _eventStreamingManager;
      if (prepared != null) {
        if (streamingManager == null) {
          throw _gaslessTraceStreamUnavailable(
            'GasFree trace streaming is not configured',
          );
        }
        try {
          traceStreamSession = await _GaslessTraceStreamSession.attach(
            streamingManager,
            assetId,
          );
        } on GaslessTraceStreamingRequestException catch (error) {
          throw _mapGaslessTraceStreamingRequestError(error);
        } on Object {
          throw _gaslessTraceStreamUnavailable(
            'GasFree trace stream could not be attached before submission',
          );
        }
        await _requireWalletContextCurrent(walletContext!);
        traceStreamSession.requireActiveForSubmission();
      }

      // Broadcast the pre-signed transaction (or relay the gas-free payload).
      final SendRawTransactionResponse response;
      try {
        relayInvocationBegan = true;
        response = await _client.rpc.withdraw.sendRawTransaction(
          coin: assetId,
          txHex: preview.txHex,
          // Submit the exact payload snapshot that passed validation. The
          // caller-owned preview map may otherwise be mutated while secure
          // persistence and stream registration are awaiting completion.
          gaslessRelayPayload: validated?.relay,
          // Raw transaction JSON is reserved for non-GasFree platform
          // transactions. GasFree always crosses this boundary as the typed
          // payload that passed validation above.
          txJson: validated == null ? preview.txJson : null,
        );
      } catch (error) {
        if (prepared == null) rethrow;
        // `send_raw_transaction` exposes plain-string failures and cannot
        // prove whether the provider accepted the relay before the response
        // was lost. Preserve the reservation and never infer retryability from
        // message text.
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
          taskId: prepared.journalId,
          sdkError: _mapError(
            GaslessTransferException(
              kind: GaslessTransferErrorKind.traceUnavailable,
              message: 'GasFree submission failed without an accepted trace',
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
            journalId: prepared.journalId,
          ),
        );
        return;
      }

      if (prepared != null) {
        final traceId = response.isGaslessRelay ? response.traceId : null;
        if (traceId == null || traceId.trim().isEmpty) {
          final unknown = prepared.copyWith(
            state: GaslessTransferState.submittedUnknown,
            updatedAt: DateTime.now().toUtc(),
          );
          await _upsertPendingGaslessTransfer(unknown);
          if (!await _isWalletContextCurrent(walletContext!)) return;
          yield WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: response.txHash == null
                ? 'Gas-free relay returned an unexpected response'
                : 'Gas-free relay unexpectedly used the native rail',
            withdrawalResult: _withdrawalResultFromPreview(preview, assetId),
            taskId: prepared.journalId,
            sdkError: _mapError(
              GaslessTransferException(
                kind: GaslessTransferErrorKind.providerResponse,
                message: 'GasFree relay response did not include a trace',
                retryable: false,
                terminal: false,
                code: GaslessTransferErrorCode.responseMismatch,
                stage: GaslessTransferStage.submission,
                localizationKey: 'sdk_errors.gasless_response_invalid',
              ),
              operation: 'withdrawal.gasless.submit',
              assetId: assetId,
            ),
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: WithdrawalSubmission.gaslessUnknown(
              journalId: prepared.journalId,
            ),
          );
          return;
        }

        final pending = prepared.copyWith(
          traceId: traceId,
          state: switch (response.state!) {
            GaslessSubmitState.confirming ||
            GaslessSubmitState.succeed => GaslessTransferState.confirming,
            GaslessSubmitState.waiting ||
            GaslessSubmitState.inProgress ||
            GaslessSubmitState.failed => GaslessTransferState.submittedPending,
          },
          updatedAt: DateTime.now().toUtc(),
        );
        final persisted = await _persistAcceptedGaslessTransfer(pending);

        if (!await _isWalletContextCurrent(walletContext!)) return;

        // Surface the accepted trace before synchronous reconciliation so the
        // app can persist/render a pending activity even if status is
        // temporarily unavailable.
        yield WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: persisted
              ? _gaslessSubmitStateMessage(response.state!)
              : 'Gas-free transfer submitted; status is temporarily unknown',
          gaslessTransferState: persisted
              ? pending.state
              : GaslessTransferState.submittedUnknown,
          taskId: traceId,
          submission: WithdrawalSubmission.gaslessRelay(
            traceId: traceId,
            journalId: pending.journalId,
          ),
          withdrawalResult: _withdrawalResultFromPreview(
            preview,
            assetId,
            gaslessTraceId: traceId,
          ),
        );

        // An accepted trace must be durable before tracking can turn it
        // into a terminal UI state. Keep the visible outcome unknown when
        // secure storage cannot confirm the write.
        if (!persisted) return;

        yield* _trackGaslessTrace(
          assetId: assetId,
          traceId: traceId,
          withdrawalResult: _withdrawalResultFromPreview(
            preview,
            assetId,
            gaslessTraceId: traceId,
          ),
          pending: pending,
          streamSession: traceStreamSession,
        );
        return;
      }

      // Final success (standard broadcast)
      if (response.isGaslessRelay || response.txHash == null) {
        throw GaslessTransferException(
          kind: GaslessTransferErrorKind.providerResponse,
          message: 'Standard withdrawal returned a GasFree relay response',
          retryable: false,
          terminal: true,
          code: GaslessTransferErrorCode.responseMismatch,
          stage: GaslessTransferStage.submission,
        );
      }
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
            operationPending.journalId,
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
    } finally {
      await traceStreamSession?.close();
    }
  }

  /// Whether [preview] represents a gas-free (gasless) transfer that must be
  /// relayed (rather than directly broadcast) and then tracked.
  bool _isGaslessPreview(WithdrawalPreview preview) =>
      preview.fee is FeeInfoTronGasless;

  /// Rejects a raw GasFree relay marker paired with non-GasFree fee details.
  ///
  /// The fee union is the typed rail discriminator. Looking at raw relay JSON
  /// is restricted to rejecting an inconsistent response; it must never
  /// select the GasFree happy path.
  void _rejectInconsistentGaslessRailShape(WithdrawalPreview preview) {
    if (!_isGaslessPreview(preview) &&
        preview.txJson?['relay_type'] ==
            TronGasfreeRelayPayload.relayTypeValue) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        message:
            'GasFree relay payload is inconsistent with the withdrawal fee',
        retryable: false,
        terminal: true,
        code: GaslessTransferErrorCode.responseMismatch,
        stage: GaslessTransferStage.preview,
        localizationKey: 'sdk_errors.gasless_response_invalid',
      );
    }
  }

  /// Builds a [WithdrawalResult] from a preview, optionally overriding the
  /// (on-chain) [txHash] and final [fee].
  WithdrawalResult _withdrawalResultFromPreview(
    WithdrawalPreview preview,
    String assetId, {
    String? txHash,
    FeeInfo? fee,
    String? gaslessTraceId,
  }) {
    final isGasless = _isGaslessPreview(preview);
    return WithdrawalResult(
      txHash: txHash ?? (isGasless ? null : preview.txHash),
      balanceChanges: preview.balanceChanges,
      coin: assetId,
      toAddress: preview.to.isNotEmpty ? preview.to.first : '',
      fee: fee ?? preview.fee,
      kmdRewardsEligible:
          preview.kmdRewards != null &&
          Decimal.parse(preview.kmdRewards!.amount) > Decimal.zero,
      confirmationBlockHeight: !isGasless && preview.blockHeight > 0
          ? preview.blockHeight
          : null,
      confirmedAt: !isGasless && preview.timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              preview.timestamp * 1000,
              isUtc: true,
            )
          : null,
      gaslessTraceId: gaslessTraceId,
    );
  }

  /// Reconciles once immediately, then follows the trace stream registered
  /// before relay submission. No timer-based client polling is used.
  Stream<WithdrawalProgress> _trackGaslessTrace({
    required String assetId,
    required String traceId,
    required WithdrawalResult withdrawalResult,
    required PendingGaslessTransfer pending,
    _GaslessTraceStreamSession? streamSession,
  }) async* {
    var current = pending;
    final initial = await _reconcileGaslessTraceOnce(
      assetId: assetId,
      traceId: traceId,
      withdrawalResult: withdrawalResult,
      pending: current,
    );
    current = initial.pending;
    if (!await _isPendingWalletCurrent(current)) return;
    if (initial.isTerminal) {
      final terminalWallet = _pendingGaslessWallets[current.journalId];
      await _removePendingGaslessTransfer(traceId);
      if (terminalWallet == null || !await _isWalletIdCurrent(terminalWallet)) {
        return;
      }
    }
    yield initial.progress;
    if (initial.isTerminal || streamSession == null) return;

    try {
      await for (final event in streamSession.forTrace(assetId, traceId)) {
        if (!await _isPendingWalletCurrent(current)) return;
        if (event is GaslessTraceErrorEvent) {
          // KDF removes a trace after its bounded provider-error limit but
          // leaves the coin-level stream open. Every typed error therefore
          // ends this live trace session; recover once through the
          // authoritative status endpoint below without inspecting its text.
          break;
        }
        if (event is! GaslessTraceEvent) continue;
        final applied = await _applyGaslessTraceSnapshot(
          snapshot: _GaslessTraceSnapshot.fromEvent(event),
          withdrawalResult: withdrawalResult,
          pending: current,
        );
        current = applied.pending;
        if (!await _isPendingWalletCurrent(current)) return;
        if (!applied.wasApplied) continue;
        if (applied.isTerminal) {
          final terminalWallet = _pendingGaslessWallets[current.journalId];
          await _removePendingGaslessTransfer(traceId);
          if (terminalWallet == null ||
              !await _isWalletIdCurrent(terminalWallet)) {
            return;
          }
        }
        yield applied.progress;
        if (applied.isTerminal) return;
      }
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (_) {
      // A disconnected stream gets one authoritative status reconciliation.
    }

    final fallback = await _reconcileGaslessTraceOnce(
      assetId: assetId,
      traceId: traceId,
      withdrawalResult: withdrawalResult,
      pending: current,
    );
    if (!await _isPendingWalletCurrent(fallback.pending)) return;
    if (fallback.isTerminal) {
      final terminalWallet = _pendingGaslessWallets[fallback.pending.journalId];
      await _removePendingGaslessTransfer(traceId);
      if (terminalWallet == null || !await _isWalletIdCurrent(terminalWallet)) {
        return;
      }
    }
    yield fallback.progress;
  }

  Future<_AppliedGaslessTrace> _reconcileGaslessTraceOnce({
    required String assetId,
    required String traceId,
    required WithdrawalResult withdrawalResult,
    required PendingGaslessTransfer pending,
  }) async {
    if (!await _isPendingWalletCurrent(pending)) {
      throw const WalletChangedDisconnectException(
        'Wallet changed during GasFree trace reconciliation',
      );
    }
    try {
      final status = await _client.rpc.withdraw.gaslessTraceStatus(
        coin: assetId,
        traceId: traceId,
      );
      if (!await _isPendingWalletCurrent(pending)) {
        throw const WalletChangedDisconnectException(
          'Wallet changed during GasFree trace reconciliation',
        );
      }
      return _applyGaslessTraceSnapshot(
        snapshot: _GaslessTraceSnapshot.fromResponse(status),
        withdrawalResult: withdrawalResult,
        pending: pending,
      );
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (error) {
      if (!await _isPendingWalletCurrent(pending)) {
        throw const WalletChangedDisconnectException(
          'Wallet changed during GasFree trace reconciliation',
        );
      }
      // An RPC error supplies no lifecycle evidence. Retain any accepted,
      // submitted, or on-chain state already established by KDF.
      final retained = switch (pending.state) {
        GaslessTransferState.preparing ||
        GaslessTransferState.rejectedBeforeRelay => pending.copyWith(
          state: GaslessTransferState.submittedUnknown,
          updatedAt: DateTime.now().toUtc(),
        ),
        GaslessTransferState.submittedPending ||
        GaslessTransferState.submittedUnknown ||
        GaslessTransferState.confirming ||
        GaslessTransferState.confirmed ||
        GaslessTransferState.failedFinal => pending,
      };
      if (retained.state != pending.state) {
        await _upsertPendingGaslessTransfer(retained);
        if (!await _isPendingWalletCurrent(retained)) {
          throw const WalletChangedDisconnectException(
            'Wallet changed during GasFree trace reconciliation',
          );
        }
      }
      return _AppliedGaslessTrace(
        pending: retained,
        wasApplied: false,
        progress: _gaslessTraceUnavailableProgress(
          assetId: assetId,
          traceId: traceId,
          withdrawalResult: withdrawalResult,
          pending: retained,
          error: _mapGaslessTraceStatusError(error, traceId),
        ),
      );
    }
  }

  Future<_AppliedGaslessTrace> _applyGaslessTraceSnapshot({
    required _GaslessTraceSnapshot snapshot,
    required WithdrawalResult withdrawalResult,
    required PendingGaslessTransfer pending,
  }) async {
    final traceId = pending.traceId!;
    final submission = WithdrawalSubmission.gaslessRelay(
      traceId: traceId,
      journalId: pending.journalId,
    );

    // The stream is attached before submission, so it may contain a snapshot
    // older than the immediate one-shot reconciliation. Never let that buffer
    // move the durable journal or visible progress backwards.
    if (snapshot.state != GaslessTraceState.confirmed &&
        snapshot.state != GaslessTraceState.failed &&
        _gaslessTraceRank(snapshot.state) < _pendingGaslessTraceRank(pending)) {
      final retainedState = _traceStateForPendingTransfer(pending);
      return _AppliedGaslessTrace(
        pending: pending,
        wasApplied: false,
        progress: WithdrawalProgress(
          status: WithdrawalStatus.inProgress,
          message: _gaslessStateMessage(retainedState),
          gaslessState: retainedState,
          taskId: traceId,
          withdrawalResult: withdrawalResult,
          gaslessTransferState: pending.state,
          submission: submission,
        ),
      );
    }

    if (snapshot.state == GaslessTraceState.confirmed) {
      final finalFee = snapshot.finalFee;
      final onChainHash = snapshot.txHashOnChain;
      final confirmedAtSeconds = snapshot.confirmedAt;
      final confirmedAt = confirmedAtSeconds == null
          ? null
          : _gaslessConfirmedAt(confirmedAtSeconds);
      if ((finalFee != null &&
              (finalFee < Decimal.zero || finalFee > pending.signedMaxFee)) ||
          (onChainHash != null && onChainHash.trim().isEmpty) ||
          (confirmedAtSeconds != null && confirmedAtSeconds < 0)) {
        final unknown = pending.copyWith(
          state: GaslessTransferState.submittedUnknown,
          updatedAt: DateTime.now().toUtc(),
        );
        await _upsertPendingGaslessTransfer(unknown);
        return _AppliedGaslessTrace(
          pending: unknown,
          progress: WithdrawalProgress(
            status: WithdrawalStatus.inProgress,
            message: 'Gas-free confirmation requires support review',
            withdrawalResult: withdrawalResult,
            taskId: traceId,
            sdkError: _mapError(
              GaslessTransferException(
                kind: GaslessTransferErrorKind.providerResponse,
                message: finalFee != null && finalFee < Decimal.zero
                    ? 'GasFree final fee is negative'
                    : finalFee != null && finalFee > pending.signedMaxFee
                    ? 'GasFree final fee exceeds the signed maximum'
                    : confirmedAtSeconds != null && confirmedAtSeconds < 0
                    ? 'GasFree confirmation timestamp is negative'
                    : 'GasFree confirmation included an invalid transaction hash',
                retryable: false,
                terminal: false,
                traceId: traceId,
              ),
              operation: 'withdrawal.gasless.trace',
              assetId: pending.assetId,
            ),
            gaslessState: snapshot.state,
            gaslessTransferState: GaslessTransferState.submittedUnknown,
            submission: submission,
          ),
        );
      }
      // Construct the complete terminal result before deleting its recovery
      // record. Any malformed provider value must leave the journal durable
      // and non-resubmittable.
      final applied = _AppliedGaslessTrace(
        pending: pending.copyWith(
          state: GaslessTransferState.confirmed,
          updatedAt: DateTime.now().toUtc(),
        ),
        isTerminal: true,
        progress: WithdrawalProgress(
          status: WithdrawalStatus.complete,
          message: 'Withdrawal complete',
          withdrawalResult: WithdrawalResult(
            txHash: onChainHash,
            balanceChanges: withdrawalResult.balanceChanges,
            coin: withdrawalResult.coin,
            toAddress: withdrawalResult.toAddress,
            fee: withdrawalResult.fee,
            gaslessFinalFee: finalFee,
            gaslessTraceId: traceId,
            kmdRewardsEligible: withdrawalResult.kmdRewardsEligible,
            confirmationBlockHeight: snapshot.blockHeight,
            confirmedAt: confirmedAt,
          ),
          taskId: traceId,
          gaslessState: snapshot.state,
          gaslessTransferState: GaslessTransferState.confirmed,
          submission: submission,
        ),
      );
      return applied;
    }

    if (snapshot.state == GaslessTraceState.failed) {
      return _AppliedGaslessTrace(
        pending: pending.copyWith(
          state: GaslessTransferState.failedFinal,
          updatedAt: DateTime.now().toUtc(),
        ),
        isTerminal: true,
        progress: WithdrawalProgress(
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
            assetId: pending.assetId,
          ),
          gaslessState: snapshot.state,
          gaslessTransferState: GaslessTransferState.failedFinal,
          submission: submission,
        ),
      );
    }

    final transferState = snapshot.state == GaslessTraceState.onChain
        ? GaslessTransferState.confirming
        : GaslessTransferState.submittedPending;
    final updated = pending.copyWith(
      state: transferState,
      updatedAt: DateTime.now().toUtc(),
    );
    await _upsertPendingGaslessTransfer(updated);
    return _AppliedGaslessTrace(
      pending: updated,
      progress: WithdrawalProgress(
        status: WithdrawalStatus.inProgress,
        message: _gaslessStateMessage(snapshot.state),
        gaslessState: snapshot.state,
        taskId: traceId,
        withdrawalResult: withdrawalResult,
        gaslessTransferState: transferState,
        submission: submission,
      ),
    );
  }

  DateTime? _gaslessConfirmedAt(int secondsSinceEpoch) {
    if (secondsSinceEpoch < 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        secondsSinceEpoch * Duration.millisecondsPerSecond,
        isUtc: true,
      );
    } on ArgumentError {
      // KDF's confirmed state is authoritative even when its optional u64
      // timestamp cannot be represented by this Dart runtime.
      return null;
    }
  }

  int _gaslessTraceRank(GaslessTraceState state) => switch (state) {
    GaslessTraceState.pending => 0,
    GaslessTraceState.submitted => 1,
    GaslessTraceState.onChain => 2,
    GaslessTraceState.confirmed || GaslessTraceState.failed => 3,
  };

  int _pendingGaslessTraceRank(PendingGaslessTransfer pending) =>
      switch (pending.state) {
        GaslessTransferState.preparing ||
        GaslessTransferState.rejectedBeforeRelay ||
        GaslessTransferState.submittedUnknown => -1,
        GaslessTransferState.submittedPending => 1,
        GaslessTransferState.confirming => 2,
        GaslessTransferState.confirmed || GaslessTransferState.failedFinal => 3,
      };

  GaslessTraceState _traceStateForPendingTransfer(
    PendingGaslessTransfer pending,
  ) => switch (pending.state) {
    GaslessTransferState.confirming => GaslessTraceState.onChain,
    GaslessTransferState.confirmed => GaslessTraceState.confirmed,
    GaslessTransferState.failedFinal => GaslessTraceState.failed,
    GaslessTransferState.preparing ||
    GaslessTransferState.rejectedBeforeRelay ||
    GaslessTransferState.submittedPending ||
    GaslessTransferState.submittedUnknown => GaslessTraceState.submitted,
  };

  WithdrawalProgress _gaslessTraceUnavailableProgress({
    required String assetId,
    required String traceId,
    required WithdrawalResult withdrawalResult,
    required PendingGaslessTransfer pending,
    GaslessTransferException? error,
  }) {
    final traceError =
        error ??
        GaslessTransferException(
          kind: GaslessTransferErrorKind.traceUnavailable,
          code: GaslessTransferErrorCode.traceUnavailable,
          stage: GaslessTransferStage.status,
          message: 'GasFree transfer status could not be reconciled',
          retryable: false,
          terminal: false,
          localizationKey: 'sdk_errors.gasless_status_unavailable',
          traceId: traceId,
        );
    return WithdrawalProgress(
      status: WithdrawalStatus.inProgress,
      message: traceError.message,
      withdrawalResult: withdrawalResult,
      taskId: traceId,
      sdkError: _mapError(
        traceError,
        operation: 'withdrawal.gasless.trace',
        assetId: assetId,
      ),
      gaslessTransferState: pending.state,
      submission: WithdrawalSubmission.gaslessRelay(
        traceId: traceId,
        journalId: pending.journalId,
      ),
    );
  }

  GaslessTransferException _mapGaslessTraceStatusError(
    Object error,
    String traceId,
  ) {
    // `retryable` in this status-only path means that reconciliation may be
    // attempted again. The accepted relay and its journal are never retried.
    if (error is GaslessTransferException) {
      final retryable =
          error.code == GaslessTransferErrorCode.providerError ||
          error.code == GaslessTransferErrorCode.providerUnavailable ||
          error.code == GaslessTransferErrorCode.providerTimeout;
      return GaslessTransferException(
        kind: error.kind,
        code: error.code,
        stage: GaslessTransferStage.status,
        message: error.message,
        retryable: retryable,
        terminal: false,
        localizationKey: error.localizationKey,
        traceId: traceId,
      );
    }
    if (error is FormatException || error is ArgumentError) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        code: GaslessTransferErrorCode.responseMismatch,
        stage: GaslessTransferStage.status,
        message: 'GasFree trace status has an invalid response shape',
        retryable: false,
        terminal: false,
        localizationKey: 'sdk_errors.gasless_response_invalid',
        traceId: traceId,
      );
    }
    if (error is TimeoutException) {
      return GaslessTransferException(
        kind: GaslessTransferErrorKind.traceUnavailable,
        code: GaslessTransferErrorCode.providerTimeout,
        stage: GaslessTransferStage.status,
        message: 'GasFree trace status timed out',
        retryable: true,
        terminal: false,
        localizationKey: 'sdk_errors.gasless_status_unavailable',
        traceId: traceId,
      );
    }
    if (error is GaslessTraceStatusException) {
      final (
        GaslessTransferErrorKind,
        GaslessTransferErrorCode,
        String,
        bool,
        String,
      )
      mapping = switch (error.type) {
        GaslessTraceStatusErrorType.traceNotFound => (
          GaslessTransferErrorKind.invalidTrace,
          GaslessTransferErrorCode.traceNotFound,
          'GasFree trace was not found',
          false,
          'sdk_errors.gasless_response_invalid',
        ),
        GaslessTraceStatusErrorType.invalidTraceId => (
          GaslessTransferErrorKind.invalidTrace,
          GaslessTransferErrorCode.invalidTraceId,
          'GasFree trace ID is invalid',
          false,
          'sdk_errors.gasless_response_invalid',
        ),
        GaslessTraceStatusErrorType.coinNotFound => (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.coinNotFound,
          'GasFree trace asset is not activated',
          false,
          'sdk_errors.gasless_capability_not_ready',
        ),
        GaslessTraceStatusErrorType.notEthCoin => (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.notEthCoin,
          'GasFree trace asset has an unsupported protocol',
          false,
          'sdk_errors.gasless_capability_not_ready',
        ),
        GaslessTraceStatusErrorType.coinNotSupported => (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.coinNotSupported,
          'GasFree trace asset is not supported',
          false,
          'sdk_errors.gasless_token_unsupported',
        ),
        GaslessTraceStatusErrorType.gaslessNotConfigured => (
          GaslessTransferErrorKind.configuration,
          GaslessTransferErrorCode.gaslessNotConfigured,
          'GasFree trace provider is not configured',
          false,
          'sdk_errors.gasless_capability_not_ready',
        ),
        GaslessTraceStatusErrorType.providerError => (
          GaslessTransferErrorKind.traceUnavailable,
          GaslessTransferErrorCode.providerError,
          'GasFree provider could not return the trace status',
          true,
          'sdk_errors.gasless_status_unavailable',
        ),
        GaslessTraceStatusErrorType.internalError => (
          GaslessTransferErrorKind.traceUnavailable,
          GaslessTransferErrorCode.internalError,
          'KDF could not process the GasFree trace status',
          false,
          'sdk_errors.gasless_status_unavailable',
        ),
      };
      return GaslessTransferException(
        kind: mapping.$1,
        code: mapping.$2,
        stage: GaslessTransferStage.status,
        message: mapping.$3,
        retryable: mapping.$4,
        terminal: false,
        localizationKey: mapping.$5,
        traceId: traceId,
      );
    }
    // Unknown failures provide no evidence about lifecycle or connectivity.
    // Keep the accepted trace recoverable without advertising a retry.
    return GaslessTransferException(
      kind: GaslessTransferErrorKind.traceUnavailable,
      code: GaslessTransferErrorCode.traceUnavailable,
      stage: GaslessTransferStage.status,
      message: 'GasFree transfer status could not be reconciled',
      retryable: false,
      terminal: false,
      localizationKey: 'sdk_errors.gasless_status_unavailable',
      traceId: traceId,
    );
  }

  GaslessTransferException _gaslessTraceStreamUnavailable(String message) =>
      GaslessTransferException(
        kind: GaslessTransferErrorKind.traceUnavailable,
        code: GaslessTransferErrorCode.traceUnavailable,
        stage: GaslessTransferStage.submission,
        message: message,
        retryable: true,
        terminal: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      );

  GaslessTransferException _mapGaslessTraceStreamingRequestError(
    GaslessTraceStreamingRequestException error,
  ) {
    final (
      GaslessTransferErrorKind,
      GaslessTransferErrorCode,
      String,
      bool,
      String,
    )
    mapping = switch (error.type) {
      GaslessTraceStreamingRequestErrorType.enableError => (
        GaslessTransferErrorKind.traceUnavailable,
        GaslessTransferErrorCode.traceStreamEnableError,
        'KDF could not enable GasFree trace streaming',
        true,
        'sdk_errors.gasless_capability_not_ready',
      ),
      GaslessTraceStreamingRequestErrorType.coinNotFound => (
        GaslessTransferErrorKind.configuration,
        GaslessTransferErrorCode.coinNotFound,
        'The GasFree trace-stream coin was not found',
        false,
        'sdk_errors.gasless_capability_not_ready',
      ),
      GaslessTraceStreamingRequestErrorType.coinNotSupported => (
        GaslessTransferErrorKind.configuration,
        GaslessTransferErrorCode.coinNotSupported,
        'GasFree trace streaming is not supported for this coin',
        false,
        'sdk_errors.gasless_token_unsupported',
      ),
      GaslessTraceStreamingRequestErrorType.gaslessNotConfigured => (
        GaslessTransferErrorKind.configuration,
        GaslessTransferErrorCode.gaslessNotConfigured,
        'GasFree is not configured for trace streaming',
        false,
        'sdk_errors.gasless_capability_not_ready',
      ),
      GaslessTraceStreamingRequestErrorType.internal => (
        GaslessTransferErrorKind.traceUnavailable,
        GaslessTransferErrorCode.traceStreamInternal,
        'KDF returned an internal GasFree trace-stream error',
        false,
        'sdk_errors.gasless_capability_not_ready',
      ),
    };
    return GaslessTransferException(
      kind: mapping.$1,
      code: mapping.$2,
      stage: GaslessTransferStage.submission,
      message: mapping.$3,
      retryable: mapping.$4,
      terminal: false,
      localizationKey: mapping.$5,
    );
  }

  String _gaslessStateMessage(GaslessTraceState state) => switch (state) {
    GaslessTraceState.pending => 'Awaiting gas-free relay...',
    GaslessTraceState.submitted => 'Gas-free transfer submitted...',
    GaslessTraceState.onChain => 'Confirming on chain...',
    GaslessTraceState.confirmed => 'Confirmed',
    GaslessTraceState.failed => 'Failed',
  };

  String _gaslessSubmitStateMessage(GaslessSubmitState state) =>
      switch (state) {
        GaslessSubmitState.waiting => 'Awaiting gas-free relay...',
        GaslessSubmitState.inProgress => 'Gas-free relay in progress...',
        GaslessSubmitState.confirming => 'Confirming gas-free transfer...',
        GaslessSubmitState.succeed => 'Gas-free relay accepted...',
        GaslessSubmitState.failed =>
          'Gas-free relay status requires reconciliation...',
      };

  /// Unresolved GasFree transfers for the currently signed-in wallet.
  Future<List<PendingGaslessTransfer>> listPendingGaslessTransfers() async {
    final repository = _pendingGaslessTransfers;
    if (repository == null || _walletIdResolver == null) {
      return const <PendingGaslessTransfer>[];
    }
    final walletContext = await _captureWalletContext();
    final walletId = walletContext.walletId;
    _requireVerifiedGaslessJournalIdentity(walletId);
    await _resolveAmbiguousLegacyTransfers(repository, walletContext);
    final transfers = await repository.list(walletId);
    await _requireWalletContextCurrent(walletContext);
    for (final transfer in transfers) {
      _pendingGaslessWallets[transfer.journalId] = walletId;
      final traceId = transfer.traceId;
      if (traceId != null) _pendingGaslessWallets[traceId] = walletId;
    }
    return transfers;
  }

  /// Clears a GasFree journal reservation the SDK cannot resolve on its own.
  ///
  /// A reservation is written *before* the relay round-trip, so a process death
  /// in that window leaves a record with `traceId == null`. Such a record is
  /// deliberately non-terminal and non-resubmittable: without a KDF trace the
  /// SDK cannot prove the transfer was never relayed, and
  /// `PendingGaslessTransferRepository.reserve` refuses every later send for
  /// the same asset + custody address to prevent a blind resubmit. Correct -
  /// but with no way out it leaves gas-free permanently dead for that address.
  ///
  /// This is that way out, and it is deliberately explicit rather than a
  /// timer or a sweep: only the user can tell, from their balance and history,
  /// whether the original transfer actually landed. Surface the record from
  /// [listPendingGaslessTransfers], show them what it was, and call this only
  /// on their acknowledgement.
  ///
  /// Refuses a record that still carries a `traceId` - that one is
  /// reconcilable, so [reconcilePendingGaslessTransfers] must resolve it
  /// instead. Returns whether a record was removed.
  Future<bool> discardPendingGaslessTransfer(String journalId) async {
    final repository = _pendingGaslessTransfers;
    if (repository == null || _walletIdResolver == null) return false;

    final walletContext = await _captureWalletContext();
    final walletId = walletContext.walletId;
    _requireVerifiedGaslessJournalIdentity(walletId);

    final pending = await repository.find(walletId, journalId);
    if (pending == null) return false;
    if (pending.traceId != null) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.capabilityNotReady,
        code: GaslessTransferErrorCode.capabilityNotReady,
        stage: GaslessTransferStage.recovery,
        message:
            'Transfer $journalId carries a relay trace and must be reconciled, '
            'not discarded.',
        retryable: false,
        terminal: false,
        localizationKey: 'sdk_errors.gasless_capability_not_ready',
      );
    }

    await _requireWalletContextCurrent(walletContext);
    await _removePendingGaslessTransfer(journalId);
    return true;
  }

  /// Wallet-scoped journal updates for app-wide pending activity surfaces.
  Stream<List<PendingGaslessTransfer>> watchPendingGaslessTransfers() async* {
    final repository = _pendingGaslessTransfers;
    if (repository == null || _walletIdResolver == null) {
      yield const <PendingGaslessTransfer>[];
      return;
    }
    final walletContext = await _captureWalletContext();
    _requireVerifiedGaslessJournalIdentity(walletContext.walletId);
    await _resolveAmbiguousLegacyTransfers(repository, walletContext);
    final events =
        StreamController<
          ({List<PendingGaslessTransfer>? transfers, bool walletChanged})
        >();
    final repositorySubscription = repository
        .watch(walletContext.walletId)
        .listen(
          (transfers) {
            if (!events.isClosed) {
              events.add((transfers: transfers, walletChanged: false));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!events.isClosed) events.addError(error, stackTrace);
          },
          onDone: () {
            if (!events.isClosed) unawaited(events.close());
          },
        );
    final walletSubscription = _walletGenerationChanges.stream
        .where((generation) => generation != walletContext.generation)
        .listen((_) {
          if (!events.isClosed) {
            events.add((transfers: null, walletChanged: true));
          }
        });
    try {
      await for (final event in events.stream) {
        if (event.walletChanged) {
          // Clear wallet-scoped activity immediately. The auth flow can
          // subscribe again for the new wallet after this stream terminates.
          yield const <PendingGaslessTransfer>[];
          return;
        }
        await _requireWalletContextCurrent(walletContext);
        yield event.transfers!;
      }
    } finally {
      // Cancellation starts synchronously, but an async-generator
      // subscription can keep its cancellation future pending while paused at
      // a yield. Do not hold wallet-switch stream completion behind it.
      unawaited(repositorySubscription.cancel());
      unawaited(walletSubscription.cancel());
      if (!events.isClosed) unawaited(events.close());
    }
  }

  /// Resume authoritative trace reconciliation for an accepted GasFree relay.
  Stream<WithdrawalProgress> resumePendingGaslessTransfer(
    String identity,
  ) async* {
    final repository = _pendingGaslessTransfers;
    if (repository == null || _walletIdResolver == null) {
      throw StateError('No signed-in wallet is available for reconciliation');
    }
    final walletContext = await _captureWalletContext();
    final walletId = walletContext.walletId;
    _requireVerifiedGaslessJournalIdentity(walletId);
    await _resolveAmbiguousLegacyTransfers(repository, walletContext);
    final pending = await repository.find(walletId, identity);
    await _requireWalletContextCurrent(walletContext);
    if (pending == null) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.invalidTrace,
        message: 'Pending GasFree transfer was not found',
        retryable: false,
        terminal: false,
        traceId: identity,
      );
    }

    _pendingGaslessWallets[pending.journalId] = walletId;
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
        taskId: pending.journalId,
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
          journalId: pending.journalId,
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
      gaslessTraceId: traceId,
    );
    yield WithdrawalProgress(
      status: WithdrawalStatus.inProgress,
      message: 'Checking gas-free transfer status...',
      withdrawalResult: result,
      taskId: traceId,
      gaslessTransferState: pending.state,
      submission: WithdrawalSubmission.gaslessRelay(
        traceId: traceId,
        journalId: pending.journalId,
      ),
    );
    final reconciled = await _reconcileGaslessTraceOnce(
      assetId: pending.assetId,
      traceId: traceId,
      withdrawalResult: result,
      pending: pending,
    );
    await _requireWalletContextCurrent(walletContext);
    if (reconciled.isTerminal) {
      // The terminal progress has already been fully constructed and validated
      // at this point. Delete only under the same wallet context, then recheck
      // before exposing completion to the caller.
      await _removePendingGaslessTransfer(traceId);
      await _requireWalletContextCurrent(walletContext);
    }
    yield reconciled.progress;
  }

  /// Reconcile every unresolved transfer for the current wallet in order.
  Stream<WithdrawalProgress> reconcilePendingGaslessTransfers() async* {
    final pending = await listPendingGaslessTransfers();
    for (final transfer in pending) {
      yield* resumePendingGaslessTransfer(
        transfer.traceId ?? transfer.journalId,
      );
    }
  }

  PendingGaslessTransfer _pendingTransferFromPreview({
    required WithdrawalPreview preview,
    required String assetId,
    required String? traceId,
    required String journalId,
    required TronGasfreeRelayPayload relay,
    required Decimal authorizationMaxFee,
    GaslessTransferState state = GaslessTransferState.submittedPending,
  }) {
    final now = DateTime.now().toUtc();
    return PendingGaslessTransfer(
      traceId: traceId,
      journalId: journalId,
      assetId: assetId,
      network: relay.chainId,
      sourceAddress: relay.fromAddress,
      custodyAddress: relay.gasfreeAddress,
      destinationAddress: relay.signedAuthorization.receiver,
      requestedAmount: preview.balanceChanges.totalAmount,
      signedMaxFee: authorizationMaxFee,
      authorizationDeadline: relay.signedAuthorization.deadline,
      balanceChanges: preview.balanceChanges,
      fee: preview.fee,
      acceptedAt: now,
      updatedAt: now,
      state: state,
    );
  }

  _ValidatedGaslessPreview _validateGaslessPreview(
    WithdrawalPreview preview,
    Asset asset,
    WalletOperationContext walletContext, {
    WithdrawParameters? requestedParameters,
  }) {
    final assetId = asset.id.id;
    final relay = preview.gaslessRelayPayload;
    if (relay == null) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        message: 'GasFree signed preview has no relay payload',
        retryable: false,
        terminal: true,
        code: GaslessTransferErrorCode.invalidSignedPreview,
        stage: GaslessTransferStage.preview,
        localizationKey: 'sdk_errors.gasless_preview_invalid',
      );
    }
    final auth = relay.signedAuthorization;
    final gaslessFee = preview.fee is FeeInfoTronGasless
        ? preview.fee as FeeInfoTronGasless
        : null;
    final authorizationMaxFee = Decimal.tryParse(
      _tokenBaseUnitsToDecimalString(auth.maxFee, asset.id.chainId.decimals) ??
          '',
    );
    final authorizationAmount = Decimal.tryParse(
      _tokenBaseUnitsToDecimalString(auth.value, asset.id.chainId.decimals) ??
          '',
    );
    final authorizationNonce = _parseUnsigned256(auth.nonce);
    final sourceMatches =
        relay.fromAddress == auth.user &&
        preview.from.length == 1 &&
        preview.from.single == auth.user;
    final custodyMatches =
        gaslessFee != null && gaslessFee.gasfreeAddress == relay.gasfreeAddress;
    final receiverMatches =
        preview.to.length == 1 && auth.receiver == preview.to.single;
    final amountMatches =
        authorizationAmount != null &&
        authorizationAmount > Decimal.zero &&
        authorizationAmount == preview.balanceChanges.totalAmount;
    final requestMatches =
        requestedParameters == null ||
        requestedParameters.asset == assetId &&
            requestedParameters.feeMethod == WithdrawalFeeMethod.gasless &&
            preview.coin == requestedParameters.asset &&
            preview.to.length == 1 &&
            preview.to.single == requestedParameters.toAddress &&
            ((requestedParameters.isMax ?? false)
                ? requestedParameters.amount == null
                : requestedParameters.amount != null &&
                      requestedParameters.amount ==
                          preview.balanceChanges.totalAmount);
    final requestedSource = requestedParameters?.from?.toRpcParams();
    final sourceSelectorMatches =
        requestedParameters == null ||
        const DeepCollectionEquality().equals(relay.hdFrom, requestedSource);
    final maxFeeMatches =
        gaslessFee != null &&
        authorizationMaxFee != null &&
        authorizationMaxFee >= Decimal.zero &&
        gaslessFee.signedMaxFee >= Decimal.zero &&
        authorizationMaxFee == gaslessFee.signedMaxFee;
    final requestedMaxFee = requestedParameters?.gaslessOptions?.maxFee;
    final requestedMaxFeeMatches =
        requestedMaxFee == null ||
        requestedMaxFee >= Decimal.zero &&
            authorizationMaxFee != null &&
            authorizationMaxFee <= requestedMaxFee;
    final activationFee = gaslessFee?.activationFee ?? Decimal.zero;
    final feeBreakdownMatches =
        gaslessFee != null &&
        gaslessFee.transferFee >= Decimal.zero &&
        activationFee >= Decimal.zero &&
        gaslessFee.totalTokenFee >= Decimal.zero &&
        gaslessFee.totalTokenFee == gaslessFee.transferFee + activationFee &&
        authorizationMaxFee != null &&
        gaslessFee.totalTokenFee <= authorizationMaxFee;
    final createdAt = DateTime.tryParse(relay.createdAt)?.toUtc();
    final requestedDeadlineSeconds =
        requestedParameters?.gaslessOptions?.deadlineSeconds;
    final allowedDeadlineSeconds =
        requestedDeadlineSeconds ?? _defaultGaslessDeadlineSeconds;
    final nowSeconds =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
    final createdAtSeconds = createdAt == null
        ? null
        : createdAt.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    final createdAtDeadline = createdAtSeconds == null
        ? null
        : BigInt.from(createdAtSeconds);
    final deadlineMatches =
        requestedDeadlineSeconds != null && requestedDeadlineSeconds <= 0
        ? false
        : createdAtSeconds != null &&
              createdAtDeadline != null &&
              createdAtSeconds <=
                  nowSeconds + _gaslessDeadlineClockSkewSeconds &&
              auth.deadline > createdAtDeadline &&
              (requestedParameters == null ||
                  auth.deadline <=
                      BigInt.from(
                        createdAtSeconds +
                            allowedDeadlineSeconds +
                            _gaslessDeadlineClockSkewSeconds,
                      ));
    final signature = auth.signature;
    final signatureShapeValid =
        signature.length == 130 &&
        RegExp(r'^[0-9a-f]+$', caseSensitive: false).hasMatch(signature);
    final feeContextMatches =
        gaslessFee != null &&
        gaslessFee.coin == assetId &&
        gaslessFee.feeMethod == 'gasless' &&
        gaslessFee.providerName == 'gasfree';
    final walletPubkeyHash = walletContext.walletId.pubkeyHash?.trim();
    final status = _gaslessCapabilities.statusFor(asset.id);
    final protocol = asset.protocol;
    final contract = protocol is Trc20Protocol
        ? protocol.contractAddress
        : null;
    final capabilityContextMatches =
        walletPubkeyHash != null &&
        walletPubkeyHash.isNotEmpty &&
        _gaslessCapabilities.isConfigured(asset) &&
        (status == null || status.gasfreeAddress == relay.gasfreeAddress) &&
        (status?.serviceProvider == null ||
            status!.serviceProvider == auth.serviceProvider) &&
        contract == auth.token;
    final walletSourceTypeMatches =
        walletContext.walletId.authOptions.derivationMethod ==
            DerivationMethod.hdWallet ||
        relay.hdFrom == null;
    if (relay.coin != assetId ||
        preview.coin != assetId ||
        preview.txHex != null ||
        preview.txHash != null ||
        !receiverMatches ||
        !sourceMatches ||
        !custodyMatches ||
        !amountMatches ||
        !requestMatches ||
        !sourceSelectorMatches ||
        !maxFeeMatches ||
        !requestedMaxFeeMatches ||
        !feeBreakdownMatches ||
        !deadlineMatches ||
        !feeContextMatches ||
        !capabilityContextMatches ||
        !walletSourceTypeMatches ||
        authorizationNonce == null ||
        !signatureShapeValid) {
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
    if (auth.isExpiredAt(DateTime.now().toUtc())) {
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
    return _ValidatedGaslessPreview(relay, authorizationMaxFee);
  }

  void _validateGaslessRequestOptions(WithdrawParameters parameters) {
    final options = parameters.gaslessOptions;
    final maxFee = options?.maxFee;
    final deadlineSeconds = options?.deadlineSeconds;
    if ((maxFee != null && maxFee < Decimal.zero) ||
        (deadlineSeconds != null && deadlineSeconds <= 0)) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.configuration,
        message: 'GasFree withdrawal constraints are invalid',
        retryable: false,
        terminal: true,
        code: GaslessTransferErrorCode.configurationInvalid,
        stage: GaslessTransferStage.preview,
        localizationKey: 'sdk_errors.gasless_configuration_invalid',
      );
    }
  }

  Future<PendingGaslessTransfer> _prepareGaslessTransfer(
    WithdrawalPreview preview,
    Asset asset,
    _ValidatedGaslessPreview validated,
    WalletOperationContext walletContext,
  ) async {
    final journalId = _newGaslessJournalId();
    final pending = _pendingTransferFromPreview(
      preview: preview,
      assetId: asset.id.id,
      traceId: null,
      journalId: journalId,
      relay: validated.relay,
      authorizationMaxFee: validated.authorizationMaxFee,
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
    await _resolveAmbiguousLegacyTransfers(repository, walletContext);
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
      await repository.remove(walletId, pending.journalId);
      throw const WalletChangedDisconnectException(
        'Wallet changed before GasFree relay submission',
      );
    }
    _pendingGaslessWallets[pending.journalId] = walletId;
    return pending;
  }

  Future<void> _resolveAmbiguousLegacyTransfers(
    PendingGaslessTransferRepository repository,
    WalletOperationContext walletContext,
  ) async {
    final candidates = await repository.listAmbiguousLegacyTransfers(
      walletContext.walletId,
    );
    await _requireWalletContextCurrent(walletContext);
    if (candidates.isEmpty) return;

    final resolver = _freshSourceAddressResolver;
    if (resolver == null) {
      throw const GaslessTransferLegacyResolutionException();
    }

    final assets = candidates.map((transfer) => transfer.assetId).toSet();
    final ownedSourcesByAsset = <String, Set<String>>{};
    for (final assetId in assets) {
      try {
        final asset = _assetProvider.findAssetsByConfigId(assetId).single;
        final freshAddresses = await resolver(asset);
        await _requireWalletContextCurrent(walletContext);
        final normalized = freshAddresses
            .map((address) => address.trim())
            .where((address) => address.isNotEmpty)
            .toSet();
        if (normalized.isEmpty) {
          throw const GaslessTransferLegacyResolutionException();
        }
        ownedSourcesByAsset[assetId] = normalized;
      } on WalletChangedDisconnectException {
        rethrow;
      } on GaslessTransferLegacyResolutionException {
        rethrow;
      } catch (_) {
        // Do not partially resolve a legacy journal when any asset lacks a
        // complete, fresh ownership proof.
        throw const GaslessTransferLegacyResolutionException();
      }
    }

    await _requireWalletContextCurrent(walletContext);
    await repository.resolveAmbiguousLegacyTransfers(
      walletContext.walletId,
      ownedSourceAddressesByAsset: ownedSourcesByAsset,
    );
    await _requireWalletContextCurrent(walletContext);
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

  String _newGaslessJournalId() {
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

  Future<bool> _persistAcceptedGaslessTransfer(
    PendingGaslessTransfer transfer,
  ) async {
    final repository = _pendingGaslessTransfers;
    final walletId =
        _pendingGaslessWallets[transfer.journalId] ??
        await _walletIdResolver?.call();
    if (repository == null || walletId == null) return false;
    _pendingGaslessWallets[transfer.journalId] = walletId;
    final traceId = transfer.traceId;
    if (traceId != null) _pendingGaslessWallets[traceId] = walletId;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await repository.upsert(walletId, transfer);
        final stored = traceId == null
            ? await repository.findByJournalId(walletId, transfer.journalId)
            : await repository.findByTraceId(walletId, traceId);
        if (stored?.journalId == transfer.journalId &&
            stored?.traceId == transfer.traceId &&
            stored?.state == transfer.state &&
            stored?.custodyAddress == transfer.custodyAddress) {
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

  Future<bool> _isPendingWalletCurrent(PendingGaslessTransfer transfer) async {
    final original = _pendingGaslessWallets[transfer.journalId];
    return original != null && await _isWalletIdCurrent(original);
  }

  Future<bool> _isWalletIdCurrent(WalletId original) async {
    final current = await _walletIdResolver?.call();
    return current != null && isSameStableWallet(original, current);
  }

  Future<void> _upsertPendingGaslessTransfer(
    PendingGaslessTransfer transfer,
  ) async {
    final repository = _pendingGaslessTransfers;
    if (repository == null) return;
    final walletId =
        _pendingGaslessWallets[transfer.journalId] ??
        (transfer.traceId == null
            ? null
            : _pendingGaslessWallets[transfer.traceId]) ??
        await _walletIdResolver?.call();
    if (walletId == null) return;
    _pendingGaslessWallets[transfer.journalId] = walletId;
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
        _pendingGaslessWallets.remove(pending.journalId);
        _pendingGaslessWallets.remove(pending.traceId);
      }
    } catch (_) {
      log('Failed to remove terminal GasFree relay');
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

      final preview = await previewWithdrawal(parameters);
      yield* executeWithdrawal(preview, parameters.asset);
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
}

class _ValidatedGaslessPreview {
  const _ValidatedGaslessPreview(this.relay, this.authorizationMaxFee);

  final TronGasfreeRelayPayload relay;
  final Decimal authorizationMaxFee;
}

class _GaslessTraceSnapshot {
  const _GaslessTraceSnapshot({
    required this.state,
    this.txHashOnChain,
    this.blockHeight,
    this.confirmedAt,
    this.finalFee,
  });

  factory _GaslessTraceSnapshot.fromResponse(
    GaslessTraceStatusResponse response,
  ) => _GaslessTraceSnapshot(
    state: response.state,
    txHashOnChain: response.txHashOnChain,
    blockHeight: response.blockHeight,
    confirmedAt: response.confirmedAt,
    finalFee: response.finalFee,
  );

  factory _GaslessTraceSnapshot.fromEvent(GaslessTraceEvent event) {
    final blockHeight = event.blockHeight;
    final confirmedAt = event.confirmedAt;
    if ((blockHeight != null && blockHeight < 0) ||
        (confirmedAt != null && confirmedAt < 0)) {
      throw const FormatException(
        'GasFree trace event contains a negative unsigned field',
      );
    }
    return _GaslessTraceSnapshot(
      state: switch (event.state) {
        GaslessTraceEventState.pending => GaslessTraceState.pending,
        GaslessTraceEventState.submitted => GaslessTraceState.submitted,
        GaslessTraceEventState.onChain => GaslessTraceState.onChain,
        GaslessTraceEventState.confirmed => GaslessTraceState.confirmed,
        GaslessTraceEventState.failed => GaslessTraceState.failed,
      },
      txHashOnChain: event.txHashOnChain,
      blockHeight: blockHeight,
      confirmedAt: confirmedAt,
      finalFee: event.finalFee == null ? null : Decimal.parse(event.finalFee!),
    );
  }

  final GaslessTraceState state;
  final String? txHashOnChain;
  final int? blockHeight;
  final int? confirmedAt;
  final Decimal? finalFee;
}

class _AppliedGaslessTrace {
  const _AppliedGaslessTrace({
    required this.pending,
    required this.progress,
    this.isTerminal = false,
    this.wasApplied = true,
  });

  final PendingGaslessTransfer pending;
  final WithdrawalProgress progress;
  final bool isTerminal;
  final bool wasApplied;
}

/// Buffers coin-level GasFree events from before relay submission until the
/// response supplies the trace identifier to filter on.
class _GaslessTraceStreamSession {
  _GaslessTraceStreamSession._(this._subscription, this._events);

  static Future<_GaslessTraceStreamSession> attach(
    EventStreamingManager manager,
    String coin,
  ) async {
    final events = StreamController<KdfEvent>();
    final subscription = await manager.subscribeToGaslessTrace(coin: coin);
    final session = _GaslessTraceStreamSession._(subscription, events);
    subscription
      ..onData(events.add)
      ..onError(session._onStreamError)
      ..onDone(session._onStreamDone);
    return session;
  }

  final StreamSubscription<KdfEvent> _subscription;
  final StreamController<KdfEvent> _events;
  bool _isTerminated = false;

  void _onStreamError(Object error, StackTrace stackTrace) {
    _isTerminated = true;
    if (!_events.isClosed) {
      _events.addError(error, stackTrace);
    }
  }

  void _onStreamDone() {
    _isTerminated = true;
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
  }

  void requireActiveForSubmission() {
    if (!_isTerminated && !_events.isClosed) return;
    throw GaslessTransferException(
      kind: GaslessTransferErrorKind.traceUnavailable,
      code: GaslessTransferErrorCode.traceUnavailable,
      stage: GaslessTransferStage.submission,
      message: 'GasFree trace stream disconnected before submission',
      retryable: true,
      terminal: false,
      localizationKey: 'sdk_errors.gasless_capability_not_ready',
    );
  }

  Stream<KdfEvent> forTrace(String coin, String traceId) =>
      _events.stream.where(
        (event) =>
            (event is GaslessTraceEvent &&
                event.coin == coin &&
                event.traceId == traceId) ||
            (event is GaslessTraceErrorEvent &&
                event.coin == coin &&
                event.traceId == traceId),
      );

  Future<void> close() async {
    await _subscription.cancel();
    // A single-subscription controller's close future waits for a listener.
    // Submission failures and immediate terminal reconciliation never consume
    // the buffered stream, so do not deadlock cleanup in those paths.
    if (!_events.isClosed) unawaited(_events.close());
  }
}
