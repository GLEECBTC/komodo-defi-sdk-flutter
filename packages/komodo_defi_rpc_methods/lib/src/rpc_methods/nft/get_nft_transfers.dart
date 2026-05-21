import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to fetch NFT transfer history.
class GetNftTransfersRequest
    extends BaseRequest<GetNftTransfersResponse, GeneralErrorResponse> {
  GetNftTransfersRequest({
    required String rpcPass,
    required this.chains,
    this.max = true,
    this.protectFromSpam = true,
    this.filters = const NftTransferFilter(
      excludeSpam: true,
      excludePhishing: true,
    ),
  }) : super(
         method: 'get_nft_transfers',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  /// NFT chain identifiers.
  final List<String> chains;

  /// Whether to fetch the maximum available set.
  final bool max;

  /// Whether KDF should apply its anti-spam protection.
  final bool protectFromSpam;

  /// Transfer filters to apply.
  final NftTransferFilter filters;

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
  GetNftTransfersResponse parse(Map<String, dynamic> json) =>
      GetNftTransfersResponse.parse(json);
}

/// Response from `get_nft_transfers`.
class GetNftTransfersResponse extends BaseResponse {
  GetNftTransfersResponse({required super.mmrpc, required this.transfers});

  factory GetNftTransfersResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    final transfersJson =
        result.valueOrNull<List<dynamic>>('transfer_history') ?? [];
    return GetNftTransfersResponse(
      mmrpc: json.value<String>('mmrpc'),
      transfers: transfersJson
          .map((item) => NftTransfer.fromJson(item as JsonMap))
          .toList(),
    );
  }

  /// NFT transfer history.
  final List<NftTransfer> transfers;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {'transfer_history': transfers.map((tx) => tx.toJson()).toList()},
  };
}
