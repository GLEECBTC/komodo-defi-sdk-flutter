// Minimal streaming service facade; on Web, relies on a SharedWorker posting
// messages from the WASM layer using `mm2_net::handle_worker_stream`.

import 'dart:async';
import 'dart:convert' as convert;

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_framework/src/config/kdf_config.dart';
import 'package:komodo_defi_framework/src/streaming/event_streaming_platform_stub.dart'
    if (dart.library.io) 'package:komodo_defi_framework/src/streaming/event_streaming_platform_io.dart'
    if (dart.library.js_interop) 'package:komodo_defi_framework/src/streaming/event_streaming_platform_web.dart';
import 'package:komodo_defi_framework/src/streaming/events/kdf_event.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

typedef EventPredicate = bool Function(KdfEvent event);

enum SseConnectionState { disconnected, connecting, connected }

enum KdfEventDisconnectionKind {
  manual,
  transportRegistrationsDropped,
  transportRegistrationsMayPersist,
}

class KdfEventDisconnection {
  const KdfEventDisconnection(this.kind);

  final KdfEventDisconnectionKind kind;

  bool get isManual => kind == KdfEventDisconnectionKind.manual;

  bool get registrationsMayPersist =>
      kind == KdfEventDisconnectionKind.transportRegistrationsMayPersist;
}

class KdfEventStreamingService {
  KdfEventStreamingService({IKdfHostConfig? hostConfig})
    : _hostConfig = hostConfig;

  final IKdfHostConfig? _hostConfig;

  final StreamController<KdfEvent> _events = StreamController.broadcast();
  final StreamController<KdfEventDisconnection> _disconnections =
      StreamController<KdfEventDisconnection>.broadcast(sync: true);
  Completer<void> _firstByteCompleter = Completer<void>();
  SseConnectionState _connectionState = SseConnectionState.disconnected;
  int _connectionGeneration = 0;
  bool _isDisposed = false;

  Stream<KdfEvent> get events => _events.stream;

  /// Emits whenever the underlying SSE client registration is discarded.
  ///
  /// Managed KDF stream registrations are scoped to that connection and must
  /// be invalidated and re-enabled after every disconnect.
  Stream<KdfEventDisconnection> get disconnections => _disconnections.stream;

  /// Completes when the transport confirms the KDF event client registration.
  ///
  /// On native platforms this is the validated HTTP event-stream handshake.
  /// On Web it is an explicit acknowledgement from the SharedWorker bridge.
  Future<void> get firstByteReceived => _firstByteCompleter.future;

  /// Current connection state
  SseConnectionState get connectionState => _connectionState;

  /// Whether the SSE connection is currently connected
  bool get isConnected => _connectionState == SseConnectionState.connected;

  /// Start listening to stream events.
  /// - Web: Connects to SharedWorker forwarded messages.
  /// - Native (IO): Connects to SSE endpoint exposed by KDF RPC server.
  ///
  /// DEPRECATED: Use connectIfNeeded() instead. This method is kept for
  /// backward compatibility, but should not be called at app startup.
  @Deprecated('Use connectIfNeeded() instead')
  void initialize() {
    connectIfNeeded();
  }

  /// Ensures SSE connection is established if not already connected.
  /// This method is idempotent and can be called multiple times safely.
  ///
  /// Should be called:
  /// - After user authentication completes
  /// - Before attempting enable_* RPC calls
  /// - After a previous transport generation has been invalidated
  void connectIfNeeded() {
    if (_isDisposed) return;
    if (_connectionState != SseConnectionState.disconnected) {
      // Already connecting or connected
      return;
    }

    _connectionState = SseConnectionState.connecting;
    _log('SSE Connect: Initiating connection...');

    final connectionGeneration = ++_connectionGeneration;
    final unsubscribe = connectEventStream(
      hostConfig: _hostConfig,
      onMessage: (data) => _onIncomingData(data, connectionGeneration),
      onFirstByte: () => _onFirstByte(connectionGeneration),
      onDisconnected: ({required registrationsMayPersist}) =>
          _onTransportDisconnected(
            connectionGeneration,
            registrationsMayPersist: registrationsMayPersist,
          ),
    );
    if (_isDisposed ||
        connectionGeneration != _connectionGeneration ||
        _connectionState == SseConnectionState.disconnected) {
      unawaited(unsubscribe());
      return;
    }
    _unsubscribe = unsubscribe;
  }

