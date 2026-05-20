import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Fee details returned for NFT withdrawals or transfer enrichment.
class NftFeeDetails {
  const NftFeeDetails({
    required this.type,
    required this.coin,
    this.amount,
    this.totalFee,
    this.gasPrice,
    this.gas,
    this.gasLimit,
    this.minerFee,
    this.totalGasFee,
  });

  factory NftFeeDetails.fromJson(JsonMap json) {
    return NftFeeDetails(
      type: json.valueOrNull<String>('type') ?? '',
      coin: json.valueOrNull<String>('coin') ?? '',
      amount: json.valueOrNull<String>('amount'),
      totalFee: json.valueOrNull<String>('total_fee'),
      gasPrice: json.valueOrNull<String>('gas_price'),
      gas: json.valueOrNull<int>('gas'),
      gasLimit: json.valueOrNull<int>('gas_limit'),
      minerFee: json.valueOrNull<String>('miner_fee'),
      totalGasFee: json.valueOrNull<String>('total_gas_fee'),
    );
  }

  /// Fee type.
  final String type;

  /// Fee coin.
  final String coin;

  /// Simple amount field.
  final String? amount;

  /// Total fee field.
  final String? totalFee;

  /// Gas price for gas-based chains.
  final String? gasPrice;

  /// Gas used.
  final int? gas;

  /// Gas limit.
  final int? gasLimit;

  /// Miner fee.
  final String? minerFee;

  /// Total gas fee.
  final String? totalGasFee;

  Map<String, dynamic> toJson() => {
    'type': type,
    'coin': coin,
    if (amount != null) 'amount': amount,
    if (totalFee != null) 'total_fee': totalFee,
    if (gasPrice != null) 'gas_price': gasPrice,
    if (gas != null) 'gas': gas,
    if (gasLimit != null) 'gas_limit': gasLimit,
    if (minerFee != null) 'miner_fee': minerFee,
    if (totalGasFee != null) 'total_gas_fee': totalGasFee,
  };
}

/// NFT transaction details returned by `withdraw_nft`.
class NftTransactionDetails {
  const NftTransactionDetails({
    required this.txHash,
    required this.from,
    required this.to,
    required this.contractType,
    required this.tokenAddress,
    required this.tokenId,
    required this.amount,
    required this.feeDetails,
    required this.coin,
    required this.blockHeight,
    required this.timestamp,
    required this.internalId,
    required this.transactionType,
    this.txHex,
  });

  factory NftTransactionDetails.fromJson(JsonMap json) {
    return NftTransactionDetails(
      txHex: json.valueOrNull<String>('tx_hex'),
      txHash: json.value<String>('tx_hash'),
      from: List<String>.from(json.value<List<dynamic>>('from')),
      to: List<String>.from(json.value<List<dynamic>>('to')),
      contractType: json.value<String>('contract_type'),
      tokenAddress: json.value<String>('token_address'),
      tokenId: _firstOrString(json.value<dynamic>('token_id')),
      amount: _firstOrString(json.value<dynamic>('amount')),
      feeDetails: NftFeeDetails.fromJson(json.value<JsonMap>('fee_details')),
      coin: json.value<String>('coin'),
      blockHeight: json.valueOrNull<int>('block_height') ?? 0,
      timestamp: json.value<int>('timestamp'),
      internalId: json.valueOrNull<int>('internal_id') ?? 0,
      transactionType: json.value<String>('transaction_type'),
    );
  }

  /// Signed transaction hex, when returned by KDF.
  final String? txHex;

  /// Transaction hash.
  final String txHash;

  /// Source addresses.
  final List<String> from;

  /// Destination addresses.
  final List<String> to;

  /// Contract type, for example `ERC721`.
  final String contractType;

  /// Token contract address.
  final String tokenAddress;

  /// Token id.
  final String tokenId;

  /// Amount transferred.
  final String amount;

  /// Fee details.
  final NftFeeDetails feeDetails;

  /// Chain coin ticker.
  final String coin;

  /// Block height.
  final int blockHeight;

  /// Unix timestamp.
  final int timestamp;

  /// Internal KDF transaction id.
  final int internalId;

  /// Transaction type returned by KDF.
  final String transactionType;

  Map<String, dynamic> toJson() => {
    if (txHex != null) 'tx_hex': txHex,
    'tx_hash': txHash,
    'from': from,
    'to': to,
    'contract_type': contractType,
    'token_address': tokenAddress,
    'token_id': tokenId,
    'amount': amount,
    'fee_details': feeDetails.toJson(),
    'coin': coin,
    'block_height': blockHeight,
    'timestamp': timestamp,
    'internal_id': internalId,
    'transaction_type': transactionType,
  };
}

/// NFT transfer history item.
class NftTransfer {
  const NftTransfer({
    required this.chain,
    required this.blockNumber,
    required this.blockTimestamp,
    required this.transactionHash,
    required this.contractType,
    required this.tokenAddress,
    required this.tokenId,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    required this.verified,
    required this.possibleSpam,
    this.blockHash,
    this.confirmations,
    this.feeDetails,
    this.transactionIndex,
    this.logIndex,
    this.value,
    this.transactionType,
    this.operator,
    this.collectionName,
    this.imageUrl,
    this.imageDomain,
    this.tokenName,
    this.tokenUri,
    this.tokenDomain,
    this.status,
    this.possiblePhishing,
  });

