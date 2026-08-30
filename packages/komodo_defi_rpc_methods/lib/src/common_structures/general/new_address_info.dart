import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/src/common_structures/general/balance_info.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class NewAddressInfo extends Equatable {
  const NewAddressInfo({
    required this.address,
    required this.derivationPath,
    required this.chain,
    required this.balances,
    this.gasfreeAddress,
  });

  factory NewAddressInfo.fromJson(Map<String, dynamic> json) {
    final balanceMap = json.value<JsonMap>('balance');
    final balances = <String, BalanceInfo>{};

    for (final entry in balanceMap.entries) {
      balances[entry.key] = BalanceInfo.fromJson(entry.value as JsonMap);
    }

    return NewAddressInfo(
      address: json.value<String>('address'),
      derivationPath: json.valueOrNull<String>('derivation_path'),
      chain: json.valueOrNull<String>('chain'),
      balances: balances,
      gasfreeAddress: json.valueOrNull<String>('gasfree_address'),
    );
  }
  final String address;
  final String? gasfreeAddress;
  final Map<String, BalanceInfo> balances;

  /// Get balance for a specific coin ticker
  BalanceInfo? getBalanceForCoin(String coinTicker) => balances[coinTicker];

  /// Get the first balance entry (for backwards compatibility)
  BalanceInfo get balance {
    assert(
      balances.length == 1,
      'Expected 1 balance entry, got ${balances.length}',
    );
    return balances.values.fold(
      BalanceInfo.zero(),
      (total, balance) => total + balance,
    );
  }

  // HD Wallet properties (Null if not HD Wallet)
  final String? derivationPath;
  final String? chain;

  Map<String, dynamic> toJson() {
    final balanceMap = <String, dynamic>{};
    for (final entry in balances.entries) {
      balanceMap[entry.key] = entry.value.toJson();
    }

    return {
      'address': address,
      'derivation_path': derivationPath,
      'chain': chain,
      'balance': balanceMap,
      if (gasfreeAddress != null) 'gasfree_address': gasfreeAddress,
    };
  }

  @override
  List<Object?> get props => [
    address,
    gasfreeAddress,
    derivationPath,
    chain,
    balances,
  ];
}