  /// Disconnect the SSE connection.
  /// Should be called when user signs out.
  Future<void> disconnect() async {
    // Invalidate callbacks already queued by the old native/Web transport.
    // Without this generation boundary, a late first-byte callback can mark a
    // freshly disconnected service as connected and make the next enable RPC
    // target a stale KDF client registration.
    _connectionGeneration++;
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    if (_connectionState != SseConnectionState.disconnected ||
        unsubscribe != null) {
      _log('SSE Disconnect: Closing connection...');
    }
    _connectionState = SseConnectionState.disconnected;
    _resetReadiness();
    _emitDisconnection(
      const KdfEventDisconnection(KdfEventDisconnectionKind.manual),
    );
    try {
      await unsubscribe?.call();
    } catch (error) {
      _log('SSE Disconnect: Transport cleanup failed: $error');
    }
  }

  void _onTransportDisconnected(
    int connectionGeneration, {
    required bool registrationsMayPersist,
  }) {
    if (_isDisposed ||
        connectionGeneration != _connectionGeneration ||
        _connectionState == SseConnectionState.disconnected) {
      return;
    }

    _connectionGeneration++;
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    _connectionState = SseConnectionState.disconnected;
    _resetReadiness();
    _emitDisconnection(
      KdfEventDisconnection(
        registrationsMayPersist
            ? KdfEventDisconnectionKind.transportRegistrationsMayPersist
            : KdfEventDisconnectionKind.transportRegistrationsDropped,
      ),
    );
    if (unsubscribe != null) {
      unawaited(unsubscribe());
    }
  }

  void _resetReadiness() {
    // Wake waiters from the old generation so they can observe the generation
    // boundary instead of hanging on an obsolete readiness future.
    if (!_firstByteCompleter.isCompleted) {
      _firstByteCompleter.complete();
    }
    _firstByteCompleter = Completer<void>();
  }

  void _emitDisconnection(KdfEventDisconnection event) {
    if (!_disconnections.isClosed) {
      _disconnections.add(event);
    }
  }

  void _onFirstByte(int connectionGeneration) {
    if (_isDisposed ||
        connectionGeneration != _connectionGeneration ||
        _connectionState != SseConnectionState.connecting) {
      return;
    }
    if (!_firstByteCompleter.isCompleted) {
      _firstByteCompleter.complete();
      _connectionState = SseConnectionState.connected;
      _log('SSE Connect: KDF event client registration is ready');
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      print('[EventStreamingService] $message');
    }
  }

  void _onIncomingData(Object? data, int connectionGeneration) {
    if (_isDisposed ||
        connectionGeneration != _connectionGeneration ||
        _connectionState == SseConnectionState.disconnected) {
      return;
    }
    try {
      if (data == null) return;
      JsonMap? map;

      if (data is String) {
        final String trimmed = data.trim();
        // First attempt: direct JSON object string
        map = tryParseJson(trimmed);
        if (map == null) {
          // Second attempt: payload is a JSON string wrapped in quotes
          try {
            final dynamic once = convert.jsonDecode(trimmed);
            if (once is String) {
              map = tryParseJson(once);
            } else if (once is Map) {
              map = JsonMap.from(once);
            }
          } catch (_) {}
        }

        if (map == null) {
          throw ArgumentError('Unsupported event payload string');
        }
      } else if (data is Map) {
        map = JsonMap.from(data);
      } else {
        throw ArgumentError('Unsupported event data type: ${data.runtimeType}');
      }
      // A single raw message can expand to multiple events (e.g. a BALANCE
      // payload listing several tokens), so add each parsed event.
      final List<KdfEvent> events = KdfEvent.parseAll(map);
      for (final event in events) {
        if (kDebugMode) {
          final summary = _summarizeEvent(event);
          // UnknownEvent.typeEnum throws by design, so resolve the label safely
          // to avoid the debug print aborting this batch (which would drop any
          // events parsed after an unrecognized one, e.g. an ERROR:BALANCE:*).
          final typeLabel = event is UnknownEvent
              ? event.typeString
              : event.typeEnum.value;
          print('[EventStream] Received $typeLabel: $summary');
        }
        _events.add(event);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to parse stream event: $e');
      }
    }
  }

