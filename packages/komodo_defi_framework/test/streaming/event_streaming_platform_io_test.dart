import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/streaming/event_streaming_platform_io.dart';

void main() {
  group('native event-stream transport', () {
    test('disconnect during preflight prevents GET and a clean connection '
        'becomes ready at the SSE handshake', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final firstPreflight = Completer<void>();
      final releaseFirstPreflight = Completer<void>();
      var preflightCount = 0;
      var eventStreamGets = 0;
      HttpResponse? liveEventStream;

      final serverSubscription = server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'POST') {
          preflightCount++;
          if (preflightCount == 1) {
            firstPreflight.complete();
            await releaseFirstPreflight.future;
          }
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        if (request.method == 'GET' && request.uri.path == '/event-stream') {
          eventStreamGets++;
          liveEventStream = request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            // dart:io holds the response headers back until something is
            // written, so a bodyless flush() never puts them on the wire and
            // the client waits on a handshake that never arrives. A real SSE
            // server opens the stream immediately; emit the conventional
            // no-op comment to do the same. The client ignores comments, so
            // `messages` stays empty.
            ..write(':ok\n\n');
          await request.response.flush();
        }
      });
      final config = RemoteConfig(
        ipAddress: InternetAddress.loopbackIPv4.address,
        port: server.port,
        rpcPassword: 'test-password',
        https: false,
      );

      final firstDisconnects = <bool>[];
      final unsubscribeFirst = connectEventStream(
        hostConfig: config,
        onMessage: (_) {},
        onFirstByte: () {
          fail('A cancelled preflight must not reach SSE readiness');
        },
        onDisconnected: ({required registrationsMayPersist}) {
          firstDisconnects.add(registrationsMayPersist);
        },
      );

      await firstPreflight.future.timeout(const Duration(seconds: 2));
      await unsubscribeFirst();
      releaseFirstPreflight.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(eventStreamGets, 0);
      expect(firstDisconnects, isEmpty);

      final ready = Completer<void>();
      final messages = <Object?>[];
      final unsubscribeSecond = connectEventStream(
        hostConfig: config,
        onMessage: messages.add,
        onFirstByte: ready.complete,
        onDisconnected: ({required registrationsMayPersist}) {},
      );

      await ready.future.timeout(const Duration(seconds: 2));
      expect(eventStreamGets, 1);
      expect(messages, isEmpty);

      await unsubscribeSecond();
      await liveEventStream?.close();
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    test('remote SSE close reports one unexpected native disconnect', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final ready = Completer<void>();
      final disconnected = Completer<bool>();
      var disconnectCount = 0;

      final serverSubscription = server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'POST') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream');
        await request.response.flush();
        await request.response.close();
      });
      final config = RemoteConfig(
        ipAddress: InternetAddress.loopbackIPv4.address,
        port: server.port,
        rpcPassword: 'test-password',
        https: false,
      );

      final unsubscribe = connectEventStream(
        hostConfig: config,
        onMessage: (_) {},
        onFirstByte: ready.complete,
        onDisconnected: ({required registrationsMayPersist}) {
          disconnectCount++;
          if (!disconnected.isCompleted) {
            disconnected.complete(registrationsMayPersist);
          }
        },
      );

      await ready.future.timeout(const Duration(seconds: 2));
      expect(
        await disconnected.future.timeout(const Duration(seconds: 2)),
        isFalse,
      );
      expect(disconnectCount, 1);

      await unsubscribe();
      await Future<void>.delayed(Duration.zero);
      expect(disconnectCount, 1);

      await serverSubscription.cancel();
      await server.close(force: true);
    });
  });
}
