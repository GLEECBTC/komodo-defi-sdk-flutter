// Web implementation: connect to SharedWorker('event_streaming_worker.js')
// and forward messages to Dart via the provided callback.

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:web/web.dart' as web;

typedef EventStreamUnsubscribe = void Function();

const _eventStreamingWorkerPath =
    'assets/packages/komodo_defi_framework/assets/web/event_streaming_worker.js';

final web.EventHandlerNonNull _noopHandler = ((web.Event _) {}).toJS;

EventStreamUnsubscribe connectEventStream({
  required void Function(Object? data) onMessage,
  required void Function() onFirstByte,
  IKdfHostConfig? hostConfig,
}) {
  try {
    final worker = web.SharedWorker(_eventStreamingWorkerPath.toJS);
    final port = worker.port..start();

    bool firstMessageReceived = false;

    void handler(web.MessageEvent event) {
      final data = event.data.dartify();

      // Signal first byte received on first message
      if (!firstMessageReceived) {
        firstMessageReceived = true;
        onFirstByte();
      }

      if (kDebugMode) {
        print('EventStream: Received message: $data');
      }
      onMessage(data);
    }

    port.onmessage = handler.toJS;

    return () {
      try {
        port
          ..onmessage = _noopHandler
          ..close();
      } catch (_) {}
    };
  } catch (_) {
    return () {};
  }
}
