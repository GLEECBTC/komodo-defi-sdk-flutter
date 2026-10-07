import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;

part 'routed_swap_contract_roundtrip_cases_1.dart';
part 'routed_swap_contract_roundtrip_cases_2.dart';

/// Parses everything the scripted KDF emits with the real SDK models, through
/// the same request pipeline production uses (`parseResponseJson`).
///
/// The fixture and the models are two independent readings of the engine.
/// Either could drift — a key renamed on one side, an optional treated as
/// required on the other — and every test built on top would keep passing
/// while the app broke against real KDF. This is the seam that catches it.

void main() {
  _cases1();
  _cases2();
}

const from = 'USDT-PLG20';

const to = 'USDC-ERC20';

RoutedSwapQuote route({
  bool crossChain = true,
  RoutedSwapQuoteApproval? approval = const RoutedSwapQuoteApproval.noAllowance(
    gasCoin: 'MATIC',
    gasAmount: '0.0009',
  ),
}) => RoutedSwapQuote(
  from: from,
  to: to,
  toAmount: '100.21',
  toAmountMin: '99.71',
  crossChain: crossChain,
  toolLogoUrl: 'https://li.fi/logos/stargate.png',
  approval: approval,
  steps: const [
    RoutedSwapQuoteStep.swap(tool: '1inch', chainId: 137),
    RoutedSwapQuoteStep.cross(
      tool: 'stargateV2',
      fromChainId: 137,
      toChainId: 1,
    ),
  ],
  feeCosts: [
    RoutedSwapQuoteFee(
      name: 'LIFI Fixed Fee',
      coin: from,
      amount: '0.05',
      amountUsd: '0.05',
      included: true,
    ),
    RoutedSwapQuoteFee(
      name: 'Bridge fee',
      symbol: 'axlUSDC',
      amount: '0.02',
      included: false,
    ),
  ],
  gasCosts: const [
    RoutedSwapQuoteGas(coin: 'MATIC', amount: '0.012', amountUsd: '0.01'),
  ],
);

Future<Map<String, dynamic>> call(
  KdfScript script,
  String method, [
  Map<String, dynamic> params = const {},
]) async {
  final response = await script.respondTo({
    'mmrpc': '2.0',
    'method': method,
    'params': params,
  });
  if (response == null) fail('nothing scripted for $method');
  return response;
}

Future<int> start(KdfScript script) async {
  final json = await call(script, 'task::routed_swap::init', {
    'from': from,
    'to': to,
    'amount': '100.5',
    'min_to_amount': '99.71',
  });
  return rpc.RoutedSwapInitRequest(
    rpcPass: '',
    from: from,
    to: to,
    amount: '100.5',
    minToAmount: '99.71',
  ).parseResponseJson(json).taskId;
}

Future<rpc.RoutedSwapStatus> status(KdfScript script, int taskId) async {
  final json = await call(script, 'task::routed_swap::status', {
    'task_id': taskId,
    'forget_if_finished': false,
  });
  return rpc.RoutedSwapStatusRequest(
    rpcPass: '',
    taskId: taskId,
  ).parseResponseJson(json).details;
}

Future<List<rpc.RoutedSwapStatus>> drain(KdfScript script, int taskId) async {
  final seen = <rpc.RoutedSwapStatus>[];
  for (var i = 0; i < 50; i++) {
    seen.add(await status(script, taskId));
    if (seen.last.isTerminal) return seen;
  }
  fail('the run never reached a terminal result');
}

Future<rpc.RoutedSwapStatus> terminal(RoutedSwapRun run) async {
  final script = (RoutedSwapFixture()..run(run)).build();
  return (await drain(script, await start(script))).last;
}

Future<Object> thrownBy(Future<void> Function() parse) async {
  try {
    await parse();
  } on Object catch (e) {
    return e;
  }
  fail('parsed as a response');
}

class _Accepted implements Exception {
  const _Accepted(this.result);

  final String result;
}
