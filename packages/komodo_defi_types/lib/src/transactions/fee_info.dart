import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

part 'fee_info.freezed.dart';
// We are doing manual fromJson/toJson, so no need for part 'fee_info.g.dart';

/// A union representing eight possible fee types:
/// - UtxoFixed
/// - UtxoPerKbyte
/// - EthGas (legacy)
/// - EthGasEip1559 (EIP1559)
/// - Qrc20Gas
/// - CosmosGas
/// - Tendermint
/// - Sia
@Freezed()
sealed class FeeInfo with _$FeeInfo {
  //////////////////////////////////////////////////////////////////////////////
  //  Custom Manual JSON Parsing
  //
  //  The docs show that each variant includes a "type" field and possibly
  //  different fields like "amount", "gas_price", "gas", "gas_limit", etc.
  //////////////////////////////////////////////////////////////////////////////

  /// Parse a JSON object into one of the [FeeInfo] variants, based on `type`.
  factory FeeInfo.fromJson(JsonMap json) {
    final type = json['type'] as String? ?? '';
    switch (type) {
      case 'UtxoFixed' || 'Utxo':
        return FeeInfo.utxoFixed(
          coin: json['coin'] as String? ?? '',
          amount: Decimal.parse(json['amount'] as String),
        );
      case 'UtxoPerKbyte':
        return FeeInfo.utxoPerKbyte(
          coin: json['coin'] as String? ?? '',
          amount: Decimal.parse(json['amount'] as String),
        );
      case 'Sia':
        final rawTotal =
            json['total_amount'] ??
            json['amount']; // some examples use total_amount
        if (rawTotal == null) {
          throw ArgumentError('Sia fee_details missing total_amount/amount');
        }
        return FeeInfo.utxoFixed(
          coin: json['coin'] as String? ?? '',
          amount: Decimal.parse(rawTotal.toString()),
        );
      case 'EthGas' || 'Eth':
        final totalGasFee = json['total_fee'] != null
            ? Decimal.parse(json['total_fee'].toString())
            : null;
        return FeeInfo.ethGas(
          coin: json['coin'] as String? ?? '',
          // If JSON provides e.g. "0.000000003", parse to Decimal => 3e-9
          gasPrice: Decimal.parse(json['gas_price'].toString()),
          gas: json['gas'] as int,
          totalGasFee: totalGasFee,
        );
      case 'EthGasEip1559':
        final totalGasFee = json['total_fee'] != null
            ? Decimal.parse(json['total_fee'].toString())
            : null;
        return FeeInfo.ethGasEip1559(
          coin: json['coin'] as String? ?? '',
          maxFeePerGas: Decimal.parse(json['max_fee_per_gas'].toString()),
          maxPriorityFeePerGas:
              Decimal.parse(json['max_priority_fee_per_gas'].toString()),
          gas: json['gas'] as int,
          totalGasFee: totalGasFee,
        );
      case 'Qrc20Gas':
        final totalGasFee = json['total_gas_fee'] != null
            ? Decimal.parse(json['total_gas_fee'].toString())
            : null;
        return FeeInfo.qrc20Gas(
          coin: json['coin'] as String? ?? '',
          gasPrice: Decimal.parse(json['gas_price'].toString()),
          gasLimit: json['gas_limit'] as int,
          totalGasFee: totalGasFee,
        );
      case 'Tendermint':
        return FeeInfo.tendermint(
          coin: json['coin'] as String? ?? '',
          amount: Decimal.parse(json['amount'].toString()),
          gasLimit: json['gas_limit'] as int,
        );
      case 'CosmosGas':
        return FeeInfo.cosmosGas(
          coin: json['coin'] as String? ?? '',
          // The doc sometimes shows 0.05 as a number (double),
          // so we convert it to string, then parse:
          gasPrice: Decimal.parse(json['gas_price'].toString()),
          gasLimit: json['gas_limit'] as int,
        );
      case 'Sia':
        return FeeInfo.sia(
          coin: json['coin'] as String? ?? '',
          amount: Decimal.parse(json['total_amount'].toString()),
          policy: json['policy'] as String? ?? 'Fixed',
        );
      default:
        throw ArgumentError('Unknown fee type: $type');
    }
  }

  const FeeInfo._();

