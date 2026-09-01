import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// True when compiled for a browser target (dart2js or dart2wasm).
///
/// `package:flutter/foundation.dart`'s `kIsWeb` is not reachable here - this is
/// a pure Dart package with no Flutter dependency - so the same predicate
/// Flutter itself uses is spelled out. It is a `const`, so the branch it guards
/// is folded away at compile time and the unused list never ships.
const bool _kIsWeb = bool.fromEnvironment('dart.library.js_interop');

/// Whether to send `ws_url` endpoints to KDF on native builds.
///
/// **Currently web-only, deliberately.** The rollout is a measured win on web:
/// every EVM POST there carries a CORS preflight, the endpoint's 429 response
/// arrives without an `Access-Control-Allow-Origin` header and so is
/// unrecoverable, and a WebSocket replaces the whole burst with one HTTP
/// Upgrade - outside the per-request rate limiter and outside the CORS model
/// entirely. None of those three problems exists on native.
///
/// Against that, two costs land only on native, and both are unmeasured here:
///
///  * **iOS file descriptors.** `create_websocket_transport` spawns a
///    *temporary* connection loop for every ws node at activation
///    (`mm2src/coins/eth/v2_activation.rs:1301`, 20s expiry via
///    `TMP_SOCKET_CONNECTION`), so activating all 13 ws-carrying chains
///    transiently opens up to 24 extra sockets, on top of a previously measured
///    ~+12 peak against iOS's 256-per-process soft limit.
///  * **Socket lifecycle on mobile.** A long-lived socket across backgrounding
///    and network changes is a failure mode the HTTP path does not have.
///    `stop_connection_loop` fires on any transport error, and the socket is
///    `Arc`-shared by the platform coin and all its tokens, so one bad frame
///    drops it for every one of them.
///
/// To turn native on: re-run `tool/kdf_fd_probe.py` with ws nodes configured
/// and record the new peak, soak a mobile build across backgrounding and a
/// network change, then flip this to `true`. Endpoint availability is not the
/// blocker - `tool/evm_ws_probe.py` measured native as strictly better than
/// web (23/24 vs 22/24; see [_webUnusableWsEndpoints]).
///
/// Two further properties of the transport, true on both platforms, that are
/// worth knowing before anyone tunes this:
///
///  * **Keepalive is application-level and unconditional.** There is no
///    protocol ping/pong; the transport sends a `net_version` JSON-RPC every
///    10s per socket per node for the life of the session
///    (`mm2src/coins/eth/web3_transport/websocket_transport.rs:37`, `:127`).
///    So each ws node costs a steady 6 requests/minute even while idle - still
///    far below what it replaces, but not zero.
///  * **One bad frame drops every coin on that chain.** The socket is
///    `Arc`-shared by the platform coin and all its tokens
///    (`mm2src/coins/eth/v2_activation.rs:643`, `:751`) and
///    `stop_connection_loop` fires on any transport error.
const bool _kSendWsNodesOnNative = false;

/// Endpoints `tool/evm_ws_probe.py` could not use at all, and why.
///
/// Not free to leave in: KDF's `try_every_node` allots `TRY_RPC_NODE_TIMEOUT_S`
/// = 10s per node, and the ws path has no fast fail - `send_request` parks on an
/// unbounded channel while `attempt_to_establish_socket_connection` burns three
/// attempts at 1/2/4s and then returns, leaving the caller to time out.
///
/// Raw probe output: `docs/assets/evm_ws_probe/evm_ws_probe_2026-08-07.json`.
const Map<String, String> _deadWsEndpoints = {
  'wss://polygon.gateway.tenderly.co':
      '2026-08-07: HTTP 404 with and without an Origin header. The Tenderly '
      'gateway wants an access key in the path (`/ws` answers 401); the coins '
      'config carries the bare host. MATIC keeps three other ws endpoints.',
};

