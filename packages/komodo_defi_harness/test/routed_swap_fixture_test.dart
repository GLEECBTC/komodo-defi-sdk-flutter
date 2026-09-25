import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_harness/komodo_defi_harness.dart';

part 'routed_swap_fixture_cases_1.dart';
part 'routed_swap_fixture_cases_2.dart';
part 'routed_swap_fixture_cases_3.dart';
part 'routed_swap_fixture_cases_4.dart';

/// Asserts the scripted `routed_swap` KDF against the engine's wire shapes
/// (`komodo-defi-framework` `feat/lifi-integration`, `routed_swap/`).
///
/// These test the fake, not a GUI: every consumer test inherits whatever the
/// fake gets wrong, so the shapes the engine promises are pinned here first.

void main() {
  _cases1();
  _cases2();
  _cases3();
  _cases4();
}

const from = 'USDT-PLG20';

const to = 'USDC-ERC20';

RoutedSwapQuote route({
  RoutedSwapQuoteApproval? approval,
  bool crossChain = true,
  String toAmount = '100.21',
  String toAmountMin = '99.71',
  String? toolLogoUrl,
}) => RoutedSwapQuote(
  from: from,
  to: to,
  toAmount: toAmount,
  toAmountMin: toAmountMin,
  crossChain: crossChain,
  toolLogoUrl: toolLogoUrl,
  approval: approval,
  steps: [
    const RoutedSwapQuoteStep.swap(tool: '1inch', chainId: 137),
    if (crossChain)
      const RoutedSwapQuoteStep.cross(
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
    RoutedSwapQuoteGas(coin: 'ETH', amount: '0.001', amountUsd: '2.5'),
    RoutedSwapQuoteGas(coin: 'MATIC', amount: '0.003', amountUsd: '0.002'),
  ],
);

const approval = RoutedSwapQuoteApproval.noAllowance(
  gasCoin: 'MATIC',
  gasAmount: '0.0009',
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

Future<int> start(
  KdfScript script, {
  String amount = '100.5',
  String minToAmount = '99.71',
}) async {
  final init = await call(script, 'task::routed_swap::init', {
    'from': from,
    'to': to,
    'amount': amount,
    'min_to_amount': minToAmount,
  });
  return _map(init['result'])['task_id'] as int;
}

Future<Map<String, dynamic>> poll(
  KdfScript script,
  int taskId, {
  bool? forget = false,
}) => call(script, 'task::routed_swap::status', {
  'task_id': taskId,
  'forget_if_finished': ?forget,
});

/// Polls until terminal, returning every `result` seen.
Future<List<Map<String, dynamic>>> drain(KdfScript script, int taskId) async {
  final seen = <Map<String, dynamic>>[];
  for (var i = 0; i < 50; i++) {
    final result = _map((await poll(script, taskId))['result']);
    seen.add(result);
    if (result['status'] != 'InProgress') return seen;
  }
  fail('the run never reached a terminal result');
}

Future<Map<String, dynamic>> terminal(
  RoutedSwapRun run, {
  RoutedSwapFixture? fixture,
  String minToAmount = '99.71',
}) async {
  final f = (fixture ?? RoutedSwapFixture())..run(run);
  final script = f.build();
  final taskId = await start(script, minToAmount: minToAmount);
  return (await drain(script, taskId)).last;
}

String _uuid(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

Map<String, dynamic> _map(Object? value) => value! as Map<String, dynamic>;

List<dynamic> _list(Object? value) => value! as List<dynamic>;

String _json(Object? value) => jsonEncode(value);

/// Optional fields are omitted, never null.
void _expectNoNulls(Object? value, [String path = r'$']) {
  if (value == null) fail('null at $path');
  if (value is Map) {
    for (final entry in value.entries) {
      _expectNoNulls(entry.value, '$path.${entry.key}');
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _expectNoNulls(value[i], '$path[$i]');
    }
  }
}
