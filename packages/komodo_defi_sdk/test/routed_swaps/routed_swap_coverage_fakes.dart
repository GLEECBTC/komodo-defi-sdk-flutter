import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

Decimal d(String value) => Decimal.parse(value);

AssetId coverageAsset(
  String id, {
  required int chainId,
  int? decimals,
  AssetId? parent,
}) => AssetId(
  id: id,
  name: id,
  symbol: AssetSymbol(assetConfigId: id),
  chainId: AssetChainId(chainId: chainId, decimalsValue: decimals),
  derivationPath: null,
  subClass: parent == null ? CoinSubClass.polygon : CoinSubClass.erc20,
  parentId: parent,
);

final AssetId eth = coverageAsset('ETH', chainId: 1, decimals: 18);
final AssetId usdc = coverageAsset(
  'USDC-ERC20',
  chainId: 1,
  decimals: 6,
  parent: eth,
);
final AssetId matic = coverageAsset('MATIC', chainId: 137, decimals: 18);
final AssetId usdt = coverageAsset(
  'USDT-PLG20',
  chainId: 137,
  decimals: 6,
  parent: matic,
);

final Map<String, AssetId> knownAssets = {
  for (final asset in [eth, usdc, matic, usdt]) asset.id: asset,
};

String uuidOf(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

typedef KdfHandler = FutureOr<JsonMap> Function(JsonMap params);

/// A KDF that answers from scripted handlers and records every request.
///
/// [next] handlers are used once, in order, before falling back to the
/// [always] handler for the method.
class ScriptedKdf implements ApiClient {
  final Map<String, List<KdfHandler>> _next = {};
  final Map<String, KdfHandler> _always = {};
  final List<JsonMap> requests = [];

  void always(String method, KdfHandler handler) => _always[method] = handler;

  void next(String method, KdfHandler handler) =>
      (_next[method] ??= []).add(handler);

  int calls(String method) =>
      requests.where((request) => request['method'] == method).length;

  List<JsonMap> paramsFor(String method) => [
    for (final request in requests)
      if (request['method'] == method)
        request['params'] as JsonMap? ?? const {},
  ];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    requests.add(request);
    final method = request['method'] as String;
    final params = request['params'] as JsonMap? ?? const <String, dynamic>{};
    final queued = _next[method];
    final handler = queued != null && queued.isNotEmpty
        ? queued.removeAt(0)
        : _always[method];
    if (handler == null) throw StateError('nothing scripted for $method');
    return handler(params);
  }
}

/// A dropped connection, as the transport reports it.
Never dropped(JsonMap _) => throw TimeoutException('scripted connection drop');

JsonMap ok(Object result) => {'mmrpc': '2.0', 'result': result, 'id': null};

JsonMap rpcError(String type, Object? data, {String message = 'refused'}) => {
  'mmrpc': '2.0',
  'error': message,
  'error_path': 'routed_swap',
  'error_trace': 'routed_swap:1]',
  'error_type': type,
  'error_data': ?data,
  'id': null,
};

JsonMap routeJson({
  String from = 'USDC-ERC20',
  String fromAmount = '100',
  String to = 'USDT-PLG20',
  String toAmount = '99.5',
  String toMin = '99',
  String kind = 'cross_chain',
  List<JsonMap> gasCosts = const [
    {'coin': 'ETH', 'amount': '0.01', 'amount_usd': '20'},
  ],
  List<JsonMap>? totalGasCosts,
  JsonMap? approval,
  List<JsonMap> feeCosts = const [],
  int? durationS = 95,
}) => {
  'provider': 'lifi',
  'from': {'coin': from, 'amount': fromAmount},
  'to': {'coin': to, 'amount': toAmount, 'amount_min': toMin},
  'tool': {'key': 'stargateV2', 'name': 'Stargate V2'},
  'kind': kind,
  'from_address': '0xwallet',
  'to_address': '0xwallet',
  'approval': ?approval,
  'total_gas_costs': totalGasCosts ?? gasCosts,
  'steps': [
    {
      'type': 'cross',
      'tool': 'stargateV2',
      'from_chain_id': 1,
      'to_chain_id': 137,
    },
  ],
  'fee_costs': feeCosts,
  'gas_costs': gasCosts,
  'execution_duration_s': ?durationS,
};

JsonMap approvalJson({List<JsonMap> gasCosts = const []}) => {
  'required': true,
  'tx_count': 1,
  'reason': 'no_allowance',
  'spender': '0xdiamond',
  'gas_costs': gasCosts,
};

JsonMap inProgress(
  String uuid,
  String state, {
  JsonMap? route,
  String? approveTxHash,
  String? sourceTxHash,
  String? stage,
  String? substatus,
  String? substatusMessage,
  int? durationS,
}) => {
  'status': 'InProgress',
  'details': {
    'uuid': uuid,
    'provider': 'lifi',
    'state': state,
    'executed_route': ?route,
    'approve_tx_hash': ?approveTxHash,
    'source_tx_hash': ?sourceTxHash,
    'stage': ?stage,
    'substatus': ?substatus,
    'substatus_message': ?substatusMessage,
    'execution_duration_s': ?durationS,
  },
};

