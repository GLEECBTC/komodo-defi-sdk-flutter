import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to delete a wallet.
///
/// Errors are automatically parsed into typed [MmRpcException] subclasses
/// by the [KdfErrorRegistry]. Common error types include:
/// - `InvalidRequest` - The request was malformed
/// - `WalletNotFound` - The specified wallet does not exist
/// - `InvalidPassword` - The provided password is incorrect
/// - `CannotDeleteActiveWallet` - Cannot delete the currently active wallet
/// - `WalletsStorageError` - Error accessing wallet storage
/// - `InternalError` - An internal error occurred
class DeleteWalletRequest
    extends BaseRequest<DeleteWalletResponse, GeneralErrorResponse> {
  DeleteWalletRequest({
    required this.walletName,
    required this.password,
    super.rpcPass,
  }) : super(method: 'delete_wallet', mmrpc: RpcVersion.v2_0);

  final String walletName;
  final String password;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'userpass': rpcPass,
    'mmrpc': mmrpc,
    'method': method,
    'params': {'wallet_name': walletName, 'password': password},
  };

  @override
  DeleteWalletResponse parse(Map<String, dynamic> json) =>
      DeleteWalletResponse.parse(json);
}

class DeleteWalletResponse extends BaseResponse {
  DeleteWalletResponse({required super.mmrpc});

  factory DeleteWalletResponse.parse(Map<String, dynamic> json) {
    return DeleteWalletResponse(mmrpc: json.value<String>('mmrpc'));
  }

  @override
  Map<String, dynamic> toJson() => {'mmrpc': mmrpc, 'result': null};
}
