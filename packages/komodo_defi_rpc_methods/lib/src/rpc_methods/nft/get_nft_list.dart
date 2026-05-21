import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to list NFTs cached by KDF for activated NFT chains.
class GetNftListRequest
    extends BaseRequest<GetNftListResponse, GeneralErrorResponse> {
  GetNftListRequest({
    required String rpcPass,
    required this.chains,
    this.max = true,
    this.protectFromSpam = true,
    this.filters = const NftFilter(excludeSpam: true, excludePhishing: true),
  }) : super(method: 'get_nft_list', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  /// NFT chain identifiers, for example `ETH`, `BSC`, or `POLYGON`.
  final List<String> chains;

  /// Whether to fetch the maximum available set.
  final bool max;

  /// Whether KDF should apply its anti-spam protection.
  final bool protectFromSpam;

  /// NFT filters to apply.
  final NftFilter filters;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'chains': chains,
      'max': max,
      'protect_from_spam': protectFromSpam,
      'filters': filters.toJson(),
    },
  });

  @override
  GetNftListResponse parse(Map<String, dynamic> json) =>
      GetNftListResponse.parse(json);
}

/// Response from `get_nft_list`.
class GetNftListResponse extends BaseResponse {
  GetNftListResponse({required super.mmrpc, required this.nfts});

  factory GetNftListResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    final nftsJson = result.valueOrNull<List<dynamic>>('nfts') ?? [];
    return GetNftListResponse(
      mmrpc: json.value<String>('mmrpc'),
      nfts: nftsJson
          .map((item) => NftTokenInfo.fromJson(item as JsonMap))
          .toList(),
    );
  }

  /// NFT tokens returned by KDF.
  final List<NftTokenInfo> nfts;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {'nfts': nfts.map((nft) => nft.toJson()).toList()},
  };
}
