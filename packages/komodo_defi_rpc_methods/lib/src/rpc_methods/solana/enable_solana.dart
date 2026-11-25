import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class EnableSolanaWithAssetsRequest
    extends BaseRequest<EnableSolanaWithAssetsResponse, GeneralErrorResponse> {
  EnableSolanaWithAssetsRequest({
    required this.ticker,
    required List<SolanaNode> nodes,
    List<SolanaTokenRequest> tokensParams = const [],
    bool txHistory = true,
    super.rpcPass,
  }) : super(
         method: 'experimental::enable_solana_with_assets',
         mmrpc: RpcVersion.v2_0,
         params: SolanaActivationParams(
           nodes: nodes,
           tokensParams: tokensParams,
           txHistory: txHistory,
         ),
       );

  final String ticker;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {'ticker': ticker, ...params!.toRpcParams()},
  };

  @override
  EnableSolanaWithAssetsResponse parse(JsonMap json) =>
      EnableSolanaWithAssetsResponse.parse(json);
}

class EnableSolanaWithAssetsResponse extends BaseResponse {
  EnableSolanaWithAssetsResponse({
    required super.mmrpc,
    required this.ticker,
    required this.address,
    required this.currentBlock,
    required this.balance,
    required this.tokensBalances,
  });

  factory EnableSolanaWithAssetsResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    return EnableSolanaWithAssetsResponse(
      mmrpc: json.value<String>('mmrpc'),
      ticker: result.value<String>('ticker'),
      address: result.value<String>('address'),
      currentBlock: result.value<int>('current_block'),
      balance: BalanceInfo.fromJson(result.value<JsonMap>('balance')),
      tokensBalances: result
          .value<JsonMap>('tokens_balances')
          .map(
            (ticker, value) =>
                MapEntry(ticker, BalanceInfo.fromJson(value as JsonMap)),
          ),
    );
  }

  final String ticker;
  final String address;

  /// Solana slot, not an EVM or UTXO block height.
  final int currentBlock;
  final BalanceInfo balance;
  final Map<String, BalanceInfo> tokensBalances;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'ticker': ticker,
      'address': address,
      'current_block': currentBlock,
      'balance': balance.toJson(),
      'tokens_balances': tokensBalances.map(
        (ticker, balance) => MapEntry(ticker, balance.toJson()),
      ),
    },
  };
}

class EnableSolanaTokenRequest
    extends BaseRequest<EnableSolanaTokenResponse, GeneralErrorResponse> {
  EnableSolanaTokenRequest({required this.ticker, this.protocol, super.rpcPass})
    : super(
        method: 'experimental::enable_solana_token',
        mmrpc: RpcVersion.v2_0,
      );

  final String ticker;

  /// Complete CoinProtocol object, not just its protocol_data.
  final JsonMap? protocol;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {
      'ticker': ticker,
      'activation_params': <String, dynamic>{},
      if (protocol != null) 'protocol': validateSolanaTokenProtocol(protocol!),
    },
  };

  @override
  EnableSolanaTokenResponse parse(JsonMap json) =>
      EnableSolanaTokenResponse.parse(json);
}

class EnableSolanaTokenResponse extends BaseResponse {
  EnableSolanaTokenResponse({
    required super.mmrpc,
    required this.ticker,
    required this.address,
    required this.currentBlock,
    required this.balance,
  });

  factory EnableSolanaTokenResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    return EnableSolanaTokenResponse(
      mmrpc: json.value<String>('mmrpc'),
      ticker: result.value<String>('ticker'),
      address: result.value<String>('address'),
      currentBlock: result.value<int>('current_block'),
      balance: BalanceInfo.fromJson(result.value<JsonMap>('balance')),
    );
  }

  final String ticker;
  final String address;
  final int currentBlock;
  final BalanceInfo balance;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'ticker': ticker,
      'address': address,
      'current_block': currentBlock,
      'balance': balance.toJson(),
    },
  };
}
