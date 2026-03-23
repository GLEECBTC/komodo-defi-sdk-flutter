import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Production-visible logger for streaming operations
void _log(String msg) {
  // Production-visible logging - always print for critical streaming events
  print('[EventStreamingManager] $msg');
}

/// Internal manager for handling event stream lifecycle.
///
/// This class abstracts away the complexity of managing event streams,
/// including:
/// - Enabling and disabling streams
/// - Tracking active subscriptions
/// - Managing streamer IDs and client IDs
/// - Automatic cleanup
/// - Reference counting for shared streams
///
/// This class is not publicly exposed by the SDK.
class EventStreamingManager {
  /// Creates a new event streaming manager.
  ///
  /// Requires an [ApiClient] for making RPC calls and a [KdfEventStreamingService]
  /// for receiving events.
  EventStreamingManager({
    required ApiClient client,
    required KdfEventStreamingService eventService,
  }) : _rpcMethods = KomodoDefiRpcMethods(client),
       _eventService = eventService {
    _log('EventStreamingManager initialized (instance=${hashCode})');
  }

  final KomodoDefiRpcMethods _rpcMethods;
  final KdfEventStreamingService _eventService;

  // Client ID used for all streaming operations
  // In a production app, this could be configurable or derived from app state
  static const int _defaultClientId = 0;

  // Active stream subscriptions keyed by a unique identifier
  final Map<String, _StreamSubscription> _activeStreams = {};

  // Reference counters for shared streams (e.g., heartbeat, network)
  final Map<String, int> _streamRefCounts = {};

  // Track if SSE connection is ready (first byte received + grace period elapsed)
  bool _sseReadinessComplete = false;
  Timer? _gracePeriodTimer;

  // Post-connect delay before first enable_* call (1500ms for robust readiness)
  static const Duration _postConnectDelay = Duration(milliseconds: 1500);

  /// Per-attempt wait for the first real event from SSE / SharedWorker (KDF
  /// client registration). Short timeouts caused enable_* before registration.
  static const Duration _firstByteTimeout = Duration(seconds: 30);

  static const int _firstByteMaxAttempts = 3;

  static const Duration _firstByteReconnectDelay = Duration(seconds: 1);

  // Per-key in-flight guards to prevent duplicate enable_* calls
  final Map<String, Future<StreamSubscription<KdfEvent>>> _inFlightEnables = {};

  /// Wait for SSE readiness: first byte received + grace period elapsed
  Future<void> _waitForSseReadiness() async {
    if (_sseReadinessComplete) return;

    _log(
      'Waiting for SSE readiness (first real event + '
      '${_postConnectDelay.inMilliseconds}ms grace period)...',
    );

    for (var attempt = 1; attempt <= _firstByteMaxAttempts; attempt++) {
      _eventService.connectIfNeeded();

      try {
        await _eventService.firstByteReceived.timeout(
          _firstByteTimeout,
          onTimeout: () {
            _log(
              'First byte timeout after ${_firstByteTimeout.inSeconds}s '
              '(attempt $attempt/$_firstByteMaxAttempts)',
            );
            throw TimeoutException('First byte not received');
          },
        );
        _log('First byte received from SSE stream');
        break;
      } on TimeoutException {
        if (attempt >= _firstByteMaxAttempts) {
          _log(
            'SSE first byte not received after $_firstByteMaxAttempts attempts; '
            'aborting enable_* (avoid UnknownClient)',
          );
          rethrow;
        }
        _log('Reconnecting SSE before next first-byte wait...');
        _eventService.disconnect();
        await Future<void>.delayed(_firstByteReconnectDelay);
      } catch (e) {
        _log('Error waiting for first byte: $e');
        if (attempt >= _firstByteMaxAttempts) rethrow;
        _eventService.disconnect();
        await Future<void>.delayed(_firstByteReconnectDelay);
      }
    }

    _log('Waiting ${_postConnectDelay.inMilliseconds}ms grace period...');
    await Future<void>.delayed(_postConnectDelay);

    _sseReadinessComplete = true;
    _log('SSE readiness complete - ready for enable_* calls');
  }

