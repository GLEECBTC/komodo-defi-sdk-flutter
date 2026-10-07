import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

part 'routed_swap_route.dart';
part 'routed_swap_status.dart';
part 'routed_swap_task_errors.dart';

/// An amount of a token, as `routed_swap` reports it.
///
/// The token is identified by **either** a KDF [coin] ticker **or** a provider
/// [symbol] — exactly one of the two keys is present, and which one tells you
/// which you got. A symbol must never be treated as a tradable ticker: provider
/// symbols collide with real tickers (axlUSDC's on-chain symbol is frequently
/// `USDC`), so resolving one against the coin registry names the wrong asset.
///
/// The same rule covers `fee_costs[]` and a terminal `received`.
class RoutedSwapAmount extends Equatable {
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

  @override
  List<Object?> get props => [amount, coin, symbol];
}

/// The executing tool for a route, e.g. Stargate V2.
///
/// Infrastructure identity: diagnostic, not customer-facing copy.
class RoutedSwapTool extends Equatable {
  const RoutedSwapTool({required this.key, required this.name, this.logoUrl});

  /// Parses `{key, name, logo_url?}`.
  factory RoutedSwapTool.fromJson(JsonMap json) => RoutedSwapTool(
    key: json.value<String>('key'),
    name: json.value<String>('name'),
    logoUrl: json.valueOrNull<String>('logo_url'),
  );

  /// Stable provider key, e.g. `stargateV2`.
  final String key;

  /// Human-readable name.
  final String name;

  /// Optional logo. Absent optional fields are omitted, not null.
  final String? logoUrl;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'key': key,
    'name': name,
    if (logoUrl != null) 'logo_url': logoUrl,
  };

  @override
  List<Object?> get props => [key, name, logoUrl];
}

/// One provider or protocol fee on a route.
class RoutedSwapFeeCost extends Equatable {
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

  /// Free-text provider label.
  final String name;

  /// The fee token and amount.
  final RoutedSwapAmount amount;

  /// `true`: already deducted from the route's `to.amount`, so subtracting it
  /// again double-counts. `false`: charged in addition to the displayed
  /// amounts, and must be counted into total cost.
  final bool included;

  /// Optional provider-reported USD value.
  final String? amountUsd;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'name': name,
    ...amount.toJson(),
    if (amountUsd != null) 'amount_usd': amountUsd,
    'included': included,
  };

  @override
  List<Object?> get props => [name, amount, included, amountUsd];
}

/// Gas for one coin.
///
/// Used for the route's execution gas, the approval's gas, and the per-coin
/// totals. Approval gas never carries [amountUsd] — KDF computes it on-chain
/// and has no USD source — so a total for the coin paying approval gas omits
/// it too; fill it from the app's own price source rather than presenting a
/// partial sum as a total.
class RoutedSwapGasCost extends Equatable {
  const RoutedSwapGasCost({required this.amount, this.amountUsd});

  /// Parses a gas entry.
  factory RoutedSwapGasCost.fromJson(JsonMap json) => RoutedSwapGasCost(
    amount: RoutedSwapAmount.fromJson(json),
    amountUsd: json.valueOrNull<String>('amount_usd'),
  );

  /// The gas token and amount.
  final RoutedSwapAmount amount;

  /// Optional USD value.
  final String? amountUsd;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    ...amount.toJson(),
    if (amountUsd != null) 'amount_usd': amountUsd,
  };

  @override
  List<Object?> get props => [amount, amountUsd];
}

/// Why a sell needs approval transactions.
enum RoutedSwapApprovalReason {
  /// No confirmed allowance covers the sell. One exact-amount approval.
  noAllowance('no_allowance'),

  /// A token that requires its allowance to pass through zero: a reset to
  /// zero, then the exact-amount approval. Two transactions.
  zeroReset('zero_reset'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapApprovalReason(this.wire);

  /// Parses leniently.
  static RoutedSwapApprovalReason parse(String? value) => values.firstWhere(
    (reason) => reason.wire == value,
    orElse: () => RoutedSwapApprovalReason.unknown,
  );

  /// The wire value.
  final String wire;
}

/// The approval transactions a sell requires before the swap.
///
/// Present on a route only when approval is needed; omitted when the
/// confirmed allowance already covers the sell, and always omitted for a
/// native sell. An estimate that goes stale with the rest of the quote.
class RoutedSwapApproval extends Equatable {
  const RoutedSwapApproval({
    required this.required,
    required this.txCount,
    required this.reason,
    required this.spender,
    required this.gasCosts,
  });

