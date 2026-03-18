import 'dart:async';

import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show OrderbookEvent, SwapStatusEvent;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// High-level trading helpers for orderbook/swap monitoring and
/// frequently-requested trading RPCs.
///
/// This manager provides:
/// - stream-first orderbook and swap status watchers with polling fallback
/// - in-flight and short-TTL dedupe for expensive trade requests
class TradingManager {
  /// Creates a [TradingManager] backed by shared SDK services.
  TradingManager({
    required ApiClient client,
    required EventStreamingManager eventStreamingManager,
  }) : _client = client,
       _eventStreamingManager = eventStreamingManager;

  final ApiClient _client;
  final EventStreamingManager _eventStreamingManager;
  final _requestCache = _TimedRequestCache();

  static const Duration _orderbookCacheTtl = Duration(milliseconds: 800);
  static const Duration _swapStatusCacheTtl = Duration(milliseconds: 800);
  static const Duration _recentSwapsCacheTtl = Duration(seconds: 2);
  static const Duration _tradePreimageCacheTtl = Duration(seconds: 2);
  static const Duration _maxTakerCacheTtl = Duration(seconds: 5);
  static const Duration _minTradingCacheTtl = Duration(seconds: 10);

  /// Fetches a single orderbook snapshot.
  Future<OrderbookResponse> getOrderbook({
    required String base,
    required String rel,
  }) {
    return _requestCache.getOrCreate<OrderbookResponse>(
      'orderbook:$base:$rel',
      ttl: _orderbookCacheTtl,
      request: () => _client.rpc.orderbook.orderbook(base: base, rel: rel),
    );
  }

  /// Watches orderbook updates using stream events and a polling fallback.
  ///
  /// Emits one immediate snapshot first, then emits stream updates. If stream
  /// updates are stale for [streamStaleTimeout], polling snapshots are emitted.
  Stream<OrderbookResponse> watchOrderbook({
    required String base,
    required String rel,
    Duration fallbackPollingInterval = const Duration(seconds: 15),
    Duration streamStaleTimeout = const Duration(seconds: 20),
  }) {
    late StreamController<OrderbookResponse> controller;
    StreamSubscription<OrderbookEvent>? streamSubscription;
    Timer? pollingTimer;
    DateTime? lastStreamUpdateAt;
    var fetchInProgress = false;
    var isCancelled = false;

    bool canEmit() => !isCancelled && !controller.isClosed;

    Future<void> tearDownResources() async {
      pollingTimer?.cancel();
      pollingTimer = null;
      await streamSubscription?.cancel();
      streamSubscription = null;
    }

    Future<void> emitSnapshot() async {
      if (fetchInProgress || !canEmit()) return;
      fetchInProgress = true;
      try {
        final snapshot = await getOrderbook(base: base, rel: rel);
        if (canEmit()) {
          controller.add(snapshot);
        }
      } on Object catch (e, s) {
        if (canEmit()) {
          controller.addError(e, s);
        }
      } finally {
        fetchInProgress = false;
      }
    }

    Future<void> start() async {
      await emitSnapshot();
      if (!canEmit()) return;

      try {
        final subscription = await _eventStreamingManager.subscribeToOrderbook(
          base: base,
          rel: rel,
        );
        if (!canEmit()) {
          await subscription.cancel();
          return;
        }

        streamSubscription = subscription
          ..onData((event) {
            if (!canEmit()) return;
            lastStreamUpdateAt = DateTime.now();
            controller.add(_mapOrderbookEventToResponse(event));
          })
          ..onError((Object error, StackTrace trace) {
            if (canEmit()) {
              controller.addError(error, trace);
            }
          });
      } on Object catch (e, s) {
        if (canEmit()) {
          controller.addError(e, s);
        }
      }
      if (!canEmit()) {
        await tearDownResources();
        return;
      }

      pollingTimer = Timer.periodic(fallbackPollingInterval, (_) {
        if (!canEmit()) return;
        final lastUpdateAt = lastStreamUpdateAt;
        final streamIsFresh =
            lastUpdateAt != null &&
            DateTime.now().difference(lastUpdateAt) < streamStaleTimeout;
        if (!streamIsFresh) {
          emitSnapshot().ignore();
        }
      });
    }

    controller = StreamController<OrderbookResponse>(
      onListen: () => start().ignore(),
      onCancel: () async {
        isCancelled = true;
        await tearDownResources();
      },
    );

    return controller.stream;
  }

