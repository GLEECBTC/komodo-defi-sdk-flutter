import 'package:flutter/foundation.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

part 'balance_event.dart';
part 'heartbeat_event.dart';
part 'network_event.dart';
part 'order_status_event.dart';
part 'orderbook_event.dart';
part 'shutdown_signal_event.dart';
part 'swap_status_event.dart';
part 'task_event.dart';
part 'tx_history_event.dart';
part 'unknown_event.dart';

/// Private enum for internal event type string mapping
enum EventTypeString {
  balance('BALANCE'),
  orderbook('ORDERBOOK'),
  network('NETWORK'),
  heartbeat('HEARTBEAT'),
  swapStatus('SWAP_STATUS'),
  orderStatus('ORDER_STATUS'),
  task('TASK'),
  txHistory('TX_HISTORY'),
  shutdownSignal('SHUTDOWN_SIGNAL');

  const EventTypeString(this.value);
  final String value;
}

/// Base class for all KDF stream events.
///
/// This is a sealed class, which means you can exhaustively pattern match
/// on all possible event types using switch expressions.
///
/// Example:
/// ```dart
/// final event = KdfEvent.fromJson(json);
/// switch (event) {
///   case BalanceEvent(:final coin, :final balance):
///     print('Balance for $coin: $balance');
///   case OrderbookEvent(:final base, :final rel):
///     print('Orderbook update for $base/$rel');
///   case TaskEvent(:final taskId, :final taskData):
///     print('Task $taskId update: $taskData');
///   // ... handle other event types
/// }
/// ```
sealed class KdfEvent {
  const KdfEvent();

  /// Parse a single [KdfEvent] from raw JSON data.
  ///
  /// Most stream messages map to exactly one event. A BALANCE message with a
  /// list payload can describe several tickers (see [parseAll]); this method
  /// returns only the first. Prefer [parseAll] when consuming the raw stream so
  /// multi-token balance updates are not dropped.
  static KdfEvent fromJson(JsonMap json) {
    final List<KdfEvent> events = parseAll(json);
    if (events.isNotEmpty) return events.first;

    // Empty payloads (e.g. an empty BALANCE list) carry no concrete event.
    return UnknownEvent(
      typeString: json.valueOrNull<String>('_type') ?? 'UNKNOWN',
      rawData: json,
    );
  }

  /// Parse one raw stream message into one or more [KdfEvent]s.
  ///
  /// Most messages yield a single event. A BALANCE message with a list payload
  /// — used by protocols where one platform account holds several tokens and/or
  /// addresses (e.g. `BALANCE:TRX` carrying `USDT-TRC20` entries) — expands to
  /// one [BalanceEvent] per distinct ticker, with balances summed across
  /// addresses.
  static List<KdfEvent> parseAll(JsonMap json) {
    final typeString = json.value<String>('_type');
    final dynamic message = json.value<dynamic>('message');

    // Handle TASK:{taskId} pattern
    if (typeString.startsWith('TASK:')) {
      final taskIdStr = typeString.substring(5); // Remove "TASK:" prefix
      final taskId = int.tryParse(taskIdStr);
      if (taskId != null) {
        return [TaskEvent.fromJson(_asJsonMap(message), taskId)];
      }
    }

    // Some event types include contextual suffixes (e.g. "TX_HISTORY:COIN",
    // "ORDERBOOK:BASE:REL"). Normalize by stripping everything after the first
    // ':' so the base type can be matched, while keeping message payload for
    // concrete details (coin, pair, uuid, etc.).
    final normalizedType = typeString.contains(':')
        ? typeString.substring(0, typeString.indexOf(':'))
        : typeString;

    return switch (normalizedType) {
      'BALANCE' => _parseBalanceEvents(typeString, message),
      'ORDERBOOK' => [OrderbookEvent.fromJson(_asJsonMap(message))],
      'NETWORK' => [NetworkEvent.fromJson(_asJsonMap(message))],
      'HEARTBEAT' => [HeartbeatEvent.fromJson(_asJsonMap(message))],
      'SWAP_STATUS' => [SwapStatusEvent.fromJson(_asJsonMap(message))],
      'ORDER_STATUS' => [OrderStatusEvent.fromJson(_asJsonMap(message))],
      'TX_HISTORY' => [TxHistoryEvent.fromJson(_asJsonMap(message))],
      'SHUTDOWN_SIGNAL' => [ShutdownSignalEvent.fromJson(_asJsonMap(message))],
      _ => [_handleUnknownEvent(typeString, _wrapUnknown(message))],
    };
  }