  /// Generic method to handle stream subscription with automatic lifecycle
  /// management. This reduces boilerplate by extracting common subscription logic.
  Future<StreamSubscription<T>> _subscribeToStream<T extends KdfEvent>({
    required String key,
    required Future<StreamEnableResponse> Function() enableStream,
    required Stream<T> eventStream,
    required String streamType,
    String? coin,
  }) async {
    // Check if stream is already active
    final existing = _activeStreams[key];
    if (existing != null && !existing.isCancelled) {
      _log('Stream already active: $key (refCount=${_streamRefCounts[key]})');
      _incrementRefCount(key);
      return _createTypedSubscription<T>(key, eventStream);
    }

    // Check if there's already an in-flight enable for this key
    final inFlight = _inFlightEnables[key];
    if (inFlight != null) {
      _log('Enable already in-flight for $key, awaiting completion...');
      final subscription = await inFlight;
      _incrementRefCount(key);
      return subscription as StreamSubscription<T>;
    }

    // Create the enable future and store it to prevent duplicates
    final enableFuture = _performEnableStream<T>(
      key: key,
      enableStream: enableStream,
      eventStream: eventStream,
      streamType: streamType,
      coin: coin,
    );
    _inFlightEnables[key] = enableFuture;

    try {
      final subscription = await enableFuture;
      return subscription;
    } finally {
      // Remove from in-flight map once complete
      _inFlightEnables.remove(key);
    }
  }

  /// Performs the actual enable stream operation with readiness checks and retries
  Future<StreamSubscription<T>> _performEnableStream<T extends KdfEvent>({
    required String key,
    required Future<StreamEnableResponse> Function() enableStream,
    required Stream<T> eventStream,
    required String streamType,
    String? coin,
  }) async {
    // Wait for SSE readiness (first byte + grace period)
    await _waitForSseReadiness();

    // Log enable_* attempt with details
    final coinInfo = coin != null ? ', coin=$coin' : '';
    _log(
      'Enable stream attempt: type=$streamType, key=$key, client_id=$_defaultClientId$coinInfo',
    );

    int attemptCount = 0;
    const maxAttempts = 3;
    const retryDelay = Duration(seconds: 1);

    while (attemptCount < maxAttempts) {
      try {
        attemptCount++;

        // Enable new stream
        final response = await enableStream();

        final streamerId = response.streamerId;
        _activeStreams[key] = _StreamSubscription(
          streamerId: streamerId,
          clientId: _defaultClientId,
        );
        _incrementRefCount(key);

        _log(
          'Enable stream success: type=$streamType, key=$key, streamer_id=$streamerId',
        );
        return _createTypedSubscription<T>(key, eventStream);
      } catch (e) {
        _log(
          'Enable stream failed (attempt $attemptCount/$maxAttempts): type=$streamType, error=$e',
        );

        // Check if it's an UnknownClient error
        final errorStr = e.toString();
        if (errorStr.contains('UnknownClient')) {
          _log(
            'UnknownClient error detected - server forgot client registration',
          );

          if (attemptCount < maxAttempts) {
            // Force full SSE reconnect on UnknownClient regardless of connection state
            // The client may think it's connected, but KDF has dropped the registration
            _log('Forcing SSE reconnect due to UnknownClient error...');
            _eventService.disconnect();
            _sseReadinessComplete = false; // Reset readiness flag
            _activeStreams.remove(key); // Clear stale stream entry

            // Wait for first real event + grace (same as initial connect)
            await _waitForSseReadiness();

            _log('Retrying enable_* after SSE reconnection...');
            await Future<void>.delayed(retryDelay);
            continue;
          }
        }

        // Rethrow if max attempts reached or non-UnknownClient error
        rethrow;
      }
    }

    throw Exception(
      'Failed to enable stream after $maxAttempts attempts: $key',
    );
  }

