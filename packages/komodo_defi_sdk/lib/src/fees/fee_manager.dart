import 'package:komodo_defi_sdk/src/errors/sdk_error_mapper.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Manages cryptocurrency transaction fee operations and policies.
///
/// The [FeeManager] provides functionality for:
/// - Retrieving estimated gas fees for Ethereum-based transactions
/// - Retrieving estimated fees for UTXO-based transactions (Bitcoin, Litecoin, etc.)
/// - Retrieving estimated fees for Tendermint/Cosmos-based transactions
/// - Getting and setting fee policies for swap transactions
/// - Managing fee-related configuration for blockchain operations
///
/// This manager abstracts away the complexity of fee estimation and management,
/// providing a simple interface for applications to work with transaction fees
/// across different blockchain protocols.
///
/// **Note:** Fee estimation features are currently disabled as the API endpoints
/// are not yet available. Set `_feeEstimationEnabled` to `true` when the API
/// endpoints become available.
///
/// Usage example:
/// ```dart
/// final feeManager = FeeManager(apiClient);
///
/// // Get ETH gas fee estimates
/// final gasEstimates = await feeManager.getEthEstimatedFeePerGas('ETH');
/// print('Slow fee: ${gasEstimates.slow.maxFeePerGas} gwei');
/// print('Medium fee: ${gasEstimates.medium.maxFeePerGas} gwei');
/// print('Fast fee: ${gasEstimates.fast.maxFeePerGas} gwei');
///
/// // Get UTXO fee estimates
/// final utxoEstimates = await feeManager.getUtxoEstimatedFee('BTC');
/// print('Low fee: ${utxoEstimates.low.feePerKbyte} sat/KB');
/// print('Medium fee: ${utxoEstimates.medium.feePerKbyte} sat/KB');
/// print('High fee: ${utxoEstimates.high.feePerKbyte} sat/KB');
///
/// // Get Tendermint fee estimates
/// final tendermintEstimates = await feeManager.getTendermintEstimatedFee('ATOM');
/// print('Low fee: ${tendermintEstimates.low.totalFee} ATOM');
/// print('Medium fee: ${tendermintEstimates.medium.totalFee} ATOM');
/// print('High fee: ${tendermintEstimates.high.totalFee} ATOM');
/// ```
class FeeManager {
  /// Creates a new [FeeManager] instance.
  ///
  /// Requires:
  /// - [_client] - API client for making RPC calls to fee management endpoints
  FeeManager(this._client);

  /// Flag to enable/disable fee estimation features.
  ///
  /// TODO: Set to true when the fee estimation API endpoints become available.
  /// Currently disabled as the endpoints are not yet implemented in the API.
  static const bool _feeEstimationEnabled = false;

  final ApiClient _client;
  static const SdkErrorMapper _errorMapper = SdkErrorMapper();

  /// Enable fee estimator for a specific coin.
  ///
  /// This method enables the fee estimator service for the specified coin,
  /// which is required before requesting fee estimates.
  ///
  /// Parameters:
  /// - [coin] - The ticker symbol of the coin (e.g., 'BTC', 'ETH', 'ATOM')
  /// - [estimatorType] - The type of estimator to enable (e.g., 'simple', 'electrum')
  ///
  /// Returns a [Future<String>] containing the status result.
  ///
  /// Example:
  /// ```dart
  /// final result = await feeManager.enableFeeEstimator('BTC', 'electrum');
  /// print('Fee estimator enabled: $result');
  /// ```
  Future<String> enableFeeEstimator(String coin, String estimatorType) async {
    try {
      final response = await _client.rpc.feeManagement.feeEstimatorEnable(
        coin: coin,
        estimatorType: estimatorType,
      );
      return response.result;
    } catch (e) {
      throw _mapError(e, operation: 'fee_estimator.enable', assetId: coin);
    }
  }

