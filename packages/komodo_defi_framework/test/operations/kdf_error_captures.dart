/// KDF answers as each transport receives them, recorded from KDF
/// 3.1.0-beta_4872ef2 on 2026-09-28 with a throwaway wallet: over HTTP from
/// the native macOS binary, and from `mm2_rpc` in the WebAssembly build
/// running in Chrome.
library;

/// One answer, from both builds.
class KdfCapture {
  const KdfCapture({
    required this.name,
    required this.request,
    required this.status,
    required this.native,
    required this.web,
  });

  final String name;

  /// The request, less `userpass`.
  final Map<String, dynamic> request;

  /// The native HTTP status. The native build sent no Content-Type.
  final int status;

  /// The native body, verbatim.
  final String native;

  /// What the web build's `mm2_rpc` resolved to.
  final Map<String, dynamic> web;
}

/// [response] with KDF's `module:line] ` trace segments cut from its `error`
/// text. The two builds trace an error differently; the words are the same.
Map<String, dynamic> withoutTraces(Map<String, dynamic> response) => {
  ...response,
  if (response['error'] case final String error)
    'error': error.replaceAll(RegExp(r'\w+:\d+\] '), ''),
};

const _uuid = '0d4dbd0c-5a4e-4b7f-9c1d-2e3f4a5b6c7d';
const _pubkey =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _uuidParse =
    'UUID parsing failed: invalid character: expected an optional prefix of '
    '`urn:uuid:` followed by [0-9a-fA-F-], found `ü` at 1';

const kdfCaptures = <KdfCapture>[
  KdfCapture(
    name: 'an unknown swap',
    request: {
      'method': 'my_swap_status',
      'params': {'uuid': _uuid},
    },
    status: 500,
    native:
        '{"error":"rpc:198] RPC call failed: lp_swap:1155] '
        'No swap with uuid $_uuid"}',
    web: {
      'error':
          'rpc:157] rpc:198] RPC call failed: lp_swap:1155] '
          'No swap with uuid $_uuid',
    },
  ),
  KdfCapture(
    name: 'an unknown order',
    request: {'method': 'order_status', 'uuid': _uuid},
    status: 500,
    native:
        '{"error":"rpc:198] RPC call failed: lp_ordermatch:5805] '
        'my_orders_storage:319] Order with uuid $_uuid is not found"}',
    web: {
      'error':
          'rpc:157] rpc:198] RPC call failed: lp_ordermatch:5805] '
          'my_orders_storage:555] Order with uuid $_uuid is not found',
    },
  ),
  KdfCapture(
    name: 'a cancellation of an unknown order',
    request: {'method': 'cancel_order', 'uuid': _uuid},
    status: 404,
    native: '{"error":"Order with uuid $_uuid is not found"}',
    web: {'error': 'Order with uuid $_uuid is not found'},
  ),
  KdfCapture(
    name: 'a legacy error quoting non-ASCII input',
    request: {
      'method': 'my_swap_status',
      'params': {'uuid': 'ünïcødé'},
    },
    status: 500,
    native: '{"error":"rpc:198] RPC call failed: lp_swap:1118] $_uuidParse"}',
    web: {
      'error':
          'rpc:157] rpc:198] RPC call failed: lp_swap:1118] '
          '$_uuidParse',
    },
  ),
  KdfCapture(
    name: 'a typed error',
    request: {
      'mmrpc': '2.0',
      'method': 'task::routed_swap::status',
      'params': {'task_id': 987654, 'forget_if_finished': false},
    },
    status: 400,
    native:
        // ignore: missing_whitespace_between_adjacent_strings
        '''{"mmrpc":"2.0","error":"No such task '987654'",'''
        '"error_path":"swap_task","error_trace":"swap_task:1952]",'
        '"error_type":"NoSuchTask","error_data":987654,"id":null}',
    web: {
      'mmrpc': '2.0',
      'error': "No such task '987654'",
      'error_path': 'swap_task',
      'error_trace': 'swap_task:1952]',
      'error_type': 'NoSuchTask',
      'error_data': 987654,
      'id': null,
    },
  ),
  KdfCapture(
    name: 'a result quoting non-ASCII input',
    request: {'method': 'list_banned_pubkeys'},
    status: 200,
    native:
        '{"result":{"$_pubkey":'
        '{"type":"Manual","reason":"scratch ünïcødé reason"}}}',
    web: {
      'result': {
        _pubkey: {'type': 'Manual', 'reason': 'scratch ünïcødé reason'},
      },
    },
  ),
];
