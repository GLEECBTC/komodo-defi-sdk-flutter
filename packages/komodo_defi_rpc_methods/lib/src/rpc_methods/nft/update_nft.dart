import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to update KDF's NFT cache for one or more chains.
class UpdateNftRequest
    extends BaseRequest<NftOperationResponse, GeneralErrorResponse> {
  UpdateNftRequest({
    required String rpcPass,
    required this.chains,
    required this.url,
    required this.urlAntispam,
    this.komodoProxy,
  }) : super(method: 'update_nft', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  /// NFT chain identifiers to update.
  final List<String> chains;

  /// NFT metadata/indexer URL supplied by the app.
  final String url;

  /// Anti-spam service URL supplied by the app.
  final String urlAntispam;

  /// Whether to use KDF's Komodo proxy setting.
  final bool? komodoProxy;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'chains': chains,
      'url': url,
      'url_antispam': urlAntispam,
      if (komodoProxy != null) 'komodo_proxy': komodoProxy,
    },
  });

  @override
  NftOperationResponse parse(Map<String, dynamic> json) =>
      NftOperationResponse.parse(json);
}

/// Generic response for NFT operations whose result shape is KDF-version
/// specific.
class NftOperationResponse extends BaseResponse {
  NftOperationResponse({required super.mmrpc, this.result});

  factory NftOperationResponse.parse(JsonMap json) {
    return NftOperationResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      result: json.valueOrNull<dynamic>('result'),
    );
  }

  /// Raw result payload, if KDF returned one.
  final dynamic result;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    if (result != null) 'result': result,
  };
}
