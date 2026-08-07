import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

/// `ws_url` reaches KDF as a second node entry, or it does not reach it at all.
///
/// KDF has no `ws_url` field: `EthNode` is `{url, komodo_proxy}` and, with no
/// `deny_unknown_fields`, an extra key is silently dropped
/// (`mm2src/coins/eth/v2_activation.rs:261-266`). Transport choice is scheme
/// sniffing on `url` (`:1269-1275`). So the only way to reach a ws endpoint is
/// to give it its own entry with the `wss://` URL in `url` - and the only way
/// to find out that we failed to is a test, because the failure mode is silent
/// on both sides.
///
/// The web/native split is a compile-time `const`, so these tests assert the
/// behaviour of *this* build. Under `dart test` that is the native branch.
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

JsonMap _ethConfig(List<JsonMap> nodes) => {
  'coin': 'GLEEC',
  'nodes': nodes,
  'swap_contract_address': '0x0000000000000000000000000000000000000001',
  'fallback_swap_contract': '0x0000000000000000000000000000000000000002',
};

JsonMap _erc20Config(List<JsonMap> nodes) => {
  'coin': 'USDT-GRC20',
  'nodes': nodes,
  'swap_contract_address': '0x0000000000000000000000000000000000000001',
  'fallback_swap_contract': '0x0000000000000000000000000000000000000002',
};

List<String> _urlsOf(Map<String, dynamic> params) => (params['nodes'] as List)
    .cast<Map<String, dynamic>>()
    .map((node) => node['url'] as String)
    .toList();

