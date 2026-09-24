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
    _disconnectSubscription = _eventService.disconnections.listen(
      _handleServiceDisconnected,
    );
    _log('EventStreamingManager initialized (instance=${hashCode})');
  }

  final KomodoDefiRpcMethods _rpcMethods;
  final KdfEventStreamingService _eventService;
  late final StreamSubscription<KdfEventDisconnection> _disconnectSubscription;
  int _connectionGeneration = 0;
  Completer<void> _generationChanged = Completer<void>();
  Future<void> _registrationCleanup = Future<void>.value();
  Future<void>? _managedDisconnectFuture;
  bool _isDisposed = false;

  // Client ID used for all streaming operations
  // In a production app, this could be configurable or derived from app state
  static const int _defaultClientId = 0;

  // Active stream subscriptions keyed by a unique identifier
  final Map<String, _StreamSubscription> _activeStreams = {};

  // Reference counters for shared streams (e.g., heartbeat, network)
  final Map<String, int> _streamRefCounts = {};

  // Track whether the transport has confirmed KDF client registration.
  bool _sseReadinessComplete = false;

  /// Bound the transport registration handshake without inventing retries.
  static const Duration _firstByteTimeout = Duration(seconds: 30);

  // Per-key in-flight guards to prevent duplicate enable_* calls
  final Map<String, Future<StreamSubscription<KdfEvent>>> _inFlightEnables = {};

  /// Wait for the native SSE handshake or the Web worker registration ack.
  Future<void> _waitForSseReadiness(int expectedGeneration) async {
    if (_sseReadinessComplete &&
        expectedGeneration == _connectionGeneration &&
        _eventService.isConnected) {
      return;
    }

    _log('Waiting for KDF event-client registration...');
    _eventService.connectIfNeeded();
    final generationChanged = _generationChanged.future;
    await Future.any<void>([
      _eventService.firstByteReceived,
      generationChanged,
    ]).timeout(
      _firstByteTimeout,
      onTimeout: () {
        throw TimeoutException('KDF event-client registration timed out');
      },
    );
    if (expectedGeneration != _connectionGeneration ||
        !_eventService.isConnected) {
      throw StateError('KDF event connection changed before stream readiness');
    }

    _sseReadinessComplete = true;
    _log('KDF event-client registration is ready for stream::enable');
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
    await _awaitEnableGate();
    if (_isDisposed) {
      throw StateError('Event streaming manager is disposed');
    }

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
      await inFlight;
      final enabled = _activeStreams[key];
      if (enabled == null || enabled.isCancelled) {
        throw StateError('KDF stream registration changed while enabling $key');
      }
      _incrementRefCount(key);
      return _createTypedSubscription<T>(key, eventStream);
    }

    // Create the enable future and store it to prevent duplicates
    final enableFuture = _performEnableStream<T>(
      key: key,
      enableStream: enableStream,
      eventStream: eventStream,
      streamType: streamType,
      coin: coin,
      expectedGeneration: _connectionGeneration,
    );
    _inFlightEnables[key] = enableFuture;

    try {
      final subscription = await enableFuture;
      return subscription;
    } finally {
      // Remove from in-flight map once complete
      if (identical(_inFlightEnables[key], enableFuture)) {
        _inFlightEnables.remove(key);
      }
    }
  }

  /// Performs one enable operation against the current connection generation.
  Future<StreamSubscription<T>> _performEnableStream<T extends KdfEvent>({
    required String key,
    required Future<StreamEnableResponse> Function() enableStream,
    required Stream<T> eventStream,
    required String streamType,
    String? coin,
    required int expectedGeneration,
  }) async {
    await _waitForSseReadiness(expectedGeneration);

    final coinInfo = coin != null ? ', coin=$coin' : '';
    _log(
      'Enable stream attempt: type=$streamType, key=$key, client_id=$_defaultClientId$coinInfo',
    );

    final response = await enableStream();
    if (expectedGeneration != _connectionGeneration ||
        !_eventService.isConnected) {
      await _disableRegistration(
        _StreamSubscription(
          streamerId: response.streamerId,
          clientId: _defaultClientId,
        ),
      );
      throw StateError('KDF connection changed while enabling $streamType');
    }

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
  }

  /// Enable balance stream for a specific coin.
  ///
  /// Returns a [StreamSubscription] that can be used to listen to balance
  /// events and cancel the subscription.
  ///
  /// [streamerCoin] names the coin whose KDF streamer already covers [coin],
  /// when that is a different coin. The registration and the reference count
  /// then key on [streamerCoin] while the events handed back are still filtered
  /// to [coin], so several tickers can share one KDF streamer and each caller
  /// still sees only its own balance.
  ///
  /// This exists because KDF's `EthBalanceEventStreamer` already polls
  /// `all_addresses()` x (its own ticker **plus every registered token**) on
  /// each tick (`mm2src/coins/eth/eth_balance_events.rs:74-105`), and tokens
  /// register onto the *platform* coin
  /// (`mm2src/coins_activation/src/eth_with_token_activation.rs:215-229`; a
  /// token's own `erc20_tokens_infos` is `Default::default()`,
  /// `mm2src/coins/eth/v2_activation.rs:654`). A streamer enabled on a token
  /// ticker therefore re-polls the same address set for a balance the platform
  /// streamer is already reporting. Since the payload is one event carrying an
  /// array of per-ticker entries, which this SDK already splits into one
  /// [BalanceEvent] per ticker, the platform streamer alone satisfies every
  /// token subscriber.
  Future<StreamSubscription<BalanceEvent>> subscribeToBalance({
    required String coin,
    String? streamerCoin,
    StreamConfig? config,
  }) {
    final registrationCoin = streamerCoin ?? coin;
    return _subscribeToStream<BalanceEvent>(
      key: 'balance:$registrationCoin',
      streamType: 'balance',
      coin: registrationCoin,
      enableStream: () => _rpcMethods.streaming.enableBalance(
        coin: registrationCoin,
        clientId: _defaultClientId,
        config: config,
      ),
      eventStream: _eventService.balanceEvents.where((e) => e.coin == coin),
    );
  }

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

  /// Enable GasFree trace streaming for [coin].
  ///
  /// The returned subscription carries both lifecycle snapshots and
  /// `ERROR:GASLESS_TRACE:<coin>` events. Callers must attach it before relay
  /// submission because KDF trace registration is not retroactive.
  Future<StreamSubscription<KdfEvent>> subscribeToGaslessTrace({
    required String coin,
  }) => _subscribeToStream<KdfEvent>(
    key: 'gasless_trace:$coin',
    streamType: 'gasless_trace',
    coin: coin,
    enableStream: () => _rpcMethods.streaming.enableGaslessTrace(
      coin: coin,
      clientId: _defaultClientId,
    ),
    eventStream: _eventService.events.where(
      (event) =>
          (event is GaslessTraceEvent && event.coin == coin) ||
          (event is GaslessTraceErrorEvent && event.coin == coin),
    ),
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
    final serverSubscription = _activeStreams[key];
    if (serverSubscription == null || serverSubscription.isCancelled) {
      throw StateError('KDF stream registration disappeared for $key');
    }

    // Create a broadcast stream controller to wrap the original stream
    // This allows us to properly handle cleanup
    final controller = StreamController<T>.broadcast();

    final innerSubscription = stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    final invalidationSubscription = serverSubscription.invalidations.listen((
      error,
    ) {
      if (!controller.isClosed) {
        controller.addError(error);
        unawaited(controller.close());
      }
      unawaited(innerSubscription.cancel());
    });

    // Wrap the subscription to handle cleanup on cancel
    return _ManagedStreamSubscription<T>(
      controller.stream.listen(null),
      onCancel: () async {
        // Detach this exact server-generation reference before the first
        // await. A replacement registration with the same key must never be
        // decremented or disabled by this older handle.
        final serverCleanup = _handleStreamCancelled(key, serverSubscription);
        await innerSubscription.cancel();
        await invalidationSubscription.cancel();
        if (!controller.isClosed) await controller.close();
        await serverCleanup;
      },
    );
  }

  void _handleServiceDisconnected(KdfEventDisconnection event) {
    if (_isDisposed) return;
    _advanceConnectionGeneration();
    final registrations = _invalidateAllStreams(
      StateError('KDF event connection was disconnected'),
    );
    if (event.registrationsMayPersist) {
      _queueRegistrationCleanup(registrations);
    }
  }

  void _advanceConnectionGeneration() {
    _connectionGeneration++;
    _sseReadinessComplete = false;
    if (!_generationChanged.isCompleted) {
      _generationChanged.complete();
    }
    _generationChanged = Completer<void>();
  }

  List<_StreamSubscription> _invalidateAllStreams(Object error) {
    final subscriptions = _activeStreams.values.toList(growable: false);
    _activeStreams.clear();
    _streamRefCounts.clear();
    for (final subscription in subscriptions) {
      subscription.invalidate(error);
    }
    return subscriptions;
  }

  Future<void> _queueRegistrationCleanup(
    Iterable<_StreamSubscription> registrations,
  ) {
    final snapshot = registrations.toList(growable: false);
    if (snapshot.isEmpty) return _registrationCleanup;

    final previous = _registrationCleanup;
    final cleanup = () async {
      await previous;
      await Future.wait(snapshot.map(_disableRegistration), eagerError: false);
    }();
    _registrationCleanup = cleanup;
    return cleanup;
  }

  Future<void> _awaitEnableGate() async {
    while (true) {
      if (_isDisposed) {
        throw StateError('Event streaming manager is disposed');
      }
      final disconnect = _managedDisconnectFuture;
      if (disconnect != null) await disconnect;
      final cleanup = _registrationCleanup;
      await cleanup;
      if (_managedDisconnectFuture == null &&
          identical(cleanup, _registrationCleanup)) {
        return;
      }
    }
  }

  Future<void> _settleInFlight(
    Iterable<Future<StreamSubscription<KdfEvent>>> operations,
  ) async {
    await Future.wait(
      operations.map(
        (operation) =>
            operation.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ),
      eagerError: false,
    );
  }

  /// Increment reference count for a stream.
  void _incrementRefCount(String key) {
    _streamRefCounts[key] = (_streamRefCounts[key] ?? 0) + 1;
  }

  /// Handle stream cancellation with reference counting.
  Future<void> _handleStreamCancelled(
    String key,
    _StreamSubscription generation,
  ) {
    if (!identical(_activeStreams[key], generation)) {
      return Future<void>.value();
    }
    final refCount = (_streamRefCounts[key] ?? 1) - 1;
    if (refCount > 0) {
      _streamRefCounts[key] = refCount;
      return Future<void>.value();
    }
    _streamRefCounts.remove(key);
    _activeStreams.remove(key);
    generation.markCancelled();
    return _queueRegistrationCleanup([generation]);
  }

  Future<void> _disableRegistration(_StreamSubscription subscription) async {
    try {
      await _rpcMethods.streaming.disable(
        clientId: subscription.clientId,
        streamerId: subscription.streamerId,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to disable stream ${subscription.streamerId}: $e');
      }
    }
  }

  /// Get a list of all active stream keys.
  List<String> get activeStreamKeys => _activeStreams.keys.toList();

  /// Check if a specific stream is active.
  bool isStreamActive(String key) {
    final subscription = _activeStreams[key];
    return subscription != null && !subscription.isCancelled;
  }

  /// Disables every managed KDF registration before closing the transport.
  ///
  /// New enables are gated until cleanup and transport shutdown are complete.
  Future<void> disconnect() {
    final existing = _managedDisconnectFuture;
    if (existing != null) return existing;
    if (_isDisposed) return Future<void>.value();

    final completer = Completer<void>();
    final future = completer.future;
    _managedDisconnectFuture = future;

    _advanceConnectionGeneration();
    final registrations = _invalidateAllStreams(
      StateError('KDF event connection was disconnected'),
    );
    final inFlight = _inFlightEnables.values.toList(growable: false);
    unawaited(
      _finishManagedDisconnect(
        future: future,
        completer: completer,
        registrations: registrations,
        inFlight: inFlight,
      ),
    );
    return future;
  }

  Future<void> _finishManagedDisconnect({
    required Future<void> future,
    required Completer<void> completer,
    required List<_StreamSubscription> registrations,
    required List<Future<StreamSubscription<KdfEvent>>> inFlight,
  }) async {
    try {
      await _queueRegistrationCleanup(registrations);
      await _settleInFlight(inFlight);
      await _registrationCleanup;
      await _eventService.disconnect();
      if (identical(_managedDisconnectFuture, future)) {
        _managedDisconnectFuture = null;
      }
      completer.complete();
    } catch (error, stackTrace) {
      if (identical(_managedDisconnectFuture, future)) {
        _managedDisconnectFuture = null;
      }
      completer.completeError(error, stackTrace);
    }
  }

  /// Disable all active streams and clean up resources.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    final managedDisconnect = _managedDisconnectFuture;
    if (managedDisconnect != null) {
      await managedDisconnect;
    }
    _advanceConnectionGeneration();
    await _disconnectSubscription.cancel();
    final registrations = _invalidateAllStreams(
      StateError('Event streaming manager disposed'),
    );
    final inFlight = _inFlightEnables.values.toList(growable: false);
    await _queueRegistrationCleanup(registrations);
    await _settleInFlight(inFlight);
    await _registrationCleanup;
    await _eventService.disconnect();
  }
}

/// Internal subscription metadata.
class _StreamSubscription {
  _StreamSubscription({required this.streamerId, required this.clientId});

  final String streamerId;
  final int clientId;
  final StreamController<Object> _invalidations =
      StreamController<Object>.broadcast(sync: true);
  bool isCancelled = false;

  Stream<Object> get invalidations => _invalidations.stream;

  void invalidate(Object error) {
    if (isCancelled) return;
    isCancelled = true;
    _invalidations.add(error);
    unawaited(_invalidations.close());
  }

  void markCancelled() {
    if (isCancelled) return;
    isCancelled = true;
    unawaited(_invalidations.close());
  }
}

/// Wrapper around StreamSubscription that handles cleanup.
class _ManagedStreamSubscription<T> implements StreamSubscription<T> {
  _ManagedStreamSubscription(this._inner, {required this.onCancel});

  final StreamSubscription<T> _inner;
  final Future<void> Function() onCancel;
  Future<void>? _cancelFuture;

  @override
  Future<void> cancel() => _cancelFuture ??= _cancel();

  Future<void> _cancel() async {
    // [onCancel] removes this handle's server-generation reference
    // synchronously before its first await.
    final cleanup = onCancel();
    await _inner.cancel();
    await cleanup;
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