JsonMap completed(String uuid, {String outcome = 'completed'}) => {
  'status': 'Ok',
  'details': {
    'uuid': uuid,
    'provider': 'lifi',
    'executed_route': routeJson(),
    'outcome': outcome,
    'received': {'coin': 'USDT-PLG20', 'amount': '99.4'},
    'source_tx_hash': '0xsource',
    'dest_tx_hash': '0xdest',
  },
};

JsonMap failedWith(
  String uuid,
  String errorType, {
  Object? data,
  String message = 'failed',
  JsonMap? route,
}) => {
  'status': 'Error',
  'details': {
    'uuid': uuid,
    'provider': 'lifi',
    'executed_route': ?route,
    'error_type': errorType,
    'error': message,
    'error_data': ?data,
  },
};

JsonMap entryJson(
  JsonMap swap, {
  int createdAt = 1754784000,
  int updatedAt = 1754784010,
  int? finishedAt,
  String from = 'USDC-ERC20',
  String to = 'USDT-PLG20',
  String amount = '100',
  String minimum = '99',
  List<String> approvals = const [],
  List<JsonMap> gasSpent = const [],
  List<JsonMap> totalGasSpent = const [],
}) => {
  'created_at': createdAt,
  'updated_at': updatedAt,
  'finished_at': ?finishedAt,
  'requested': {'from': from, 'to': to, 'amount': amount},
  'min_to_amount_accepted': minimum,
  'approval_tx_hashes': approvals,
  'gas_spent': gasSpent,
  'total_gas_spent': totalGasSpent,
  'swap': swap,
};

JsonMap historyAnswer(
  List<JsonMap> entries, {
  int? total,
  int page = 1,
  int totalPages = 1,
}) => ok({
  'entries': entries,
  'total': total ?? entries.length,
  'limit': 20,
  'page_number': page,
  'total_pages': totalPages,
});

RoutedSwapManager managerFor(
  ScriptedKdf kdf, {
  RoutedSwapTaskNudges? nudges,
  int firstReadAttempts = 3,
  RoutedSwapAssetResolver? resolve,
}) => RoutedSwapManager(
  client: kdf,
  resolveAsset: resolve ?? (ticker) => knownAssets[ticker],
  taskNudges: nudges,
  firstReadAttempts: firstReadAttempts,
);

/// Runs [future] to completion on fake time and returns its value.
T awaited<T>(
  FakeAsync async,
  Future<T> future, {
  Duration elapse = Duration.zero,
}) {
  late T value;
  Object? error;
  StackTrace? stack;
  var done = false;
  future.then<void>(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      stack = s;
      done = true;
    },
  );
  async
    ..flushMicrotasks()
    ..elapse(elapse);
  if (!done) throw StateError('the future did not complete');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value;
}

/// Runs [future] on fake time and returns what it threw.
Object? thrownBy(FakeAsync async, Future<Object?> future) {
  try {
    awaited(async, future);
  } on Object catch (error) {
    return error;
  }
  return null;
}

/// Quotes the default route and starts it; the first status read answers
/// [first].
RoutedSwapHandle startSwap(
  FakeAsync async,
  ScriptedKdf kdf,
  RoutedSwapManager manager, {
  required JsonMap first,
  int taskId = 1,
}) {
  kdf
    ..always(
      'routed_swap::quote',
      (_) => ok({
        'routes': [routeJson()],
      }),
    )
    ..next('task::routed_swap::init', (_) => ok({'task_id': taskId}))
    ..next('task::routed_swap::status', (_) => ok(first));
  final offer = awaited(
    async,
    manager.quote(from: usdc, to: usdt, amount: d('100')),
  );
  return awaited(async, manager.start(offer));
}

/// An offer on the default route, built directly rather than quoted.
RoutedSwapOffer offerOf({
  RoutedSwapRouteKind kind = RoutedSwapRouteKind.crossChain,
  List<RoutedSwapCost> costs = const [],
  RoutedSwapApprovalInfo? approval,
  DateTime? quotedAt,
  RoutedSwapOrder? order,
  String? toolLogoUrl,
  Duration? estimatedDuration,
  double? slippage,
  String? address,
}) => RoutedSwapOffer(
  from: usdc,
  to: usdt,
  sellAmount: d('100'),
  expectedReceive: d('99.5'),
  guaranteedReceive: d('99'),
  kind: kind,
  costs: costs,
  networkFees: [
    RoutedSwapNetworkFee(ticker: 'ETH', assetId: eth, amount: d('0.01')),
  ],
  legs: const [
    RoutedSwapLeg(
      type: RoutedSwapStepType.cross,
      fromChainId: 1,
      toChainId: 137,
    ),
  ],
  quotedAt: quotedAt ?? DateTime.utc(2026, 9, 25, 12),
  provider: 'lifi',
  toolKey: 'stargateV2',
  toolName: 'Stargate V2',
  route: rpc.RoutedSwapRoute.fromJson(routeJson()),
  approval: approval,
  order: order,
  toolLogoUrl: toolLogoUrl,
  estimatedDuration: estimatedDuration,
  slippage: slippage,
  fromAddress: address,
  toAddress: address,
);
