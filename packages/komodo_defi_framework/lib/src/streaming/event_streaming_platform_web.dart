// Web implementation: connect to SharedWorker('event_streaming_worker.js')
// and forward messages to Dart via the provided callback.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:web/web.dart' as web;

typedef EventStreamUnsubscribe = Future<void> Function();

const _eventStreamingWorkerPath =
    'assets/packages/komodo_defi_framework/assets/web/event_streaming_worker.js';
const _controlKey = '__kdf_event_stream_control';
const _healthInterval = Duration(seconds: 5);
const _healthTimeout = Duration(seconds: 12);
const _readinessProbeInterval = Duration(milliseconds: 250);

final web.EventHandlerNonNull _noopHandler = ((web.Event _) {}).toJS;

EventStreamUnsubscribe connectEventStream({
  required void Function(Object? data) onMessage,
  required void Function() onFirstByte,
  required void Function({required bool registrationsMayPersist})
  onDisconnected,
  IKdfHostConfig? hostConfig,
}) {
  web.SharedWorker? worker;
  web.MessagePort? port;
  Timer? healthTimer;
  Timer? readinessTimer;
  var isClosed = false;
  var resourcesClosed = false;
  var unexpectedDisconnectNotified = false;
  var readinessSignalled = false;
  var pingNonce = 0;
  var lastPongAt = DateTime.now();

  Future<void> closeResources() async {
    if (resourcesClosed) return;
    resourcesClosed = true;
    healthTimer?.cancel();
    readinessTimer?.cancel();
    try {
      worker?.onerror = _noopHandler;
      final currentPort = port;
      if (currentPort != null) {
        try {
          currentPort.postMessage(
            <String, Object>{_controlKey: 'disconnect'}.jsify(),
          );
        } catch (_) {}
        currentPort
          ..onmessage = _noopHandler
          ..onmessageerror = _noopHandler
          ..close();
      }
    } catch (_) {}
  }

  void notifyUnexpectedDisconnect() {
    if (isClosed || unexpectedDisconnectNotified) return;
    unexpectedDisconnectNotified = true;
    // Closing only the UI port does not prove that the KDF-side SharedWorker
    // client was removed. The manager must best-effort disable the old
    // streamer ids before allowing replacement enables.
    try {
      onDisconnected(registrationsMayPersist: true);
    } finally {
      unawaited(closeResources());
    }
  }

  void postControl(String kind, {int? nonce}) {
    if (isClosed || unexpectedDisconnectNotified) return;
    try {
      port?.postMessage(
        <String, Object>{
          _controlKey: kind,
          if (nonce != null) 'nonce': nonce,
        }.jsify(),
      );
    } catch (_) {
      notifyUnexpectedDisconnect();
    }
  }

  try {
    worker = web.SharedWorker(_eventStreamingWorkerPath.toJS);
    port = worker.port..start();

    void handler(web.MessageEvent event) {
      if (isClosed || unexpectedDisconnectNotified) return;
      final data = event.data.dartify();
      if (data case final Map<Object?, Object?> control
          when control[_controlKey] is String) {
        switch (control[_controlKey]) {
          case 'ready':
            if (control['ready'] == true && !readinessSignalled) {
              readinessSignalled = true;
              readinessTimer?.cancel();
              onFirstByte();
            }
          case 'pong':
            lastPongAt = DateTime.now();
          default:
            break;
        }
        return;
      }

      // A real KDF event is also authoritative readiness evidence. This keeps
      // compatibility with an older cached worker while the explicit ready
      // handshake is rolling out.
      if (!readinessSignalled) {
        readinessSignalled = true;
        readinessTimer?.cancel();
        onFirstByte();
      }

      if (kDebugMode) {
        print('EventStream: Received message: $data');
      }
      onMessage(data);
    }

    void errorHandler(web.Event _) => notifyUnexpectedDisconnect();

    port
      ..onmessage = handler.toJS
      ..onmessageerror = errorHandler.toJS;
    worker.onerror = errorHandler.toJS;

    readinessTimer = Timer.periodic(
      _readinessProbeInterval,
      (_) => postControl('ready'),
    );
    postControl('ready');

    healthTimer = Timer.periodic(_healthInterval, (_) {
      if (DateTime.now().difference(lastPongAt) > _healthTimeout) {
        notifyUnexpectedDisconnect();
        return;
      }
      postControl('ping', nonce: ++pingNonce);
    });
    postControl('ping', nonce: ++pingNonce);
  } catch (_) {
    scheduleMicrotask(notifyUnexpectedDisconnect);
  }

  return () async {
    if (isClosed) return;
    isClosed = true;
    await closeResources();
  };
}
