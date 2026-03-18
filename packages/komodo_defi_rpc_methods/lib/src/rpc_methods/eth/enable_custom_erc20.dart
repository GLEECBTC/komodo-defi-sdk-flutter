import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class EnableCustomErc20TokenRequest
    extends BaseRequest<EnableErc20Response, GeneralErrorResponse> {
  EnableCustomErc20TokenRequest({
    required String rpcPass,
    required this.ticker,
    required this.activationParams,
    required this.platform,
    required this.contractAddress,
    this.protocolType = 'ERC20',
  }) : super(method: 'enable_erc20', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  final String ticker;
  final ActivationParams activationParams;
  final String platform;
  final String contractAddress;
  final String protocolType;

  @override
  Map<String, dynamic> toJson() {
    assert(
      platform.isNotEmpty,
      'Platform is required when activating a custom token.',
    );
    assert(
      contractAddress.isNotEmpty,
      'Contract address is required when activating a custom token.',
    );

    return super.toJson().deepMerge({
      'params': {
        'ticker': ticker,
        'activation_params': activationParams.toRpcParams(),
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
  EnableErc20Response parse(Map<String, dynamic> json) =>
      EnableErc20Response.parse(json);
}
