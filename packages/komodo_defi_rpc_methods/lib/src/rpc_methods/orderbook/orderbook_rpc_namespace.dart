import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// RPC namespace for orderbook operations.
///
/// This namespace provides methods for interacting with the decentralized
/// orderbook in the Komodo DeFi Framework. It enables users to view market
/// depth, place orders, and manage their trading positions.
///
/// ## Key Features:
///
/// - **Market Data**: View orderbook depth and best prices
/// - **Order Management**: Place, cancel, and monitor orders
/// - **Price Discovery**: Find the best available prices for trades
/// - **Order Types**: Support for both maker and taker orders
///
/// ## Order Lifecycle:
///
/// 1. **Creation**: Orders are placed using `setOrder`
/// 2. **Matching**: Orders wait in the orderbook for matching
/// 3. **Execution**: Matched orders proceed to atomic swap
/// 4. **Completion**: Orders are removed after execution or cancellation
///
/// ## Usage Example:
///
/// ```dart
/// final orderbook = client.orderbook;
///
/// // View orderbook
/// final book = await orderbook.orderbook(
///   base: 'BTC',
///   rel: 'KMD',
/// );
///
/// // Place an order
/// final order = await orderbook.setOrder(
///   base: 'BTC',
///   rel: 'KMD',
///   price: '100',
///   volume: '0.1',
/// );
/// ```
class OrderbookMethodsNamespace extends BaseRpcMethodNamespace {
  /// Creates a new [OrderbookMethodsNamespace] instance.
  ///
  /// This is typically called internally by the [KomodoDefiRpcMethods] class.
  OrderbookMethodsNamespace(super.client);