  /// Enable balance stream for a specific coin.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to balance
  /// events and cancel the subscription.
  Future<StreamSubscription<BalanceEvent>> subscribeToBalance({
    required String coin,
    StreamConfig? config,
  }) => _subscribeToStream<BalanceEvent>(
    key: 'balance:$coin',
    streamType: 'balance',
    coin: coin,
    enableStream: () => _rpcMethods.streaming.enableBalance(
      coin: coin,
      clientId: _defaultClientId,
      config: config,
    ),
    eventStream: _eventService.balanceEvents.where((e) => e.coin == coin),
  );

  /// Enable orderbook stream for a trading pair.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to orderbook
  /// events and cancel the subscription.
  Future<StreamSubscription<OrderbookEvent>> subscribeToOrderbook({
    required String base,
    required String rel,
  }) => _subscribeToStream<OrderbookEvent>(
    key: 'orderbook:$base:$rel',
    streamType: 'orderbook',
    coin: '$base/$rel',
    enableStream: () => _rpcMethods.streaming.enableOrderbook(
      base: base,
      rel: rel,
      clientId: _defaultClientId,
    ),
    eventStream: _eventService.orderbookEvents.where(
      (e) => e.base == base && e.rel == rel,
    ),
  );

  /// Enable transaction history stream for a specific coin.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to transaction
  /// history events and cancel the subscription.
  Future<StreamSubscription<TxHistoryEvent>> subscribeToTxHistory({
    required String coin,
  }) => _subscribeToStream<TxHistoryEvent>(
    key: 'tx_history:$coin',
    streamType: 'tx_history',
    coin: coin,
    enableStream: () => _rpcMethods.streaming.enableTxHistory(
      coin: coin,
      clientId: _defaultClientId,
    ),
    eventStream: _eventService.txHistoryEvents.where((e) => e.coin == coin),
  );

  /// Enable swap status stream.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to swap status
  /// events and cancel the subscription.
  Future<StreamSubscription<SwapStatusEvent>> subscribeToSwapStatus() =>
      _subscribeToStream<SwapStatusEvent>(
        key: 'swap_status',
        streamType: 'swap_status',
        enableStream: () =>
            _rpcMethods.streaming.enableSwapStatus(clientId: _defaultClientId),
        eventStream: _eventService.swapStatusEvents,
      );

  /// Enable order status stream.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to order status
  /// events and cancel the subscription.
  Future<StreamSubscription<OrderStatusEvent>> subscribeToOrderStatus() =>
      _subscribeToStream<OrderStatusEvent>(
        key: 'order_status',
        streamType: 'order_status',
        enableStream: () =>
            _rpcMethods.streaming.enableOrderStatus(clientId: _defaultClientId),
        eventStream: _eventService.orderStatusEvents,
      );

  /// Enable network status stream.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to network
  /// events and cancel the subscription.
  Future<StreamSubscription<NetworkEvent>> subscribeToNetwork({
    StreamConfig? config,
    bool? alwaysSend,
  }) => _subscribeToStream<NetworkEvent>(
    key: 'network',
    streamType: 'network',
    enableStream: () => _rpcMethods.streaming.enableNetwork(
      clientId: _defaultClientId,
      config: config,
      alwaysSend: alwaysSend,
    ),
    eventStream: _eventService.networkEvents,
  );

  /// Enable heartbeat stream.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to heartbeat
  /// events and cancel the subscription.
  Future<StreamSubscription<HeartbeatEvent>> subscribeToHeartbeat({
    StreamConfig? config,
    bool? alwaysSend,
  }) => _subscribeToStream<HeartbeatEvent>(
    key: 'heartbeat',
    streamType: 'heartbeat',
    enableStream: () => _rpcMethods.streaming.enableHeartbeat(
      clientId: _defaultClientId,
      config: config,
      alwaysSend: alwaysSend,
    ),
    eventStream: _eventService.heartbeatEvents,
  );