  factory NftTransfer.fromJson(JsonMap json) {
    final feeDetailsJson = json.valueOrNull<JsonMap>('fee_details');
    return NftTransfer(
      chain: json.value<String>('chain'),
      blockNumber: json.value<int>('block_number'),
      blockTimestamp: json.value<int>('block_timestamp'),
      blockHash: json.valueOrNull<String>('block_hash'),
      confirmations: json.valueOrNull<int>('confirmations'),
      feeDetails: feeDetailsJson == null
          ? null
          : NftFeeDetails.fromJson(feeDetailsJson),
      transactionHash: json.value<String>('transaction_hash'),
      transactionIndex: json.valueOrNull<int>('transaction_index'),
      logIndex: json.valueOrNull<int>('log_index'),
      value: json.valueOrNull<String>('value'),
      contractType: json.value<String>('contract_type'),
      transactionType: json.valueOrNull<String>('transaction_type'),
      tokenAddress: json.value<String>('token_address'),
      tokenId: json.value<String>('token_id'),
      fromAddress: json.value<String>('from_address'),
      toAddress: json.value<String>('to_address'),
      amount: json.value<String>('amount'),
      verified: json.value<bool>('verified'),
      operator: json.valueOrNull<String>('operator'),
      collectionName: json.valueOrNull<String>('collection_name'),
      imageUrl: json.valueOrNull<String>('image_url'),
      imageDomain: json.valueOrNull<String>('image_domain'),
      tokenName: json.valueOrNull<String>('token_name'),
      tokenUri: json.valueOrNull<String>('token_uri'),
      tokenDomain: json.valueOrNull<String>('token_domain'),
      status: json.valueOrNull<String>('status'),
      possibleSpam: json.value<bool>('possible_spam'),
      possiblePhishing: json.valueOrNull<bool>('possible_phishing'),
    );
  }

  /// Chain identifier.
  final String chain;

  /// Block number.
  final int blockNumber;

  /// Block timestamp in Unix seconds.
  final int blockTimestamp;

  /// Block hash.
  final String? blockHash;

  /// Confirmations added by KDF or optional app enrichment.
  final int? confirmations;

  /// Fee details added by KDF or optional app enrichment.
  final NftFeeDetails? feeDetails;

  /// Transaction hash.
  final String transactionHash;

  /// Transaction index.
  final int? transactionIndex;

  /// Log index.
  final int? logIndex;

  /// Transfer value.
  final String? value;

  /// Contract type.
  final String contractType;

  /// Transaction type.
  final String? transactionType;

  /// Token contract address.
  final String tokenAddress;

  /// Token id.
  final String tokenId;

  /// Sender address.
  final String fromAddress;

  /// Recipient address.
  final String toAddress;

  /// Amount transferred.
  final String amount;

  /// Verification flag returned by KDF.
  final bool verified;

  /// Operator address.
  final String? operator;

  /// Collection name.
  final String? collectionName;

  /// Image URL.
  final String? imageUrl;

  /// Image URL domain.
  final String? imageDomain;

  /// Token name.
  final String? tokenName;

  /// Token URI.
  final String? tokenUri;

  /// Token URI domain.
  final String? tokenDomain;

  /// Transfer status, for example `Receive` or `Send`.
  final String? status;

  /// Whether KDF flagged this transfer as possible spam.
  final bool possibleSpam;

  /// Whether KDF flagged this transfer as possible phishing.
  final bool? possiblePhishing;

  /// Creates a copy with additional details, commonly provided by an app proxy.
  NftTransfer copyWith({int? confirmations, NftFeeDetails? feeDetails}) {
    return NftTransfer(
      chain: chain,
      blockNumber: blockNumber,
      blockTimestamp: blockTimestamp,
      transactionHash: transactionHash,
      contractType: contractType,
      tokenAddress: tokenAddress,
      tokenId: tokenId,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amount: amount,
      verified: verified,
      possibleSpam: possibleSpam,
      blockHash: blockHash,
      confirmations: confirmations ?? this.confirmations,
      feeDetails: feeDetails ?? this.feeDetails,
      transactionIndex: transactionIndex,
      logIndex: logIndex,
      value: value,
      transactionType: transactionType,
      operator: operator,
      collectionName: collectionName,
      imageUrl: imageUrl,
      imageDomain: imageDomain,
      tokenName: tokenName,
      tokenUri: tokenUri,
      tokenDomain: tokenDomain,
      status: status,
      possiblePhishing: possiblePhishing,
    );
  }

  Map<String, dynamic> toJson() => {
    'chain': chain,
    'block_number': blockNumber,
    'block_timestamp': blockTimestamp,
    if (blockHash != null) 'block_hash': blockHash,
    if (confirmations != null) 'confirmations': confirmations,
    if (feeDetails != null) 'fee_details': feeDetails!.toJson(),
    'transaction_hash': transactionHash,
    if (transactionIndex != null) 'transaction_index': transactionIndex,
    if (logIndex != null) 'log_index': logIndex,
    if (value != null) 'value': value,
    'contract_type': contractType,
    if (transactionType != null) 'transaction_type': transactionType,
    'token_address': tokenAddress,
    'token_id': tokenId,
    'from_address': fromAddress,
    'to_address': toAddress,
    'amount': amount,
    'verified': verified,
    if (operator != null) 'operator': operator,
    if (collectionName != null) 'collection_name': collectionName,
    if (imageUrl != null) 'image_url': imageUrl,
    if (imageDomain != null) 'image_domain': imageDomain,
    if (tokenName != null) 'token_name': tokenName,
    if (tokenUri != null) 'token_uri': tokenUri,
    if (tokenDomain != null) 'token_domain': tokenDomain,
    if (status != null) 'status': status,
    'possible_spam': possibleSpam,
    if (possiblePhishing != null) 'possible_phishing': possiblePhishing,
  };
}

String _firstOrString(dynamic value) {
  if (value is List && value.isNotEmpty) return value.first.toString();
  return value.toString();
}
