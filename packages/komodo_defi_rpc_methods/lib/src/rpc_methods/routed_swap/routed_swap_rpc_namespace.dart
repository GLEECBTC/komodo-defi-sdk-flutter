import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';

/// Routed (aggregator-executed) swaps — `routed_swap::*` and
/// `task::routed_swap::*`.
///
/// KDF owns the whole lifecycle: it quotes, handles any ERC-20 approval, signs
/// locally, broadcasts, and tracks the bridge to a terminal outcome. The GUI
/// never sees a key and never talks to the provider.
///
/// Provider-generic by design: `lifi` is the only v1 value, and requests accept
/// an optional `provider` so a second aggregator does not force a rename of
/// anything the app codes against.
///
/// Top-level errors throw a typed [RoutedSwapRpcException].
class RoutedSwapMethodsNamespace extends BaseRpcMethodNamespace {
  /// Creates the namespace.
  RoutedSwapMethodsNamespace(super.client);

  /// Display-only pricing for the swap form. Reserves nothing.
  ///
  /// Quotes go stale in roughly 1–2 minutes and there is no reserve/commit
  /// semantic, so refresh while the form is idle-open. Show the route's
  /// `toMinimum`, not `to` — that is the number the user is guaranteed and the
  /// one [init] guards against.
  Future<RoutedSwapQuoteResponse> quote({
    required String from,
    required String to,
    required String amount,
    double? slippage,
    RoutedSwapOrder? order,
    String? provider,
  }) {
    return execute(
      RoutedSwapQuoteRequest(
        rpcPass: rpcPass ?? '',
        from: from,
        to: to,
        amount: amount,
        slippage: slippage,
        order: order,
        provider: provider,
      ),
    );
  }

  /// Which activated coins are eligible to attempt a quote.
  ///
  /// Eligible is not routable: two coins listed here can still fail the quote
  /// on coverage, liquidity or bounds. Cached KDF-side and cheap to call.
  Future<RoutedSwapSupportedCoinsResponse> supportedCoins({String? provider}) {
    return execute(
      RoutedSwapSupportedCoinsRequest(
        rpcPass: rpcPass ?? '',
        provider: provider,
      ),
    );
  }

  /// Starts a swap. Returns a `task_id` only.
  ///
  /// [minToAmount] must be the `amount_min` the user actually saw and accepted.
  /// KDF re-quotes fresh before doing anything; if the fresh guaranteed minimum
  /// is below this, the task fails `QuoteWorsened` and nothing is sent
  /// on-chain.
  ///
  /// The returned task id is in-memory and does not survive a KDF restart, a
  /// cancellation, or a terminal read that forgets. The durable handle is the
  /// `uuid`, which arrives on the first [status] read.
  Future<RoutedSwapInitResponse> init({
    required String from,
    required String to,
    required String amount,
    required String minToAmount,
    double? slippage,
    RoutedSwapOrder? order,
    String? provider,
    int? clientId,
  }) {
    return execute(
      RoutedSwapInitRequest(
        rpcPass: rpcPass ?? '',
        from: from,
        to: to,
        amount: amount,
        minToAmount: minToAmount,
        slippage: slippage,
        order: order,
        provider: provider,
        clientId: clientId,
      ),
    );
  }

  /// Reads task progress.
  ///
  /// [forgetIfFinished] defaults to false here, unlike the wire default of
  /// true: a terminal read that forgets is destructive and unrepeatable, and
  /// both reconciliation polling and SSE recovery need to re-read a terminal
  /// result. Pass true only from a caller that owns the task outright.
  ///
  /// Throws [RoutedSwapNoSuchTaskException] once the task has been forgotten,
  /// cancelled or lost to a restart. That is not an error state for the swap —
  /// resolve it through [history] by `uuid`.
  Future<RoutedSwapStatusResponse> status(
    int taskId, {
    bool forgetIfFinished = false,
  }) {
    return execute(
      RoutedSwapStatusRequest(
        rpcPass: rpcPass ?? '',
        taskId: taskId,
        forgetIfFinished: forgetIfFinished,
      ),
    );
  }

  /// Cancels a swap, if it has not yet been broadcast.
  ///
  /// Accepted through `FetchingQuote`, `CheckingAllowance`, `Approving` and
  /// `Signing`. From `Broadcasting` the handoff is irreversible and this throws
  /// [RoutedSwapTaskAlreadyBroadcastException].
  ///
  /// On success the task is removed, so a following [status] call answers
  /// `NoSuchTask` — confirm the cancellation through [history] instead. An
  /// approval already confirmed on-chain cannot be undone.
  Future<RoutedSwapCancelResponse> cancel(int taskId) {
    return execute(
      RoutedSwapCancelRequest(rpcPass: rpcPass ?? '', taskId: taskId),
    );
  }

  /// The durable routed-swap record, newest first on `created_at`.
  ///
  /// Every argument is optional and omitted when null, so KDF's defaults apply
  /// (`status_filter: all`, `limit: 10`, `page_number: 1`).
  Future<RoutedSwapHistoryResponse> history({
    String? uuid,
    RoutedSwapHistoryFilter? filter,
    String? myCoin,
    String? otherCoin,
    int? fromTimestamp,
    int? toTimestamp,
    int? limit,
    int? pageNumber,
  }) {
    return execute(
      RoutedSwapHistoryRequest(
        rpcPass: rpcPass ?? '',
        uuid: uuid,
        filter: filter,
        myCoin: myCoin,
        otherCoin: otherCoin,
        fromTimestamp: fromTimestamp,
        toTimestamp: toTimestamp,
        limit: limit,
        pageNumber: pageNumber,
      ),
    );
  }
}
