import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';
import '../primitive/mm2_rational.dart';
import '../primitive/fraction.dart';

/// Comprehensive information about an atomic swap.
///
/// This class represents the complete state and history of an atomic swap,
/// including the involved coins, amounts, timeline, and event log. It's used
/// across various RPC responses to provide detailed swap information.
///
/// ## Swap Lifecycle:
///
/// 1. **Initiation**: Swap is created with initial parameters
/// 2. **Negotiation**: Peers exchange required information
/// 3. **Payment**: Maker and taker send their payments
/// 4. **Claiming**: Recipients claim their payments
/// 5. **Completion**: Swap completes successfully or fails
///
/// ## Event Tracking:
///
/// The swap tracks two types of events:
/// - **Success Events**: Milestones achieved during normal execution
/// - **Error Events**: Problems encountered during the swap
class SwapInfo {
  /// Creates a new [SwapInfo] instance.
  ///
  /// All parameters except [startedAt] and [finishedAt] are required.
  ///
  /// - [uuid]: Unique identifier for the swap
  /// - [myOrderUuid]: UUID of the order that initiated this swap
  /// - [takerAmount]: Amount of taker coin in the swap
  /// - [takerCoin]: Ticker of the taker coin
  /// - [makerAmount]: Amount of maker coin in the swap
  /// - [makerCoin]: Ticker of the maker coin
  /// - [type]: The swap type (Maker or Taker)
  /// - [gui]: Optional GUI identifier that initiated the swap
  /// - [mmVersion]: Market maker version information
  /// - [successEvents]: List of successfully completed swap events
  /// - [errorEvents]: List of error events encountered
  /// - [startedAt]: Unix timestamp when the swap started
  /// - [finishedAt]: Unix timestamp when the swap finished
  SwapInfo({
    required this.uuid,
    required this.myOrderUuid,
    required this.takerAmount,
    required this.takerCoin,
    required this.makerAmount,
    required this.makerCoin,
    required this.type,
    required this.gui,
    required this.mmVersion,
    required this.successEvents,
    required this.errorEvents,
    this.startedAt,
    this.finishedAt,
    this.takerAmountFraction,
    this.takerAmountRat,
    this.makerAmountFraction,
    this.makerAmountRat,
    this.eventTypes = const [],
    this.isFinishedFlag,
  });

  /// Creates a [SwapInfo] instance from a JSON map.
  ///
  /// Parses the swap information from the API response format.
  factory SwapInfo.fromJson(JsonMap json) {
    return SwapInfo(
      uuid: json.value<String>('uuid'),
      myOrderUuid: json.value<String>('my_order_uuid'),
      takerAmount: json.value<String>('taker_amount'),
      takerCoin: json.value<String>('taker_coin'),
      makerAmount: json.value<String>('maker_amount'),
      makerCoin: json.value<String>('maker_coin'),
      type: json.value<String>('type'),
      gui: json.valueOrNull<String?>('gui'),
      mmVersion: json.valueOrNull<String?>('mm_version'),
      successEvents: json.value<List<String>>('success_events'),
      errorEvents: json.value<List<String>>('error_events'),
      startedAt: json.valueOrNull<int?>('started_at'),
      finishedAt: json.valueOrNull<int?>('finished_at'),
      eventTypes: _eventTypesOf(json.valueOrNull<List<dynamic>>('events')),
      isFinishedFlag: json.valueOrNull<bool>('is_finished'),
      takerAmountFraction:
          json.valueOrNull<JsonMap>('taker_amount_fraction') != null
              ? Fraction.fromJson(json.value<JsonMap>('taker_amount_fraction'))
              : null,
      takerAmountRat:
          json.valueOrNull<List<dynamic>>('taker_amount_rat') != null
              ? rationalFromMm2(json.value<List<dynamic>>('taker_amount_rat'))
              : null,
      makerAmountFraction:
          json.valueOrNull<JsonMap>('maker_amount_fraction') != null
              ? Fraction.fromJson(json.value<JsonMap>('maker_amount_fraction'))
              : null,
      makerAmountRat:
          json.valueOrNull<List<dynamic>>('maker_amount_rat') != null
              ? rationalFromMm2(json.value<List<dynamic>>('maker_amount_rat'))
              : null,
    );
  }

  /// Unique identifier for this swap.
  ///
  /// This UUID is used to track and reference the swap throughout its lifecycle.
  final String uuid;

  /// UUID of the order that initiated this swap.
  ///
  /// Links this swap to the original maker order that was matched.
  final String myOrderUuid;

  /// Amount of the taker coin involved in the swap.
  ///
  /// Expressed as a string to maintain precision. This is the amount
  /// the taker is sending in the swap.
  final String takerAmount;

  /// Ticker of the taker coin.
  ///
  /// Identifies which coin the taker is sending in the swap.
  final String takerCoin;

  /// Amount of the maker coin involved in the swap.
  ///
  /// Expressed as a string to maintain precision. This is the amount
  /// the maker is sending in the swap.
  final String makerAmount;

  /// Ticker of the maker coin.
  ///
  /// Identifies which coin the maker is sending in the swap.
  final String makerCoin;

