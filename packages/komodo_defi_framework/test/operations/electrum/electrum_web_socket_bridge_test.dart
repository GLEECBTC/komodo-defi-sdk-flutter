@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

const _timeout = Duration(seconds: 5);
const _kmdWss = {
  'url': 'kmd.electrum1.example:30001',
  'ws_url': 'kmd.electrum1.example:30001',
  'protocol': 'WSS',
  'disable_cert_verification': false,
};

/// Plain `ws://` stand-in for an ElectrumX WSS port: answers each request
/// frame with one reply frame, and lets a test push frames of its own.
final class _FakeElectrumWs {
  late final HttpServer _http;
  final List<String> received = [];
  final List<WebSocket> sessions = [];

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      sessions.add(ws);
      ws.listen((message) {
        final text = message as String;
        received.add(text);
        ws.add(jsonEncode(_reply(jsonDecode(text))));
      });
    });
  }

  Uri get uri => Uri.parse('ws://127.0.0.1:${_http.port}');

  Future<void> stop() async {
    for (final session in sessions) {
      await session.close();
    }
    await _http.close(force: true);
  }

  static Object _reply(Object? request) {
    if (request is List) return [for (final r in request) _reply(r)];
    final single = request! as Map;
    return {'jsonrpc': '2.0', 'id': single['id'], 'result': single['method']};
  }
}

/// What native KDF does: one JSON message per line over plain TCP.
final class _LineClient {
  _LineClient(this.socket)
    : _lines = StreamIterator(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );

  static Future<_LineClient> connect(JsonMap bridged) async {
    final address = (bridged['url'] as String).split(':');
    final socket = await Socket.connect(address[0], int.parse(address[1]));
    return _LineClient(socket);
  }

  final Socket socket;
  final StreamIterator<String> _lines;

  void send(Object message) => socket.write('${jsonEncode(message)}\n');

  Future<Object?> next() async {
    if (!await _lines.moveNext().timeout(_timeout)) {
      throw StateError('connection closed');
    }
    return jsonDecode(_lines.current);
  }

  Future<bool> isClosed() async => !await _lines.moveNext().timeout(_timeout);
}