  static JsonMap _asJsonMap(dynamic value) {
    if (value is Map) {
      return JsonMap.from(value);
    }
    if (value is String) {
      return JsonMapExtension.jsonFromString(value);
    }
    throw ArgumentError(
      'Expected type Map<String, dynamic> for message, but got ${value.runtimeType}',
    );
  }

  static JsonMap _wrapUnknown(dynamic value) {
    if (value is Map) return JsonMap.from(value);
    return {'raw': value};
  }

  /// Parse a BALANCE message into one [BalanceEvent] per distinct ticker.
  ///
  /// KDF sends balance updates in two shapes:
  ///  * a single object — `{"coin": "DOC", "balance": {...}}`
  ///  * a list of per-address entries — `[{"ticker": "USDT-TRC20",
  ///    "address": "...", "balance": {...}}, ...]`
  ///
  /// In the list form each entry carries its own `ticker`, so entries are
  /// grouped by ticker and summed across addresses, yielding one [BalanceEvent]
  /// per ticker. The `_type` suffix (e.g. the `TRX` in `BALANCE:TRX`) is the
  /// platform, not necessarily the ticker, so it is only used as a fallback
  /// when an entry omits its own `ticker`.
  static List<BalanceEvent> _parseBalanceEvents(
    String typeString,
    dynamic message,
  ) {
    // Single-object form: already in the expected shape.
    if (message is Map) {
      return [BalanceEvent.fromJson(JsonMap.from(message))];
    }

    if (message is List) {
      final String? coinFromType = _coinSuffix(typeString);

      // Group per-address entries by ticker, summing across addresses. A plain
      // map literal preserves first-seen insertion order, so emitted events
      // keep the order the tickers appeared in the payload.
      final Map<String, BalanceInfo> byTicker = {};

      for (final dynamic raw in message) {
        if (raw is! Map) continue;
        final JsonMap entry = JsonMap.from(raw);

        final String ticker =
            entry.valueOrNull<String>('ticker') ?? coinFromType ?? 'UNKNOWN';
        final BalanceInfo balance = BalanceInfo.fromJson(
          entry.value<JsonMap>('balance'),
        );

        final BalanceInfo? existing = byTicker[ticker];
        byTicker[ticker] = existing == null ? balance : existing + balance;
      }

      return [
        for (final MapEntry<String, BalanceInfo> entry in byTicker.entries)
          BalanceEvent(coin: entry.key, balance: entry.value),
      ];
    }

    // Fallback: unknown shape
    throw ArgumentError(
      'Expected BALANCE message to be Map or List, got ${message.runtimeType}',
    );
  }

  /// Extract the coin/platform suffix from an event type, e.g.
  /// `BALANCE:DOC` -> `DOC` and `BALANCE:TRX` -> `TRX`. Returns null when the
  /// type carries no suffix.
  static String? _coinSuffix(String typeString) {
    final int firstColon = typeString.indexOf(':');
    if (firstColon == -1 || firstColon + 1 >= typeString.length) return null;
    final int nextColon = typeString.indexOf(':', firstColon + 1);
    return nextColon == -1
        ? typeString.substring(firstColon + 1)
        : typeString.substring(firstColon + 1, nextColon);
  }

  /// Handles unknown event types by logging and returning an UnknownEvent
  static UnknownEvent _handleUnknownEvent(String typeString, JsonMap message) {
    if (kDebugMode) {
      print('[EventStream] Unknown event type: $typeString');
    }
    return UnknownEvent(typeString: typeString, rawData: message);
  }

  /// Internal method to get the event type enum for linking with RPC responses
  EventTypeString get typeEnum;
}
