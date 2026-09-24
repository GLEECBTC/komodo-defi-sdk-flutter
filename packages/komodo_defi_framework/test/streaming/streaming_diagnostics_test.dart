import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/streaming/event_streaming_platform_io.dart';
import 'package:komodo_defi_framework/src/streaming/event_streaming_service.dart';
import 'package:komodo_defi_framework/src/streaming/events/kdf_event.dart';

void main() {
  test(
    'stream diagnostics omit payloads while preserving event delivery',
    () async {
      const secret = 'synthetic-private-stream-data';
      final logs = await _captureLogs(() async {
        final server = await _EventServer.start();
        final service = KdfEventStreamingService(hostConfig: server.config);
        try {
          final received = service.events.take(6).toList();
          service.connectIfNeeded();
          await service.firstByteReceived.timeout(const Duration(seconds: 2));

          // Decoder errors can include the input in their exception message.
          server.response!.write('data: $secret invalid JSON\n\n');
          server
            ..send({
              '_type': secret,
              'message': {'mnemonic': secret},
            })
            ..send({
              '_type': 'ERROR:GASLESS_TRACE:TRX',
              'message': {'coin': 'TRX', 'trace_id': secret, 'error': secret},
            })
            // Parser errors can include untrusted field names.
            ..send({
              '_type': 'ERROR:GASLESS_TRACE:TRX',
              'message': {
                'coin': 'TRX',
                'trace_id': secret,
                'error': secret,
                secret: secret,
              },
            })
            ..send({
              '_type': 'BALANCE:TRX',
              'message': [
                {
                  'ticker': secret,
                  'balance': {'spendable': '7', 'unspendable': '0'},
                },
                {
                  'ticker': 'TRX',
                  'balance': {'spendable': '3', 'unspendable': '0'},
                },
              ],
            })
            ..send({
              '_type': 'TASK:1',
              'message': {
                'result': {'private_key': secret},
              },
            })
            ..send({
              '_type': 'SHUTDOWN_SIGNAL',
              'message': {'message': secret},
            });
          await server.response!.flush();

          final events = await received.timeout(const Duration(seconds: 2));
          final unknown = events[0] as UnknownEvent;
          expect(unknown.typeString, secret);
          expect(unknown.rawData, {'mnemonic': secret});
          final traceError = events[1] as GaslessTraceErrorEvent;
          expect(traceError.traceId, secret);
          expect(traceError.error, secret);
          expect((events[2] as BalanceEvent).coin, secret);
          expect((events[2] as BalanceEvent).balance.spendable.toString(), '7');
          expect((events[3] as BalanceEvent).coin, 'TRX');
          expect((events[4] as TaskEvent).taskData, {
            'result': {'private_key': secret},
          });
          expect((events[5] as ShutdownSignalEvent).signalName, secret);
        } finally {
          await service.dispose();
          await server.close();
        }
      });

      expect(logs.join('\n'), isNot(contains(secret)));
      expect(logs, contains('[EventStream] Received UNKNOWN'));
      expect(logs, contains('[EventStream] Received ERROR:GASLESS_TRACE'));
      expect(logs, contains('[EventStream] Received BALANCE'));
      expect(logs, contains('Failed to parse stream event'));
    },
  );

  test(
    'native diagnostics omit endpoints and never stringify callback errors',
    () async {
      final callbackError = _UntrustedError();
      final logs = await _captureLogs(() async {
        final server = await _EventServer.start();
        final ready = Completer<void>();
        final delivered = Completer<void>();
        final disconnected = Completer<void>();
        final unsubscribe = connectEventStream(
          hostConfig: server.config,
          clientId: 87654321,
          onFirstByte: ready.complete,
          onMessage: (data) {
            expect(data, {'private_key': 'synthetic-private-stream-data'});
            delivered.complete();
            throw callbackError;
          },
          onDisconnected: ({required registrationsMayPersist}) {
            disconnected.complete();
            throw callbackError;
          },
        );
        try {
          await ready.future.timeout(const Duration(seconds: 2));
          server.send({'private_key': 'synthetic-private-stream-data'});
          await server.response!.flush();
          await delivered.future.timeout(const Duration(seconds: 2));
          await server.response!.close();
          await disconnected.future.timeout(const Duration(seconds: 2));
        } finally {
          await unsubscribe();
          await server.close();
        }
      });

      expect(callbackError.stringifyCount, 0);
      expect(logs.join('\n'), isNot(contains('synthetic-private-stream-data')));
      expect(logs.join('\n'), isNot(contains('127.0.0.1')));
      expect(logs.join('\n'), isNot(contains('87654321')));
      expect(logs.join('\n'), isNot(contains('event-stream?id')));
      expect(logs.join('\n'), contains('Event processing failed'));
      expect(logs.join('\n'), contains('disconnect callback failed'));
    },
  );

  for (final validStream in [false, true]) {
    test(
      'native handshake omits response header contents ($validStream)',
      () async {
        final logs = await _captureLogs(() async {
          final server = await _EventServer.start(
            contentType: ContentType(
              'text',
              validStream ? 'event-stream' : 'plain',
              parameters: {'private-key': 'synthetic-private-stream-data'},
            ),
          );
          final result = Completer<void>();
          final unsubscribe = connectEventStream(
            hostConfig: server.config,
            onFirstByte: result.complete,
            onMessage: (_) {},
            onDisconnected: ({required registrationsMayPersist}) {
              if (!result.isCompleted) result.complete();
            },
          );
          try {
            // A rejected handshake drains the body before disconnecting.
            if (!validStream) {
              await server.opened.future.timeout(const Duration(seconds: 2));
              await server.response!.close();
            }
            await result.future.timeout(const Duration(seconds: 2));
          } finally {
            await unsubscribe();
            await server.close();
          }
        });
        expect(
          logs.join('\n'),
          isNot(contains('synthetic-private-stream-data')),
        );
        expect(logs.join('\n'), isNot(contains('private-key')));
      },
    );
  }
}

Future<List<String>> _captureLogs(Future<void> Function() body) async {
  final logs = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, message) => logs.add(message),
    ),
  );
  return logs;
}

class _UntrustedError extends Error {
  int stringifyCount = 0;

  @override
  String toString() {
    stringifyCount++;
    return 'synthetic-private-stream-data';
  }
}

class _EventServer {
  _EventServer(this.server);

  final HttpServer server;
  final Completer<void> opened = Completer<void>();
  late final StreamSubscription<HttpRequest> subscription;
  HttpResponse? response;

  RemoteConfig get config => RemoteConfig(
    ipAddress: InternetAddress.loopbackIPv4.address,
    port: server.port,
    rpcPassword: 'synthetic-private-stream-data',
    https: false,
  );

  static Future<_EventServer> start({ContentType? contentType}) async {
    final server = _EventServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server.subscription = server.server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'POST') {
        await request.response.close();
        return;
      }
      server.response = request.response
        // Send every event immediately while keeping the stream open.
        ..bufferOutput = false
        ..headers.contentType =
            contentType ?? ContentType('text', 'event-stream')
        ..write(':ok\n\n');
      await request.response.flush();
      server.opened.complete();
    });
    return server;
  }

  void send(Map<String, Object?> data) {
    response!.write('data: ${jsonEncode(data)}\n\n');
  }

  Future<void> close() async {
    await subscription.cancel();
    await server.close(force: true);
  }
}
