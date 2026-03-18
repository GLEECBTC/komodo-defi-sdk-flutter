import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class EnableErc20Request
    extends BaseRequest<EnableErc20Response, GeneralErrorResponse> {
  EnableErc20Request({
    required String rpcPass,
    required this.ticker,
    required this.activationParams,
  }) : super(method: 'enable_erc20', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  final String ticker;
  final ActivationParams activationParams;

  @override
  Map<String, dynamic> toJson() {
    return super.toJson().deepMerge({
      'params': {
        'ticker': ticker,
        'activation_params': activationParams.toRpcParams(),
      },
    });
  }

  @override
  EnableErc20Response parse(Map<String, dynamic> json) =>
      EnableErc20Response.parse(json);
}

class EnableErc20Response extends BaseResponse {
  EnableErc20Response({
    required super.mmrpc,
    required this.balances,
    required this.platformCoin,
    required this.tokenContractAddress,
    required this.requiredConfirmations,
  });

  factory EnableErc20Response.parse(Map<String, dynamic> json) {
    return EnableErc20Response(
      mmrpc: json.value<String>('mmrpc'),
      balances: json.value<Map<String, dynamic>>('result', 'balances'),
      platformCoin: json.value<String>('result', 'platform_coin'),
      tokenContractAddress: json.value<String>(
        'result',
        'token_contract_address',
      ),
      requiredConfirmations: json.value<int>(
        'result',
        'required_confirmations',
      ),
    );
  }

  final Map<String, dynamic> balances;
  final String platformCoin;
  final String tokenContractAddress;
  final int requiredConfirmations;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'balances': balances,
      'platform_coin': platformCoin,
      'token_contract_address': tokenContractAddress,
      'required_confirmations': requiredConfirmations,
    },
  };
}