  /// Retrieves estimated fee per gas for Ethereum-based transactions.
  ///
  /// This method provides up-to-date gas fee estimates for Ethereum-compatible
  /// chains with different speed options (slow, medium, fast).
  ///
  /// **Note:** This feature is currently disabled as the API endpoints are not yet available.
  /// TODO: Enable when the fee estimation API endpoints become available.
  ///
  /// Parameters:
  /// - [coin] - The ticker symbol of the coin (e.g., 'ETH', 'MATIC')
  /// - [estimatorType] - The type of estimator to use (default: simple)
  ///
  /// Returns a [Future<EthEstimatedFeePerGas>] containing gas fee estimates at
  /// different priority levels:
  /// - `slow` - Lower cost but potentially longer confirmation time
  /// - `medium` - Balanced cost and confirmation time
  /// - `fast` - Higher cost for faster confirmation
  ///
  /// Each estimate includes:
  /// - `maxFeePerGas` - Maximum fee per gas unit
  /// - `maxPriorityFeePerGas` - Maximum priority fee per gas unit
  ///
  /// Throws:
  /// - [UnsupportedError] when fee estimation is disabled
  ///
  /// Example:
  /// ```dart
  /// final estimates = await feeManager.getEthEstimatedFeePerGas('ETH');
  ///
  /// // Choose a fee based on desired confirmation speed
  /// final selectedFee = estimates.medium;
  ///
  /// print('Max fee: ${selectedFee.maxFeePerGas} gwei');
  /// print('Max priority fee: ${selectedFee.maxPriorityFeePerGas} gwei');
  /// ```
  Future<EthEstimatedFeePerGas> getEthEstimatedFeePerGas(
    String coin, {
    FeeEstimatorType estimatorType = FeeEstimatorType.simple,
  }) async {
    try {
      if (!_feeEstimationEnabled) {
        throw UnsupportedError(
          'Fee estimation is currently disabled. The API endpoints are not yet available. '
          'Set `_feeEstimationEnabled` to `true` when the endpoints become available.',
        );
      }

      final response = await _client.rpc.feeManagement.getEthEstimatedFeePerGas(
        coin: coin,
        estimatorType: estimatorType,
      );
      return response.result;
    } catch (e) {
      throw _mapError(e, operation: 'fee.estimate.eth', assetId: coin);
    }
  }

  /// Retrieves estimated fees for UTXO-based transactions (Bitcoin, Litecoin, etc.).
  ///
  /// This method provides up-to-date fee estimates for UTXO-based chains
  /// with different priority levels (low, medium, high).
  ///
  /// **Note:** This feature is currently disabled as the API endpoints are not yet available.
  /// TODO: Enable when the fee estimation API endpoints become available.
  ///
  /// Parameters:
  /// - [coin] - The ticker symbol of the coin (e.g., 'BTC', 'LTC', 'DOGE')
  /// - [estimatorType] - The type of estimator to use (default: simple)
  ///
  /// Returns a [Future<UtxoEstimatedFee>] containing fee estimates at
  /// different priority levels:
  /// - `low` - Lower fee rate for non-urgent transactions
  /// - `medium` - Balanced fee rate for normal transactions
  /// - `high` - Higher fee rate for urgent transactions
  ///
  /// Each estimate includes:
  /// - `feePerKbyte` - Fee rate in satoshis per kilobyte
  /// - `estimatedTime` - Estimated confirmation time
  ///
  /// Throws:
  /// - [UnsupportedError] when fee estimation is disabled
  ///
  /// Example:
  /// ```dart
  /// final estimates = await feeManager.getUtxoEstimatedFee('BTC');
  ///
  /// // Choose a fee based on desired confirmation speed
  /// final selectedFee = estimates.medium;
  ///
  /// print('Fee rate: ${selectedFee.feePerKbyte} sat/KB');
  /// print('Estimated time: ${selectedFee.estimatedTime}');
  /// ```
  Future<UtxoEstimatedFee> getUtxoEstimatedFee(
    String coin, {
    FeeEstimatorType estimatorType = FeeEstimatorType.simple,
  }) async {
    try {
      if (!_feeEstimationEnabled) {
        throw UnsupportedError(
          'Fee estimation is currently disabled. The API endpoints are not yet available. '
          'Set `_feeEstimationEnabled` to `true` when the endpoints become available.',
        );
      }

      final response = await _client.rpc.feeManagement.getUtxoEstimatedFee(
        coin: coin,
        estimatorType: estimatorType,
      );
      return response.result;
    } catch (e) {
      throw _mapError(e, operation: 'fee.estimate.utxo', assetId: coin);
    }
  }