  /// Retrieves the orderbook for a specific trading pair.
  ///
  /// This method fetches the current state of the orderbook, including
  /// all active buy and sell orders for the specified trading pair.
  ///
  /// - [base]: The base coin of the trading pair
  /// - [rel]: The rel/quote coin of the trading pair
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with an [OrderbookResponse]
  /// containing lists of bids and asks.
  ///
  /// The orderbook includes:
  /// - **Bids**: Buy orders sorted by price (highest first)
  /// - **Asks**: Sell orders sorted by price (lowest first)
  /// - Order details including price, volume, and age
  /// - Timestamp of the orderbook snapshot
  Future<OrderbookResponse> orderbook({
    required String base,
    required String rel,
    String? rpcPass,
  }) {
    return execute(
      OrderbookRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        base: base,
        rel: rel,
      ),
    );
  }

  /// Retrieves orderbook depth for multiple trading pairs.
  ///
  /// This method efficiently fetches depth information for multiple
  /// trading pairs in a single request, useful for market overview
  /// displays or price aggregation.
  ///
  /// - [pairs]: List of trading pairs to query
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with an [OrderbookDepthResponse]
  /// containing depth data for each requested pair.
  ///
  /// Depth information includes:
  /// - Best bid and ask prices
  /// - Available volume at best prices
  /// - Number of orders at each price level
  Future<OrderbookDepthResponse> orderbookDepth({
    required List<OrderbookPair> pairs,
    String? rpcPass,
  }) {
    return execute(
      OrderbookDepthRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        pairs: pairs,
      ),
    );
  }

  /// Finds the best orders for a specific trading action.
  ///
  /// This method searches the orderbook to find the best available
  /// orders that can fulfill a desired trade volume. It's useful for
  /// determining the expected execution price for market orders.
  ///
  /// - [coin]: The coin to trade
  /// - [action]: Whether to buy or sell
  /// - [requestBy]: The desired trade volume or value request
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [BestOrdersResponse]
  /// containing the best available orders.
  ///
  /// The response includes:
  /// - Orders sorted by best price
  /// - Cumulative volume information
  /// - Average execution price for the volume
  Future<BestOrdersResponse> bestOrders({
    required String coin,
    required OrderType action,
    required RequestBy requestBy,
    bool? excludeMine,
    String? rpcPass,
  }) {
    return execute(
      BestOrdersRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        coin: coin,
        action: action,
        requestBy: requestBy,
        excludeMine: excludeMine,
      ),
    );
  }

  /// Places a new maker order on the orderbook.
  ///
  /// This method creates a new limit order that will be added to the
  /// orderbook and wait for a matching taker. The order remains active
  /// until it's matched, cancelled, or expires.
  ///
  /// - [base]: The base coin to trade
  /// - [rel]: The rel/quote coin to trade
  /// - [price]: The price per unit of base coin in rel coin
  /// - [volume]: The amount of base coin to trade
  /// - [minVolume]: Optional minimum acceptable volume for partial fills
  /// - [baseConfs]: Optional required confirmations for base coin (int)
  /// - [baseNota]: Optional NOTA requirement for base coin (bool)
  /// - [relConfs]: Optional required confirmations for rel coin (int)
  /// - [relNota]: Optional NOTA requirement for rel coin (bool)
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [SetOrderResponse]
  /// containing the created order details.
  ///
  /// ## Order Configuration:
  ///
  /// - **Price**: Must be positive and reasonable for the market
  /// - **Volume**: Must exceed minimum trading requirements
  /// - **Confirmations**: Higher values increase security but slow execution
  /// - **Nota**: Requires notarization for additional security
  Future<SetOrderResponse> setOrder({
    required String base,
    required String rel,
    required String price,
    required String volume,
    String? minVolume,
    int? baseConfs,
    bool? baseNota,
    int? relConfs,
    bool? relNota,
    String? rpcPass,
  }) {
    return execute(
      SetOrderRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        base: base,
        rel: rel,
        price: price,
        volume: volume,
        minVolume: minVolume,
        baseConfs: baseConfs,
        baseNota: baseNota,
        relConfs: relConfs,
        relNota: relNota,
      ),
    );
  }

  /// Cancels a specific order.
  ///
  /// This method removes an active order from the orderbook. Only orders
  /// that haven't been matched can be cancelled.
  ///
  /// - [uuid]: The unique identifier of the order to cancel
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [CancelOrderResponse]
  /// indicating the cancellation result.
  ///
  /// Note: Orders that are already matched and proceeding to swap
  /// cannot be cancelled.
  Future<CancelOrderResponse> cancelOrder({
    required String uuid,
    String? rpcPass,
  }) {
    return execute(
      CancelOrderRequest(rpcPass: rpcPass ?? this.rpcPass ?? '', uuid: uuid),
    );
  }

  /// Cancels multiple orders based on the specified criteria.
  ///
  /// This method provides bulk cancellation functionality, allowing users
  /// to cancel all their orders or all orders for a specific coin.
  ///
  /// - [cancelType]: Specifies which orders to cancel (all or by coin)
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [CancelAllOrdersResponse]
  /// containing the results of the cancellation operation.
  ///
  /// ## Cancel Types:
  ///
  /// - `CancelOrdersType.all()`: Cancels all active orders
  /// - `CancelOrdersType.coin("BTC")`: Cancels all orders involving BTC
  ///
  /// This is useful for:
  /// - Emergency stops
  /// - Portfolio rebalancing
  /// - Market exit strategies
  Future<CancelAllOrdersResponse> cancelAllOrders({
    CancelOrdersType? cancelType,
    String? rpcPass,
  }) {
    return execute(
      CancelAllOrdersRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        cancelType: cancelType,
      ),
    );
  }

  /// Retrieves all orders created by the current user.
  ///
  /// This method returns a comprehensive list of the user's orders,
  /// including their current status and match information.
  ///
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [MyOrdersResponse]
  /// containing all user orders.
  ///
  /// The response includes:
  /// - Active orders waiting for matches
  /// - Orders currently being matched
  /// - Recently completed or cancelled orders
  /// - Detailed status and configuration for each order
  Future<MyOrdersResponse> myOrders({String? rpcPass}) {
    return execute(MyOrdersRequest(rpcPass: rpcPass ?? this.rpcPass ?? ''));
  }

  /// Retrieves status for a maker or taker order.
  Future<OrderStatusResponse> orderStatus({
    required String uuid,
    String? rpcPass,
  }) {
    return execute(
      OrderStatusRequest(rpcPass: rpcPass ?? this.rpcPass ?? '', uuid: uuid),
    );
  }
}
