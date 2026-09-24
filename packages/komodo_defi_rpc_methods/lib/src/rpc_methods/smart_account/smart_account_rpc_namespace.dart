import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

class SmartAccountMethodsNamespace extends BaseRpcMethodNamespace {
  SmartAccountMethodsNamespace(super.client);

  Future<RegisterSmartAccountResponse> register({
    required String coin,
    required String safeAddress,
    AddressPath? from,
  }) => execute(
    RegisterSmartAccountRequest(
      rpcPass: rpcPass ?? '',
      coin: coin,
      safeAddress: safeAddress,
      from: from,
    ),
  );

  Future<SignSmartAccountTypedDataResponse> signTypedData({
    required String coin,
    required PreparedSmartAccountIntent intent,
    AddressPath? from,
  }) => execute(
    SignSmartAccountTypedDataRequest(
      rpcPass: rpcPass ?? '',
      coin: coin,
      intent: intent,
      from: from,
    ),
  );
}
