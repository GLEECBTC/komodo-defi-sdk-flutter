import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Optional app-provided NFT transaction enrichment boundary.
///
/// Apps that maintain their own proxy/indexer can implement this interface and
/// pass it to [NftManager] without the SDK hardcoding provider URLs.
// Keep this as an interface so apps can plug in their own indexer/proxy.
// ignore: one_member_abstracts
abstract interface class NftTransactionDetailsProvider {
  /// Returns transfers enriched with optional fields such as confirmations or
  /// fee details.
  Future<List<NftTransfer>> enrichTransfers(List<NftTransfer> transfers);
}

/// High-level NFT helpers over KDF NFT RPCs.
class NftManager {
  /// Creates an [NftManager].
  NftManager({
    required ApiClient client,
    NftTransactionDetailsProvider? transactionDetailsProvider,
  }) : _client = client,
       _transactionDetailsProvider = transactionDetailsProvider;

  final ApiClient _client;
  final NftTransactionDetailsProvider? _transactionDetailsProvider;

  /// Lists NFTs cached by KDF for the provided chains.
  Future<List<NftTokenInfo>> getNftList({
    required List<String> chains,
    bool max = true,
    bool protectFromSpam = true,
    NftFilter filters = const NftFilter(
      excludeSpam: true,
      excludePhishing: true,
    ),
  }) async {
    final response = await _client.rpc.nft.getNftList(
      chains: chains,
      max: max,
      protectFromSpam: protectFromSpam,
      filters: filters,
    );
    return response.nfts;
  }

  /// Updates KDF's NFT cache for the provided chains.
  Future<NftOperationResponse> updateNft({
    required List<String> chains,
    String? url,
    String? urlAntispam,
    bool? komodoProxy,
  }) {
    return _client.rpc.nft.updateNft(
      chains: chains,
      url: url,
      urlAntispam: urlAntispam,
      komodoProxy: komodoProxy,
    );
  }

  /// Refreshes metadata for a single NFT.
  Future<NftOperationResponse> refreshNftMetadata({
    required String chain,
    required String tokenAddress,
    required String tokenId,
    String? url,
    String? urlAntispam,
    bool? komodoProxy,
  }) {
    return _client.rpc.nft.refreshNftMetadata(
      chain: chain,
      tokenAddress: tokenAddress,
      tokenId: tokenId,
      url: url,
      urlAntispam: urlAntispam,
      komodoProxy: komodoProxy,
    );
  }

  /// Builds a signed NFT withdrawal transaction.
  Future<NftTransactionDetails> withdrawNft({
    required NftWithdrawType type,
    required WithdrawNftData withdrawData,
  }) async {
    final response = await _client.rpc.nft.withdrawNft(
      type: type,
      withdrawData: withdrawData,
    );
    return response.result;
  }

  /// Gets NFT transfer history.
  ///
  /// When [withAdditionalDetails] is true and an
  /// [NftTransactionDetailsProvider] was supplied, transfers are enriched by
  /// that provider. Otherwise, the raw KDF transfer history is returned.
  Future<List<NftTransfer>> getNftTransfers({
    required List<String> chains,
    bool max = true,
    bool protectFromSpam = true,
    NftTransferFilter filters = const NftTransferFilter(
      excludeSpam: true,
      excludePhishing: true,
    ),
    bool withAdditionalDetails = false,
  }) async {
    final response = await _client.rpc.nft.getNftTransfers(
      chains: chains,
      max: max,
      protectFromSpam: protectFromSpam,
      filters: filters,
    );

    if (!withAdditionalDetails || _transactionDetailsProvider == null) {
      return response.transfers;
    }

    return _transactionDetailsProvider.enrichTransfers(response.transfers);
  }
}
