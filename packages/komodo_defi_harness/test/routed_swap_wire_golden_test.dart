import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;

part 'routed_swap_wire_golden_cases_1.dart';
part 'routed_swap_wire_golden_cases_2.dart';
part 'routed_swap_wire_golden_cases_3.dart';

/// Parses hand-written engine JSON with the real SDK models.
///
/// Every payload below is written from the engine itself —
/// `komodo-defi-framework` `feat/lifi-integration` @ 4872ef2e,
/// `mm2src/mm2_main/src/routed_swap/{types,errors,swap_task,history}.rs` and
/// `rpc/lp_commands/routed_swap/` — with values lifted from its Rust unit
/// tests where they exist (`quote_fixture`, `completed_status`,
/// `routed_swap_task_error_wire_omits_absent_optional_fields`, …). Unlike the
/// round-trip suite this does not go through the fake, so it anchors the SDK
/// to the engine even if the fake drifts with it.

void main() {
  _cases1();
  _cases2();
  _cases3();
}

const String _uuid = '0d4dbd0c-5a4e-4b7f-9c1d-2e3f4a5b6c7d';
const String _wallet = '0x9f3aE7e1b2C4d5E6f7A8b9C0d1E2f3A4b5C6d7E8';
const String _diamond = '0x5555555555555555555555555555555555555555';
const String _sourceHash =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const String _destHash =
    '0x0000000000000000000000000000000000000000000000000000000000000002';
const String _approveHash =
    '0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const String _exactApproveHash =
    '0xa2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2';

/// `no_route_reasons` in errors.rs: provider summary, failed tools, then
/// filtered-out candidates.
const List<String> _noRouteReasons = [
  'no liquidity',
  'amount too low (hop)',
  'slippage exceeded (across)',
  'amount out of range',
];

/// `quote_fixture` / `source_token_fixture` through `build_route`, as
/// asserted by `erc20_quote_includes_direct_approval_cost_and_totals`.
final Map<String, dynamic> _erc20Route = _decode('''
{
  "provider": "lifi",
  "from": {"coin": "USDT-ETH", "amount": "1"},
  "to": {"coin": "USDC-POLYGON", "amount": "2", "amount_min": "1.9"},
  "tool": {"key": "across", "name": "Across V4"},
  "kind": "cross_chain",
  "from_address": "$_wallet",
  "to_address": "$_wallet",
  "approval": {
    "required": true,
    "tx_count": 1,
    "reason": "no_allowance",
    "spender": "$_diamond",
    "gas_costs": [{"coin": "ETH", "amount": "0.000057501"}]
  },
  "total_gas_costs": [
    {"coin": "ETH", "amount": "0.013057501"},
    {"coin": "MATIC", "amount": "0.002", "amount_usd": "4"}
  ],
  "steps": [
    {"type": "swap", "tool": "1inch", "chain_id": 1},
    {
      "type": "cross",
      "tool": "across",
      "from_chain_id": 1,
      "to_chain_id": 137
    }
  ],
  "fee_costs": [
    {
      "name": "native fee",
      "coin": "MATIC",
      "amount": "0.001",
      "included": true
    },
    {
      "name": "configured inactive fee",
      "coin": "FEE-INACTIVE",
      "amount": "0.25",
      "included": false
    },
    {
      "name": "malformed address fee",
      "symbol": "BROKEN",
      "amount": "0.25",
      "included": true
    }
  ],
  "gas_costs": [
    {"coin": "ETH", "amount": "0.01", "amount_usd": "20"},
    {"coin": "MATIC", "amount": "0.002", "amount_usd": "4"},
    {"coin": "ETH", "amount": "0.003", "amount_usd": "6"}
  ],
  "execution_duration_s": 31
}
''');

/// `native_cross_chain_quote_ignores_approval_metadata`: no approval, so
/// both totals keep USD (ETH 20 + 6).
final Map<String, dynamic> _nativeRoute = {
  ..._erc20Route,
  'from': {'coin': 'ETH', 'amount': '1'},
  'tool': {
    'key': 'across',
    'name': 'Across V4',
    'logo_url': 'https://cdn.example/logo.svg',
  },
  'total_gas_costs': [
    {'coin': 'ETH', 'amount': '0.013', 'amount_usd': '26'},
    {'coin': 'MATIC', 'amount': '0.002', 'amount_usd': '4'},
  ],
}..remove('approval');

