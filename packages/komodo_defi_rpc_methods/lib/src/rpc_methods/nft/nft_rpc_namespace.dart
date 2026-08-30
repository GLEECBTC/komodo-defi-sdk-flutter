import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// Extensions for NFT-related RPC methods
class NftMethodsNamespace extends BaseRpcMethodNamespace {
  NftMethodsNamespace(super.client);

  /// Enables NFT functionality for a given coin
  Future<EnableNftResponse> enableNft({
    required String ticker,
    required NftActivationParams activationParams,
  }) {
    return execute(
      EnableNftRequest(
        rpcPass: rpcPass ?? '',
        ticker: ticker,
        activationParams: activationParams,
      ),
    );
  }

  /// Lists NFTs cached by KDF for the provided chains.
  Future<GetNftListResponse> getNftList({
    required List<String> chains,
    bool max = true,
    bool protectFromSpam = true,
    NftFilter filters = const NftFilter(
      excludeSpam: true,
      excludePhishing: true,
    ),
    String? rpcPass,
  }) {
    return execute(
      GetNftListRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        chains: chains,
        max: max,
        protectFromSpam: protectFromSpam,
        filters: filters,
      ),
    );
  }

  /// Updates KDF's NFT cache for the provided chains.
  Future<NftOperationResponse> updateNft({
    required List<String> chains,
    required String url,
    required String urlAntispam,
    bool? komodoProxy,
    String? rpcPass,
  }) {
    return execute(
      UpdateNftRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        chains: chains,
        url: url,
        urlAntispam: urlAntispam,
        komodoProxy: komodoProxy,
      ),
    );
  }

  /// Refreshes metadata for a single NFT.
  Future<NftOperationResponse> refreshNftMetadata({
    required String chain,
    required String tokenAddress,
    required String tokenId,
    required String url,
    required String urlAntispam,
    bool? komodoProxy,
    String? rpcPass,
  }) {
    return execute(
      RefreshNftMetadataRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        chain: chain,
        tokenAddress: tokenAddress,
        tokenId: tokenId,
        url: url,
        urlAntispam: urlAntispam,
        komodoProxy: komodoProxy,
      ),
    );
  }

  /// Builds a signed NFT withdrawal transaction.
  Future<WithdrawNftResponse> withdrawNft({
    required NftWithdrawType type,
    required WithdrawNftData withdrawData,
    String? rpcPass,
  }) {
    return execute(
      WithdrawNftRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        type: type,
        withdrawData: withdrawData,
      ),
    );
  }

  /// Gets NFT transfer history for the provided chains.
  Future<GetNftTransfersResponse> getNftTransfers({
    required List<String> chains,
    bool max = true,
    bool protectFromSpam = true,
    NftTransferFilter filters = const NftTransferFilter(
      excludeSpam: true,
      excludePhishing: true,
    ),
    String? rpcPass,
  }) {
    return execute(
      GetNftTransfersRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        chains: chains,
        max: max,
        protectFromSpam: protectFromSpam,
        filters: filters,
      ),
    );
  }
}
