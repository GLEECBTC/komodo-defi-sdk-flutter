import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Thrown when a stored record cannot be decoded into a [Transaction].
class TransactionRecordFormatException implements Exception {
  /// Creates a decode failure with a human-readable [message].
  TransactionRecordFormatException(this.message);

  /// What was wrong with the record.
  final String message;

  @override
  String toString() => 'TransactionRecordFormatException: $message';
}

/// Thrown when a record was written by a newer schema than this build knows.
///
/// Callers drop the record rather than failing: transaction history is fully
/// reconstructible from the network, so a downgrade should cost a refetch
/// rather than break the wallet.
class TransactionRecordVersionException implements Exception {
  /// Creates a version mismatch for the given [version].
  TransactionRecordVersionException(this.version);

  /// The record's declared schema version.
  final int version;

  @override
  String toString() =>
      'TransactionRecordVersionException: record schema v$version is newer '
      'than the supported v${TransactionRecordCodec.currentVersion}';
}

/// A [ChainId] rebuilt from storage.
///
/// Only used when no live [AssetId] is available to rebuild from - see
/// [TransactionRecordCodec.decode]. `AssetId.props` compares
/// `chainId.formattedChainId` rather than the [ChainId] object, so an
/// [AssetId] carrying this type still compares equal to the live one.
class StoredChainId extends ChainId {
  /// Creates a chain identity from its persisted parts.
  StoredChainId({required this.formattedChainId, required this.decimals});

  @override
  final String formattedChainId;

  @override
  final int? decimals;

  @override
  List<Object?> get props => [formattedChainId, decimals];
}

/// Lossless, versioned JSON codec for [Transaction].
///
/// ## Why not `Transaction.toJson` / `Transaction.fromJson`
///
/// Those exist to parse the KDF wire format, and do not round-trip:
///
/// * `toJson` nests `balance_changes`, but `fromJson` passes the whole map to
///   `BalanceChanges.fromJson`, which reads `my_balance_change` at the top
///   level - so decoding an encoded transaction throws.
/// * `AssetId.toJson` writes `chain_id` as a formatted String while
///   `AssetChainId.fromConfig` reads an `int`, so every `ChainId.parse`
///   candidate fails.
/// * `AssetSymbol`'s external price-provider IDs are written nested and read
///   at the top level, so all four silently become `null`; `parentId` is
///   written as a bare ticker that `Transaction.fromJson` cannot resolve
///   because it passes `knownIds: null`.
/// * `FeeInfoTendermint.toJson` emits `'type': 'CosmosGas'`, so it decodes
///   back as a *different* variant, and `FeeInfoQrc20Gas`/`FeeInfoCosmosGas`
///   write `gas_price` through `double`, losing [Decimal] precision.
///
/// This codec is therefore independent of them. Two conventions carry most of
/// the correctness:
///
/// * Every [Decimal] is stored as `toString()`. `Decimal.toString` emits plain
///   notation and `Decimal.==` compares by value, so the round-trip is exact.
/// * [FeeInfo] is tagged by its **Dart** variant, resolved through an
///   exhaustive `switch` over the sealed type - never by the wire `type`.
///   Because the type is sealed, adding a variant upstream turns into a
///   compile error here rather than silent data loss.
abstract final class TransactionRecordCodec {
  /// Schema version written into every record.
  static const int currentVersion = 1;

  /// Encodes [transaction] as a self-describing JSON record.
  static String encode(Transaction transaction) =>
      jsonEncode(encodeToMap(transaction));

  /// Encodes [transaction] into its map form, before serialization.
  static Map<String, Object?> encodeToMap(Transaction transaction) {
    final assetId = transaction.assetId;
    final symbol = assetId.symbol;
    final balance = transaction.balanceChanges;
    return {
      'v': currentVersion,
      'id': transaction.id,
      'internal_id': transaction.internalId,
      // Microseconds plus the UTC flag: DateTime equality compares both, and
      // Transaction is Equatable with timestamp among its props, so dropping
      // isUtc would make restored rows compare unequal to freshly parsed ones.
      'ts_us': transaction.timestamp.microsecondsSinceEpoch,
      'ts_utc': transaction.timestamp.isUtc,
      'confirmations': transaction.confirmations,
      'block_height': transaction.blockHeight,
      // Order matters: Transaction.props compares these lists element-wise.
      'from': transaction.from,
      'to': transaction.to,
      'tx_hash': transaction.txHash,
      'memo': transaction.memo,
      'balance': {
        'net': balance.netChange.toString(),
        'received': balance.receivedByMe.toString(),
        'spent': balance.spentByMe.toString(),
        'total': balance.totalAmount.toString(),
      },
      'asset': {
        'coin': assetId.id,
        'name': assetId.name,
        // The enum NAME, never `subClass.formatted`: CoinSubClass.parse
        // sanitizes its input but matches against un-sanitized formatted
        // names, so every multi-word name ('Komodo Smart Chain',
        // 'Avalanche C-Chain', ...) is unresolvable, and 'Ethereum' resolves
        // to ethereumClassic rather than erc20.
        'sub_class': assetId.subClass.name,
        'chain_id': assetId.chainId.formattedChainId,
        'decimals': assetId.chainId.decimals,
        'derivation_path': assetId.derivationPath,
        'parent_coin': assetId.parentId?.id,
        'symbol': {
          'asset_config_id': symbol.assetConfigId,
          'coinpaprika_id': symbol.coinPaprikaId,
          'coingecko_id': symbol.coinGeckoId,
          'livecoinwatch_id': symbol.liveCoinWatchId,
          'binance_id': symbol.binanceId,
        },
      },
      'fee': transaction.fee == null
          ? null
          : FeeRecordCodec.encode(transaction.fee!),
    };
  }