  /// Parses `{required, tx_count, reason, spender, gas_costs}`.
  factory RoutedSwapApproval.fromJson(JsonMap json) => RoutedSwapApproval(
    required: json.valueOrNull<bool>('required') ?? true,
    txCount: json.valueOrNull<int>('tx_count') ?? 1,
    reason: RoutedSwapApprovalReason.parse(json.valueOrNull<String>('reason')),
    spender: json.valueOrNull<String>('spender') ?? '',
    gasCosts: _list(json, 'gas_costs', RoutedSwapGasCost.fromJson),
  );

  /// Always true when present in v1.
  final bool required;

  /// 1, or 2 when [reason] is [RoutedSwapApprovalReason.zeroReset].
  final int txCount;

  /// Why approval is needed.
  final RoutedSwapApprovalReason reason;

  /// The contract the approval grants to. KDF allowlists it independently.
  final String spender;

  /// Approval gas, additive to the route's execution gas. Never has USD.
  final List<RoutedSwapGasCost> gasCosts;

  /// Whether the current allowance is reset to zero before the exact approval.
  bool get resetsFirst => reason == RoutedSwapApprovalReason.zeroReset;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'required': required,
    'tx_count': txCount,
    'reason': reason.wire,
    'spender': spender,
    'gas_costs': [for (final gas in gasCosts) gas.toJson()],
  };

  @override
  List<Object?> get props => [required, txCount, reason, spender, gasCosts];
}

/// Kind of one route leg.
enum RoutedSwapStepType {
  /// A conversion on one chain.
  swap('swap'),

  /// A bridge between two chains.
  cross('cross'),

  /// A leg type this build does not know.
  unknown('');

  const RoutedSwapStepType(this.wire);

  /// Parses leniently.
  static RoutedSwapStepType parse(String value) => values.firstWhere(
    (type) => type.wire == value,
    orElse: () => RoutedSwapStepType.unknown,
  );

  /// The wire value.
  final String wire;
}

/// One leg of a route.
class RoutedSwapStep extends Equatable {
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
    tool: json.valueOrNull<String>('tool') ?? '',
    chainId: json.valueOrNull<int>('chain_id'),
    fromChainId: json.valueOrNull<int>('from_chain_id'),
    toChainId: json.valueOrNull<int>('to_chain_id'),
  );

  /// The raw `type`, kept so a leg type added later is still reportable.
  final String type;

  /// Provider key of the tool running this leg. Diagnostic only.
  final String tool;

  /// Set for same-chain legs.
  final int? chainId;

  /// Set for cross-chain legs.
  final int? fromChainId;

  /// Set for cross-chain legs.
  final int? toChainId;

  /// The parsed leg type.
  RoutedSwapStepType get stepType => RoutedSwapStepType.parse(type);

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'type': type,
    'tool': tool,
    if (chainId != null) 'chain_id': chainId,
    if (fromChainId != null) 'from_chain_id': fromChainId,
    if (toChainId != null) 'to_chain_id': toChainId,
  };

  @override
  List<Object?> get props => [type, tool, chainId, fromChainId, toChainId];
}

/// One activated coin eligible to attempt a quote.
class RoutedSwapSupportedCoin extends Equatable {
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

  @override
  List<Object?> get props => [coin, chainId];
}

List<T> _list<T>(JsonMap json, String key, T Function(JsonMap) parse) => [
  for (final entry in json.valueOrNull<List<dynamic>>(key) ?? const [])
    if (entry is Map) parse(convertToJsonMap(entry)),
];

List<String> _strings(JsonMap json, String key) => [
  for (final entry in json.valueOrNull<List<dynamic>>(key) ?? const [])
    if (entry is String) entry,
];