void main() {
  late _FakeElectrumWs upstream;
  late List<Uri> dialled;
  late ElectrumWebSocketBridge bridge;

  setUp(() async {
    upstream = _FakeElectrumWs();
    await upstream.start();
    dialled = [];
    bridge = ElectrumWebSocketBridge(
      connect: (uri) {
        dialled.add(uri);
        return WebSocket.connect(upstream.uri.toString());
      },
    );
  });

  tearDown(() async {
    await bridge.close();
    await upstream.stop();
  });

  test('hands KDF a loopback TCP entry for a WSS server', () async {
    final bridged = await bridge.replacementFor(Map.of(_kmdWss));

    expect(bridged, isNotNull);
    expect(bridged!['protocol'], 'TCP');
    expect(bridged['url'], startsWith('127.0.0.1:'));
    expect(bridged.containsKey('ws_url'), isFalse);
  });

  test('relays request lines as frames and reply frames as lines', () async {
    final kdf = await _LineClient.connect(
      (await bridge.replacementFor(Map.of(_kmdWss)))!,
    );

    kdf.send({'jsonrpc': '2.0', 'id': 7, 'method': 'server.version'});

    expect(await kdf.next(), {
      'jsonrpc': '2.0',
      'id': 7,
      'result': 'server.version',
    });
    expect(upstream.received, [
      '{"jsonrpc":"2.0","id":7,"method":"server.version"}',
    ]);
    expect(dialled, [Uri.parse('wss://kmd.electrum1.example:30001')]);
  });

  test('carries a batch as one frame and its reply as one line', () async {
    final kdf = await _LineClient.connect(
      (await bridge.replacementFor(Map.of(_kmdWss)))!,
    );

    kdf.send([
      {'id': 1, 'method': 'blockchain.scripthash.get_balance'},
      {'id': 2, 'method': 'blockchain.scripthash.get_balance'},
    ]);

    expect(await kdf.next(), hasLength(2));
    expect(upstream.received, hasLength(1));
  });

  test('passes on server pushes and splits multi-line frames', () async {
    final kdf = await _LineClient.connect(
      (await bridge.replacementFor(Map.of(_kmdWss)))!,
    );
    kdf.send({'id': 1, 'method': 'blockchain.headers.subscribe'});
    await kdf.next();

    final notification = {
      'jsonrpc': '2.0',
      'method': 'blockchain.scripthash.subscribe',
      'params': ['abc', 'def'],
    };
    upstream.sessions.single.add(
      '${jsonEncode(notification)}\n${jsonEncode({'id': 9, 'result': 1})}',
    );

    expect(await kdf.next(), notification);
    expect(await kdf.next(), {'id': 9, 'result': 1});
  });

  test('gives each KDF connection its own upstream session', () async {
    final first = await bridge.replacementFor(Map.of(_kmdWss));
    final second = await bridge.replacementFor(Map.of(_kmdWss));
    expect(second, first, reason: 'one listener per upstream');

    final a = await _LineClient.connect(first!);
    final b = await _LineClient.connect(second!);
    a.send({'id': 1, 'method': 'a'});
    b.send({'id': 2, 'method': 'b'});

    expect((await a.next())! as Map, containsPair('result', 'a'));
    expect((await b.next())! as Map, containsPair('result', 'b'));
    expect(upstream.sessions, hasLength(2));
  });

  test('uses a separate listener per upstream server', () async {
    final kmd = await bridge.replacementFor(Map.of(_kmdWss));
    final btc = await bridge.replacementFor({
      ..._kmdWss,
      'url': 'btc.electrum1.example:30000',
      'ws_url': 'btc.electrum1.example:30000',
    });

    expect(btc!['url'], isNot(kmd!['url']));
  });

  test('declines entries it cannot bridge safely', () async {
    expect(
      await bridge.replacementFor({
        ..._kmdWss,
        'disable_cert_verification': true,
      }),
      isNull,
      reason: 'an entry that skips certificate checks keeps SSL fallback',
    );
    expect(
      await bridge.replacementFor({
        'url': 'ws://plain.example:30001',
        'protocol': 'WSS',
      }),
      isNull,
      reason: 'never downgrade to an unencrypted upstream',
    );
    expect(await bridge.replacementFor({'protocol': 'WSS'}), isNull);
  });

  test('prefers ws_url and keeps an explicit scheme and path', () {
    expect(
      ElectrumWebSocketBridge.upstreamOf({
        'url': 'ignored.example:1',
        'ws_url': 'wss://ws.example:443/electrum',
      }),
      Uri.parse('wss://ws.example:443/electrum'),
    );
  });

  test('closes the KDF connection when the upstream is unreachable', () async {
    final failing = ElectrumWebSocketBridge(
      connect: (_) => Future.error(const SocketException('refused')),
    );
    addTearDown(failing.close);
    final kdf = await _LineClient.connect(
      (await failing.replacementFor(Map.of(_kmdWss)))!,
    );

    expect(await kdf.isClosed(), isTrue);
  });

  test('closes the KDF connection when the upstream hangs up', () async {
    final kdf = await _LineClient.connect(
      (await bridge.replacementFor(Map.of(_kmdWss)))!,
    );
    kdf.send({'id': 1, 'method': 'server.version'});
    await kdf.next();

    await upstream.sessions.single.close();

    expect(await kdf.isClosed(), isTrue);
  });

  test('closes the upstream session when KDF disconnects', () async {
    final kdf = await _LineClient.connect(
      (await bridge.replacementFor(Map.of(_kmdWss)))!,
    );
    kdf.send({'id': 1, 'method': 'server.version'});
    await kdf.next();

    kdf.socket.destroy();

    await upstream.sessions.single.done.timeout(_timeout);
  });

  test('close stops listening and ends live relays', () async {
    final bridged = (await bridge.replacementFor(Map.of(_kmdWss)))!;
    final kdf = await _LineClient.connect(bridged);
    kdf.send({'id': 1, 'method': 'server.version'});
    await kdf.next();

    await bridge.close();

    expect(await kdf.isClosed(), isTrue);
    await expectLater(
      _LineClient.connect(bridged),
      throwsA(isA<SocketException>()),
    );
    expect(await bridge.replacementFor(Map.of(_kmdWss)), isNull);
  });
}
