import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// RPC namespace for rewards-related operations.
class RewardsMethodsNamespace extends BaseRpcMethodNamespace {
  RewardsMethodsNamespace(super.client);

  /// Fetches KMD rewards information.
  Future<KmdRewardsInfoResponse> kmdRewardsInfo({String? rpcPass}) {
    return execute(
      KmdRewardsInfoRequest(rpcPass: rpcPass ?? this.rpcPass ?? ''),
    );
  }
}
