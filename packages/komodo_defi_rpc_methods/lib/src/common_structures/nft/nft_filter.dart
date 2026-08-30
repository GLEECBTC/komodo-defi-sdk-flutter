/// Filter options used by NFT list APIs.
class NftFilter {
  const NftFilter({this.excludeSpam, this.excludePhishing});

  factory NftFilter.fromJson(Map<String, dynamic> json) {
    return NftFilter(
      excludeSpam: json['exclude_spam'] as bool?,
      excludePhishing: json['exclude_phishing'] as bool?,
    );
  }

  /// Exclude NFTs flagged as spam.
  final bool? excludeSpam;

  /// Exclude NFTs flagged as phishing.
  final bool? excludePhishing;

  Map<String, dynamic> toJson() => {
    if (excludeSpam != null) 'exclude_spam': excludeSpam,
    if (excludePhishing != null) 'exclude_phishing': excludePhishing,
  };
}
