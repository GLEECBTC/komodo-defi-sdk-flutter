import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

enum HistoryTargetType {
  accountId,
  addressId;

  String toJson() => value;

  String get value {
    switch (this) {
      case HistoryTargetType.accountId:
        return 'account_id';
      case HistoryTargetType.addressId:
        return 'address_id';
    }
  }

  static HistoryTargetType parse(String value) {
    return HistoryTargetType.tryParse(value) ??
        (throw ArgumentError('Invalid HistoryTargetType value: $value'));
  }

  static HistoryTargetType? tryParse(String value) {
    switch (value) {
      case 'account_id':
        return HistoryTargetType.accountId;
      case 'address_id':
        return HistoryTargetType.addressId;
      default:
        return null;
    }
  }
}

// ignore: one_member_abstracts
abstract interface class HistoryTarget {
  JsonMap? toJson();

  String get value;
}

/// Specifies a HD wallet `account_id` or `address_id` for transaction history requests.
///
/// This class is used to filter transaction history results based on either an account
/// or specific address in a BIP44 derivation path (m/44'/COIN'/ACCOUNT_ID'/CHAIN/ADDRESS_ID').
class HdHistoryTarget implements HistoryTarget {
  /// Creates a new [HistoryTarget] instance.
  ///
  /// Parameters:
  /// - [type]: Must be either 'account_id' or 'address_id'
  /// - [accountId]: The account ID in the derivation path
  /// - [addressId]: Required only when type is 'address_id'
  /// - [chain]: Required only when type is 'address_id'. Must be 'Internal' or 'External'
  HdHistoryTarget({
    required this.type,
    required this.accountId,
    this.addressId,
    this.chain,
  }) {
    // Validate required fields for address_id type
    if (type == HistoryTargetType.addressId) {
      if (addressId == null) {
        throw ArgumentError('addressId is required when type is "address_id"');
      }
      if (chain == null) {
        throw ArgumentError('chain is required when type is "address_id"');
      }
      if (chain != 'Internal' && chain != 'External') {
        throw ArgumentError('chain must be either "Internal" or "External"');
      }
    }
  }

  const HdHistoryTarget.accountId(this.accountId)
    : type = HistoryTargetType.accountId,
      addressId = null,
      chain = null;

  HdHistoryTarget.addressId(this.accountId, this.addressId, this.chain)
    : type = HistoryTargetType.addressId;

  /// Creates a [HistoryTarget] instance from a JSON map.
  factory HdHistoryTarget.fromJson(Map<String, dynamic> json) {
    return HdHistoryTarget(
      type: HistoryTargetType.parse(json['type'] as String),
      accountId: (json['account_id'] as num).toInt(),
      addressId: (json['address_id'] as num?)?.toInt(),
      chain: json['chain'] as String?,
    );
  }

  /// The type of target to filter by - either 'account_id' or 'address_id'.
  final HistoryTargetType type;

  /// The account ID in the BIP44 derivation path.
  /// Represents the ACCOUNT_ID part in m/44'/COIN'/ACCOUNT_ID'/CHAIN/ADDRESS_ID'
  final int accountId;

  /// The address ID in the BIP44 derivation path.
  /// Only required when type is 'address_id'.
  /// Represents the ADDRESS_ID part in m/44'/COIN'/ACCOUNT_ID'/CHAIN/ADDRESS_ID'
  final int? addressId;

  /// The chain type - either 'Internal' or 'External'.
  /// Only required when type is 'address_id'.
  /// - External: Used for addresses visible outside the wallet (e.g., receiving payments)
  /// - Internal: Used for addresses not visible outside the wallet (e.g., change addresses)
  final String? chain;

  /// Converts the [HistoryTarget] instance to a JSON map in the format as
  /// per the Komodo Defi API documentation.
  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{'type': type.value, 'account_id': accountId};

    if (type == HistoryTargetType.addressId) {
      data['address_id'] = addressId;
      data['chain'] = chain;
    }

    return data;
  }

  @override
  String get value => type.value;

  @override
  String toString() {
    return 'HistoryTarget(type: $type, accountId: $accountId, '
        'addressId: $addressId, chain: $chain)';
  }
}

class IguanaHistoryTarget implements HistoryTarget {
  IguanaHistoryTarget();

  @override
  String get value => 'Iguana';

  @override
  JsonMap? toJson() => null;
}
