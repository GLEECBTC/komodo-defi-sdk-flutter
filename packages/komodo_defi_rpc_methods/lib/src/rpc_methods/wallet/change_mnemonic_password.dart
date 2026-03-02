// lib/src/rpc_methods/wallet/change_mnemonic_password.dart

import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to change the mnemonic password.
///
/// Known errors may surface either as typed [MmRpcException] subclasses
/// from the [KdfErrorRegistry] or as a [GeneralErrorResponse] fallback.
class ChangeMnemonicPasswordRequest
    extends BaseRequest<ChangeMnemonicPasswordResponse, GeneralErrorResponse> {
  ChangeMnemonicPasswordRequest({
    required super.rpcPass,
    required this.currentPassword,
    required this.newPassword,
  }) : super(method: 'change_mnemonic_password', mmrpc: RpcVersion.v2_0);

  final String currentPassword;
  final String newPassword;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'userpass': rpcPass,
    'mmrpc': mmrpc,
    'method': method,
    'params': {
      'current_password': currentPassword,
      'new_password': newPassword,
    },
  };

  @override
  ChangeMnemonicPasswordResponse parse(Map<String, dynamic> json) =>
      ChangeMnemonicPasswordResponse.parse(json);
}

class ChangeMnemonicPasswordResponse extends BaseResponse {
  ChangeMnemonicPasswordResponse({required super.mmrpc});

  @override
  factory ChangeMnemonicPasswordResponse.parse(Map<String, dynamic> json) {
    return ChangeMnemonicPasswordResponse(mmrpc: json.value<String>('mmrpc'));
  }

  @override
  Map<String, dynamic> toJson() => {'mmrpc': mmrpc, 'result': null};
}
