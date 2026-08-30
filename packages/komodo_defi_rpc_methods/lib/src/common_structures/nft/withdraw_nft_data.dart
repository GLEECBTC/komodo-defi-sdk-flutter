import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Supported NFT withdrawal RPC operation types.
enum NftWithdrawType {
  /// Withdraw an ERC-721 NFT.
  erc721('withdraw_erc721'),

  /// Withdraw an ERC-1155 NFT.
  erc1155('withdraw_erc1155');

  const NftWithdrawType(this.rpcValue);

  /// RPC value sent under the `type` field.
  final String rpcValue;

  /// Parses a KDF NFT withdrawal type.
  static NftWithdrawType parse(String value) {
    return switch (value) {
      'withdraw_erc721' || 'ERC721' => NftWithdrawType.erc721,
      'withdraw_erc1155' || 'ERC1155' => NftWithdrawType.erc1155,
      _ => throw ArgumentError('Unknown NFT withdraw type: $value'),
    };
  }
}

/// Data required to withdraw an NFT.
class WithdrawNftData {
  const WithdrawNftData({
    required this.chain,
    required this.to,
    required this.tokenAddress,
    required this.tokenId,
    this.max,
    this.amount,
  });

  factory WithdrawNftData.fromJson(JsonMap json) {
    return WithdrawNftData(
      chain: json.value<String>('chain'),
      to: json.value<String>('to'),
      tokenAddress: json.value<String>('token_address'),
      tokenId: json.value<String>('token_id'),
      max: json.valueOrNull<bool>('max'),
      amount: json.valueOrNull<String>('amount'),
    );
  }

  /// NFT chain identifier.
  final String chain;

  /// Destination address.
  final String to;

  /// Token contract address.
  final String tokenAddress;

  /// Token id.
  final String tokenId;

  /// Whether to withdraw the maximum amount for ERC-1155 tokens.
  final bool? max;

  /// Amount for ERC-1155 withdrawals.
  final String? amount;

  Map<String, dynamic> toJson() => {
    'chain': chain,
    'to': to,
    'token_address': tokenAddress,
    'token_id': tokenId,
    if (max != null) 'max': max,
    if (amount != null) 'amount': amount,
  };
}