  /// 1) A *fixed* fee in coin units (e.g. "0.0001 BTC").
  const factory FeeInfo.utxoFixed({
    /// Which coin pays the fee
    required String coin,

    /// The fee amount in coin units
    required Decimal amount,
  }) = FeeInfoUtxoFixed;

  /// 2) A *per kilobyte* fee in coin units (e.g. "0.0001 BTC per KB").
  const factory FeeInfo.utxoPerKbyte({
    required String coin,
    required Decimal amount,
  }) = FeeInfoUtxoPerKbyte;

  /// 3) ETH-like gas (legacy): you specify *gasPrice* (in ETH) and *gas* (units).
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "type": "EthGas",
  ///   "coin": "ETH",
  ///   "gas_price": "0.000000003",
  ///   "gas": 21000,
  ///   "total_fee": "0.000021"
  /// }
  /// ```
  /// Interpreted as: 3 Gwei -> total fee = 0.000000003 ETH * 21000 = 0.000063 ETH.
  /// If `totalGasFee` is provided, it will be used directly instead of calculating from gasPrice * gas.
  const factory FeeInfo.ethGas({
    required String coin,

    /// Gas price in ETH. e.g. "0.000000003" => 3 Gwei
    required Decimal gasPrice,

    /// Gas limit (number of gas units)
    required int gas,

    /// Optional total fee override. If provided, this value will be used directly
    /// instead of calculating from gasPrice * gas.
    Decimal? totalGasFee,
  }) = FeeInfoEthGas;

  /// 4) ETH-like gas (EIP1559): you specify *maxFeePerGas* and *maxPriorityFeePerGas*.
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "type": "EthGasEip1559",
  ///   "coin": "ETH",
  ///   "max_fee_per_gas": "0.000000003",
  ///   "max_priority_fee_per_gas": "0.000000001",
  ///   "gas": 21000,
  ///   "total_fee": "0.000021"
  /// }
  /// ```
  /// EIP1559 transactions use maxFeePerGas and maxPriorityFeePerGas instead of gasPrice.
  /// If `totalGasFee` is provided, it will be used directly instead of calculating.
  const factory FeeInfo.ethGasEip1559({
    required String coin,

    /// Maximum fee per gas in ETH. e.g. "0.000000003" => 3 Gwei
    required Decimal maxFeePerGas,

    /// Maximum priority fee per gas in ETH. e.g. "0.000000001" => 1 Gwei
    required Decimal maxPriorityFeePerGas,

    /// Gas limit (number of gas units)
    required int gas,

    /// Optional total fee override. If provided, this value will be used directly
    /// instead of calculating from maxFeePerGas * gas.
    Decimal? totalGasFee,
  }) = FeeInfoEthGasEip1559;

  /// 5) Qtum/QRC20-like gas, specifying `gasPrice` (in coin units) and `gasLimit`.
  const factory FeeInfo.qrc20Gas({
    required String coin,

    /// Gas price in coin units. e.g. "0.000000004"
    required Decimal gasPrice,

    /// Gas limit
    required int gasLimit,

    /// Optional total gas fee in coin units. If not provided, it will be calculated
    /// as `gasPrice * gasLimit`.
    Decimal? totalGasFee,
  }) = FeeInfoQrc20Gas;

  /// 6) Cosmos-like gas, specifying `gasPrice` (in coin units) and `gasLimit`.
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "type": "CosmosGas",
  ///   "coin": "IRIS",
  ///   "gas_price": 0.05,
  ///   "gas_limit": 21000
  /// }
  /// ```
  const factory FeeInfo.cosmosGas({
    required String coin,

    /// Gas price in coin units. e.g. "0.05"
    required Decimal gasPrice,

    /// Gas limit
    required int gasLimit,
  }) = FeeInfoCosmosGas;

  /// 7) Tendermint fee, with fixed `amount` and `gasLimit`.
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "type": "Tendermint",
  ///   "coin": "IRIS",
  ///   "amount": "0.038553",
  ///   "gas_limit": 100000
  /// }
  /// ```
  /// Total fee is just the amount (not calculated from gas * price)
  const factory FeeInfo.tendermint({
    required String coin,

    /// The fee amount in coin units
    required Decimal amount,

    /// Gas limit
    required int gasLimit,
  }) = FeeInfoTendermint;

