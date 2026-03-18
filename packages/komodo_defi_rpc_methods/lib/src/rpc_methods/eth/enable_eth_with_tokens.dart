import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Request to enable ETH with multiple ERC20 tokens
class EnableEthWithTokensRequest
    extends BaseRequest<EnableEthWithTokensResponse, GeneralErrorResponse> {
  EnableEthWithTokensRequest({
    required String rpcPass,
    required this.ticker,
    required this.activationParams,
    this.getBalances = true,
  }) : super(
         method: 'enable_eth_with_tokens',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
         params: activationParams,
       );

  final String ticker;
  final ActivationParams activationParams;
  final bool getBalances;

  @override
  Map<String, dynamic> toJson() {
    return super.toJson().deepMerge({
      'params': {
        'ticker': ticker,
        ...activationParams.toRpcParams(),
        'get_balances': getBalances,
      },
    });
  }

  @override
  EnableEthWithTokensResponse parse(Map<String, dynamic> json) =>
      EnableEthWithTokensResponse.parse(json, platformTicker: ticker);
}

/// Response from enabling ETH with tokens request
class EnableEthWithTokensResponse extends BaseResponse {
  EnableEthWithTokensResponse({
    required super.mmrpc,
    required this.currentBlock,
    required this.walletBalance,
    required this.nftsInfos,
  });

  factory EnableEthWithTokensResponse.parse(
    JsonMap json, {
    String? platformTicker,
  }) {
    final result = json.value<JsonMap>('result');

    final walletBalanceJson = result.valueOrNull<JsonMap>('wallet_balance');
    return EnableEthWithTokensResponse(
      mmrpc: json.value<String>('mmrpc'),
      currentBlock: result.value<int>('current_block'),
      walletBalance: walletBalanceJson != null
          ? WalletBalance.fromJson(walletBalanceJson)
          : WalletBalance.fromLegacyAddressInfos(
              result,
              platformTicker: platformTicker,
            ),
      nftsInfos: result.valueOrNull<JsonMap>('nfts_infos') ?? const {},
    );
  }

  final int currentBlock;
  final WalletBalance walletBalance;
  final JsonMap nftsInfos; // Could be expanded into a proper type if needed

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'current_block': currentBlock,
      'wallet_balance': walletBalance.toJson(),
      'nfts_infos': nftsInfos,
    },
  };
}

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

  factory WalletBalance.fromLegacyAddressInfos(
    JsonMap json, {
    String? platformTicker,
  }) {
    final platformAddresses =
        json.valueOrNull<JsonMap>('eth_addresses_infos') ?? const {};
    final tokenAddresses =
        json.valueOrNull<JsonMap>('erc20_addresses_infos') ?? const {};
    final addressesByValue = <String, WalletAddress>{};
    void addLegacyAddress(String address, JsonMap json) {
      final next = WalletAddress.fromLegacyJson(
        address: address,
        json: json,
        platformTicker: platformTicker,
      );
      final previous = addressesByValue[address];
      addressesByValue[address] = previous == null
          ? next
          : previous.merge(next);
    }

    for (final entry in platformAddresses.entries) {
      addLegacyAddress(entry.key, entry.value as JsonMap);
    }
    for (final entry in tokenAddresses.entries) {
      addLegacyAddress(entry.key, entry.value as JsonMap);
    }
    final addresses = addressesByValue.values.toList();
    final totalBalance = _aggregateTokenBalances(
      addresses.map((address) => address.balance),
    );

    return WalletBalance(
      walletType: 'iguana',
      accounts: [
        WalletAccount(
          accountIndex: 0,
          derivationPath: '',
          totalBalance: totalBalance,
          addresses: addresses,
        ),
      ],
    );
  }

  final String walletType;
  final List<WalletAccount> accounts;

  Map<String, dynamic> toJson() => {
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

  Map<String, dynamic> toJson() => {
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
  });

  factory WalletAddress.fromJson(JsonMap json) {
    return WalletAddress(
      address: json.value<String>('address'),
      derivationPath: json.value<String>('derivation_path'),
      chain: json.value<String>('chain'),
      balance: TokenBalanceMap.fromJson(json.value<JsonMap>('balance')),
    );
  }

  factory WalletAddress.fromLegacyJson({
    required String address,
    required JsonMap json,
    String? platformTicker,
  }) {
    final balancesJson = json.valueOrNull<JsonMap>('balances');
    return WalletAddress(
      address: address,
      derivationPath: json.valueOrNull<String>('derivation_path') ?? '',
      chain: json.valueOrNull<String>('chain') ?? 'external',
      balance: _legacyBalancesToTokenBalanceMap(
        balancesJson,
        platformTicker: platformTicker,
      ),
    );
  }

  final String address;
  final String derivationPath;
  final String chain;
  final TokenBalanceMap balance;

  Map<String, dynamic> toJson() => {
    'address': address,
    'derivation_path': derivationPath,
    'chain': chain,
    'balance': balance.toJson(),
  };

  WalletAddress merge(WalletAddress other) {
    return WalletAddress(
      address: address,
      derivationPath: derivationPath.isNotEmpty
          ? derivationPath
          : other.derivationPath,
      chain: chain.isNotEmpty ? chain : other.chain,
      balance: _aggregateTokenBalances([balance, other.balance]),
    );
  }
}

TokenBalanceMap _legacyBalancesToTokenBalanceMap(
  JsonMap? balancesJson, {
  String? platformTicker,
}) {
  if (balancesJson == null) {
    return const TokenBalanceMap(balances: <String, BalanceInfo>{});
  }
  if (balancesJson.values.every((value) => value is JsonMap)) {
    return TokenBalanceMap.fromJson(balancesJson);
  }
  final ticker = platformTicker ?? 'ETH';
  return TokenBalanceMap(
    balances: {ticker: BalanceInfo.fromJson(balancesJson)},
  );
}

TokenBalanceMap _aggregateTokenBalances(Iterable<TokenBalanceMap> balances) {
  final aggregated = <String, BalanceInfo>{};
  for (final tokenBalanceMap in balances) {
    final json = tokenBalanceMap.toJson();
    for (final entry in json.entries) {
      final balance = BalanceInfo.fromJson(entry.value as JsonMap);
      aggregated.update(
        entry.key,
        (current) => current + balance,
        ifAbsent: () => balance,
      );
    }
  }
  return TokenBalanceMap(balances: aggregated);
}
