import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// RPC namespace for trading and swap operations.
///
/// This namespace provides methods for managing atomic swaps and trading
/// operations within the Komodo DeFi Framework. It enables users to initiate,
/// monitor, and manage cross-chain atomic swaps in a decentralized manner.
///
/// ## Key Features:
///
/// - **Swap Initiation**: Start new swaps as maker or taker
/// - **Swap Monitoring**: Track active and recent swap status
/// - **Trade Analysis**: Calculate fees and validate trade parameters
/// - **Swap Management**: Cancel active swaps when needed
///
/// ## Swap Types:
///
/// - **Maker**: Sets an order at a specific price and waits for takers
/// - **Taker**: Takes existing orders from the orderbook immediately
///
/// ## Usage Example:
///
/// ```dart
/// final trading = client.trading;
///
/// // Start a new swap
/// final swap = await trading.startSwap(
///   swapRequest: SwapRequest(
///     base: 'BTC',
///     rel: 'KMD',
///     baseCoinAmount: '0.1',
///     relCoinAmount: '1000',
///     method: SwapMethod.sell,
///   ),
/// );
///
/// // Monitor swap status
/// final status = await trading.swapStatus(uuid: swap.uuid);
/// ```
class TradingMethodsNamespace extends BaseRpcMethodNamespace {
  /// Creates a new [TradingMethodsNamespace] instance.
  ///
  /// This is typically called internally by the [KomodoDefiRpcMethods] class.
  TradingMethodsNamespace(super.client);