  /// 8) SIA fee, with fixed `amount` and `policy`.
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "type": "Sia",
  ///   "coin": "SC",
  ///   "policy": "Fixed",
  ///   "total_amount": "0.000010000000000000000000"
  /// }
  /// ```
  /// Total fee is just the amount
  const factory FeeInfo.sia({
    required String coin,

    /// The fee amount in coin units
    required Decimal amount,

    /// The fee policy (e.g., "Fixed")
    required String policy,
  }) = FeeInfoSia;

  /// A convenience getter returning the *total fee* in the coin's main units.
  Decimal get totalFee => switch (this) {
        FeeInfoUtxoFixed(:final amount) => amount,
        FeeInfoUtxoPerKbyte(:final amount) => amount,
        FeeInfoEthGas(:final gasPrice, :final gas, :final totalGasFee) =>
          totalGasFee ?? (gasPrice * Decimal.fromInt(gas)),
        FeeInfoEthGasEip1559(
          :final maxFeePerGas,
          :final gas,
          :final totalGasFee
        ) =>
          totalGasFee ?? (maxFeePerGas * Decimal.fromInt(gas)),
        FeeInfoQrc20Gas(:final gasPrice, :final gasLimit, :final totalGasFee) =>
          totalGasFee ?? (gasPrice * Decimal.fromInt(gasLimit)),
        FeeInfoCosmosGas(:final gasPrice, :final gasLimit) =>
          gasPrice * Decimal.fromInt(gasLimit),
        FeeInfoTendermint(:final amount) => amount,
        FeeInfoSia(:final amount) => amount,
      };

  /// Convert this [FeeInfo] to a JSON object matching the mmRPC 2.0 docs.
  JsonMap toJson() => switch (this) {
        FeeInfoUtxoFixed(:final coin, :final amount) => {
            'type': 'UtxoFixed',
            'coin': coin,
            'amount': amount.toString(),
          },
        FeeInfoUtxoPerKbyte(:final coin, :final amount) => {
            'type': 'UtxoPerKbyte',
            'coin': coin,
            'amount': amount.toString(),
          },
        FeeInfoEthGas(
          :final coin,
          :final gasPrice,
          :final gas,
          :final totalGasFee
        ) =>
          {
            'type': 'EthGas',
            'coin': coin,
            'gas_price': gasPrice.toString(),
            'gas': gas,
            if (totalGasFee != null) 'total_fee': totalGasFee.toString(),
          },
        FeeInfoEthGasEip1559(
          :final coin,
          :final maxFeePerGas,
          :final maxPriorityFeePerGas,
          :final gas,
          :final totalGasFee
        ) =>
          {
            'type': 'EthGasEip1559',
            'coin': coin,
            'max_fee_per_gas': maxFeePerGas.toString(),
            'max_priority_fee_per_gas': maxPriorityFeePerGas.toString(),
            'gas': gas,
            if (totalGasFee != null) 'total_fee': totalGasFee.toString(),
          },
        FeeInfoQrc20Gas(
          :final coin,
          :final gasPrice,
          :final gasLimit,
          :final totalGasFee
        ) =>
          {
            'type': 'Qrc20Gas',
            'coin': coin,
            'gas_price': gasPrice.toDouble(),
            'gas_limit': gasLimit,
            if (totalGasFee != null) 'total_gas_fee': totalGasFee.toString(),
          },
        FeeInfoCosmosGas(:final coin, :final gasPrice, :final gasLimit) => {
            'type': 'CosmosGas',
            'coin': coin,
            'gas_price': gasPrice.toDouble(),
            'gas_limit': gasLimit,
          },
        // TODO: update to Tendermint for KDF v2.5.0-beta
        FeeInfoTendermint(:final coin, :final amount, :final gasLimit) => {
            'type': 'CosmosGas',
            'coin': coin,
            'gas_price': gasLimit > 0
                ? (amount / Decimal.fromInt(gasLimit)).toDouble()
                : 0.0,
            'gas_limit': gasLimit,
          },
        FeeInfoSia(:final coin, :final amount, :final policy) => {
            'type': 'Sia',
            'coin': coin,
            'total_amount': amount.toString(),
            'policy': policy,
          },
      };
}
