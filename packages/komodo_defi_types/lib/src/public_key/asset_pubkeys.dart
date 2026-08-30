import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class AssetPubkeys extends Equatable {
  const AssetPubkeys({
    required this.assetId,
    required this.keys,
    required this.availableAddressesCount,
    required this.syncStatus,
  });
  final AssetId assetId;
  final List<PubkeyInfo> keys;
  final int availableAddressesCount;
  final SyncStatusEnum syncStatus;

  Balance get balance =>
      keys.fold(Balance.zero(), (prev, element) => prev + element.balance);

  bool get isEmpty => keys.isEmpty;

  bool get isNotEmpty => keys.isNotEmpty;

  JsonMap toJson() {
    return {
      'assetId': assetId.toJson(),
      'addresses': keys.map((e) => e.toJson()).toList(),
      'availableAddressesCount': availableAddressesCount,
      'syncStatus': syncStatus.toString(),
    };
  }

  @override
  String toString() {
    return 'AssetPubkeys${toJson().toJsonString()}';
  }

  @override
  List<Object?> get props => [
    assetId,
    keys,
    availableAddressesCount,
    syncStatus,
  ];
}

/// Public type for the pubkeys info. Note that this is a separate type from the
/// on in the RPC library even though they are similar because we want to keep
/// the GUI types independent from the API types.

class PubkeyInfo extends NewAddressInfo {
  PubkeyInfo({
    required String address,
    required String? derivationPath,
    required String? chain,
    required BalanceInfo balance,
    required String coinTicker,
    String? gasfreeAddress,
    this.name,
  }) : super(
         address: address,
         derivationPath: derivationPath,
         chain: chain,
         balances: {coinTicker: balance},
         gasfreeAddress: gasfreeAddress,
       );

  final String? name;

  // The coin is active for swap if it is non-HD or if it is HD and is the
  // first address index. e.g. "m/44'/141'/0'/0/0", where the last 0 is the
  // address index.
  // NB: The intention is to add multi-address swap support in the future
  // either as an abstraction in the SDK or as a feature in the API. For the
  // former, the swap address will be locked to a single address when the
  // asset has ongoing swaps.
  bool get isActiveForSwap =>
      derivationPath == null || derivationPath!.endsWith('/0');

  @override
  JsonMap toJson() {
    return {
      ...super.toJson(),
      'address': address,
      if (gasfreeAddress != null) 'gasfree_address': gasfreeAddress,
      'derivationPath': derivationPath,
      'chain': chain,
      'balance': balance.toJson(),
      'name': name,
    };
  }

  @Deprecated('Use the formatters in the UI library instead')
  String get addressShort =>
      '${address.substring(0, 6)}...${address.substring(address.length - 6)}';

  @override
  String toString() {
    return 'PubkeyInfo{${toJson().toJsonString()}}';
  }

  @override
  List<Object?> get props => [...super.props, name];
}

typedef Balance = BalanceInfo;
