import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class WalletBalance {
  const WalletBalance({required this.walletType, required this.accounts});

  factory WalletBalance.fromJson(JsonMap json) {
    return WalletBalance(
      walletType: json.value<String>('wallet_type'),
      accounts: json
          .value<List<dynamic>>('accounts')
          .map((e) => WalletAccount.fromJson(e as JsonMap))
          .toList(),
    );
  }

  final String walletType;
  final List<WalletAccount> accounts;

  JsonMap toJson() => {
    'wallet_type': walletType,
    'accounts': accounts.map((e) => e.toJson()).toList(),
  };
}

class WalletAccount {
  const WalletAccount({
    required this.accountIndex,
    required this.derivationPath,
    required this.totalBalance,
    required this.addresses,
  });

  factory WalletAccount.fromJson(JsonMap json) {
    return WalletAccount(
      accountIndex: json.value<int>('account_index'),
      derivationPath: json.value<String>('derivation_path'),
      totalBalance: TokenBalanceMap.fromJson(
        json.value<JsonMap>('total_balance'),
      ),
      addresses: json
          .value<List<dynamic>>('addresses')
          .map((e) => WalletAddress.fromJson(e as JsonMap))
          .toList(),
    );
  }

  final int accountIndex;
  final String derivationPath;
  final TokenBalanceMap totalBalance;
  final List<WalletAddress> addresses;

  JsonMap toJson() => {
    'account_index': accountIndex,
    'derivation_path': derivationPath,
    'total_balance': totalBalance.toJson(),
    'addresses': addresses.map((e) => e.toJson()).toList(),
  };
}

class WalletAddress {
  const WalletAddress({
    required this.address,
    required this.derivationPath,
    required this.chain,
    required this.balance,
    this.gasfreeAddress,
  });

  factory WalletAddress.fromJson(JsonMap json) {
    return WalletAddress(
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
