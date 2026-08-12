import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// An amount of a token, as `routed_swap` reports it.
///
/// The token is identified by **either** a KDF [coin] ticker **or** a provider
/// [symbol], never both. §1 defines this fallback for `fee_costs`: an entry
/// carries `symbol` when the token does not map to a KDF ticker, and a symbol
/// must never be treated as a tradable ticker. Provider symbols collide with
/// real tickers — axlUSDC's on-chain symbol is frequently `USDC` — so resolving
/// one against the coin registry names the wrong asset.
///
/// §3's `received` is not yet specified this way; the GUI review asks for it.
/// Parsing it through the same type means the day it lands, nothing changes.
class RoutedSwapAmount {
  const RoutedSwapAmount({required this.amount, this.coin, this.symbol})
    : assert(
        coin != null || symbol != null,
        'a routed-swap amount must identify its token',
      );

  /// Parses `{coin|symbol, amount}`.
  factory RoutedSwapAmount.fromJson(JsonMap json) => RoutedSwapAmount(
    amount: json.value<String>('amount'),
    coin: json.valueOrNull<String>('coin'),
    symbol: json.valueOrNull<String>('symbol'),
  );

  /// Decimal string in coin units — never wei.
  final String amount;

  /// KDF ticker, when the token maps to one.
  final String? coin;

  /// The provider's token symbol, when it does not.
  final String? symbol;

  /// Whether this token can be looked up in the wallet's coin registry.
  ///
  /// When false the UI may show [symbol] as text but must not resolve it to an
  /// asset, link it to a balance, or offer it as something to trade.
  bool get isKnownAsset => coin != null;

  /// The best available label for display.
  String get label => coin ?? symbol!;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    if (coin != null) 'coin': coin,
    if (symbol != null) 'symbol': symbol,
    'amount': amount,
  };
}

/// The executing tool for a route, e.g. Stargate V2.
class RoutedSwapTool {
  const RoutedSwapTool({required this.key, required this.name, this.logoUrl});

  /// Parses `{key, name, logo_url?}`.
  factory RoutedSwapTool.fromJson(JsonMap json) => RoutedSwapTool(
    key: json.value<String>('key'),
    name: json.value<String>('name'),
    logoUrl: json.valueOrNull<String>('logo_url'),
  );

  /// Provider key, e.g. `stargateV2`.
  final String key;

  /// Human-readable name.
  final String name;

  /// Optional logo. §1: absent optional fields are omitted, not null.
  final String? logoUrl;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'key': key,
    'name': name,
    if (logoUrl != null) 'logo_url': logoUrl,
  };
}

/// One provider or protocol fee on a route.
class RoutedSwapFeeCost {
  const RoutedSwapFeeCost({
    required this.name,
    required this.amount,
    required this.included,
    this.amountUsd,
  });

  /// Parses a `fee_costs[]` entry.
  factory RoutedSwapFeeCost.fromJson(JsonMap json) => RoutedSwapFeeCost(
    name: json.value<String>('name'),
    amount: RoutedSwapAmount.fromJson(json),
    included: json.valueOrNull<bool>('included') ?? false,
    amountUsd: json.valueOrNull<String>('amount_usd'),
  );

  /// Free-text provider label. Not machine-readable — the GUI review asks for
  /// a `kind` discriminator so the integrator fee can be shown as its own line
  /// without string-matching text the provider can change.
  final String name;

  /// The fee token and amount.
  final RoutedSwapAmount amount;

  /// When true the fee is already deducted from the route's receive amount, so
  /// subtracting it again double-counts.
  ///
  /// §1 defines `true` and never defines `false`; until it does, treat `false`
  /// as "charged on top" and do not present a precise total that depends on it.
  final bool included;

  /// Optional USD value.
  final String? amountUsd;
}

/// Gas for the routed execution.
///
/// Approval gas is **not** represented here — §1 says an ERC-20 sell may need
/// one approval transaction, or two for a zero-reset token, and that the GUI
/// must warn the cost is extra. Any "total network fee" built from this alone
/// is knowingly incomplete.
class RoutedSwapGasCost {
  const RoutedSwapGasCost({required this.amount, this.amountUsd});

  /// Parses a `gas_costs[]` entry.
  factory RoutedSwapGasCost.fromJson(JsonMap json) => RoutedSwapGasCost(
    amount: RoutedSwapAmount.fromJson(json),
    amountUsd: json.valueOrNull<String>('amount_usd'),
  );

  /// The gas token and amount.
  final RoutedSwapAmount amount;

