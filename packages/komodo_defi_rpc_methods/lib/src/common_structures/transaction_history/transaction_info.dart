import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class TransactionInfo {
  TransactionInfo({
    required this.txHash,
    required this.from,
    required this.to,
    required this.myBalanceChange,
    required this.blockHeight,
    required this.confirmations,
    required this.timestamp,
    required this.feeDetails,
    required this.coin,
    required this.internalId,
    required this.memo,
    this.txJson,
    this.spentByMe,
    this.receivedByMe,
    this.transactionFee,
  });

  factory TransactionInfo.fromJson(JsonMap json) {
    return TransactionInfo(
      txHash: json.value<String>('tx_hash'),
      from: List<String>.from(json.value('from')),
      to: List<String>.from(json.value('to')),
      txJson: json.valueOrNull<JsonMap>('tx_json'),
      myBalanceChange: json.value<String>('my_balance_change'),
      blockHeight: json.value<int>('block_height'),
      confirmations: json.value<int>('confirmations'),
      timestamp: json.value<int>('timestamp'),
      feeDetails: json.containsKey('fee_details')
          ? FeeInfo.fromJson(json.value('fee_details'))
          : null,
      transactionFee: json.valueOrNull<String>('transaction_fee'),
      coin: json.value<String>('coin'),
      internalId: json.value<String>('internal_id'),
      spentByMe: json.valueOrNull<String>('spent_by_me'),
      receivedByMe: json.valueOrNull<String>('received_by_me'),
      memo: json.valueOrNull<String>('memo'),
    );
  }

  final String txHash;
  final List<String> from;
  final List<String> to;
  final String myBalanceChange;
  final int blockHeight;
  final int confirmations;

  /// Raw transaction JSON (present for SIA protocol transactions).
  final JsonMap? txJson;
  final int timestamp;
  final FeeInfo? feeDetails;
  final String? transactionFee;
  final String coin;
  final String internalId;
  final String? spentByMe;
  final String? receivedByMe;
  final String? memo;

  Map<String, dynamic> toJson() => {
    'tx_hash': txHash,
    'from': from,
    'to': to,
    'tx_json': ?txJson,
    'my_balance_change': myBalanceChange,
    'block_height': blockHeight,
    'confirmations': confirmations,
    'timestamp': timestamp,
    if (feeDetails != null) 'fee_details': feeDetails!.toJson(),
    'coin': coin,
    'internal_id': internalId,
    if (spentByMe != null) 'spent_by_me': spentByMe,
    if (receivedByMe != null) 'received_by_me': receivedByMe,
    if (transactionFee != null) 'transaction_fee': transactionFee,
    if (memo != null) 'memo': memo,
  };
}