  /// Enable shutdown signal stream.
  ///
  /// Note: This feature is not supported on Windows and doesn't run on Web.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to shutdown
  /// signal events and cancel the subscription.
  Future<StreamSubscription<ShutdownSignalEvent>>
  subscribeToShutdownSignals() => _subscribeToStream<ShutdownSignalEvent>(
    key: 'shutdown_signal',
    streamType: 'shutdown_signal',
    enableStream: () =>
        _rpcMethods.streaming.enableShutdownSignal(clientId: _defaultClientId),
    eventStream: _eventService.shutdownSignals,
  );

  /// Create a typed subscription that handles reference counting and cleanup.
  StreamSubscription<T> _createTypedSubscription<T extends KdfEvent>(
    String key,
    Stream<T> stream,
  ) {
    // Create a broadcast stream controller to wrap the original stream
    // This allows us to properly handle cleanup
    final controller = StreamController<T>.broadcast();

    final innerSubscription = stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );

    // Wrap the subscription to handle cleanup on cancel
    return _ManagedStreamSubscription<T>(
      controller.stream.listen(null),
      onCancel: () async {
        await innerSubscription.cancel();
        await controller.close();
        await _handleStreamCancelled(key);
      },
    );
  }

  /// Increment reference count for a stream.
  void _incrementRefCount(String key) {
    _streamRefCounts[key] = (_streamRefCounts[key] ?? 0) + 1;
  }

  /// Handle stream cancellation with reference counting.
  Future<void> _handleStreamCancelled(String key) async {
    final refCount = (_streamRefCounts[key] ?? 1) - 1;
    _streamRefCounts[key] = refCount;

    // Only disable the stream if no more references exist
    if (refCount <= 0) {
      _streamRefCounts.remove(key);
      await _disableStream(key);
    }
  }

  /// Disable a stream by key.
  Future<void> _disableStream(String key) async {
    final subscription = _activeStreams[key];
    if (subscription == null || subscription.isCancelled) {
      return;
    }

    try {
      await _rpcMethods.streaming.disable(
        clientId: subscription.clientId,
        streamerId: subscription.streamerId,
      );

      subscription.markCancelled();
      _activeStreams.remove(key);
    } on Exception catch (e) {
      if (kDebugMode) {
        print('Failed to disable stream $key: $e');
      }
      // Still mark as cancelled and remove from active streams
      subscription.markCancelled();
      _activeStreams.remove(key);
    }
  }

  /// Get a list of all active stream keys.
  List<String> get activeStreamKeys => _activeStreams.keys.toList();

  /// Check if a specific stream is active.
  bool isStreamActive(String key) {
    final subscription = _activeStreams[key];
    return subscription != null && !subscription.isCancelled;
  }

  /// Disable all active streams and clean up resources.
  Future<void> dispose() async {
    final keys = _activeStreams.keys.toList();

    // Disable all streams in parallel
    await Future.wait(
      keys.map(_disableStream),
      eagerError: false, // Continue even if some fail
    );

    _activeStreams.clear();
    _streamRefCounts.clear();
  }
}

/// Internal subscription metadata.
class _StreamSubscription {
  _StreamSubscription({required this.streamerId, required this.clientId});

  final String streamerId;
  final int clientId;
  bool isCancelled = false;

  void markCancelled() {
    isCancelled = true;
  }
}

/// Wrapper around StreamSubscription that handles cleanup.
class _ManagedStreamSubscription<T> implements StreamSubscription<T> {
  _ManagedStreamSubscription(this._inner, {required this.onCancel});

  final StreamSubscription<T> _inner;
  final Future<void> Function() onCancel;

  @override
  Future<void> cancel() async {
    await _inner.cancel();
    await onCancel();
  }

  @override
  void onData(void Function(T data)? handleData) {
    _inner.onData(handleData);
  }

  @override
  void onError(Function? handleError) {
    _inner.onError(handleError);
  }

  @override
  void onDone(void Function()? handleDone) {
    _inner.onDone(handleDone);
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return _inner.asFuture(futureValue);
  }

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void pause([Future<void>? resumeSignal]) {
    _inner.pause(resumeSignal);
  }

  @override
  void resume() {
    _inner.resume();
  }
}