void main() {
  group('EvmNode parses ws_url', () {
    test('fromJson reads ws_url alongside url', () {
      final node = EvmNode.fromJson({
        'url': 'https://evm-rpc.gleec.com',
        'ws_url': 'wss://evm-ws.gleec.com',
      });

      expect(node.url, 'https://evm-rpc.gleec.com');
      expect(node.wsUrl, 'wss://evm-ws.gleec.com');
    });

    test('a node without ws_url keeps a null wsUrl', () {
      final node = EvmNode.fromJson({'url': 'https://evm-rpc.gleec.com'});
      expect(node.wsUrl, isNull);
    });

    test('toJson still emits only the keys KDF declares', () {
      final node = EvmNode(
        url: 'https://evm-rpc.gleec.com',
        wsUrl: 'wss://evm-ws.gleec.com',
      );

      // ws_url must NOT ride along inside a node object: KDF would discard it
      // silently, which reads at a glance like the endpoint is being used.
      expect(node.toJson(), {
        'url': 'https://evm-rpc.gleec.com',
        'komodo_proxy': false,
      });
    });
  });

  group('EvmNode.toRpcNodeList expansion', () {
    test('a node carrying ws_url becomes two entries, https first', () {
      final expanded = EvmNode.toRpcNodeList([
        EvmNode(
          url: 'https://evm-rpc.gleec.com',
          wsUrl: 'wss://evm-ws.gleec.com',
        ),
      ]);

      if (_isWeb) {
        expect(expanded, hasLength(2));
        expect(expanded.first['url'], 'https://evm-rpc.gleec.com');
        expect(expanded.last['url'], 'wss://evm-ws.gleec.com');
      } else {
        // Native is deliberately HTTP-only for now; see _kSendWsNodesOnNative.
        expect(expanded, hasLength(1));
        expect(expanded.single['url'], 'https://evm-rpc.gleec.com');
      }
    });

    test('the https entry is never dropped, whatever the ws verdict', () {
      final nodes = [
        // usable everywhere
        EvmNode(
          url: 'https://evm-rpc.gleec.com',
          wsUrl: 'wss://evm-ws.gleec.com',
        ),
        // probed dead on 2026-08-07
        EvmNode(
          url: 'https://polygon.gateway.tenderly.co',
          wsUrl: 'wss://polygon.gateway.tenderly.co',
        ),
        // refuses any Origin header, so web-unusable / native-fine
        EvmNode(
          url: 'https://rpc.energyweb.org',
          wsUrl: 'wss://rpc.energyweb.org/ws',
        ),
        // no ws endpoint published at all
        EvmNode(url: 'https://eth1.cipig.net:18555'),
      ];

      final urls = EvmNode.toRpcNodeList(nodes)
          .map((node) => node['url'] as String)
          .toList();

      // This is the property that matters most. GLEEC, EWT, GLMR, MATIC and
      // MOVR have no http-only node, so a bug that substituted rather than
      // added would leave them with no HTTP fallback at all.
      expect(urls, containsAll(nodes.map((node) => node.url)));
    });

    test('a probed-dead endpoint is never sent', () {
      final expanded = EvmNode.toRpcNodeList([
        EvmNode(
          url: 'https://polygon.gateway.tenderly.co',
          wsUrl: 'wss://polygon.gateway.tenderly.co',
        ),
      ]);

      // 404 on 2026-08-07 with and without Origin. Leaving it in costs a real
      // activation up to 10s on KDF's TRY_RPC_NODE_TIMEOUT_S and buys nothing.
      expect(
        expanded.map((node) => node['url']),
        isNot(contains('wss://polygon.gateway.tenderly.co')),
      );
      expect(expanded.single['url'], 'https://polygon.gateway.tenderly.co');
    });

    test('an Origin-refusing endpoint is excluded on web only', () {
      final expanded = EvmNode.toRpcNodeList([
        EvmNode(
          url: 'https://rpc.energyweb.org',
          wsUrl: 'wss://rpc.energyweb.org/ws',
        ),
      ]);
      final urls = expanded.map((node) => node['url']).toList();

      // Browsers always stamp Origin and this endpoint answers 403 to it, so
      // it must never be offered on web. Native sends no Origin and gets 101.
      expect(urls, isNot(contains('wss://rpc.energyweb.org/ws')));
    });

    test('komodo_proxy carries onto the ws entry', () {
      final expanded = EvmNode.toRpcNodeList([
        EvmNode(
          url: 'https://proxied.example',
          wsUrl: 'wss://proxied.example',
          komodoProxy: true,
        ),
      ]);

      for (final node in expanded) {
        expect(node['komodo_proxy'], isTrue);
      }
    });

    test('an empty ws_url is treated as absent', () {
      final expanded = EvmNode.toRpcNodeList([
        EvmNode(url: 'https://evm-rpc.gleec.com', wsUrl: ''),
      ]);
      expect(expanded, hasLength(1));
    });
  });

  // The expansion exists for web, but `dart test` runs on the VM, so every
  // assertion above only ever exercises the native branch. These reach the web
  // branch by passing the platform in explicitly.
  group('shipping policy, both platforms', () {
    const healthy = 'wss://evm-ws.gleec.com';
    const dead = 'wss://polygon.gateway.tenderly.co';
    const originRefusing = 'wss://rpc.energyweb.org/ws';

    test('web ships a healthy endpoint', () {
      expect(
        EvmNode.shippableWsUrlFor(healthy, isWeb: true),
        healthy,
        reason: 'this is the entire point of the change',
      );
    });

    test('web refuses the Origin-refusing endpoint, native keeps it', () {
      expect(EvmNode.shippableWsUrlFor(originRefusing, isWeb: true), isNull);
      // Native's answer is gated by _kSendWsNodesOnNative, but it must never
      // be excluded for the *Origin* reason - that reason does not apply there.
      expect(
        EvmNode.shippableWsUrlFor(originRefusing, isWeb: false),
        EvmNode.shippableWsUrlFor(healthy, isWeb: false),
        reason: 'on native an Origin-refusing endpoint is as usable as any '
            'other; only the native rollout flag may exclude it',
      );
    });

    test('a dead endpoint is refused on both platforms', () {
      expect(EvmNode.shippableWsUrlFor(dead, isWeb: true), isNull);
      expect(EvmNode.shippableWsUrlFor(dead, isWeb: false), isNull);
    });

    test('null and empty are refused on both platforms', () {
      for (final isWeb in [true, false]) {
        expect(EvmNode.shippableWsUrlFor(null, isWeb: isWeb), isNull);
        expect(EvmNode.shippableWsUrlFor('', isWeb: isWeb), isNull);
      }
    });
  });

  group('activation payloads carry the expansion', () {
    test('EthWithTokensActivationParams expands its nodes', () {
      final params = EthWithTokensActivationParams.fromJson(
        _ethConfig([
          {
            'url': 'https://evm-rpc.gleec.com',
            'ws_url': 'wss://evm-ws.gleec.com',
          },
        ]),
      );

      final urls = _urlsOf(params.toRpcParams());
      expect(urls, contains('https://evm-rpc.gleec.com'));
      expect(urls, hasLength(_isWeb ? 2 : 1));
      if (_isWeb) expect(urls, contains('wss://evm-ws.gleec.com'));
    });

    test('Erc20ActivationParams expands its nodes', () {
      final params = Erc20ActivationParams.fromJsonConfig(
        _erc20Config([
          {
            'url': 'https://evm-rpc.gleec.com',
            'ws_url': 'wss://evm-ws.gleec.com',
          },
        ]),
      );

      final urls = _urlsOf(params.toRpcParams());
      expect(urls, contains('https://evm-rpc.gleec.com'));
      expect(urls, hasLength(_isWeb ? 2 : 1));
      if (_isWeb) expect(urls, contains('wss://evm-ws.gleec.com'));
    });

    test('TRON activation params are left alone', () {
      // TRON hard-rejects any non-HTTP node
      // (`mm2src/coins/eth/v2_activation.rs:1242-1251`), so it must never see
      // an expansion even if a config ever grew a ws_url for it.
      final params = TrxWithTokensActivationParams.fromJson({
        'coin': 'TRX',
        'nodes': [
          {'url': 'https://api.trongrid.io', 'ws_url': 'wss://api.trongrid.io'},
        ],
        'swap_contract_address': 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb',
        'fallback_swap_contract': 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb',
      });

      final urls = _urlsOf(params.toRpcParams());
      expect(urls, ['https://api.trongrid.io']);
    });
  });
}
