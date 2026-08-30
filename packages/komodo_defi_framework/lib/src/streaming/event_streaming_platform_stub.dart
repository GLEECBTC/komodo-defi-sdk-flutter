import 'dart:async';

import 'package:komodo_defi_framework/src/config/kdf_config.dart';

typedef EventStreamUnsubscribe = Future<void> Function();

EventStreamUnsubscribe connectEventStream({
  required void Function(Object? data) onMessage,
  required void Function() onFirstByte,
  required void Function({required bool registrationsMayPersist})
  onDisconnected,
  IKdfHostConfig? hostConfig,
}) {
  // No-op default implementation; actual logic provided by IO/Web variants
  scheduleMicrotask(() => onDisconnected(registrationsMayPersist: false));
  return () async {};
}