  /// Generic filter for a specific event type with proper type casting
  Stream<T> whereEventType<T extends KdfEvent>() =>
      events.where((e) => e is T).cast<T>();

  /// Get a stream of balance update events
  Stream<BalanceEvent> get balanceEvents => whereEventType<BalanceEvent>();

  /// GasFree transfer lifecycle snapshots for all enabled token streamers.
  Stream<GaslessTraceEvent> get gaslessTraceEvents =>
      whereEventType<GaslessTraceEvent>();

  /// Stream errors for registered GasFree traces.
  Stream<GaslessTraceErrorEvent> get gaslessTraceErrorEvents =>
      whereEventType<GaslessTraceErrorEvent>();

  /// Get a stream of orderbook update events
  Stream<OrderbookEvent> get orderbookEvents =>
      whereEventType<OrderbookEvent>();

  /// Get a stream of network connectivity events
  Stream<NetworkEvent> get networkEvents => whereEventType<NetworkEvent>();

  /// Get a stream of heartbeat events
  Stream<HeartbeatEvent> get heartbeatEvents =>
      whereEventType<HeartbeatEvent>();

  /// Get a stream of swap status update events
  Stream<SwapStatusEvent> get swapStatusEvents =>
      whereEventType<SwapStatusEvent>();

  /// Get a stream of order status update events
  Stream<OrderStatusEvent> get orderStatusEvents =>
      whereEventType<OrderStatusEvent>();

  /// Get a stream of transaction history events
  Stream<TxHistoryEvent> get txHistoryEvents =>
      whereEventType<TxHistoryEvent>();

  /// Get a stream of task update events
  Stream<TaskEvent> get taskEvents => whereEventType<TaskEvent>();

  /// Get a stream of task update events for a specific task ID
  Stream<TaskEvent> taskEventsForId(int taskId) =>
      taskEvents.where((event) => event.taskId == taskId);

  /// Get a stream of shutdown signal events.
  ///
  /// This stream emits events when OS signals (like SIGINT, SIGTERM) are
  /// received by KDF before graceful shutdown.
  ///
  /// Note: This feature is not supported on Windows and doesn't run on Web.
  Stream<ShutdownSignalEvent> get shutdownSignals =>
      whereEventType<ShutdownSignalEvent>();

  /// Cleanup
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await disconnect();
    await _events.close();
    await _disconnections.close();
  }

  /// Provides a concise summary of an event for debug logging
  String _summarizeEvent(KdfEvent event) {
    return switch (event) {
      BalanceEvent(:final coin, :final balance) =>
        'coin=$coin, spendable=${balance.spendable}, '
            'unspendable=${balance.unspendable}',
      GaslessTraceEvent(:final coin, :final traceId, :final state) =>
        'coin=$coin, traceId=$traceId, state=$state',
      GaslessTraceErrorEvent(:final coin, :final traceId) =>
        'coin=$coin, traceId=$traceId, error',
      OrderbookEvent(:final base, :final rel) => 'pair=$base/$rel',
      NetworkEvent(:final netid, :final peers) => 'netid=$netid, peers=$peers',
      HeartbeatEvent(:final timestamp) => 'timestamp=$timestamp',
      SwapStatusEvent(:final uuid) => 'uuid=$uuid',
      OrderStatusEvent(:final uuid) => 'uuid=$uuid',
      TaskEvent(:final taskId) => 'taskId=$taskId',
      TxHistoryEvent(:final coin, :final transactions) =>
        'coin=$coin, txCount=${transactions.length}',
      ShutdownSignalEvent(:final signalName) => 'signal=$signalName',
      UnknownEvent(:final typeString) => 'unknown type=$typeString',
    };
  }

  EventStreamUnsubscribe? _unsubscribe;
}
