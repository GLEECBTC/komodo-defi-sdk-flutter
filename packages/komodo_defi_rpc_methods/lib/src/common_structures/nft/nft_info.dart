import 'package:komodo_defi_rpc_methods/src/common_structures/nft/nft_metadata.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// NFT token information returned by `get_nft_list`.
class NftTokenInfo {
  const NftTokenInfo({
    required this.chain,
    required this.tokenAddress,
    required this.tokenId,
    required this.amount,
    required this.ownerOf,
    required this.contractType,
    this.tokenHash,
    this.blockNumberMinted,
    this.blockNumber,
    this.name,
    this.symbol,
    this.tokenUri,
    this.tokenDomain,
    this.metadata,
    this.lastTokenUriSync,
    this.lastMetadataSync,
    this.minterAddress,
    this.possibleSpam,
    this.possiblePhishing,
    this.uriMeta,
  });

  factory NftTokenInfo.fromJson(JsonMap json) {
    final uriMetaJson = json.valueOrNull<JsonMap>('uri_meta');
    return NftTokenInfo(
      chain: json.value<String>('chain'),
      tokenAddress: json.value<String>('token_address'),
      tokenId: json.value<String>('token_id'),
      amount: json.value<String>('amount'),
      ownerOf: json.value<String>('owner_of'),
      contractType: json.value<String>('contract_type'),
      tokenHash: json.valueOrNull<String>('token_hash'),
      blockNumberMinted: json.valueOrNull<int>('block_number_minted'),
      blockNumber: json.valueOrNull<int>('block_number'),
      name: json.valueOrNull<String>('name'),
      symbol: json.valueOrNull<String>('symbol'),
      tokenUri: json.valueOrNull<String>('token_uri'),
      tokenDomain: json.valueOrNull<String>('token_domain'),
      metadata: json.valueOrNull<String>('metadata'),
      lastTokenUriSync: json.valueOrNull<String>('last_token_uri_sync'),
      lastMetadataSync: json.valueOrNull<String>('last_metadata_sync'),
      minterAddress: json.valueOrNull<String>('minter_address'),
      possibleSpam: json.valueOrNull<bool>('possible_spam'),
      possiblePhishing: json.valueOrNull<bool>('possible_phishing'),
      uriMeta: uriMetaJson == null ? null : NftMetadata.fromJson(uriMetaJson),
    );
  }

  /// NFT chain identifier, for example `ETH` or `POLYGON`.
  final String chain;

  /// Token contract address.
  final String tokenAddress;

  /// Token id.
  final String tokenId;

  /// Token amount as a string numeric.
  final String amount;

  /// Owner address.
  final String ownerOf;

  /// NFT contract type, for example `ERC721` or `ERC1155`.
  final String contractType;

  /// Token hash if provided by the NFT indexer.
  final String? tokenHash;

  /// Mint block number.
  final int? blockNumberMinted;

  /// Latest block number associated with this token.
  final int? blockNumber;

  /// Collection or token name from KDF.
  final String? name;

  /// Token symbol.
  final String? symbol;

  /// Token URI.
  final String? tokenUri;

  /// Token URI domain.
  final String? tokenDomain;

  /// Raw metadata string returned by KDF.
  final String? metadata;

  /// Last token URI sync timestamp/string returned by KDF.
  final String? lastTokenUriSync;

  /// Last metadata sync timestamp/string returned by KDF.
  final String? lastMetadataSync;

  /// Minter address.
  final String? minterAddress;

  /// Whether the token is flagged as possible spam.
  final bool? possibleSpam;

  /// Whether the token is flagged as possible phishing.
  final bool? possiblePhishing;

  /// Parsed URI metadata.
  final NftMetadata? uriMeta;

  Map<String, dynamic> toJson() => {
    'chain': chain,
    'token_address': tokenAddress,
    'token_id': tokenId,
    'amount': amount,
    'owner_of': ownerOf,
    'contract_type': contractType,
    if (tokenHash != null) 'token_hash': tokenHash,
    if (blockNumberMinted != null) 'block_number_minted': blockNumberMinted,
    if (blockNumber != null) 'block_number': blockNumber,
    if (name != null) 'name': name,
    if (symbol != null) 'symbol': symbol,
    if (tokenUri != null) 'token_uri': tokenUri,
    if (tokenDomain != null) 'token_domain': tokenDomain,
    if (metadata != null) 'metadata': metadata,
    if (lastTokenUriSync != null) 'last_token_uri_sync': lastTokenUriSync,
    if (lastMetadataSync != null) 'last_metadata_sync': lastMetadataSync,
    if (minterAddress != null) 'minter_address': minterAddress,
    if (possibleSpam != null) 'possible_spam': possibleSpam,
    if (possiblePhishing != null) 'possible_phishing': possiblePhishing,
    if (uriMeta != null) 'uri_meta': uriMeta!.toJson(),
  };
}
