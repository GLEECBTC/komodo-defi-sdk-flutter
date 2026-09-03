import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Domain model for a transaction, decoupled from the API representation
class Transaction extends Equatable {
  const Transaction({
    required this.id,
    required this.internalId,
    required this.assetId,
    required this.balanceChanges,
    required this.timestamp,
    required this.confirmations,
    required this.blockHeight,
    required this.from,
    required this.to,
    required this.txHash,
    this.fee,
    this.memo,
  });

  factory Transaction.fromJson(JsonMap json) => Transaction(
    id: json.value<String>('id'),
    internalId: json.value<String>('internal_id'),
    assetId: AssetId.parse(json.value<JsonMap>('asset_id'), knownIds: null),
    balanceChanges: BalanceChanges.fromJson(json),
    timestamp: DateTime.parse(json.value<String>('timestamp')),
    confirmations: json.value<int>('confirmations'),
    blockHeight: json.value<int>('block_height'),
    from: List<String>.from(json.value('from')),
    to: List<String>.from(json.value('to')),
    txHash: json.valueOrNull<String>('tx_hash'),
    fee: json.containsKey('fee') || json.containsKey('fee_details')
        ? FeeInfo.fromJson(json.valueOrNull('fee') ?? json.value('fee_details'))
        : null,
    memo: json.valueOrNull<String>('memo'),
  );

  final String id;
  final String internalId;
  final AssetId assetId;
  final BalanceChanges balanceChanges;
  final DateTime timestamp;
  final int confirmations;

  // TODO! Investigate if this should be nullable. In theory it should be
  // but we haven't encountered any errors.
  final int blockHeight;
  final List<String> from;
  final List<String> to;
  final String? txHash;
  final FeeInfo? fee;
  final String? memo;

  /// Convenience getter for the net balance change
  Decimal get amount => balanceChanges.netChange;

  /// Convenience getter for whether transaction is incoming
  bool get isIncoming => balanceChanges.isIncoming;

  @override
  List<Object?> get props => [
    id,
    internalId,
    assetId,
    balanceChanges,
    timestamp,
    confirmations,
    blockHeight,
    from,
    to,
    txHash,
    fee,
    memo,
  ];

  JsonMap toJson() => {
    'id': id,
    'internal_id': internalId,
    'asset_id': assetId.toJson(),
    'balance_changes': balanceChanges.toJson(),
    'timestamp': timestamp.toIso8601String(),
    'confirmations': confirmations,
    'block_height': blockHeight,
    'from': from,
    'to': to,
    if (txHash != null) 'tx_hash': txHash,
    if (fee != null) 'fee': fee!.toJson(),
    if (memo != null) 'memo': memo,
  };

  Transaction copyWith({
    String? id,
    String? internalId,
    AssetId? assetId,
    BalanceChanges? balanceChanges,
    DateTime? timestamp,
    int? confirmations,
    int? blockHeight,
    List<String>? from,
    List<String>? to,
    String? txHash,
    FeeInfo? fee,
    String? memo,
  }) => Transaction(
    id: id ?? this.id,
    internalId: internalId ?? this.internalId,
    assetId: assetId ?? this.assetId,
    balanceChanges: balanceChanges ?? this.balanceChanges,
    timestamp: timestamp ?? this.timestamp,
    confirmations: confirmations ?? this.confirmations,
    blockHeight: blockHeight ?? this.blockHeight,
    from: from ?? this.from,
    to: to ?? this.to,
    txHash: txHash ?? this.txHash,
    fee: fee ?? this.fee,
    memo: memo ?? this.memo,
  );
}

extension TransactionInfoExtension on TransactionInfo {
  Transaction asTransaction(AssetId assetId) {
    final received = receivedByMe == null
        ? Decimal.zero
        : Decimal.parse(receivedByMe!);
    final spent = spentByMe == null ? Decimal.zero : Decimal.parse(spentByMe!);
    final total = received > spent ? received : spent;
    return Transaction(
      id: txHash,
      internalId: internalId,
      assetId: assetId,
      balanceChanges: BalanceChanges(
        netChange: Decimal.parse(myBalanceChange),
        receivedByMe: received,
        spentByMe: spent,
        totalAmount: total > Decimal.zero
            ? total
            : Decimal.parse(myBalanceChange).abs(),
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      confirmations: confirmations,
      blockHeight: blockHeight,
      from: from,
      to: to,
      txHash: txHash,
      fee: feeDetails,
      memo: memo,
    );
  }
}