  /// Optional USD value.
  final String? amountUsd;
}

/// One leg of a route.
class RoutedSwapStep {
  const RoutedSwapStep({
    required this.type,
    required this.tool,
    this.chainId,
    this.fromChainId,
    this.toChainId,
  });

  /// Parses a `steps[]` entry.
  factory RoutedSwapStep.fromJson(JsonMap json) => RoutedSwapStep(
    type: json.value<String>('type'),
    tool: json.value<String>('tool'),
    chainId: json.valueOrNull<int>('chain_id'),
    fromChainId: json.valueOrNull<int>('from_chain_id'),
    toChainId: json.valueOrNull<int>('to_chain_id'),
  );

  /// `swap`, `cross`, or a value added later.
  ///
  /// Kept as a string deliberately: §1 gives no enum, and a closed enum here
  /// would throw on the first value a provider adds.
  final String type;

  /// Provider key of the tool running this step.
  final String tool;

  /// Set for same-chain steps.
  final int? chainId;

  /// Set for cross-chain steps.
  final int? fromChainId;

  /// Set for cross-chain steps.
  final int? toChainId;
}

/// A single route from `routed_swap::quote`.
///
/// v1 returns exactly one, but the response is an array so a route picker can
/// be added without a breaking change.
class RoutedSwapRoute {
  const RoutedSwapRoute({
    required this.provider,
    required this.from,
    required this.to,
    required this.toMinimum,
    required this.tool,
    required this.kind,
    required this.steps,
    required this.feeCosts,
    required this.gasCosts,
    this.executionDurationS,
  });

  /// Parses one `routes[]` entry.
  factory RoutedSwapRoute.fromJson(JsonMap json) {
    final to = json.value<JsonMap>('to');
    return RoutedSwapRoute(
      provider: json.value<String>('provider'),
      from: RoutedSwapAmount.fromJson(json.value<JsonMap>('from')),
      to: RoutedSwapAmount.fromJson(to),
      toMinimum: RoutedSwapAmount(
        amount: to.value<String>('amount_min'),
        coin: to.valueOrNull<String>('coin'),
        symbol: to.valueOrNull<String>('symbol'),
      ),
      tool: RoutedSwapTool.fromJson(json.value<JsonMap>('tool')),
      kind: RoutedSwapRouteKind.parse(json.value<String>('kind')),
      steps: (json.valueOrNull<List<dynamic>>('steps') ?? const [])
          .map((e) => RoutedSwapStep.fromJson(e as JsonMap))
          .toList(),
      feeCosts: (json.valueOrNull<List<dynamic>>('fee_costs') ?? const [])
          .map((e) => RoutedSwapFeeCost.fromJson(e as JsonMap))
          .toList(),
      gasCosts: (json.valueOrNull<List<dynamic>>('gas_costs') ?? const [])
          .map((e) => RoutedSwapGasCost.fromJson(e as JsonMap))
          .toList(),
      executionDurationS: json.valueOrNull<int>('execution_duration_s'),
    );
  }

  /// Echoed provider, `lifi` in v1.
  final String provider;

  /// What the user sells.
  final RoutedSwapAmount from;

  /// Expected receive. **Do not headline this** — see [toMinimum].
  final RoutedSwapAmount to;

  /// The guaranteed floor after slippage.
  ///
  /// §1 instructs the GUI to display this ("you receive at least …") and to
  /// pass it to `init` as the guard. Leading with [to] overstates the outcome.
  final RoutedSwapAmount toMinimum;

  /// The executing tool.
  final RoutedSwapTool tool;

  /// Same-chain or cross-chain.
  final RoutedSwapRouteKind kind;

  /// Per-leg breakdown.
  final List<RoutedSwapStep> steps;

  /// Provider and protocol fees.
  final List<RoutedSwapFeeCost> feeCosts;

  /// Execution gas, excluding approvals.
  final List<RoutedSwapGasCost> gasCosts;

  /// Provider's total duration estimate in seconds, when supplied.
  final int? executionDurationS;
}

/// Whether a route crosses chains.
enum RoutedSwapRouteKind {
  /// Completes in one transaction; no bridge phase.
  sameChain('same_chain'),

  /// Has a bridge phase, and can take 30+ minutes.
  crossChain('cross_chain'),

  /// A value this build does not know. Render generically rather than
  /// assuming same-chain, which would hide the bridge wait.
  unknown('');

  const RoutedSwapRouteKind(this.wire);

