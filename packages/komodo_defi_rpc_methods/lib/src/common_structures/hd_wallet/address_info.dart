import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class AddressInfo {
  const AddressInfo({
    required this.address,
    required this.derivationPath,
    required this.chain,
    required this.balance,
    this.gasfreeAddress,
  });

  factory AddressInfo.fromJson(JsonMap json) {
    return AddressInfo(
      address: json.value<String>('address'),
      derivationPath: json.value<String>('derivation_path'),
      chain: json.value<String>('chain'),
      balance: TokenBalanceMap.fromJson(json.value<JsonMap>('balance')),
      gasfreeAddress: json.valueOrNull<String>('gasfree_address'),
    );
  }

  final String address;
  final String derivationPath;
  final String chain;
  final TokenBalanceMap balance;
  final String? gasfreeAddress;

  JsonMap toJson() => {
    'address': address,
    'derivation_path': derivationPath,
    'chain': chain,
    'balance': balance.toJson(),
    if (gasfreeAddress != null) 'gasfree_address': gasfreeAddress,
  };
}
