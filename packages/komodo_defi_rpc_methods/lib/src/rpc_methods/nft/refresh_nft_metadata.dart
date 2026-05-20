import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to refresh metadata for a single NFT.
class RefreshNftMetadataRequest
    extends BaseRequest<NftOperationResponse, GeneralErrorResponse> {
  RefreshNftMetadataRequest({
    required String rpcPass,
    required this.chain,
    required this.tokenAddress,
    required this.tokenId,
    required this.url,
    required this.urlAntispam,
    this.komodoProxy,
  }) : super(
         method: 'refresh_nft_metadata',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  /// NFT chain identifier.
  final String chain;

  /// Token contract address.
  final String tokenAddress;

  /// Token id.
  final String tokenId;

  /// NFT metadata/indexer URL supplied by the app.
  final String url;

  /// Anti-spam service URL supplied by the app.
  final String urlAntispam;

  /// Whether to use KDF's Komodo proxy setting.
  final bool? komodoProxy;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'chain': chain,
      'token_address': tokenAddress,
      'token_id': tokenId,
      'url': url,
      'url_antispam': urlAntispam,
      if (komodoProxy != null) 'komodo_proxy': komodoProxy,
    },
  });

  @override
  NftOperationResponse parse(Map<String, dynamic> json) =>
      NftOperationResponse.parse(json);
}
