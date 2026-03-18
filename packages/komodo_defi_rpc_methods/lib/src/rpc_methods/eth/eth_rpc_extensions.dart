import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// Extensions for ETH-related RPC methods
// lib/src/rpc_methods/eth/eth_rpc_extensions.dart
class Erc20MethodsNamespace extends BaseRpcMethodNamespace {
  Erc20MethodsNamespace(super.client);

  Future<EnableEthWithTokensResponse> enableEthWithTokens({
    required String ticker,
    required ActivationParams params,
    bool getBalances = true,
  }) {
    return execute(
      EnableEthWithTokensRequest(
        rpcPass: rpcPass ?? '',
        ticker: ticker,
        activationParams: params,
        getBalances: getBalances,
      ),
    );
  }

  Future<EnableErc20Response> enableErc20({
    required String ticker,
    required ActivationParams activationParams,
  }) {
    return execute(
      EnableErc20Request(
        rpcPass: rpcPass ?? '',
        ticker: ticker,
        activationParams: activationParams,
      ),
    );
  }

  Future<EnableErc20Response> enableCustomErc20Token({
    required String ticker,
    required ActivationParams activationParams,
    required String platform,
    required String contractAddress,
    String protocolType = 'ERC20',
  }) {
    return execute(
      EnableCustomErc20TokenRequest(
        rpcPass: rpcPass ?? '',
        ticker: ticker,
        activationParams: activationParams,
        platform: platform,
        contractAddress: contractAddress,
        protocolType: protocolType,
      ),
    );
  }

  // ETH Task Methods
  Future<NewTaskResponse> enableEthInit({
    required String ticker,
    required ActivationParams params,
  }) {
    return execute(
      TaskEnableEthInit(rpcPass: rpcPass ?? '', ticker: ticker, params: params),
    );
  }

  Future<TaskStatusResponse> taskEthStatus(int taskId, [String? rpcPass]) {
    return execute(
      TaskStatusRequest(
        taskId: taskId,
        rpcPass: rpcPass,
        method: 'task::enable_eth::status',
      ),
    );
  }
}