final Map<String, dynamic> _trackingEntry = _decode('''
{
  "created_at": 20,
  "updated_at": 24,
  "requested": {"from": "ETH", "to": "USDC-POLYGON", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": [],
  "gas_spent": [
    {"tx_hash": "$_sourceHash", "coin": "ETH", "amount": "0.000021"}
  ],
  "total_gas_spent": [{"coin": "ETH", "amount": "0.000021"}],
  "swap": {
    "status": "InProgress",
    "details": {
      "state": "TrackingBridge",
      "uuid": "$_uuid",
      "provider": "lifi",
      "executed_route": ${jsonEncode(_nativeRoute)},
      "source_tx_hash": "$_sourceHash",
      "stage": "destination_pending",
      "substatus": "WAIT_DESTINATION_TRANSACTION",
      "execution_duration_s": 31
    }
  }
}
''');

final Map<String, dynamic> _cancelledEntry = _decode('''
{
  "created_at": 20,
  "updated_at": 30,
  "finished_at": 30,
  "requested": {"from": "USDT-ETH", "to": "USDC-POLYGON", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": ["$_approveHash"],
  "gas_spent": [
    {"tx_hash": "$_approveHash", "coin": "ETH", "amount": "0.002"}
  ],
  "total_gas_spent": [{"coin": "ETH", "amount": "0.002"}],
  "swap": {
    "status": "Error",
    "details": {
      "uuid": "00000000-0000-0000-0000-000000000003",
      "provider": "lifi",
      "executed_route": ${jsonEncode(_erc20Route)},
      "error_type": "TaskCancelled",
      "error": "Routed swap cancelled before broadcast"
    }
  }
}
''');

final Map<String, dynamic> _abortedEntry = _decode('''
{
  "created_at": 10,
  "updated_at": 15,
  "finished_at": 15,
  "requested": {"from": "ETH", "to": "USDC-POLYGON", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": [],
  "gas_spent": [],
  "total_gas_spent": [],
  "swap": {
    "status": "Error",
    "details": {
      "uuid": "00000000-0000-0000-0000-000000000001",
      "provider": "lifi",
      "error_type": "AbortedOnRestart",
      "error": "Swap aborted by node restart before broadcast"
    }
  }
}
''');

final Map<String, dynamic> _zeroResetEntry = _decode('''
{
  "created_at": 5,
  "updated_at": 9,
  "finished_at": 9,
  "requested": {"from": "USDT-ETH", "to": "USDT-ETH", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": ["$_approveHash", "$_exactApproveHash"],
  "gas_spent": [
    {"tx_hash": "$_approveHash", "coin": "ETH", "amount": "0.000021"},
    {"tx_hash": "$_exactApproveHash", "coin": "ETH", "amount": "0.000021"},
    {"tx_hash": "$_sourceHash", "coin": "ETH", "amount": "0.000021"}
  ],
  "total_gas_spent": [{"coin": "ETH", "amount": "0.000063"}],
  "swap": {
    "status": "Ok",
    "details": {
      "outcome": "completed",
      "uuid": "00000000-0000-0000-0000-000000000004",
      "provider": "lifi",
      "executed_route": ${jsonEncode(_erc20Route)},
      "received": {"coin": "USDT-ETH", "amount": "2"},
      "source_tx_hash": "$_sourceHash"
    }
  }
}
''');

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

Map<String, dynamic> _envelope(Object result) => {
  'mmrpc': '2.0',
  'result': result,
  'id': null,
};

/// A top-level MMRPC error: `MmRpcResponse` with the serialized `MmError`
/// flattened beside `mmrpc`.
Map<String, dynamic> _rpcError(String type, String message, Object data) => {
  'mmrpc': '2.0',
  'error': message,
  'error_path': 'routed_swap',
  'error_trace': 'routed_swap:1]',
  'error_type': type,
  'error_data': data,
  'id': null,
};

/// Parses a `task::routed_swap::status` response through the request, so a
/// terminal `Error` must come back as a response rather than be thrown.
rpc.RoutedSwapStatus _status(String status, Map<String, dynamic> details) {
  final json =
      jsonDecode(jsonEncode(_envelope({'status': status, 'details': details})))
          as Map<String, dynamic>;
  final response = rpc.RoutedSwapStatusRequest(
    rpcPass: '',
    taskId: 3,
  ).parseResponseJson(json);
  expect(response.status, status);
  return response.details;
}
