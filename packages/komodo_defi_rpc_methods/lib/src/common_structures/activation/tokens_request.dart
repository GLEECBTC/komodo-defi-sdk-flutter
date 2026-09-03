import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class TronGaslessTokenActivationConfig {
  const TronGaslessTokenActivationConfig({
    required this.enabled,
    this.transferMaxFee,
  });

  factory TronGaslessTokenActivationConfig.fromJson(JsonMap json) {
    final transferMaxFee = json.valueOrNull<Object>('transfer_max_fee');
    return TronGaslessTokenActivationConfig(
      enabled: json.valueOrNull<bool>('enabled') ?? false,
      transferMaxFee: transferMaxFee == null
          ? null
          : Decimal.parse(transferMaxFee.toString()),
    );
  }

  final bool enabled;
  final Decimal? transferMaxFee;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (transferMaxFee != null) 'transfer_max_fee': transferMaxFee.toString(),
  };
}

class TokensRequest {
  TokensRequest({
    required this.ticker,
    this.requiredConfirmations = 3,
    this.gasless,
  });

  factory TokensRequest.fromJson(JsonMap json) {
    final gasless = json.valueOrNull<JsonMap>('gasless');
    return TokensRequest(
      ticker: json.value<String>('ticker'),
      requiredConfirmations:
          json.valueOrNull<int>('required_confirmations') ?? 3,
      gasless: gasless == null
          ? null
          : TronGaslessTokenActivationConfig.fromJson(gasless),
    );
  }

  final String ticker;
  final int requiredConfirmations;
  final TronGaslessTokenActivationConfig? gasless;

  Map<String, dynamic> toJson() => {
    'ticker': ticker,
    'required_confirmations': requiredConfirmations,
    if (gasless != null) 'gasless': gasless!.toJson(),
  };
}