  /// Decodes a record written by [encode].
  ///
  /// When [scopedAssetId] is supplied - which every wallet-and-asset-scoped
  /// read can do, because the caller already holds the live [AssetId] - the
  /// decoded transaction carries that instance verbatim. That keeps `parentId`
  /// linkage, the concrete [ChainId] subtype and the symbol's price-provider
  /// IDs exactly as the rest of the SDK produced them, instead of a
  /// reconstruction. Without it the asset identity is rebuilt from the record,
  /// which compares equal but loses `parentId`.
  ///
  /// Throws [TransactionRecordVersionException] for a newer schema and
  /// [TransactionRecordFormatException] for anything unreadable.
  static Transaction decode(String raw, {AssetId? scopedAssetId}) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException catch (e) {
      throw TransactionRecordFormatException('record is not valid JSON: $e');
    }
    if (parsed is! Map<String, Object?>) {
      throw TransactionRecordFormatException('record is not a JSON object');
    }
    return decodeFromMap(parsed, scopedAssetId: scopedAssetId);
  }

  /// Decodes a record already parsed into map form.
  static Transaction decodeFromMap(
    Map<String, Object?> json, {
    AssetId? scopedAssetId,
  }) {
    final version = _readInt(json, 'v');
    if (version > currentVersion) {
      throw TransactionRecordVersionException(version);
    }

    final balance = _readMap(json, 'balance');
    final timestamp = DateTime.fromMicrosecondsSinceEpoch(
      _readInt(json, 'ts_us'),
      isUtc: _readBool(json, 'ts_utc'),
    );

    return Transaction(
      id: _readString(json, 'id'),
      internalId: _readString(json, 'internal_id'),
      assetId: scopedAssetId ?? _decodeAssetId(_readMap(json, 'asset')),
      balanceChanges: BalanceChanges(
        netChange: _readDecimal(balance, 'net'),
        receivedByMe: _readDecimal(balance, 'received'),
        spentByMe: _readDecimal(balance, 'spent'),
        totalAmount: _readDecimal(balance, 'total'),
      ),
      timestamp: timestamp,
      confirmations: _readInt(json, 'confirmations'),
      blockHeight: _readInt(json, 'block_height'),
      from: _readStringList(json, 'from'),
      to: _readStringList(json, 'to'),
      txHash: _readOptionalString(json, 'tx_hash'),
      fee: json['fee'] == null
          ? null
          : FeeRecordCodec.decode(_readMap(json, 'fee')),
      memo: _readOptionalString(json, 'memo'),
    );
  }

  static AssetId _decodeAssetId(Map<String, Object?> json) {
    final symbol = _readMap(json, 'symbol');
    final subClassName = _readString(json, 'sub_class');
    return AssetId(
      id: _readString(json, 'coin'),
      name: _readString(json, 'name'),
      symbol: AssetSymbol(
        assetConfigId: _readString(symbol, 'asset_config_id'),
        coinPaprikaId: _readOptionalString(symbol, 'coinpaprika_id'),
        coinGeckoId: _readOptionalString(symbol, 'coingecko_id'),
        liveCoinWatchId: _readOptionalString(symbol, 'livecoinwatch_id'),
        binanceId: _readOptionalString(symbol, 'binance_id'),
      ),
      chainId: StoredChainId(
        formattedChainId: _readString(json, 'chain_id'),
        decimals: _readOptionalInt(json, 'decimals'),
      ),
      derivationPath: _readOptionalString(json, 'derivation_path'),
      subClass:
          CoinSubClass.values.firstWhereOrNull(
            (value) => value.name == subClassName,
          ) ??
          CoinSubClass.unknown,
      // Parent linkage cannot be rebuilt without the live asset registry.
      // It is not part of AssetId.props, so equality is unaffected.
    );
  }
}

