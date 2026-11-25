import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/operations/electrum/native_wss_electrum_routing.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

const _wss1 = {
  'url': 'a.example:30001',
  'ws_url': 'a.example:30001',
  'protocol': 'WSS',
  'disable_cert_verification': false,
};
const _ssl1 = {
  'url': 'a.example:20001',
  'protocol': 'SSL',
  'disable_cert_verification': false,
};
const _wss2 = {
  'url': 'b.example:30001',
  'ws_url': 'b.example:30001',
  'protocol': 'WSS',
  'disable_cert_verification': false,
};

/// Bridges every WSS entry to a numbered local port and records each request.
final class _FakeRouting implements NativeWssElectrumRouting {
  final List<JsonMap> asked = [];
  bool closed = false;

  @override
  Future<JsonMap?> replacementFor(JsonMap wssServer) async {
    asked.add(wssServer);
    return {'url': '127.0.0.1:${9000 + asked.length}', 'protocol': 'TCP'};
  }

  @override
  Future<void> close() async => closed = true;
}

JsonMap _enableUtxo(List<Object> servers) => {
  'mmrpc': '2.0',
  'method': 'task::enable_utxo::init',
  'params': {
    'ticker': 'KMD',
    'activation_params': {
      'mode': {
        'rpc': 'Electrum',
        'rpc_data': {'servers': servers, 'max_connected': 1},
      },
      'tx_history': true,
    },
  },
};

List<dynamic> _servers(JsonMap request) =>
    ((((request['params'] as JsonMap)['activation_params'] as JsonMap)['mode']
                as JsonMap)['rpc_data']
            as JsonMap)['servers']
        as List<dynamic>;

void main() {
  test('returns the same request when it has no WSS servers', () async {
    final request = _enableUtxo([_ssl1]);
    final routing = _FakeRouting();

    final routed = await routeWssElectrumServers(request, routing);

    expect(identical(routed, request), isTrue);
    expect(routing.asked, isEmpty);
  });

  test('replaces WSS servers in place and keeps the rest in order', () async {
    final request = _enableUtxo([_wss1, _wss2, _ssl1]);
    final routing = _FakeRouting();

    final routed = await routeWssElectrumServers(request, routing);

    expect(_servers(routed), [
      {'url': '127.0.0.1:9001', 'protocol': 'TCP'},
      {'url': '127.0.0.1:9002', 'protocol': 'TCP'},
      _ssl1,
    ]);
    expect(routing.asked.map((s) => s['url']), [_wss1['url'], _wss2['url']]);
    expect(_servers(request), [
      _wss1,
      _wss2,
      _ssl1,
    ], reason: "the caller's request must not be mutated");
  });

  test('drops WSS servers when the routing has no replacement', () async {
    final routed = await routeWssElectrumServers(
      _enableUtxo([_wss1, _ssl1, _wss2]),
      const DropWssElectrumRouting(),
    );

    expect(_servers(routed), [_ssl1]);
  });

  test('routes ZHTLC light-mode electrum_servers', () async {
    final routed = await routeWssElectrumServers({
      'method': 'task::enable_z_coin::init',
      'params': {
        'activation_params': {
          'mode': {
            'rpc': 'Light',
            'rpc_data': {
              'electrum_servers': [_wss1],
              'light_wallet_d_servers': ['https://lightd.example:443'],
            },
          },
        },
      },
    }, _FakeRouting());

    final rpcData =
        (((routed['params'] as JsonMap)['activation_params'] as JsonMap)['mode']
                as JsonMap)['rpc_data']
            as JsonMap;
    expect(rpcData['electrum_servers'], [
      {'url': '127.0.0.1:9001', 'protocol': 'TCP'},
    ]);
    expect(rpcData['light_wallet_d_servers'], ['https://lightd.example:443']);
  });

  test("routes the legacy electrum method's top-level servers", () async {
    final routed = await routeWssElectrumServers({
      'method': 'electrum',
      'coin': 'KMD',
      'servers': [_ssl1, _wss1],
    }, _FakeRouting());

    expect(routed['servers'], [
      _ssl1,
      {'url': '127.0.0.1:9001', 'protocol': 'TCP'},
    ]);
  });

  test('leaves WSS-looking entries outside server lists alone', () async {
    final request = <String, dynamic>{
      'method': 'enable_eth_with_tokens',
      'params': {
        'nodes': [
          {'url': 'wss://evm.example', 'protocol': 'WSS'},
        ],
      },
    };

    final routed = await routeWssElectrumServers(request, _FakeRouting());

    expect(identical(routed, request), isTrue);
  });

  test('matches the protocol case-insensitively', () async {
    final routed = await routeWssElectrumServers(
      _enableUtxo([
        {'url': 'a.example:30001', 'protocol': 'wss'},
      ]),
      const DropWssElectrumRouting(),
    );

    expect(_servers(routed), isEmpty);
  });
}
