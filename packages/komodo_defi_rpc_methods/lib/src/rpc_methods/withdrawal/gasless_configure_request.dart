import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// One TRC-20 token to install in an already-running GasFree platform.
class GaslessConfigureToken extends Equatable {
  const GaslessConfigureToken({required this.coin, this.transferMaxFee});

  final String coin;
  final Decimal? transferMaxFee;

  JsonMap toJson() => {
    'coin': coin,
    if (transferMaxFee != null) 'transfer_max_fee': transferMaxFee.toString(),
  };

  @override
  List<Object?> get props => [coin, transferMaxFee];
}

/// Reconfigures GasFree on an already-active TRON runtime.
class GaslessConfigureRequest
    extends BaseRequest<GaslessConfigureResponse, GeneralErrorResponse> {
  GaslessConfigureRequest({
    required super.rpcPass,
    required this.platformCoin,
    required this.provider,
    required this.tokens,
  }) : super(method: 'gasless::configure', mmrpc: RpcVersion.v2_0) {
    if (tokens.isEmpty) {
      throw ArgumentError.value(tokens, 'tokens', 'Must not be empty');
    }
  }

  final String platformCoin;
  final TronGaslessProviderConfig provider;
  final List<GaslessConfigureToken> tokens;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {
      'platform_coin': platformCoin,
      'provider': provider.toJson(),
      'tokens': tokens.map((token) => token.toJson()).toList(),
    },
  };

  @override
  GaslessConfigureResponse parse(JsonMap json) =>
      GaslessConfigureResponse.parse(json);
}

class GaslessConfiguredToken extends Equatable {
  const GaslessConfiguredToken({
    required this.coin,
    required this.accountStatus,
  });

  factory GaslessConfiguredToken.parse(JsonMap json) {
    return GaslessConfiguredToken(
      coin: json.value<String>('coin'),
      accountStatus: GaslessAccountStatusResponse.parse(
        json.value<JsonMap>('account_status'),
      ),
    );
  }

  final String coin;
  final GaslessAccountStatusResponse accountStatus;

  @override
  List<Object?> get props => [coin, accountStatus];
}

class GaslessConfigureResponse extends BaseResponse {
  GaslessConfigureResponse({
    required super.mmrpc,
    required this.platformCoin,
    required this.serviceProvider,
    required this.tokens,
  });

  factory GaslessConfigureResponse.parse(JsonMap json) {
    final result = json.valueOrNull<JsonMap>('result') ?? json;
    return GaslessConfigureResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      platformCoin: result.value<String>('platform_coin'),
      serviceProvider: result.value<String>('service_provider'),
      tokens: result
          .value<JsonList>('tokens')
          .map(GaslessConfiguredToken.parse)
          .toList(),
    );
  }

  final String platformCoin;
  final String serviceProvider;
  final List<GaslessConfiguredToken> tokens;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'platform_coin': platformCoin,
      'service_provider': serviceProvider,
      'tokens': [
        for (final token in tokens)
          {
            'coin': token.coin,
            'account_status': token.accountStatus.toJson()['result'],
          },
      ],
    },
  };
}
