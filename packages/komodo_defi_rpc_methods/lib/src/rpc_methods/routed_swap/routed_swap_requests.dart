import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Preferred route ordering for `routed_swap::quote`.
enum RoutedSwapOrder {
  /// Best net return. The default.
  cheapest('cheapest'),

  /// Shortest execution time.
  fastest('fastest');

  const RoutedSwapOrder(this.wire);

  /// The wire value.
  final String wire;
}

/// `routed_swap::quote` — display-only pricing. Reserves and executes nothing.
class RoutedSwapQuoteRequest
    extends BaseRequest<RoutedSwapQuoteResponse, GeneralErrorResponse> {
  RoutedSwapQuoteRequest({
    required super.rpcPass,
    required this.from,
    required this.to,
    required this.amount,
    this.slippage,
    this.order,
    this.provider,
  }) : super(method: 'routed_swap::quote', mmrpc: RpcVersion.v2_0);

  /// KDF ticker to sell. Must be activated.
  final String from;

  /// KDF ticker to buy. Must be activated.
  final String to;

  /// Sell amount in coin units — never wei.
  final String amount;

  /// Decimal fraction, max 0.5. Defaults to 0.005 (0.5%) KDF-side.
  final double? slippage;

  /// Route preference. Defaults to [RoutedSwapOrder.cheapest] KDF-side.
  final RoutedSwapOrder? order;

  /// Defaults to `lifi`, the only v1 value.
  final String? provider;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {
      'from': from,
      'to': to,
      'amount': amount,
      if (slippage != null) 'slippage': slippage,
      if (order != null) 'order': order!.wire,
      if (provider != null) 'provider': provider,
    },
  };

  @override
  RoutedSwapQuoteResponse parse(JsonMap json) =>
      RoutedSwapQuoteResponse.parse(json);
}

/// The routes `routed_swap::quote` returned.
class RoutedSwapQuoteResponse extends BaseResponse {
  RoutedSwapQuoteResponse({required super.mmrpc, required this.routes});

  /// Parses `result.routes`.
  factory RoutedSwapQuoteResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    return RoutedSwapQuoteResponse(
      mmrpc: json.value<String>('mmrpc'),
      routes: result
          .value<List<dynamic>>('routes')
          .map((e) => RoutedSwapRoute.fromJson(e as JsonMap))
          .toList(),
    );
  }

  /// Exactly one entry in v1. Read [best] rather than indexing.
  final List<RoutedSwapRoute> routes;

  /// The single v1 route, or null when the provider returned none.
  RoutedSwapRoute? get best => routes.isEmpty ? null : routes.first;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {'routes': routes.length},
  };
}

/// `routed_swap::supported_coins` — which activated coins may be quoted.
class RoutedSwapSupportedCoinsRequest
    extends
        BaseRequest<RoutedSwapSupportedCoinsResponse, GeneralErrorResponse> {
  RoutedSwapSupportedCoinsRequest({required super.rpcPass, this.provider})
    : super(method: 'routed_swap::supported_coins', mmrpc: RpcVersion.v2_0);

  /// Defaults to `lifi`.
  final String? provider;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {if (provider != null) 'provider': provider},
  };

  @override
  RoutedSwapSupportedCoinsResponse parse(JsonMap json) =>
      RoutedSwapSupportedCoinsResponse.parse(json);
}

/// Coins eligible to attempt a quote.
class RoutedSwapSupportedCoinsResponse extends BaseResponse {
  RoutedSwapSupportedCoinsResponse({
    required super.mmrpc,
    required this.provider,
    required this.coins,
  });

  /// Parses `result.{provider, coins}`.
  factory RoutedSwapSupportedCoinsResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    return RoutedSwapSupportedCoinsResponse(
      mmrpc: json.value<String>('mmrpc'),
      provider: result.value<String>('provider'),
      coins: result
          .value<List<dynamic>>('coins')
          .map((e) => RoutedSwapSupportedCoin.fromJson(e as JsonMap))
          .toList(),
    );
  }

  /// Echoed provider.
  final String provider;

  /// Eligible coins.
  ///
  /// Two coins appearing here means the pair may be *quoted*, not that a route
  /// exists. Coverage, liquidity and bounds can still fail the quote.
  final List<RoutedSwapSupportedCoin> coins;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {'provider': provider, 'coins': coins.length},
  };
}