  /// Parses leniently — an unrecognised value is [unknown], not a throw.
  static RoutedSwapRouteKind parse(String value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => RoutedSwapRouteKind.unknown,
  );

  /// The wire value.
  final String wire;
}

/// The §3 in-progress ladder.
enum RoutedSwapState {
  /// KDF is re-quoting internally.
  fetchingQuote('FetchingQuote'),

  /// Reading the confirmed on-chain allowance.
  checkingAllowance('CheckingAllowance'),

  /// Sending an ERC-20 approval.
  approving('Approving'),

  /// Signing locally. Still cancellable.
  signing('Signing'),

  /// Committed to the network transport. No longer cancellable.
  broadcasting('Broadcasting'),

  /// Waiting on source-chain confirmation.
  waitingSourceConfirmation('WaitingSourceConfirmation'),

  /// Following the bridge to the destination.
  trackingBridge('TrackingBridge'),

  /// A state this build does not know.
  ///
  /// Treated as a generic in-progress step. The alternative — throwing — would
  /// strand a user mid-swap on any KDF newer than the app.
  unknown('');

  const RoutedSwapState(this.wire);

  /// Parses leniently. Unknown values are [unknown].
  static RoutedSwapState parse(String value) => values.firstWhere(
    (state) => state.wire == value,
    orElse: () => RoutedSwapState.unknown,
  );

  /// The wire value.
  final String wire;

  /// Whether the transaction has been handed to the network.
  ///
  /// [unknown] answers **true**: refusing a cancel that might have worked is
  /// recoverable, offering one that cannot is not.
  bool get isPostBroadcast => switch (this) {
    RoutedSwapState.fetchingQuote ||
    RoutedSwapState.checkingAllowance ||
    RoutedSwapState.approving ||
    RoutedSwapState.signing => false,
    _ => true,
  };

  /// Whether `task::routed_swap::cancel` is accepted in this state.
  bool get isCancellable => !isPostBroadcast;
}

/// The §3 terminal `Ok` outcomes.
enum RoutedSwapOutcome {
  /// Delivered the requested coin.
  completed('completed'),

  /// Less than expected, or an intermediate token.
  partial('partial'),

  /// Did not happen; funds returned on the source chain.
  refunded('refunded'),

  /// A value this build does not know. Must not be rendered as success.
  unknown('');

  const RoutedSwapOutcome(this.wire);

  /// Parses leniently. Unknown values are [unknown].
  static RoutedSwapOutcome parse(String value) => values.firstWhere(
    (outcome) => outcome.wire == value,
    orElse: () => RoutedSwapOutcome.unknown,
  );

  /// The wire value.
  final String wire;

  /// Whether this may be presented to the user as a completed swap.
  ///
  /// Only [completed] qualifies. `partial` and `refunded` must be surfaced
  /// prominently as *not* the swap the user asked for, and [unknown] is
  /// excluded because a future outcome the app cannot interpret must never
  /// default to "it worked".
  bool get isSuccess => this == RoutedSwapOutcome.completed;
}

/// The `details` payload of `task::routed_swap::status`.
///
/// One sealed union across all three task statuses. Every variant carries
/// [uuid] and [provider]: the uuid is the only durable handle on a swap, since
/// `task_id` is in-memory and dies on restart, cancellation or a
/// `forget_if_finished` read.
sealed class RoutedSwapStatus {
  const RoutedSwapStatus({required this.uuid, required this.provider});

  /// Parses the `details` object for a given task [status].
  factory RoutedSwapStatus.parse(String status, JsonMap details) {
    final uuid = details.value<String>('uuid');
    final provider = details.value<String>('provider');

    switch (status) {
      case 'Ok':
        return RoutedSwapSuccess(
          uuid: uuid,
          provider: provider,
          outcome: RoutedSwapOutcome.parse(details.value<String>('outcome')),
          received: RoutedSwapAmount.fromJson(
            details.value<JsonMap>('received'),
          ),
          sourceTxHash: details.valueOrNull<String>('source_tx_hash'),
          destTxHash: details.valueOrNull<String>('dest_tx_hash'),
          providerExplorerUrl: details.valueOrNull<String>(
            'provider_explorer_url',
          ),
        );
      case 'Error':
        return RoutedSwapFailure(
          uuid: uuid,
          provider: provider,
          errorType: details.value<String>('error_type'),
          message: details.valueOrNull<String>('error') ?? '',
          errorData: details.valueOrNull<JsonMap>('error_data') ?? const {},
          typedError: KdfErrorRegistry.tryParse(
            details,
            rpcMethodHint: 'task::routed_swap::status',
          ),
        );
      default:
        return RoutedSwapInProgress(
          uuid: uuid,
          provider: provider,
          state: RoutedSwapState.parse(details.value<String>('state')),
          rawState: details.value<String>('state'),
          approveTxHash: details.valueOrNull<String>('approve_tx_hash'),
          txHash: details.valueOrNull<String>('tx_hash'),
          substatus: details.valueOrNull<String>('substatus'),
          substatusMessage: details.valueOrNull<String>('substatus_message'),
          providerExplorerUrl: details.valueOrNull<String>(
            'provider_explorer_url',
          ),
          executionDurationS: details.valueOrNull<int>('execution_duration_s'),
        );
    }
  }

