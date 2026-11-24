import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:komodo_defi_framework/src/operations/electrum/native_wss_electrum_routing.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Lets a native KDF reach `WSS` Electrum servers through loopback TCP.
///
/// Each upstream gets one listener on 127.0.0.1, bound on first use, and each
/// KDF connection to it gets its own upstream WebSocket, so per-session server
/// state such as subscriptions stays one-to-one. KDF writes one JSON message
/// per line and the WebSocket side carries one per frame.
///
/// The WebSocket client verifies the server certificate, so the only plaintext
/// hop is loopback, as for KDF's own RPC port. Entries that ask to skip
/// certificate verification are left to KDF's SSL fallback instead.
final class ElectrumWebSocketBridge implements NativeWssElectrumRouting {
  ElectrumWebSocketBridge({
    Future<WebSocket> Function(Uri upstream)? connect,
    this.connectTimeout = const Duration(seconds: 20),
    void Function(String message)? log,
  }) : _connect = connect ?? _connectWebSocket,
       _log = log ?? _ignoreLog;

  /// Matches KDF's own connection-establishment budget for an Electrum server.
  final Duration connectTimeout;

  final Future<WebSocket> Function(Uri upstream) _connect;
  final void Function(String message) _log;
  final Map<String, Future<ServerSocket>> _listeners = {};
  final Set<_ElectrumRelay> _relays = {};
  bool _closed = false;

  @override
  Future<JsonMap?> replacementFor(JsonMap wssServer) async {
    if (_closed || wssServer['disable_cert_verification'] == true) return null;
    final upstream = upstreamOf(wssServer);
    if (upstream == null) return null;

    final key = upstream.toString();
    final listener = _listeners[key] ??= _listen(upstream);
    try {
      final server = await listener;
      return {
        'url': '${server.address.address}:${server.port}',
        'protocol': 'TCP',
        'disable_cert_verification': false,
      };
    } on SocketException catch (error) {
      _listeners.removeWhere((_, pending) => identical(pending, listener));
      _log('Electrum bridge could not listen for ${upstream.host}: $error');
      return null;
    }
  }

  /// The `wss://` URI a `WSS` entry points at, or `null` if it has none.
  ///
  /// Coin configs carry WSS endpoints without a scheme (`host:port`), the form
  /// the browser build of KDF expects.
  static Uri? upstreamOf(JsonMap server) {
    final raw = server['ws_url'] ?? server['url'];
    if (raw is! String || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'wss://$raw');
    if (uri == null || uri.scheme != 'wss' || uri.host.isEmpty) return null;
    return uri;
  }

  @override
  Future<void> close() async {
    _closed = true;
    final listeners = _listeners.values.toList();
    _listeners.clear();
    for (final listener in listeners) {
      try {
        await (await listener).close();
      } on SocketException {
        // A listener that never bound has nothing to close.
      }
    }
    await Future.wait(_relays.toList().map((relay) => relay.close()));
  }

  Future<ServerSocket> _listen(Uri upstream) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (local) => unawaited(_accept(local, upstream)),
      onError: (Object error) => _log(
        'Electrum bridge stopped accepting for ${upstream.host}: '
        '$error',
      ),
    );
    return server;
  }

  Future<void> _accept(Socket local, Uri upstream) async {
    try {
      local.setOption(SocketOption.tcpNoDelay, true);
    } on SocketException {
      local.destroy();
      return;
    }
    final WebSocket remote;
    try {
      remote = await _connect(upstream).timeout(connectTimeout);
    } on Object catch (error) {
      // KDF sees the local socket close and fails over to its next server.
      _log('Electrum bridge could not reach ${upstream.host}: $error');
      local.destroy();
      return;
    }
    if (_closed) {
      local.destroy();
      try {
        await remote.close();
      } on Object {
        // Shutting down anyway.
      }
      return;
    }
    final relay = _ElectrumRelay(local, remote)..start();
    _relays.add(relay);
    unawaited(relay.done.whenComplete(() => _relays.remove(relay)));
  }
}

final class _ElectrumRelay {
  _ElectrumRelay(this._local, this._remote);

  final Socket _local;
  final WebSocket _remote;
  final Completer<void> _done = Completer<void>();
  StreamSubscription<String>? _toRemote;
  StreamSubscription<dynamic>? _toLocal;

  Future<void> get done => _done.future;

  void start() {
    // A broken pipe on either side completes `done` with an error; handle it
    // here or it surfaces as an unhandled exception.
    for (final done in [_local.done, _remote.done]) {
      unawaited(done.then((_) => close(), onError: (Object _) => close()));
    }
    _toRemote = utf8.decoder
        .bind(_local)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!_done.isCompleted && line.trim().isNotEmpty) {
              _remote.add(line);
            }
          },
          onError: (Object _) => unawaited(close()),
          onDone: () => unawaited(close()),
          cancelOnError: true,
        );
    _toLocal = _remote.listen(
      (message) {
        if (_done.isCompleted) return;
        final text = message is String
            ? message
            : utf8.decode(message as List<int>);
        for (final line in const LineSplitter().convert(text)) {
          if (line.trim().isNotEmpty) _local.add(utf8.encode('$line\n'));
        }
      },
      onError: (Object _) => unawaited(close()),
      onDone: () => unawaited(close()),
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    if (_done.isCompleted) return;
    _done.complete();
    await _toRemote?.cancel();
    await _toLocal?.cancel();
    _local.destroy();
    try {
      await _remote.close();
    } on Object {
      // The peer may already have dropped the connection.
    }
  }
}

Future<WebSocket> _connectWebSocket(Uri upstream) =>
    WebSocket.connect(upstream.toString());

void _ignoreLog(String _) {}
