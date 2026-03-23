part of 'kdf_event.dart';

/// Orderbook update event from stream::orderbook::enable
class OrderbookEvent extends KdfEvent {
  OrderbookEvent({
    required this.base,
    required this.rel,
    required this.asks,
    required this.bids,
  });

  @override
  EventTypeString get typeEnum => EventTypeString.orderbook;

  factory OrderbookEvent.fromJson(JsonMap json) {
    final asks = (json.value<List<dynamic>>(
      'asks',
    )).map((e) => _parseOrderbookEntry(e as JsonMap)).toList();
    final bids = (json.value<List<dynamic>>(
      'bids',
    )).map((e) => _parseOrderbookEntry(e as JsonMap)).toList();

    return OrderbookEvent(
      base: json.value<String>('base'),
      rel: json.value<String>('rel'),
      asks: asks,
      bids: bids,
    );
  }

  static Map<String, dynamic> _parseOrderbookEntry(JsonMap json) {
    return {
      'price': json.value<String>('price'),
      'max_volume': json.value<String>('max_volume'),
      if (json.containsKey('min_volume'))
        'min_volume': json.value<String>('min_volume'),
      if (json.containsKey('uuid')) 'uuid': json.value<String>('uuid'),
      if (json.containsKey('pubkey')) 'pubkey': json.value<String>('pubkey'),
      if (json.containsKey('age')) 'age': json.value<int>('age'),
    };
  }

  /// Base coin ticker
  final String base;

  /// Rel/quote coin ticker
  final String rel;

  /// List of ask (sell) orders
  final List<Map<String, dynamic>> asks;

  /// List of bid (buy) orders
  final List<Map<String, dynamic>> bids;

  @override
  String toString() =>
      'OrderbookEvent(base: $base, rel: $rel, asks: ${asks.length}, bids: ${bids.length})';
}
