import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

typedef EventStreamUnsubscribe = Future<void> Function();

// Default client ID used for SSE connections
const int _kDefaultClientId = 0;

Uri _buildEventsUrl(
  IKdfHostConfig hostConfig, {
  int clientId = _kDefaultClientId,
}) {
  if (hostConfig is RemoteConfig) {
    final Uri base = hostConfig.rpcUrl;
    return base.replace(
      pathSegments: <String>[...base.pathSegments, 'event-stream'],
      queryParameters: {'id': clientId.toString()},
    );
  }

  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: 7783,
    pathSegments: const ['event-stream'],
    queryParameters: {'id': clientId.toString()},
  );
}

/// Production-visible logger that always logs (not behind kDebugMode)
void _log(String msg) {
  // Production-visible logging - always print for critical SSE lifecycle events
  print('[EventStream][IO] $msg');
}

/// Performs a preflight RPC check to ensure KDF is ready before SSE connection
Future<bool> _preflightCheck(IKdfHostConfig cfg) async {
  try {
    _log('Preflight: Checking KDF availability...');
    final client = HttpClient();
    try {
      final uri = cfg is RemoteConfig
          ? cfg.rpcUrl
          : Uri(scheme: 'http', host: '127.0.0.1', port: 7783);

      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');

      // Simple version check to verify KDF is responding
      final payload = jsonEncode({
        'userpass': cfg.rpcPassword,
        'method': 'version',
      });
      request.write(payload);

      final response = await request.close().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _log('Preflight: Timeout waiting for KDF response');
          throw TimeoutException('KDF version check timeout');
        },
      );

      if (response.statusCode == 200) {
        _log('Preflight: KDF is ready (status ${response.statusCode})');
        await response.drain<void>();
        return true;
      } else {
        _log('Preflight: KDF returned status ${response.statusCode}');
        await response.drain<void>();
        return false;
      }
    } finally {
      client.close();
    }
  } catch (e) {
    _log('Preflight: Failed - $e');
    return false;
  }
}

/// Verifies SSE handshake by checking HTTP status and content-type
Future<bool> _verifyHandshake(HttpClientResponse response) async {
  if (response.statusCode != 200) {
    _log('Handshake: Failed - HTTP ${response.statusCode}');
    return false;
  }

  final contentType = response.headers.contentType?.toString() ?? '';
  if (!contentType.contains('text/event-stream')) {
    _log('Handshake: Failed - Invalid content-type: $contentType');
    return false;
  }

  _log('Handshake: Success - HTTP 200, content-type: $contentType');
  return true;
}

EventStreamUnsubscribe connectEventStream({
  required void Function(Object? data) onMessage,
  required void Function() onFirstByte,
  required void Function({required bool registrationsMayPersist})
  onDisconnected,
  IKdfHostConfig? hostConfig,
  int clientId = _kDefaultClientId,
}) {
  final IKdfHostConfig cfg = hostConfig!;
  final Uri url = _buildEventsUrl(cfg, clientId: clientId);
  bool isClosed = false;
  bool unexpectedDisconnectNotified = false;
  HttpClient? httpClient;
  HttpClientRequest? request;
  StreamSubscription<String>? streamSubscription;
  Future<void>? cleanupFuture;

  _log('SSE Start: Initializing connection to $url (client_id=$clientId)');

  Future<void> cleanup() => cleanupFuture ??= () async {
    request?.abort();
    await streamSubscription?.cancel();
    httpClient?.close(force: true);
  }();

  void notifyUnexpectedDisconnect(String reason) {
    if (isClosed || unexpectedDisconnectNotified) return;
    unexpectedDisconnectNotified = true;
    _log(reason);
    // A native SSE close drops KDF's client-scoped stream registrations.
    // Notify before cleanup/reconnect so the SDK invalidates its generation
    // and never submits against a stale streamer.
    try {
      onDisconnected(registrationsMayPersist: false);
    } catch (error) {
      _log('SSE disconnect callback failed: $error');
    }
    unawaited(cleanup());
  }

  Future<void> start() async {
    if (isClosed) return;

    try {
      // Step 1: Preflight RPC check
      final preflightOk = await _preflightCheck(cfg);
      if (isClosed) return;
      if (!preflightOk) {
        notifyUnexpectedDisconnect('SSE Start: Preflight check failed');
        return;
      }

      // Step 2: Open SSE connection with proper handshake verification
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      if (isClosed) {
        client.close(force: true);
        return;
      }
      httpClient = client;

      _log('SSE Start: Opening connection to $url...');
      final pendingRequest = await client.getUrl(url);
      if (isClosed) {
        pendingRequest.abort();
        client.close(force: true);
        return;
      }
      request = pendingRequest
        ..headers.set('Accept', 'text/event-stream')
        ..headers.set('Cache-Control', 'no-cache')
        ..headers.set('Connection', 'keep-alive');

      final response = await pendingRequest.close();
      if (isClosed) {
        client.close(force: true);
        return;
      }

      // Step 3: Verify handshake
      final handshakeOk = await _verifyHandshake(response);
      if (isClosed) {
        client.close(force: true);
        return;
      }
      if (!handshakeOk) {
        await response.drain<void>();
        if (isClosed) return;
        notifyUnexpectedDisconnect('SSE Start: Handshake verification failed');
        return;
      }

      // Step 4: Connection established, start listening to events
      _log(
        'SSE Connected: Successfully connected to $url (client_id=$clientId)',
      );
      // HTTP 200 + text/event-stream means KDF has registered this client.
      // Waiting for an application event deadlocks a clean runtime because no
      // streamer can emit until its enable RPC is sent.
      onFirstByte();
      _log('SSE Connected: KDF client registration is ready');

      // Parse SSE stream
      final StringBuffer buffer = StringBuffer();
      streamSubscription = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (isClosed) return;

              if (line.startsWith('data: ')) {
                final data = line.substring(6).trim();
                if (data.isNotEmpty) {
                  try {
                    final decoded = jsonFromString(data);
                    onMessage(decoded);
                  } catch (e) {
                    _log('SSE Data: Failed to decode event - $e');
                  }
                }
              } else if (line.isEmpty && buffer.isNotEmpty) {
                // Empty line marks end of event
                buffer.clear();
              }
            },
            onError: (Object error) {
              notifyUnexpectedDisconnect('SSE Error: $error');
            },
            onDone: () {
              notifyUnexpectedDisconnect(
                'SSE Done: Connection closed by server',
              );
            },
            cancelOnError: false,
          );
    } catch (e) {
      if (isClosed) return;
      notifyUnexpectedDisconnect('SSE Start: Exception - $e');
    }
  }

  // Start connection asynchronously
  unawaited(start());

  return () async {
    if (isClosed) return;
    isClosed = true;
    _log('SSE Disconnect: Closing connection (client_id=$clientId)');
    try {
      await cleanup();
    } catch (e) {
      _log('SSE Disconnect: Error during cleanup - $e');
    }
  };
}
