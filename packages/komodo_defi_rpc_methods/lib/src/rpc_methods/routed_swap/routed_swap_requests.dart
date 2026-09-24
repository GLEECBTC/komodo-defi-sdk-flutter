import 'dart:developer';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Preferred route ordering for `routed_swap::quote` and `init`.
enum RoutedSwapOrder {
  /// Minimises the quoted cost. The default.
  cheapest('cheapest'),

  /// Minimises the estimated execution time.
  fastest('fastest');

  const RoutedSwapOrder(this.wire);

  /// The wire value.
  final String wire;
}

/// Shared by every routed-swap request: typed routed errors are parsed before
/// the global registry, whose name-only lookup types several of them into
/// unrelated domains.
abstract class RoutedSwapRequestBase<T extends BaseResponse>
    extends BaseRequest<T, RoutedSwapRpcException> {
  RoutedSwapRequestBase({required super.rpcPass, required super.method})
    : super(mmrpc: RpcVersion.v2_0);

  @override
  RoutedSwapRpcException? parseCustomErrorResponse(JsonMap json) =>
      RoutedSwapRpcException.tryParse(json);
}

/// `routed_swap::quote` — display-only pricing. Reserves and executes nothing.
///
/// Optional fields are omitted when null, never sent as `null`: the engine
/// rejects unknown and null fields.
class RoutedSwapQuoteRequest
    extends RoutedSwapRequestBase<RoutedSwapQuoteResponse> {
  RoutedSwapQuoteRequest({
    required super.rpcPass,
    required this.from,
    required this.to,
    required this.amount,
    this.slippage,
    this.order,
    this.provider,
  }) : super(method: 'routed_swap::quote');

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
      mmrpc: json.valueOrNull<String>('mmrpc') ?? '2.0',
      routes: result
          .value<List<dynamic>>('routes')
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => RoutedSwapRoute.fromJson(convertToJsonMap(e)))
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
    'result': {
      'routes': [for (final route in routes) route.toJson()],
    },
  };
}

/// `routed_swap::supported_coins` — which activated coins may be quoted.
class RoutedSwapSupportedCoinsRequest
    extends RoutedSwapRequestBase<RoutedSwapSupportedCoinsResponse> {
  RoutedSwapSupportedCoinsRequest({required super.rpcPass, this.provider})
    : super(method: 'routed_swap::supported_coins');

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
    this.skipped = 0,
  });

  /// Parses `result.{provider, coins}`.
  ///
  /// Each entry is parsed on its own and one that fails is logged and
  /// skipped: a coin this SDK cannot read — a non-EVM chain id from a later
  /// phase, say — must not withdraw every other coin from routed swaps.
  factory RoutedSwapSupportedCoinsResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    final coins = <RoutedSwapSupportedCoin>[];
    var skipped = 0;
    for (final raw in result.value<List<dynamic>>('coins')) {
      try {
        if (raw is! Map) throw FormatException('not an object', raw);
        coins.add(RoutedSwapSupportedCoin.fromJson(convertToJsonMap(raw)));
      } on Object catch (error) {
        skipped++;
        log(
          'Skipped a supported_coins entry: $raw ($error)',
          name: 'RoutedSwapSupportedCoinsResponse',
        );
      }
    }
    return RoutedSwapSupportedCoinsResponse(
      mmrpc: json.valueOrNull<String>('mmrpc') ?? '2.0',
      provider: result.valueOrNull<String>('provider') ?? 'lifi',
      coins: coins,
      skipped: skipped,
    );
  }

  /// Echoed provider.
  final String provider;

  /// Eligible coins.
  ///
  /// Two coins appearing here means the pair may be *quoted*, not that a route
  /// exists. Coverage, liquidity and bounds can still fail the quote.
  final List<RoutedSwapSupportedCoin> coins;

  /// How many entries could not be read and were left out of [coins].
  final int skipped;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'provider': provider,
      'coins': [
        for (final coin in coins) {'coin': coin.coin, 'chain_id': coin.chainId},
      ],
    },
  };
}

/// `task::routed_swap::init` — starts a swap.
///
/// Returns a `task_id` only. The persistent `uuid` is allocated and persisted
/// KDF-side before execution begins and surfaces on the first status read; a
/// GUI that wants a durable reference before cancelling must read status once.
class RoutedSwapInitRequest
    extends RoutedSwapRequestBase<RoutedSwapInitResponse> {
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
  }) : super(method: 'task::routed_swap::init');

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

  /// Route preference. The internal re-quote uses it, so it must match the
  /// order the displayed quote was priced with.
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
///
/// A terminal task `Error` is a normal response here, not an exception. A
/// top-level error — [RoutedSwapNoSuchTaskException] for a forgotten,
/// cancelled or restarted task — still throws.
class RoutedSwapStatusRequest
    extends RoutedSwapRequestBase<RoutedSwapStatusResponse> {
  RoutedSwapStatusRequest({
    required super.rpcPass,
    required this.taskId,
    this.forgetIfFinished = false,
  }) : super(method: 'task::routed_swap::status');

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
      mmrpc: json.valueOrNull<String>('mmrpc') ?? '2.0',
      status: status,
      details: RoutedSwapStatus.parse(status, result.value<JsonMap>('details')),
    );
  }

  /// `InProgress`, `Ok` or `Error`.
  final String status;

  /// The parsed routed-swap state.
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
/// through history, not by polling for a `TaskCancelled` result. Refusals are
/// typed: [RoutedSwapNoSuchTaskException] (404),
/// [RoutedSwapTaskFinishedException] (409),
/// [RoutedSwapTaskAlreadyBroadcastException] (409) and
/// [RoutedSwapInternalException] (500).
class RoutedSwapCancelRequest
    extends RoutedSwapRequestBase<RoutedSwapCancelResponse> {
  RoutedSwapCancelRequest({required super.rpcPass, required this.taskId})
    : super(method: 'task::routed_swap::cancel');

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

  /// Parses `result`, a bare `"success"` string on the wire; a
  /// `{result: ...}` object is tolerated too.
  factory RoutedSwapCancelResponse.parse(JsonMap json) {
    final raw = json['result'];
    return RoutedSwapCancelResponse(
      mmrpc: json.valueOrNull<String>('mmrpc') ?? '2.0',
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
