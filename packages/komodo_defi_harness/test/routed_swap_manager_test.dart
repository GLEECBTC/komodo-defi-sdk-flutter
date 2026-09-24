@Timeout(Duration(seconds: 30))
library;

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

part 'routed_swap_manager_cases_1.dart';
part 'routed_swap_manager_cases_2.dart';
part 'routed_swap_manager_cases_3.dart';
part 'routed_swap_manager_cases_4.dart';

/// Drives [RoutedSwapManager] against the scripted KDF.
///
/// The manager absorbs the parts of the contract that are easy to get wrong:
/// resolving the durable uuid before handing out a handle, never destroying a
/// terminal result before reading it, treating the event stream as a hint,
/// recovering a vanished task from history, and saying honestly whether the
/// user's funds moved. None of that is visible from the type signatures, so
/// each is asserted here.

void main() {
  _cases1();
  _cases2();
  _cases3();
  _cases4();
}

final matic = _asset('MATIC', chainId: 137, decimals: 18);

final usdt = _asset('USDT-PLG20', chainId: 137, parent: matic, decimals: 6);

final eth = _asset('ETH', chainId: 1, decimals: 18);

final usdc = _asset('USDC-ERC20', chainId: 1, parent: eth, decimals: 6);

final low = _asset('LOW', chainId: 137, decimals: 4);

final assets = {
  for (final a in [matic, usdt, eth, usdc, low]) a.id: a,
};

RoutedSwapQuote route({
  String from = 'USDT-PLG20',
  String to = 'USDC-ERC20',
  RoutedSwapQuoteApproval? approval,
  bool crossChain = true,
  List<RoutedSwapQuoteGas> gasCosts = const [
    RoutedSwapQuoteGas(coin: 'MATIC', amount: '0.012', amountUsd: '0.01'),
  ],
}) => RoutedSwapQuote(
  from: from,
  to: to,
  toAmount: '100.21',
  toAmountMin: '99.71',
  crossChain: crossChain,
  approval: approval,
  gasCosts: gasCosts,
);

const approval = RoutedSwapQuoteApproval.noAllowance(
  gasCoin: 'MATIC',
  gasAmount: '0.0009',
);

RoutedSwapManager _managerFor(
  _Client client, {
  RoutedSwapTaskNudges? nudges,
  Duration pollInterval = const Duration(milliseconds: 5),
}) {
  final manager = RoutedSwapManager(
    client: client,
    resolveAsset: (ticker) => assets[ticker],
    taskNudges: nudges,
    pollInterval: pollInterval,
    historyPollInterval: const Duration(milliseconds: 5),
    maxBackoff: const Duration(milliseconds: 20),
    firstReadRetryDelay: const Duration(milliseconds: 1),
  );
  addTearDown(manager.dispose);
  return manager;
}

Future<RoutedSwapOffer> offerFrom(RoutedSwapManager manager) =>
    manager.quote(from: usdt, to: usdc, amount: Decimal.parse('100.5'));

/// Starts [run] against the scripted route and returns the handle.
Future<(RoutedSwapHandle, RoutedSwapFixture, _Client)> started(
  RoutedSwapRun run, {
  RoutedSwapQuote? quoted,
  Duration pollInterval = const Duration(milliseconds: 5),
  RoutedSwapTaskNudges? nudges,
}) async {
  final fixture = RoutedSwapFixture()
    ..quote(quoted ?? route())
    ..run(run);
  final client = _Client(fixture.build());
  final manager = _managerFor(
    client,
    pollInterval: pollInterval,
    nudges: nudges,
  );
  final handle = await manager.start(await offerFrom(manager));
  return (handle, fixture, client);
}

Future<RoutedSwapProgress> until(
  RoutedSwapHandle handle,
  bool Function(RoutedSwapProgress) test,
) => handle.progress.firstWhere(test).timeout(_timeout);

const Duration _timeout = Duration(seconds: 5);

AssetId _asset(
  String id, {
  required int chainId,
  required int decimals,
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

String _uuid(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

/// What a user could see change between two snapshots.
List<Object?> _key(RoutedSwapProgress p) => [
  p.phase,
  p.rawState,
  p.bridgeStage,
  p.providerStatusDetail,
  ...p.approvalTxHashes,
  p.sourceTxHash,
  p.destinationTxHash,
  p.receipt,
  p.failure?.errorType,
  p.delayedSince,
];

/// Lets fire-and-forget work (the final forget read) finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

/// An [ApiClient] over the scripted KDF that records requests and can fail
/// chosen calls the way a dropped connection does.
class _Client implements ApiClient {
  _Client(this._script);

  final KdfScript _script;
  final List<JsonMap> _requests = [];
  final Map<String, int> _failures = {};

  /// Throws from the next [times] calls to [method] before they reach KDF.
  void failNext(String method, {int times = 1}) {
    _failures[method] = (_failures[method] ?? 0) + times;
  }

  List<JsonMap> requestsFor(String method) =>
      _requests.where((r) => r['method'] == method).toList();

  List<JsonMap> paramsFor(String method) => [
    for (final request in requestsFor(method))
      request['params'] as JsonMap? ?? const {},
  ];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    _requests.add(request);
    final method = request['method'] as String;
    final failures = _failures[method] ?? 0;
    if (failures > 0) {
      _failures[method] = failures - 1;
      throw TimeoutException('scripted connection failure for $method');
    }
    final response = await _script.respondTo(request);
    if (response == null) throw StateError('nothing scripted for $method');
    return response;
  }
}
