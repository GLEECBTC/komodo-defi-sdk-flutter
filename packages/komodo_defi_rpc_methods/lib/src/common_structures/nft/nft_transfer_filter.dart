class NftTransferFilter {
  const NftTransferFilter({
    this.excludePhishing,
    this.excludeSpam,
    this.fromDate,
    this.receive,
    this.send,
    this.toDate,
  });

  final bool? excludePhishing;
  final bool? excludeSpam;
  final int? fromDate;
  final bool? receive;
  final bool? send;
  final int? toDate;

  Map<String, dynamic> toJson() => {
    if (excludePhishing != null) 'exclude_phishing': excludePhishing,
    if (excludeSpam != null) 'exclude_spam': excludeSpam,
    if (fromDate != null) 'from_date': fromDate,
    if (receive != null) 'receive': receive,
    if (send != null) 'send': send,
    if (toDate != null) 'to_date': toDate,
  };
}