/// Codec for the [FeeInfo] union, tagged by Dart variant name.
abstract final class FeeRecordCodec {
  /// Encodes [fee] into its map form.
  ///
  /// The tag comes from an exhaustive switch over the sealed type rather than
  /// `fee.toJson()['type']`, which is lossy: `FeeInfoTendermint` serializes as
  /// `CosmosGas` and would decode back as the wrong variant, and the Qrc20 and
  /// Cosmos variants push `gas_price` through `double`.
  static Map<String, Object?> encode(FeeInfo fee) => switch (fee) {
    FeeInfoUtxoFixed(:final coin, :final amount) => {
      'k': 'utxoFixed',
      'coin': coin,
      'amount': amount.toString(),
    },
    FeeInfoUtxoPerKbyte(:final coin, :final amount) => {
      'k': 'utxoPerKbyte',
      'coin': coin,
      'amount': amount.toString(),
    },
    FeeInfoEthGas(
      :final coin,
      :final gasPrice,
      :final gas,
      :final totalGasFee,
    ) =>
      {
        'k': 'ethGas',
        'coin': coin,
        'gas_price': gasPrice.toString(),
        'gas': gas,
        'total_gas_fee': totalGasFee?.toString(),
      },
    FeeInfoEthGasEip1559(
      :final coin,
      :final maxFeePerGas,
      :final maxPriorityFeePerGas,
      :final gas,
      :final totalGasFee,
    ) =>
      {
        'k': 'ethGasEip1559',
        'coin': coin,
        'max_fee_per_gas': maxFeePerGas.toString(),
        'max_priority_fee_per_gas': maxPriorityFeePerGas.toString(),
        'gas': gas,
        'total_gas_fee': totalGasFee?.toString(),
      },
    FeeInfoQrc20Gas(
      :final coin,
      :final gasPrice,
      :final gasLimit,
      :final totalGasFee,
    ) =>
      {
        'k': 'qrc20Gas',
        'coin': coin,
        'gas_price': gasPrice.toString(),
        'gas_limit': gasLimit,
        'total_gas_fee': totalGasFee?.toString(),
      },
    FeeInfoCosmosGas(:final coin, :final gasPrice, :final gasLimit) => {
      'k': 'cosmosGas',
      'coin': coin,
      'gas_price': gasPrice.toString(),
      'gas_limit': gasLimit,
    },
    FeeInfoTendermint(:final coin, :final amount, :final gasLimit) => {
      'k': 'tendermint',
      'coin': coin,
      'amount': amount.toString(),
      'gas_limit': gasLimit,
    },
    FeeInfoTron(
      :final coin,
      :final bandwidthUsed,
      :final energyUsed,
      :final bandwidthFee,
      :final energyFee,
      :final accountCreationFee,
      :final totalFeeAmount,
    ) =>
      {
        'k': 'tron',
        'coin': coin,
        'bandwidth_used': bandwidthUsed,
        'energy_used': energyUsed,
        'bandwidth_fee': bandwidthFee.toString(),
        'energy_fee': energyFee.toString(),
        'account_creation_fee': accountCreationFee?.toString(),
        'total_fee_amount': totalFeeAmount?.toString(),
      },
    FeeInfoTronGasless(
      :final coin,
      :final feeMethod,
      :final providerName,
      :final gasfreeAddress,
      :final transferFee,
      :final totalTokenFee,
      :final signedMaxFee,
      :final activationFee,
    ) =>
      {
        'k': 'tronGasless',
        'coin': coin,
        'fee_method': feeMethod,
        'provider_name': providerName,
        'gasfree_address': gasfreeAddress,
        'transfer_fee': transferFee.toString(),
        'total_token_fee': totalTokenFee.toString(),
        'signed_max_fee': signedMaxFee.toString(),
        'activation_fee': activationFee?.toString(),
      },
    FeeInfoSia(:final coin, :final amount, :final policy) => {
      'k': 'sia',
      'coin': coin,
      'amount': amount.toString(),
      'policy': policy,
    },
  };