  /// Initiates a new atomic swap.
  ///
  /// This method starts a new cross-chain atomic swap based on the provided
  /// parameters. The swap can be initiated as either a maker (placing an order)
  /// or a taker (taking an existing order).
  ///
  /// - [swapRequest]: The swap configuration including coins, amounts, and
  ///   method
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [StartSwapResponse] containing
  /// the swap UUID and initial status.
  ///
  /// ## Swap Methods:
  ///
  /// - **setPrice**: Creates a maker order at a specific price
  /// - **buy**: Takes the best available sell orders (taker)
  /// - **sell**: Takes the best available buy orders (taker)
  ///
  /// Throws an exception if:
  /// - Insufficient balance for the swap
  /// - No matching orders available (for taker swaps)
  /// - Invalid swap parameters
  Future<StartSwapResponse> startSwap({
    required SwapRequest swapRequest,
    String? rpcPass,
  }) {
    return execute(
      StartSwapRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        swapRequest: swapRequest,
      ),
    );
  }

  /// Starts a taker sell swap.
  Future<StartSwapResponse> sell({
    required String base,
    required String rel,
    required String baseCoinAmount,
    required String relCoinAmount,
    MatchBy? matchBy,
    String? rpcPass,
  }) {
    return startSwap(
      rpcPass: rpcPass,
      swapRequest: SwapRequest(
        base: base,
        rel: rel,
        baseCoinAmount: baseCoinAmount,
        relCoinAmount: relCoinAmount,
        method: SwapMethod.sell,
        matchBy: matchBy,
      ),
    );
  }

  /// Retrieves the status of a specific swap.
  ///
  /// This method fetches detailed information about a swap identified by
  /// its UUID, including current state, progress, and transaction details.
  ///
  /// - [uuid]: The unique identifier of the swap
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [SwapStatusResponse] containing
  /// comprehensive swap information.
  ///
  /// The status includes:
  /// - Current swap state and progress
  /// - Transaction IDs and confirmations
  /// - Error information if the swap failed
  /// - Timestamps for each swap event
  Future<SwapStatusResponse> swapStatus({
    required String uuid,
    String? rpcPass,
  }) {
    return execute(
      SwapStatusRequest(rpcPass: rpcPass ?? this.rpcPass ?? '', uuid: uuid),
    );
  }

  /// Retrieves all currently active swaps.
  ///
  /// This method returns information about all swaps that are currently
  /// in progress. Optionally, results can be filtered by coin.
  ///
  /// - [coin]: Optional coin ticker to filter results
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with an [ActiveSwapsResponse]
  /// containing lists of active swap UUIDs and their details.
  ///
  /// Active swaps include those that are:
  /// - Waiting for maker payment
  /// - Waiting for taker payment
  /// - Waiting for confirmations
  /// - In any other non-terminal state
  Future<ActiveSwapsResponse> activeSwaps({
    String? coin,
    bool? includeStatus,
    String? rpcPass,
  }) {
    return execute(
      ActiveSwapsRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        coin: coin,
        includeStatus: includeStatus,
      ),
    );
  }

  /// Retrieves recent swap history with pagination support.
  ///
  /// This method fetches historical swap data, including both completed
  /// and failed swaps. Results can be paginated and filtered by coin.
  ///
  /// - [limit]: Maximum number of swaps to return
  /// - [fromUuid]: Starting point for pagination (exclusive)
  /// - [coin]: Optional coin ticker to filter results
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [RecentSwapsResponse]
  /// containing swap history records.
  ///
  /// ## Pagination:
  ///
  /// To paginate through results, use the UUID of the last swap from
  /// the previous response as the [fromUuid] parameter.
  Future<RecentSwapsResponse> recentSwaps({
    int? limit,
    int? pageNumber,
    String? fromUuid,
    String? coin,
    String? otherCoin,
    int? fromTimestamp,
    int? toTimestamp,
    String? rpcPass,
  }) {
    return execute(
      RecentSwapsRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        filter: RecentSwapsFilter(
          limit: limit,
          pageNumber: pageNumber,
          fromUuid: fromUuid,
          myCoin: coin,
          otherCoin: otherCoin,
          fromTimestamp: fromTimestamp,
          toTimestamp: toTimestamp,
        ),
      ),
    );
  }

  /// Cancels an active swap.
  ///
  /// This method attempts to cancel a swap that is currently in progress.
  /// Cancellation is only possible for swaps in certain states, typically
  /// before the payment transactions have been broadcast.
  ///
  /// - [uuid]: The unique identifier of the swap to cancel
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [CancelSwapResponse]
  /// indicating whether the cancellation was successful.
  ///
  /// Note: Swaps cannot be cancelled after payment transactions have
  /// been broadcast to prevent loss of funds.
  Future<CancelSwapResponse> cancelSwap({
    required String uuid,
    String? rpcPass,
  }) {
    return execute(
      CancelSwapRequest(rpcPass: rpcPass ?? this.rpcPass ?? '', uuid: uuid),
    );
  }

  /// Attempts to recover funds for a swap that failed or requires recovery.
  Future<RecoverFundsOfSwapResponse> recoverFundsOfSwap({
    required String uuid,
    String? rpcPass,
  }) {
    return execute(
      RecoverFundsOfSwapRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        uuid: uuid,
      ),
    );
  }

  /// Calculates fees and validates parameters for a potential trade.
  ///
  /// This method performs a dry-run calculation of a trade, providing
  /// fee estimates and validation without actually initiating the swap.
  /// It's useful for showing users the expected costs before confirmation.
  ///
  /// - [base]: The base coin ticker
  /// - [rel]: The rel/quote coin ticker
  /// - [swapMethod]: The intended swap method (setPrice, buy, or sell)
  /// - [volume]: The trade volume
  /// - [price]: Optional price for maker orders
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [TradePreimageResponse]
  /// containing fee calculations and validation results.
  ///
  /// The preimage includes:
  /// - Estimated transaction fees for both coins
  /// - Actual tradeable volume after fees
  /// - Validation of trade parameters
  /// - Required transaction confirmations
  Future<TradePreimageResponse> tradePreimage({
    required String base,
    required String rel,
    required SwapMethod swapMethod,
    String? volume,
    bool? max,
    String? price,
    String? rpcPass,
  }) {
    return execute(
      TradePreimageRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        base: base,
        rel: rel,
        swapMethod: swapMethod,
        volume: volume,
        max: max,
        price: price,
      ),
    );
  }

  /// Calculates the maximum volume available for a taker swap.
  ///
  /// Determines the maximum amount of `coin` that can be traded as a taker for
  /// the pair (`coin`, `tradeWith`), after accounting for balances and all
  /// applicable fees.
  ///
  /// - [coin]: The coin ticker to check
  /// - [tradeWith]: Optional counter coin to trade against. Affects
  ///   pair-dependent DEX fee calculation (e.g., some pairs like KMD have
  ///   discounted fees) and defaults to `coin` when omitted.
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [MaxTakerVolumeResponse]
  /// containing the maximum tradable volume.
  ///
  /// The calculation considers:
  /// - Available coin balance
  /// - Required transaction fees
  /// - DEX fees which depend on the coin pair (`coin` vs `tradeWith`)
  /// - Dust limits
  /// - Protocol-specific constraints
  Future<MaxTakerVolumeResponse> maxTakerVolume({
    required String coin,
    String? tradeWith,
    String? rpcPass,
  }) {
    return execute(
      MaxTakerVolumeRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        coin: coin,
        tradeWith: tradeWith,
      ),
    );
  }

  /// Calculates the maximum maker volume for a coin.
  Future<MaxMakerVolumeResponse> maxMakerVolume({
    required String coin,
    String? rpcPass,
  }) {
    return execute(
      MaxMakerVolumeRequest(rpcPass: rpcPass ?? this.rpcPass ?? '', coin: coin),
    );
  }

  /// Retrieves the minimum trading volume for a coin.
  ///
  /// This method returns the minimum amount of a coin that can be
  /// traded in a swap, considering dust limits and economic viability.
  ///
  /// - [coin]: The coin ticker to check
  /// - [rpcPass]: Optional RPC password override
  ///
  /// Returns a [Future] that completes with a [MinTradingVolumeResponse]
  /// containing the minimum tradeable amount.
  ///
  /// The minimum is determined by:
  /// - Protocol dust limits
  /// - Transaction fee requirements
  /// - Economic viability thresholds
  Future<MinTradingVolumeResponse> minTradingVolume({
    required String coin,
    String? rpcPass,
  }) {
    return execute(
      MinTradingVolumeRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        coin: coin,
      ),
    );
  }

  /// Imports swap records into KDF.
  Future<ImportSwapsResponse> importSwaps({
    List<dynamic> swaps = const [],
    String? rpcPass,
  }) {
    return execute(
      ImportSwapsRequest(rpcPass: rpcPass ?? this.rpcPass ?? '', swaps: swaps),
    );
  }

  /// Starts the simple market maker bot.
  Future<MarketMakerBotResponse> startSimpleMarketMakerBot({
    required int id,
    required MarketMakerBotParameters parameters,
    String? rpcPass,
  }) {
    return execute(
      MarketMakerBotRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        id: id,
        methodType: MarketMakerBotMethod.start,
        botParameters: parameters,
      ),
    );
  }

  /// Stops the simple market maker bot.
  Future<MarketMakerBotResponse> stopSimpleMarketMakerBot({
    required int id,
    String? rpcPass,
  }) {
    return execute(
      MarketMakerBotRequest(
        rpcPass: rpcPass ?? this.rpcPass ?? '',
        id: id,
        methodType: MarketMakerBotMethod.stop,
      ),
    );
  }
}