/// `task::routed_swap::init` — starts a swap.
///
/// Returns a `task_id` only. The persistent `uuid` is allocated and persisted
/// KDF-side before execution begins and surfaces on the first status read; a
/// GUI that wants a durable reference before cancelling must read status once.
class RoutedSwapInitRequest
    extends BaseRequest<RoutedSwapInitResponse, GeneralErrorResponse> {
  RoutedSwapInitRequest({
    required super.rpcPass,
    required this.from,
    required this.to,
    required this.amount,
    required this.minToAmount,
    this.slippage,
    this.order,
    this.provider,
    this.clientId,
  }) : super(method: 'task::routed_swap::init', mmrpc: RpcVersion.v2_0);

  /// KDF ticker to sell.
  final String from;

  /// KDF ticker to buy.
  final String to;

  /// Sell amount in coin units.
  final String amount;

  /// The `amount_min` the user saw and accepted.
  ///
  /// Required, and load-bearing: KDF re-quotes fresh internally, and if the
  /// fresh guaranteed minimum falls below this the task fails `QuoteWorsened`
  /// with nothing sent on-chain. Passing the *expected* receive here instead of
  /// the minimum would reject almost every swap.
  final String minToAmount;

  /// Decimal fraction, max 0.5.
  final double? slippage;

  /// Route preference.
  final RoutedSwapOrder? order;

  /// Defaults to `lifi`.
  final String? provider;

  /// SSE client id. Defaults to 0 KDF-side, which is correct for the usual
  /// one-GUI-on-one-KDF setup.
  final int? clientId;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {
      'from': from,
      'to': to,
      'amount': amount,
      'min_to_amount': minToAmount,
      if (slippage != null) 'slippage': slippage,
      if (order != null) 'order': order!.wire,
      if (provider != null) 'provider': provider,
      if (clientId != null) 'client_id': clientId,
    },
  };

  @override
  RoutedSwapInitResponse parse(JsonMap json) => NewTaskResponse.parse(json);
}

/// Same shape as every other `task::*::init`.
typedef RoutedSwapInitResponse = NewTaskResponse;

/// `task::routed_swap::status`.
class RoutedSwapStatusRequest
    extends BaseRequest<RoutedSwapStatusResponse, GeneralErrorResponse> {
  RoutedSwapStatusRequest({
    required super.rpcPass,
    required this.taskId,
    this.forgetIfFinished = false,
  }) : super(method: 'task::routed_swap::status', mmrpc: RpcVersion.v2_0);

  /// The ephemeral task id from `init`.
  final int taskId;

  /// Whether KDF should drop the task once it reports a terminal result.
  ///
  /// KDF defaults this to **true**. This class defaults it to **false**, which
  /// is deliberate and differs from the wire default: a terminal read that
  /// forgets is destructive and unrepeatable, so any caller that wants it must
  /// say so. Reconciliation polling and SSE both depend on being able to read
  /// the same terminal result more than once.
  final bool forgetIfFinished;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {'task_id': taskId, 'forget_if_finished': forgetIfFinished},
  };

  @override
  RoutedSwapStatusResponse parse(JsonMap json) =>
      RoutedSwapStatusResponse.parse(json);

  @override
  bool shouldParseErrorAsResponse(JsonMap json) =>
      json.valueOrNull<String>('result', 'status') == 'Error' &&
      json.hasNestedKey('result', 'details');
}

/// The `{status, details}` envelope for a routed swap.
class RoutedSwapStatusResponse extends BaseResponse {
  RoutedSwapStatusResponse({
    required super.mmrpc,
    required this.status,
    required this.details,
  });

  /// Parses the generic `rpc_task` envelope into a [RoutedSwapStatus] union.
  factory RoutedSwapStatusResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    final status = result.value<String>('status');
    return RoutedSwapStatusResponse(
      mmrpc: json.value<String>('mmrpc'),
      status: status,
      details: RoutedSwapStatus.parse(status, result.value<JsonMap>('details')),
    );
  }

  /// `InProgress`, `Ok` or `Error`.
  final String status;

  /// The parsed routed-swap state.
  ///
  /// A terminal `Error` arrives here rather than as a thrown exception — see
  /// [RoutedSwapStatusRequest.shouldParseErrorAsResponse]. A top-level MMRPC
  /// error (`NoSuchTask`, a malformed request) still throws.
  final RoutedSwapStatus details;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {'status': status, 'details': details.uuid},
  };
}

/// `task::routed_swap::cancel`.
///
/// Accepted only before `Broadcasting`. On success the task is removed, so a
/// later status lookup returns `NoSuchTask` — the GUI confirms the cancellation
/// through history, not by polling for a `TaskCancelled` result.
class RoutedSwapCancelRequest
    extends BaseRequest<RoutedSwapCancelResponse, GeneralErrorResponse> {
  RoutedSwapCancelRequest({required super.rpcPass, required this.taskId})
    : super(method: 'task::routed_swap::cancel', mmrpc: RpcVersion.v2_0);

  /// The task to cancel.
  final int taskId;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {'task_id': taskId},
  };

  @override
  RoutedSwapCancelResponse parse(JsonMap json) =>
      RoutedSwapCancelResponse.parse(json);
}

/// Acknowledgement of a cancellation.
class RoutedSwapCancelResponse extends BaseResponse {
  RoutedSwapCancelResponse({required super.mmrpc, required this.result});

  /// Parses `result`, which KDF returns either as a bare string or as
  /// `{result: ...}` depending on the task implementation.
  factory RoutedSwapCancelResponse.parse(JsonMap json) {
    final raw = json['result'];
    return RoutedSwapCancelResponse(
      mmrpc: json.value<String>('mmrpc'),
      result: raw is Map
          ? convertToJsonMap(raw).valueOrNull<String>('result') ?? 'success'
          : raw?.toString() ?? 'success',
    );
  }

  /// KDF's acknowledgement string.
  final String result;

  @override
  JsonMap toJson() => {'mmrpc': mmrpc, 'result': result};
}