  /// Decodes a record written by [encode].
  ///
  /// Calls the freezed constructors directly, so `FeeInfoTronGasless`'s wire
  /// validation - unknown-key rejection, the `trace_id` gate, the
  /// `total == transfer + activation` invariant - is deliberately bypassed.
  /// This restores an object that was already validated when it was parsed
  /// from KDF; re-validating would reject legitimately stored values such as a
  /// zero activation fee.
  static FeeInfo decode(Map<String, Object?> json) {
    final kind = json['k'];
    return switch (kind) {
      'utxoFixed' => FeeInfo.utxoFixed(
        coin: _string(json, 'coin'),
        amount: _decimal(json, 'amount'),
      ),
      'utxoPerKbyte' => FeeInfo.utxoPerKbyte(
        coin: _string(json, 'coin'),
        amount: _decimal(json, 'amount'),
      ),
      'ethGas' => FeeInfo.ethGas(
        coin: _string(json, 'coin'),
        gasPrice: _decimal(json, 'gas_price'),
        gas: _int(json, 'gas'),
        totalGasFee: _optionalDecimal(json, 'total_gas_fee'),
      ),
      'ethGasEip1559' => FeeInfo.ethGasEip1559(
        coin: _string(json, 'coin'),
        maxFeePerGas: _decimal(json, 'max_fee_per_gas'),
        maxPriorityFeePerGas: _decimal(json, 'max_priority_fee_per_gas'),
        gas: _int(json, 'gas'),
        totalGasFee: _optionalDecimal(json, 'total_gas_fee'),
      ),
      'qrc20Gas' => FeeInfo.qrc20Gas(
        coin: _string(json, 'coin'),
        gasPrice: _decimal(json, 'gas_price'),
        gasLimit: _int(json, 'gas_limit'),
        totalGasFee: _optionalDecimal(json, 'total_gas_fee'),
      ),
      'cosmosGas' => FeeInfo.cosmosGas(
        coin: _string(json, 'coin'),
        gasPrice: _decimal(json, 'gas_price'),
        gasLimit: _int(json, 'gas_limit'),
      ),
      'tendermint' => FeeInfo.tendermint(
        coin: _string(json, 'coin'),
        amount: _decimal(json, 'amount'),
        gasLimit: _int(json, 'gas_limit'),
      ),
      'tron' => FeeInfo.tron(
        coin: _string(json, 'coin'),
        bandwidthUsed: _int(json, 'bandwidth_used'),
        energyUsed: _int(json, 'energy_used'),
        bandwidthFee: _decimal(json, 'bandwidth_fee'),
        energyFee: _decimal(json, 'energy_fee'),
        accountCreationFee: _optionalDecimal(json, 'account_creation_fee'),
        totalFeeAmount: _optionalDecimal(json, 'total_fee_amount'),
      ),
      'tronGasless' => FeeInfo.tronGasless(
        coin: _string(json, 'coin'),
        feeMethod: _string(json, 'fee_method'),
        providerName: _string(json, 'provider_name'),
        gasfreeAddress: _string(json, 'gasfree_address'),
        transferFee: _decimal(json, 'transfer_fee'),
        totalTokenFee: _decimal(json, 'total_token_fee'),
        signedMaxFee: _decimal(json, 'signed_max_fee'),
        activationFee: _optionalDecimal(json, 'activation_fee'),
      ),
      'sia' => FeeInfo.sia(
        coin: _string(json, 'coin'),
        amount: _decimal(json, 'amount'),
        policy: _string(json, 'policy'),
      ),
      _ => throw TransactionRecordFormatException('unknown fee kind "$kind"'),
    };
  }

  static String _string(Map<String, Object?> json, String key) =>
      _readString(json, key);

  static int _int(Map<String, Object?> json, String key) => _readInt(json, key);

  static Decimal _decimal(Map<String, Object?> json, String key) =>
      _readDecimal(json, key);

  static Decimal? _optionalDecimal(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    return _readDecimal(json, key);
  }
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw TransactionRecordFormatException('"$key" is not a string');
  }
  return value;
}

String? _readOptionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw TransactionRecordFormatException('"$key" is not a string');
  }
  return value;
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw TransactionRecordFormatException('"$key" is not a number');
  }
  return value.toInt();
}

int? _readOptionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return _readInt(json, key);
}

bool _readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw TransactionRecordFormatException('"$key" is not a boolean');
  }
  return value;
}

Decimal _readDecimal(Map<String, Object?> json, String key) {
  final value = _readString(json, key);
  try {
    return Decimal.parse(value);
  } on FormatException {
    throw TransactionRecordFormatException('"$key" is not a decimal: $value');
  }
}

List<String> _readStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw TransactionRecordFormatException('"$key" is not a list');
  }
  return value.map((entry) {
    if (entry is! String) {
      throw TransactionRecordFormatException('"$key" contains a non-string');
    }
    return entry;
  }).toList();
}

Map<String, Object?> _readMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw TransactionRecordFormatException('"$key" is not an object');
  }
  return value.cast<String, Object?>();
}