/// Endpoints that serve a native handshake but refuse a browser one.
///
/// The discriminator is the `Origin` header. Native KDF uses
/// `tokio_tungstenite`, which sends none; on web KDF uses
/// `tokio_tungstenite_wasm`, i.e. the browser's own `WebSocket`, and the browser
/// stamps the page's `Origin` on every handshake where Rust cannot suppress it.
///
/// These are excluded on web and kept on native. Listing them rather than
/// deleting them is the point: a single-setting probe reports these as simply
/// "dead" and would permanently strip a chain of a node that works.
const Map<String, String> _webUnusableWsEndpoints = {
  'wss://rpc.energyweb.org/ws':
      '2026-08-07: HTTP 403 to any request carrying an Origin header, HTTP 101 '
      'without one. EWT has a single node, so this is its only ws endpoint.',
};

class EvmNode {
  EvmNode({required this.url, this.wsUrl, bool? komodoProxy, bool? guiAuth})
    : komodoProxy = komodoProxy ?? guiAuth ?? false;

  factory EvmNode.fromJson(JsonMap json) {
    return EvmNode(
      url: json.value<String>('url'),
      wsUrl: json.valueOrNull<String>('ws_url'),
      komodoProxy:
          json.valueOrNull<bool>('komodo_proxy') ??
          json.valueOrNull<bool>('gui_auth') ??
          false,
    );
  }

  final String url;

  /// The WebSocket endpoint the coins config publishes alongside [url], if any.
  ///
  /// KDF has no `ws_url` field - `EthNode` is `{url, komodo_proxy}` and the key
  /// would be silently discarded (`mm2src/coins/eth/v2_activation.rs:261-266`,
  /// no `deny_unknown_fields`). Transport choice is scheme sniffing on `url`
  /// (`:1269-1275`), so a ws endpoint reaches KDF as its own node entry with
  /// the `wss://` URL in the `url` field. See [toRpcNodeList].
  final String? wsUrl;

  final bool komodoProxy;

  bool get guiAuth => komodoProxy;

  Map<String, dynamic> toJson() => {'url': url, 'komodo_proxy': komodoProxy};

  /// This node's [wsUrl] if it should be sent to KDF on this platform.
  String? get shippableWsUrl => shippableWsUrlFor(wsUrl, isWeb: _kIsWeb);

  /// The shipping policy, with the platform passed in.
  ///
  /// Split out from [shippableWsUrl] only so both branches are reachable from a
  /// VM test run. The production caller passes the compile-time constant, so
  /// this still folds away; nothing else should pass anything else.
  static String? shippableWsUrlFor(String? wsUrl, {required bool isWeb}) {
    if (wsUrl == null || wsUrl.isEmpty) return null;
    if (_deadWsEndpoints.containsKey(wsUrl)) return null;
    if (isWeb) {
      return _webUnusableWsEndpoints.containsKey(wsUrl) ? null : wsUrl;
    }
    return _kSendWsNodesOnNative ? wsUrl : null;
  }

  /// The node entry for [wsUrl], carrying the ws URL in KDF's `url` field.
  Map<String, dynamic> _toWsJson(String ws) => {
    'url': ws,
    'komodo_proxy': komodoProxy,
  };

  /// Expand [nodes] into the `nodes` array KDF receives.
  ///
  /// Each config node becomes its existing `https://` entry, **plus** a second
  /// entry for its `ws_url` when that endpoint is usable on this platform.
  ///
  /// **Always additive, never a replacement.** GLEEC, EWT, GLMR, MATIC and MOVR
  /// have no http-only node at all, so substituting rather than adding would
  /// strip those chains of HTTP entirely and leave them with no fallback.
  /// Expanding gives MATIC 4 entries -> 8 and GLEEC 1 -> 2, which is itself the
  /// fix for the single-node-no-fallback condition `web3_pool.rs:52-64` blames
  /// for the original incident.
  ///
  /// Order is `https` then `ws` per node, but that is presentational only:
  /// `build_web3_instances` shuffles the list before use
  /// (`mm2src/coins/eth/v2_activation.rs:1184-1185`) and `Web3Pool.preferred`
  /// starts at index 0 of the *shuffled* list, so which transport a chain
  /// reaches for first is not controllable from here.
  static List<Map<String, dynamic>> toRpcNodeList(Iterable<EvmNode> nodes) => [
    for (final node in nodes) ...[
      node.toJson(),
      if (node.shippableWsUrl case final String ws) node._toWsJson(ws),
    ],
  ];
}