  /// Fetches status for a single swap UUID.
  Future<SwapStatusResponse> getSwapStatus({required String uuid}) {
    return _requestCache.getOrCreate<SwapStatusResponse>(
      'swap_status:$uuid',
      ttl: _swapStatusCacheTtl,
      request: () => _client.rpc.trading.swapStatus(uuid: uuid),
    );
  }

  /// Watches updates for a single swap UUID using stream events and a polling
  /// fallback.
  ///
  /// Emits one immediate snapshot first, then emits matching stream updates.
  Stream<SwapInfo> watchSwapStatus({
    required String uuid,
    Duration fallbackPollingInterval = const Duration(seconds: 10),
    Duration streamStaleTimeout = const Duration(seconds: 20),
  }) {
    late StreamController<SwapInfo> controller;
    StreamSubscription<SwapStatusEvent>? streamSubscription;
    Timer? pollingTimer;
    DateTime? lastStreamUpdateAt;
    var fetchInProgress = false;
    var isCancelled = false;

    bool canEmit() => !isCancelled && !controller.isClosed;

    Future<void> tearDownResources() async {
      pollingTimer?.cancel();
      pollingTimer = null;
      await streamSubscription?.cancel();
      streamSubscription = null;
    }

    Future<void> emitSnapshot() async {
      if (fetchInProgress || !canEmit()) return;
      fetchInProgress = true;
      try {
        final snapshot = await getSwapStatus(uuid: uuid);
        if (canEmit()) {
          controller.add(snapshot.swapInfo);
        }
      } on Object catch (e, s) {
        if (canEmit()) {
          controller.addError(e, s);
        }
      } finally {
        fetchInProgress = false;
      }
    }

    Future<void> start() async {
      await emitSnapshot();
      if (!canEmit()) return;

      try {
        final subscription = await _eventStreamingManager
            .subscribeToSwapStatus();
        if (!canEmit()) {
          await subscription.cancel();
          return;
        }

        streamSubscription = subscription
          ..onData((event) {
            if (!canEmit() || event.uuid != uuid) return;
            lastStreamUpdateAt = DateTime.now();
            controller.add(event.swapInfo);
          })
          ..onError((Object error, StackTrace trace) {
            if (canEmit()) {
              controller.addError(error, trace);
            }
          });
      } on Object catch (e, s) {
        if (canEmit()) {
          controller.addError(e, s);
        }
      }
      if (!canEmit()) {
        await tearDownResources();
        return;
      }

      pollingTimer = Timer.periodic(fallbackPollingInterval, (_) {
        if (!canEmit()) return;
        final lastUpdateAt = lastStreamUpdateAt;
        final streamIsFresh =
            lastUpdateAt != null &&
            DateTime.now().difference(lastUpdateAt) < streamStaleTimeout;
        if (!streamIsFresh) {
          emitSnapshot().ignore();
        }
      });
    }

    controller = StreamController<SwapInfo>(
      onListen: () => start().ignore(),
      onCancel: () async {
        isCancelled = true;
        await tearDownResources();
      },
    );

    return controller.stream;
  }

  /// Cached wrapper for `trade_preimage`.
  Future<TradePreimageResponse> tradePreimage({
    required String base,
    required String rel,
    required SwapMethod swapMethod,
    String? volume,
    bool? max,
    String? price,
  }) {
    final key =
        'trade_preimage:$base:$rel:${swapMethod.name}:'
        '${volume?.toString() ?? 'null'}:'
        '${max?.toString() ?? 'null'}:'
        '${price?.toString() ?? 'null'}';

    return _requestCache.getOrCreate<TradePreimageResponse>(
      key,
      ttl: _tradePreimageCacheTtl,
      request: () => _client.rpc.trading.tradePreimage(
        base: base,
        rel: rel,
        swapMethod: swapMethod,
        volume: volume,
        max: max,
        price: price,
      ),
    );
  }

