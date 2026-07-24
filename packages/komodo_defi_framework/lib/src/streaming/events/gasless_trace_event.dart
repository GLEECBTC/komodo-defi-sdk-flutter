part of 'kdf_event.dart';

/// Lifecycle state emitted by `stream::gasless_trace::enable`.
enum GaslessTraceEventState {
  pending,
  submitted,
  onChain,
  confirmed,
  failed;

  static GaslessTraceEventState parse(String value) => switch (value) {
    'pending' => GaslessTraceEventState.pending,
    'submitted' => GaslessTraceEventState.submitted,
    'on_chain' => GaslessTraceEventState.onChain,
    'confirmed' => GaslessTraceEventState.confirmed,
    'failed' => GaslessTraceEventState.failed,
    _ => throw FormatException('Unknown GasFree trace state: $value'),
  };

  bool get isTerminal =>
      this == GaslessTraceEventState.confirmed ||
      this == GaslessTraceEventState.failed;
}

/// Typed GasFree trace status event.
///
/// KDF emits this as `_type: GASLESS_TRACE:<coin>`. The event is scoped to a
/// coin streamer, but [coin] is also required in the message and validated by
/// consumers before updating a transfer.
class GaslessTraceEvent extends KdfEvent {
  const GaslessTraceEvent({
    required this.coin,
    required this.traceId,
    required this.state,
    this.txHashOnChain,
    this.blockHeight,
    this.confirmedAt,
    this.finalFee,
    this.failureReason,
  });

  factory GaslessTraceEvent.fromJson(JsonMap json, {String? coinFromType}) {
    final coin = json.valueOrNull<String>('coin') ?? coinFromType;
    if (coin == null || coin.isEmpty) {
      throw const FormatException('GasFree trace event is missing coin');
    }
    if (coinFromType != null && coin != coinFromType) {
      throw const FormatException(
        'GasFree trace event coin does not match its stream type',
      );
    }
    final traceId = json.value<String>('trace_id');
    if (traceId.trim().isEmpty) {
      throw const FormatException('GasFree trace event is missing trace_id');
    }
    final state = GaslessTraceEventState.parse(json.value<String>('state'));
    final failureReason = json.valueOrNull<String>('failure_reason');
    if (state == GaslessTraceEventState.failed && failureReason == null) {
      throw const FormatException(
        'A failed GasFree trace event must include failure_reason',
      );
    }
    if (state != GaslessTraceEventState.failed && failureReason != null) {
      throw const FormatException(
        'Only a failed GasFree trace event may include failure_reason',
      );
    }
    return GaslessTraceEvent(
      coin: coin,
      traceId: traceId,
      state: state,
      txHashOnChain: json.valueOrNull<String>('tx_hash_on_chain'),
      blockHeight: json.valueOrNull<int>('block_height'),
      confirmedAt: json.valueOrNull<int>('confirmed_at'),
      finalFee: json.valueOrNull<dynamic>('final_fee')?.toString(),
      failureReason: failureReason,
    );
  }

  final String coin;
  final String traceId;
  final GaslessTraceEventState state;
  final String? txHashOnChain;
  final int? blockHeight;

  /// Unix timestamp in seconds.
  final int? confirmedAt;

  /// Token-denominated decimal string.
  final String? finalFee;
  final String? failureReason;

  @override
  EventTypeString get typeEnum => EventTypeString.gaslessTrace;

  @override
  String toString() =>
      'GaslessTraceEvent(coin: $coin, traceId: $traceId, state: $state)';
}

/// Typed stream error emitted for a registered GasFree trace.
///
/// The runtime wire prefix is `ERROR:GASLESS_TRACE:<coin>`.
class GaslessTraceErrorEvent extends KdfEvent {
  const GaslessTraceErrorEvent({
    required this.coin,
    required this.traceId,
    required this.error,
  });

  factory GaslessTraceErrorEvent.fromJson(
    JsonMap json, {
    String? coinFromType,
  }) {
    final coin = json.valueOrNull<String>('coin') ?? coinFromType;
    if (coin == null || coin.isEmpty) {
      throw const FormatException('GasFree trace error is missing coin');
    }
    if (coinFromType != null && coin != coinFromType) {
      throw const FormatException(
        'GasFree trace error coin does not match its stream type',
      );
    }
    final traceId = json.value<String>('trace_id');
    final error = json.value<String>('error');
    if (traceId.trim().isEmpty || error.trim().isEmpty) {
      throw const FormatException(
        'GasFree trace error is missing trace_id or error',
      );
    }
    return GaslessTraceErrorEvent(coin: coin, traceId: traceId, error: error);
  }

  final String coin;
  final String traceId;
  final String error;

  @override
  EventTypeString get typeEnum => EventTypeString.gaslessTraceError;

  @override
  String toString() => 'GaslessTraceErrorEvent(coin: $coin, traceId: $traceId)';
}
