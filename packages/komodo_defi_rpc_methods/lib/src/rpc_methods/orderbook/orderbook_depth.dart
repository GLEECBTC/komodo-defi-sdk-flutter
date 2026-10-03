import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to count the orders on each side of several pairs at once
///
/// KDF serves `orderbook_depth` only on its legacy dispatcher, which it
/// reaches only when `mmrpc` is absent. It answers pairs it already follows
/// itself and asks one relay for the rest, without subscribing to them. A pair
/// with a wallet-only coin fails the whole request.
class OrderbookDepthRequest
    extends BaseRequest<OrderbookDepthResponse, GeneralErrorResponse> {
  OrderbookDepthRequest({required String rpcPass, required this.pairs})
    : super(method: 'orderbook_depth', rpcPass: rpcPass, mmrpc: null);

  /// List of trading pairs to query depth for
  final List<OrderbookPair> pairs;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'pairs': pairs.map((e) => [e.base, e.rel]).toList(),
  });

  @override
  OrderbookDepthResponse parse(Map<String, dynamic> json) =>
      OrderbookDepthResponse.parse(json);
}

/// How many orders one pair has on each side
class OrderbookPairDepth {
  const OrderbookPairDepth({
    required this.base,
    required this.rel,
    required this.asks,
    required this.bids,
  });

  factory OrderbookPairDepth.fromJson(JsonMap json) {
    final pair = json.value<List<dynamic>>('pair');
    final depth = json.value<JsonMap>('depth');
    return OrderbookPairDepth(
      base: pair[0] as String,
      rel: pair[1] as String,
      asks: depth.value<int>('asks'),
      bids: depth.value<int>('bids'),
    );
  }

  final String base;
  final String rel;

  /// Orders selling [base] for [rel].
  final int asks;

  /// Orders selling [rel] for [base]: the ones a taker selling [base] matches.
  final int bids;

  JsonMap toJson() => {
    'pair': [base, rel],
    'depth': {'asks': asks, 'bids': bids},
  };
}

/// Response containing the order counts for each pair
class OrderbookDepthResponse extends BaseResponse {
  OrderbookDepthResponse({required super.mmrpc, required this.depth});

  factory OrderbookDepthResponse.parse(JsonMap json) {
    return OrderbookDepthResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      depth: json
          .value<JsonList>('result')
          .map(OrderbookPairDepth.fromJson)
          .toList(),
    );
  }

  /// One entry per requested pair. A pair KDF trades under another ticker
  /// (BTC-segwit under BTC) is answered under that ticker as well.
  final List<OrderbookPairDepth> depth;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': depth.map((e) => e.toJson()).toList(),
  };
}
