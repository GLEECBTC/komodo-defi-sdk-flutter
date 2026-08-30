/// Filter options used by NFT transfer history APIs.
class NftTransferFilter {
  const NftTransferFilter({
    this.excludeSpam,
    this.excludePhishing,
    this.receive,
    this.send,
    this.fromDate,
    this.toDate,
  });

  factory NftTransferFilter.fromJson(Map<String, dynamic> json) {
    return NftTransferFilter(
      excludeSpam: json['exclude_spam'] as bool?,
      excludePhishing: json['exclude_phishing'] as bool?,
      receive: json['receive'] as bool?,
      send: json['send'] as bool?,
      fromDate: (json['from_date'] as num?)?.toInt(),
      toDate: (json['to_date'] as num?)?.toInt(),
    );
  }

  /// Exclude transfers for NFTs flagged as spam.
  final bool? excludeSpam;

  /// Exclude transfers for NFTs flagged as phishing.
  final bool? excludePhishing;

  /// Include received NFT transfers.
  final bool? receive;

  /// Include sent NFT transfers.
  final bool? send;

  /// Lower timestamp bound in Unix seconds.
  final int? fromDate;

  /// Upper timestamp bound in Unix seconds.
  final int? toDate;

  Map<String, dynamic> toJson() => {
    if (excludeSpam != null) 'exclude_spam': excludeSpam,
    if (excludePhishing != null) 'exclude_phishing': excludePhishing,
    if (receive != null) 'receive': receive,
    if (send != null) 'send': send,
    if (fromDate != null) 'from_date': fromDate,
    if (toDate != null) 'to_date': toDate,
  };
}
