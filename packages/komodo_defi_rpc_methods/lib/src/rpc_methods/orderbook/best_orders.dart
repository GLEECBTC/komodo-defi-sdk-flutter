import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get best orders for a coin and action
class BestOrdersRequest
    extends BaseRequest<BestOrdersResponse, GeneralErrorResponse> {
  BestOrdersRequest({
    required String rpcPass,
    required this.coin,
    required this.action,
    required this.requestBy,
    this.excludeMine,
  }) : super(method: 'best_orders', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  /// Coin ticker to trade
  final String coin;

  /// Desired trade direction
  final OrderType action;

  /// Request-by selector (volume or number)
  final RequestBy requestBy;

  /// Whether to exclude orders created by the current wallet. Defaults to false in API.
  final bool? excludeMine;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'coin': coin,
      'action': action.toJson(),
      if (excludeMine != null) 'exclude_mine': excludeMine,
      'request_by': requestBy.toJson(),
    },
  });

  @override
  BestOrdersResponse parse(Map<String, dynamic> json) =>
      BestOrdersResponse.parse(json);
}

/// Response containing the best orders for each coin that trades against the
/// requested one
class BestOrdersResponse extends BaseResponse {
  BestOrdersResponse({
    required super.mmrpc,
    required this.orders,
    required this.originalTickers,
  });

  factory BestOrdersResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    final orders = result.value<JsonMap>('orders');
    final originalTickers = result.value<JsonMap>('original_tickers');

    return BestOrdersResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      orders: {
        for (final ticker in orders.keys)
          ticker: orders
              .value<JsonList>(ticker)
              .map(OrderInfo.fromJson)
              .toList(),
      },
      originalTickers: {
        for (final ticker in originalTickers.keys)
          ticker: originalTickers.value<List<String>>(ticker),
      },
    );
  }

  /// Each coin's orders, best first. KDF repeats an orderbook ticker's orders
  /// (BTC) under each of its [originalTickers] (BTC-segwit), changing only
  /// [OrderInfo.coin].
  final Map<String, List<OrderInfo>> orders;

  /// The tickers that trade under each orderbook ticker, such as
  /// `{'BTC': ['BTC-segwit']}`, for every coin in KDF's config rather than
  /// only those in [orders].
  final Map<String, List<String>> originalTickers;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': {
      'orders': orders.map(
        (ticker, tickerOrders) =>
            MapEntry(ticker, tickerOrders.map((e) => e.toJson()).toList()),
      ),
      'original_tickers': originalTickers.map(
        (ticker, aliases) => MapEntry(ticker, [...aliases]),
      ),
    },
  };
}