  /// The persistent swap id. Survives restart; recoverable via history.
  final String uuid;

  /// Echoed provider.
  final String provider;

  /// Whether the task has reached a terminal state.
  bool get isTerminal => this is! RoutedSwapInProgress;
}

/// A swap still running.
final class RoutedSwapInProgress extends RoutedSwapStatus {
  const RoutedSwapInProgress({
    required super.uuid,
    required super.provider,
    required this.state,
    required this.rawState,
    this.approveTxHash,
    this.txHash,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
    this.executionDurationS,
  });

  /// The parsed state.
  final RoutedSwapState state;

  /// The raw `state` string, kept so an unknown value can still be logged and
  /// reported to support rather than silently flattened.
  final String rawState;

  /// Present on `Approving`.
  final String? approveTxHash;

  /// Present from `WaitingSourceConfirmation` onward.
  final String? txHash;

  /// Opaque provider passthrough. Not localizable — show it in a details
  /// disclosure, never as primary copy.
  final String? substatus;

  /// Opaque provider passthrough, in the provider's own language.
  final String? substatusMessage;

  /// Provider explorer link for the bridge.
  final String? providerExplorerUrl;

  /// Provider duration estimate, when supplied.
  final int? executionDurationS;
}

/// A swap that reached a terminal `Ok`.
///
/// `Ok` is not the same as "succeeded" — check [RoutedSwapOutcome.isSuccess].
final class RoutedSwapSuccess extends RoutedSwapStatus {
  const RoutedSwapSuccess({
    required super.uuid,
    required super.provider,
    required this.outcome,
    required this.received,
    this.sourceTxHash,
    this.destTxHash,
    this.providerExplorerUrl,
  });

  /// What actually happened.
  final RoutedSwapOutcome outcome;

  /// The token and amount the user actually received. For a refund this is the
  /// returned source coin, not the requested destination coin.
  final RoutedSwapAmount received;

  /// Source-chain transaction.
  final String? sourceTxHash;

  /// Destination-chain transaction, when the swap reached the destination.
  final String? destTxHash;

  /// Provider explorer link.
  final String? providerExplorerUrl;
}

/// A swap that failed.
final class RoutedSwapFailure extends RoutedSwapStatus {
  const RoutedSwapFailure({
    required super.uuid,
    required super.provider,
    required this.errorType,
    required this.message,
    required this.errorData,
    this.typedError,
  });

  /// The `error_type` discriminator, kept as a string so an unrecognised
  /// variant still renders its human-readable [message] instead of throwing.
  final String errorType;

  /// KDF's human-readable error text.
  final String message;

  /// Variant-specific payload.
  final JsonMap errorData;

  /// The registry-typed exception, when this build knows the variant.
  final Object? typedError;

  /// Whether the user's funds are untouched, so a retry is safe to offer.
  ///
  /// Conservative by construction: only the variants §3 explicitly states are
  /// pre-broadcast qualify. An unknown variant answers false — telling a user
  /// nothing was sent when it may have been is the one mistake worth avoiding
  /// absolutely.
  bool get nothingWasSent => const {
    'QuoteWorsened',
    'InsufficientBalance',
    'ApprovalFailed',
    'AbortedOnRestart',
  }.contains(errorType);
}

/// One activated coin eligible to attempt a quote.
class RoutedSwapSupportedCoin {
  const RoutedSwapSupportedCoin({required this.coin, required this.chainId});

  /// Parses a `coins[]` entry.
  factory RoutedSwapSupportedCoin.fromJson(JsonMap json) =>
      RoutedSwapSupportedCoin(
        coin: json.value<String>('coin'),
        chainId: json.value<int>('chain_id'),
      );

  /// KDF ticker.
  final String coin;

  /// EVM chain id.
  final int chainId;
}
