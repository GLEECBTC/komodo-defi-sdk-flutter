/// Filter options used by NFT transfer history APIs.
class NftTransferFilter {
  const NftTransferFilter({
    this.excludeSpam,
    this.excludePhishing,
    this.status,
    this.fromTimestamp,
    this.toTimestamp,
  });

  factory NftTransferFilter.fromJson(Map<String, dynamic> json) {
    return NftTransferFilter(
      excludeSpam: json['exclude_spam'] as bool?,
      excludePhishing: json['exclude_phishing'] as bool?,
      status: json['status'] as String?,
      fromTimestamp: (json['from_timestamp'] as num?)?.toInt(),
      toTimestamp: (json['to_timestamp'] as num?)?.toInt(),
    );
  }

  /// Exclude transfers for NFTs flagged as spam.
  final bool? excludeSpam;

  /// Exclude transfers for NFTs flagged as phishing.
  final bool? excludePhishing;

  /// Optional transfer status filter.
  final String? status;

  /// Lower timestamp bound in Unix seconds.
  final int? fromTimestamp;

  /// Upper timestamp bound in Unix seconds.
  final int? toTimestamp;

  Map<String, dynamic> toJson() => {
    if (excludeSpam != null) 'exclude_spam': excludeSpam,
    if (excludePhishing != null) 'exclude_phishing': excludePhishing,
    if (status != null) 'status': status,
    if (fromTimestamp != null) 'from_timestamp': fromTimestamp,
    if (toTimestamp != null) 'to_timestamp': toTimestamp,
  };
}
