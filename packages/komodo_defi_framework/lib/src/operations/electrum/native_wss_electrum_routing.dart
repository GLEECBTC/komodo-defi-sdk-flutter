import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Decides what a native KDF receives in place of an Electrum `WSS` server.
///
/// Native KDF only dials TCP and SSL Electrum servers and rejects `WSS`
/// entries. On those ports ElectrumX 1.18+ pads every reply and, once a
/// session has received about 1 KB, holds small replies until a second has
/// passed since its last send (`PaddedRSTransport`). KDF waits for each reply
/// before its next request, so native activation and history run at about one
/// request per second. WebSocket sessions are not paced, which is why the web
/// build is several times faster on the same servers.
abstract interface class NativeWssElectrumRouting {
  /// The entry to send instead of [wssServer], or `null` to drop it.
  Future<JsonMap?> replacementFor(JsonMap wssServer);

  Future<void> close();
}

/// Drops `WSS` entries, leaving native KDF the SSL servers it has always used.
final class DropWssElectrumRouting implements NativeWssElectrumRouting {
  const DropWssElectrumRouting();

  @override
  Future<JsonMap?> replacementFor(JsonMap wssServer) async => null;

  @override
  Future<void> close() async {}
}

/// Electrum server lists in KDF requests: `rpc_data.servers` in Electrum mode,
/// `rpc_data.electrum_servers` in ZHTLC light mode, `servers` in the legacy
/// `electrum` method.
const Set<String> _electrumServerListKeys = {'servers', 'electrum_servers'};

/// Returns [request] with each `WSS` Electrum server replaced via [routing].
///
/// Only entries native KDF would reject are touched, so a request without any
/// is returned as the same instance and nothing else in it changes.
Future<JsonMap> routeWssElectrumServers(
  JsonMap request,
  NativeWssElectrumRouting routing,
) async {
  // Every RPC passes through here, status polls included; only activation
  // requests carry server lists, so skip the async walk for the rest.
  if (!_hasWssServers(request, null)) return request;
  final routed = await _route(request, routing, null);
  return routed! as JsonMap;
}

bool _hasWssServers(Object? node, String? key) => switch (node) {
  final Map<String, dynamic> map => map.entries.any(
    (entry) => _hasWssServers(entry.value, entry.key),
  ),
  final List<dynamic> list =>
    (_electrumServerListKeys.contains(key) && list.any(_isWssServer)) ||
        list.any((item) => _hasWssServers(item, null)),
  _ => false,
};

Future<Object?> _route(
  Object? node,
  NativeWssElectrumRouting routing,
  String? key,
) async {
  if (node is Map<String, dynamic>) {
    Map<String, dynamic>? copy;
    for (final entry in node.entries) {
      final routed = await _route(entry.value, routing, entry.key);
      if (!identical(routed, entry.value)) {
        (copy ??= Map<String, dynamic>.of(node))[entry.key] = routed;
      }
    }
    return copy ?? node;
  }
  if (node is List) {
    if (_electrumServerListKeys.contains(key) && node.any(_isWssServer)) {
      return _routeServerList(node, routing);
    }
    List<dynamic>? copy;
    for (var i = 0; i < node.length; i++) {
      final routed = await _route(node[i], routing, null);
      if (!identical(routed, node[i])) {
        (copy ??= List<dynamic>.of(node))[i] = routed;
      }
    }
    return copy ?? node;
  }
  return node;
}

Future<List<dynamic>> _routeServerList(
  List<dynamic> servers,
  NativeWssElectrumRouting routing,
) async {
  final routed = <dynamic>[];
  for (final server in servers) {
    if (!_isWssServer(server)) {
      routed.add(server);
      continue;
    }
    final replacement = await routing.replacementFor(
      Map<String, dynamic>.of(server as Map<String, dynamic>),
    );
    if (replacement != null) routed.add(replacement);
  }
  return routed;
}

bool _isWssServer(Object? server) =>
    server is Map<String, dynamic> &&
    '${server['protocol']}'.toUpperCase() == 'WSS';