  /// Retrieves estimated fees for Tendermint/Cosmos-based transactions.
  ///
  /// This method provides up-to-date fee estimates for Tendermint/Cosmos chains
  /// with different priority levels (low, medium, high).
  ///
  /// **Note:** This feature is currently disabled as the API endpoints are not yet available.
  /// TODO: Enable when the fee estimation API endpoints become available.
  ///
  /// Parameters:
  /// - [coin] - The ticker symbol of the coin (e.g., 'ATOM', 'IRIS', 'OSMO')
  /// - [estimatorType] - The type of estimator to use (default: simple)
  ///
  /// Returns a [Future<TendermintEstimatedFee>] containing fee estimates at
  /// different priority levels:
  /// - `low` - Lower gas price for non-urgent transactions
  /// - `medium` - Balanced gas price for normal transactions
  /// - `high` - Higher gas price for urgent transactions
  ///
  /// Each estimate includes:
  /// - `gasPrice` - Gas price in the native coin units
  /// - `gasLimit` - Gas limit for the transaction
  /// - `totalFee` - Calculated total fee (gasPrice * gasLimit)
  /// - `estimatedTime` - Estimated confirmation time
  ///
  /// Throws:
  /// - [UnsupportedError] when fee estimation is disabled
  ///
  /// Example:
  /// ```dart
  /// final estimates = await feeManager.getTendermintEstimatedFee('ATOM');
  ///
  /// // Choose a fee based on desired confirmation speed
  /// final selectedFee = estimates.medium;
  ///
  /// print('Gas price: ${selectedFee.gasPrice} ATOM');
  /// print('Gas limit: ${selectedFee.gasLimit}');
  /// print('Total fee: ${selectedFee.totalFee} ATOM');
  /// print('Estimated time: ${selectedFee.estimatedTime}');
  /// ```
  Future<TendermintEstimatedFee> getTendermintEstimatedFee(
    String coin, {
    FeeEstimatorType estimatorType = FeeEstimatorType.simple,
  }) async {
    try {
      if (!_feeEstimationEnabled) {
        throw UnsupportedError(
          'Fee estimation is currently disabled. The API endpoints are not yet available. '
          'Set `_feeEstimationEnabled` to `true` when the endpoints become available.',
        );
      }

      final response = await _client.rpc.feeManagement
          .getTendermintEstimatedFee(coin: coin, estimatorType: estimatorType);
      return response.result;
    } catch (e) {
      throw _mapError(e, operation: 'fee.estimate.tendermint', assetId: coin);
    }
  }

  /// Retrieves the current fee policy for swap transactions of a specific coin.
  ///
  /// Fee policies determine how transaction fees are calculated and applied
  /// for swap operations involving the specified coin.
  ///
  /// Parameters:
  /// - [coin] - The ticker symbol of the coin (e.g., 'KMD', 'BTC')
  ///
  /// Returns a [Future<FeePolicy>] containing the current fee policy
  /// configuration.
  ///
  /// Example:
  /// ```dart
  /// final policy = await feeManager.getSwapTransactionFeePolicy('KMD');
  ///
  /// if (policy == FeePolicy.medium) {
  ///   print('Using medium fee policy');
  /// }
  /// ```
  Future<FeePolicy> getSwapTransactionFeePolicy(String coin) async {
    try {
      final response = await _client.rpc.feeManagement
          .getSwapTransactionFeePolicy(coin: coin);
      return response.result;
    } catch (e) {
      throw _mapError(e, operation: 'fee.policy.get', assetId: coin);
    }
  }

  /// Sets a new fee policy for swap transactions of a specific coin.
  ///
  /// This method allows customizing how transaction fees are calculated and
  /// applied for swap operations involving the specified coin.
  ///
  /// Parameters:
  /// - [coin] - The ticker symbol of the coin (e.g., 'KMD', 'BTC')
  /// - [policy] - The new fee policy to apply
  ///
  /// Returns a [Future<FeePolicy>] containing the updated fee policy
  /// configuration.
  ///
  /// Example:
  /// ```dart
  /// final updatedPolicy = await feeManager.setSwapTransactionFeePolicy(
  ///   'BTC',
  ///   FeePolicy.high,
  /// );
  ///
  /// print('Updated fee policy: $updatedPolicy');
  /// ```
  Future<FeePolicy> setSwapTransactionFeePolicy(
    String coin,
    FeePolicy policy,
  ) async {
    try {
      final response = await _client.rpc.feeManagement
          .setSwapTransactionFeePolicy(coin: coin, swapTxFeePolicy: policy);
      return response.result;
    } catch (e) {
      throw _mapError(e, operation: 'fee.policy.set', assetId: coin);
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

  /// Disposes of resources used by the FeeManager.
  ///
  /// This method is called when the FeeManager is no longer needed.
  /// Currently, it doesn't perform any cleanup operations as the FeeManager
  /// doesn't manage any resources that require explicit disposal.
  ///
  /// Example:
  /// ```dart
  /// // When done with the fee manager
  /// await feeManager.dispose();
  /// ```
  Future<void> dispose() {
    // No resources to dispose. Return a future that completes immediately.
    return Future.value();
  }
}
