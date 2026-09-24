import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get the ticker and decimals values required for custom token
/// activation, given a platform and contract as input
class GetTokenInfoRequest
    extends BaseRequest<GetTokenInfoResponse, GeneralErrorResponse> {
  GetTokenInfoRequest({
    required String rpcPass,
    required this.protocolType,
    required this.platform,
    required this.contractAddress,
  }) : super(
         method: 'get_token_info',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  /// Token type - e.g ERC20 for tokens on the Ethereum network
  final String protocolType;

  /// The parent coin of the token's platform - e.g MATIC for PLG20 tokens
  /// protocol_data.platform
  final String platform;

  /// Must be mixed case The identifying hex string for the token's contract.
  /// Can be found on sites like EthScan, BscScan & PolygonScan
  /// platform_data.contract_address
  final String contractAddress;

  @override
  Map<String, dynamic> toJson() {
    return super.toJson().deepMerge({
      'params': {
        'protocol': {
          'type': protocolType,
          'protocol_data': {
            'platform': platform,
            'contract_address': contractAddress,
          },
        },
      },
    });
  }

  @override
  GetTokenInfoResponse parse(Map<String, dynamic> json) =>
      GetTokenInfoResponse.parse(json);
}

class GetTokenInfoResponse extends BaseResponse {
  GetTokenInfoResponse({
    required super.mmrpc,
    required this.type,
    required this.info,
  });

  factory GetTokenInfoResponse.parse(Map<String, dynamic> json) {
    final result = json.value<JsonMap>('result');
    return GetTokenInfoResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      type: result.value<String>('type'),
      info: TokenInfo.fromJson(result.value<JsonMap>('info')),
    );
  }

  /// Token type - e.g PLG20 for tokens on the Polygon network
  final String type;
  final TokenInfo info;

  @override
  Map<String, dynamic> toJson() {
    return {'type': type, 'info': info.toJson()};
  }
}

class TokenInfo {
  TokenInfo({required this.symbol, required this.decimals});

  factory TokenInfo.fromJson(Map<String, dynamic> json) {
    return TokenInfo(
      symbol: json.value<String>('symbol'),
      decimals: json.value<int>('decimals'),
    );
  }

  /// The ticker of the token linked to the contract address and
  /// network requested
  final String symbol;

  /// 	Defines the number of digits after the decimal point that should be
  /// used to display the orderbook amounts, balance, and the value of inputs
  /// to be used in the case of order creation or a withdraw transaction.
  final int decimals;

  Map<String, dynamic> toJson() {
    return {'symbol': symbol, 'decimals': decimals};
  }
}
