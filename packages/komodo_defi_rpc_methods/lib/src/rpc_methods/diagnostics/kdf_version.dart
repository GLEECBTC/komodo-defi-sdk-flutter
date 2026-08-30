import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get the running KDF version.
class KdfVersionRequest
    extends BaseRequest<KdfVersionResponse, GeneralErrorResponse> {
  KdfVersionRequest({required String rpcPass})
    : super(method: 'version', rpcPass: rpcPass, mmrpc: null);

  @override
  KdfVersionResponse parse(Map<String, dynamic> json) =>
      KdfVersionResponse.parse(json);
}

/// Response from `version`.
class KdfVersionResponse extends BaseResponse {
  KdfVersionResponse({required super.mmrpc, required this.version});

  factory KdfVersionResponse.parse(JsonMap json) {
    return KdfVersionResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      version: json.valueOrNull<String>('result') ?? '',
    );
  }

  /// KDF version string.
  final String version;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': version,
  };
}