  /// Cached wrapper for `max_taker_vol`.
  Future<MaxTakerVolumeResponse> maxTakerVolume({
    required String coin,
    String? tradeWith,
  }) async {
    final response = await _requestCache.getOrCreate<MaxTakerVolumeResponse>(
      'max_taker_vol:$coin:${tradeWith ?? ''}',
      ttl: _maxTakerCacheTtl,
      request: () =>
          _client.rpc.trading.maxTakerVolume(coin: coin, tradeWith: tradeWith),
    );
    return response;
  }

  /// Cached wrapper for `min_trading_vol`.
  Future<MinTradingVolumeResponse> minTradingVolume({
    required String coin,
  }) async {
    final response = await _requestCache.getOrCreate<MinTradingVolumeResponse>(
      'min_trading_vol:$coin',
      ttl: _minTradingCacheTtl,
      request: () => _client.rpc.trading.minTradingVolume(coin: coin),
    );
    return response;
  }

  /// Thin wrapper for `my_recent_swaps`.
  Future<RecentSwapsResponse> recentSwaps({
    int? limit,
    int? pageNumber,
    String? fromUuid,
    String? coin,
    String? otherCoin,
    int? fromTimestamp,
    int? toTimestamp,
  }) {
    final key =
        'my_recent_swaps:'
        '${limit?.toString() ?? 'null'}:'
        '${pageNumber?.toString() ?? 'null'}:'
        '${fromUuid ?? 'null'}:'
        '${coin ?? 'null'}:'
        '${otherCoin ?? 'null'}:'
        '${fromTimestamp?.toString() ?? 'null'}:'
        '${toTimestamp?.toString() ?? 'null'}';
    return _requestCache.getOrCreate<RecentSwapsResponse>(
      key,
      ttl: _recentSwapsCacheTtl,
      request: () => _client.rpc.trading.recentSwaps(
        limit: limit,
        pageNumber: pageNumber,
        fromUuid: fromUuid,
        coin: coin,
        otherCoin: otherCoin,
        fromTimestamp: fromTimestamp,
        toTimestamp: toTimestamp,
      ),
    );
  }

  OrderbookResponse _mapOrderbookEventToResponse(OrderbookEvent event) {
    final asks = event.asks.map(_mapOrderbookEntry).toList();
    final bids = event.bids.map(_mapOrderbookEntry).toList();

    return OrderbookResponse(
      mmrpc: '2.0',
      base: event.base,
      rel: event.rel,
      bids: bids,
      asks: asks,
      numBids: bids.length,
      numAsks: asks.length,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  OrderInfo _mapOrderbookEntry(Map<String, dynamic> entry) {
    final price = entry['price']?.toString();
    final maxVolume = entry['max_volume']?.toString();

    if (price == null || maxVolume == null) {
      throw ArgumentError('Orderbook entry is missing price/max_volume');
    }

    final minVolume = entry['min_volume']?.toString();

    return OrderInfo(
      uuid: entry['uuid']?.toString(),
      pubkey: entry['pubkey']?.toString(),
      price: NumericValue(decimal: price),
      baseMaxVolume: NumericValue(decimal: maxVolume),
      baseMaxVolumeAggregated: NumericValue(decimal: maxVolume),
      baseMinVolume: minVolume == null
          ? null
          : NumericValue(decimal: minVolume),
    );
  }
}

class _TimedRequestCache {
  final Map<String, _TimedCacheEntry<dynamic>> _resolved = {};
  final Map<String, Future<dynamic>> _inFlight = {};

  Future<T> getOrCreate<T>(
    String key, {
    required Duration ttl,
    required Future<T> Function() request,
  }) async {
    final now = DateTime.now();
    final cached = _resolved[key];
    if (cached != null && now.difference(cached.cachedAt) < ttl) {
      return cached.value as T;
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) {
      return await inFlight as T;
    }

    final future = request();
    _inFlight[key] = future;
    try {
      final value = await future;
      _resolved[key] = _TimedCacheEntry(value: value, cachedAt: DateTime.now());
      return value;
    } finally {
      final removed = _inFlight.remove(key);
      if (removed != null) {
        unawaited(removed);
      }
    }
  }
}

class _TimedCacheEntry<T> {
  _TimedCacheEntry({required this.value, required this.cachedAt});

  final T value;
  final DateTime cachedAt;
}