  /// The type of swap from the user's perspective.
  ///
  /// Either "Maker" if the user created the initial order, or "Taker"
  /// if the user is taking an existing order.
  final String type;

  /// Optional identifier of the GUI that initiated the swap.
  ///
  /// Used for tracking which interface or bot created the swap.
  final String? gui;

  /// Version information of the market maker software.
  ///
  /// Helps with debugging and compatibility tracking.
  final String? mmVersion;

  /// List of successfully completed swap events.
  ///
  /// Events are added as the swap progresses through its lifecycle.
  /// Examples include:
  /// - "Started"
  /// - "Negotiated"
  /// - "TakerPaymentSent"
  /// - "MakerPaymentReceived"
  /// - "MakerPaymentSpent"
  /// - "Finished"
  final List<String> successEvents;

  /// List of error events encountered during the swap.
  ///
  /// If the swap fails, this list contains information about what went wrong.
  /// Examples include:
  /// - "NegotiationFailed"
  /// - "TakerPaymentTimeout"
  /// - "MakerPaymentNotReceived"
  final List<String> errorEvents;

  /// Unix timestamp of when the swap started.
  ///
  /// Recorded when the swap is first initiated.
  final int? startedAt;

  /// Unix timestamp of when the swap finished.
  ///
  /// Recorded when the swap completes (successfully or with failure).
  final int? finishedAt;

  /// Optional fractional representation of the taker amount
  final Fraction? takerAmountFraction;

  /// Optional rational representation of the taker amount
  final Rational? takerAmountRat;

  /// Optional fractional representation of the maker amount
  final Fraction? makerAmountFraction;

  /// Optional rational representation of the maker amount
  final Rational? makerAmountRat;

  /// The types of the events that have actually happened, in order.
  ///
  /// Not to be confused with [successEvents] and [errorEvents], which KDF
  /// reports as the *static* lists of event names that count as success or
  /// error for this swap type — [errorEvents] is never empty, so it says
  /// nothing about whether an error occurred. Whether one did is answered by
  /// intersecting it with these.
  final List<String> eventTypes;

  /// KDF's own `is_finished` flag, when the payload carries one.
  final bool? isFinishedFlag;

  /// Converts this [SwapInfo] instance to a JSON map.
  ///
  /// The resulting map can be serialized to JSON and follows the
  /// expected API format.
  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'my_order_uuid': myOrderUuid,
    'taker_amount': takerAmount,
    'taker_coin': takerCoin,
    'maker_amount': makerAmount,
    'maker_coin': makerCoin,
    'type': type,
    if (gui != null) 'gui': gui,
    if (mmVersion != null) 'mm_version': mmVersion,
    'success_events': successEvents,
    'error_events': errorEvents,
    if (startedAt != null) 'started_at': startedAt,
    if (finishedAt != null) 'finished_at': finishedAt,
    if (eventTypes.isNotEmpty)
      'events': [
        for (final type in eventTypes)
          {
            'event': {'type': type},
          },
      ],
    if (isFinishedFlag != null) 'is_finished': isFinishedFlag,
    if (takerAmountFraction != null)
      'taker_amount_fraction': takerAmountFraction!.toJson(),
    if (takerAmountRat != null)
      'taker_amount_rat': rationalToMm2(takerAmountRat!),
    if (makerAmountFraction != null)
      'maker_amount_fraction': makerAmountFraction!.toJson(),
    if (makerAmountRat != null)
      'maker_amount_rat': rationalToMm2(makerAmountRat!),
  };

  /// Whether this swap has completed (successfully or with failure).
  ///
  /// Complete when it has a [finishedAt] timestamp, KDF flags it finished,
  /// or its event log contains `Finished`.
  bool get isComplete =>
      finishedAt != null ||
      (isFinishedFlag ?? false) ||
      eventTypes.contains('Finished');

  /// Whether an error event has actually occurred.
  ///
  /// [errorEvents] alone cannot answer this: it is the static list of event
  /// names that would count as errors, and it is never empty.
  bool get hasFailed => eventTypes.any(errorEvents.contains);

  /// Whether this swap completed successfully: complete, with no error event
  /// in its log.
  bool get isSuccessful => isComplete && !hasFailed;

  /// Duration of the swap in seconds.
  ///
  /// Returns `null` if the swap hasn't started or finished yet.
  int? get durationSeconds {
    if (startedAt == null || finishedAt == null) return null;
    return finishedAt! - startedAt!;
  }
}

/// Reads the event types from an `events` list.
///
/// Legacy swaps report `{timestamp, event: {type, data}}`; newer payloads have
/// used `{event_type, event_data}` and a flat `{type}`. Anything else is
/// skipped rather than failing the whole swap.
List<String> _eventTypesOf(List<dynamic>? events) {
  if (events == null) return const [];
  final types = <String>[];
  for (final entry in events) {
    if (entry is! Map) continue;
    final event = entry['event'];
    final type =
        event is Map ? event['type'] : entry['event_type'] ?? entry['type'];
    if (type is String) types.add(type);
  }
  return types;
}

