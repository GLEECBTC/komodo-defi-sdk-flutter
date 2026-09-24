part of 'routed_swap_fixture.dart';

const String _provider = 'lifi';

const Set<String> _quoteKeys = {
  'from',
  'to',
  'amount',
  'slippage',
  'order',
  'provider',
};

const Set<String> _initErrorTypes = {
  'CoinNotActive',
  'PairNotSupported',
  'InvalidParam',
  'AmountOutOfBounds',
  'MyAddressError',
  'InternalError',
};

const Set<String> _approvalFailures = {
  'approval_broadcast_failed',
  'approval_transaction_failed',
  'allowance_reset_not_confirmed',
  'confirmed_allowance_insufficient',
};

const Set<String> _txFailures = {
  'source_transaction_reverted',
  'source_transaction_not_confirmed',
};

const Set<String> _signingRejections = {
  'user_rejected',
  'timeout',
  'unsupported_method',
};

const Set<String> _preflightChecks = {
  'simulation',
  'target_allowlist',
  'spender_allowlist',
  'value_cap',
  'amount_bounds',
  'gas_bounds',
};

const List<String> _stageOrder = [
  'unknown',
  'bridging',
  'destination_pending',
  'refund_pending',
];

final RegExp _uuidPattern = RegExp(
  '^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}|[0-9a-fA-F]{32})$',
);

String _pairKey(String from, String to) => '$from->$to';

String _uuidFor(int seq) =>
    '${seq.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

String _txHash(String tag, int seq) =>
    '0x$tag${seq.toRadixString(16).padLeft(62, '0')}';

String _normalizeUuid(String uuid) {
  final lower = uuid.toLowerCase();
  if (lower.length != 32) return lower;
  return '${lower.substring(0, 8)}-${lower.substring(8, 12)}-'
      '${lower.substring(12, 16)}-${lower.substring(16, 20)}-'
      '${lower.substring(20)}';
}

Map<String, dynamic> _params(Map<String, dynamic> request) {
  final params = request['params'];
  return params is Map ? Map<String, dynamic>.from(params) : const {};
}

String _numberText(Object? value) =>
    value is String ? value : _f64Text(value! as num);

/// Rust's `f64` display: no trailing `.0` on whole numbers.
String _f64Text(num value) =>
    value is double && value.isFinite && value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();

/// `MmNumber::to_decimal`: rational, so trailing zeros are gone.
String _decimalText(String value) =>
    Decimal.tryParse(value)?.toString() ?? value;

bool _sameNumber(String a, String b) {
  final left = Decimal.tryParse(a);
  final right = Decimal.tryParse(b);
  return left != null && left == right;
}

Decimal _decimal(String value, String name) {
  final parsed = Decimal.tryParse(value);
  if (parsed == null || parsed < Decimal.zero) {
    throw ArgumentError.value(value, name, 'must be a non-negative decimal');
  }
  return parsed;
}

String _observedStage(String? substatus) => switch (substatus) {
  'WAIT_SOURCE_CONFIRMATIONS' => 'bridging',
  'WAIT_DESTINATION_TRANSACTION' => 'destination_pending',
  'REFUND_IN_PROGRESS' => 'refund_pending',
  _ => 'unknown',
};

/// `RoutedSwapTrackingStage::advance`: a refund latches, other stages only
/// move forward.
String _advanceStage(String current, String observed) {
  if (observed == 'refund_pending' || current == 'refund_pending') {
    return 'refund_pending';
  }
  return _stageOrder.indexOf(observed) > _stageOrder.indexOf(current)
      ? observed
      : current;
}

/// What goes over the wire: plain decoded JSON, so a caller can neither
/// mutate fixture state nor receive a value KDF could not send.
Map<String, dynamic> _wireMap(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class _ScriptedQuoteError {
  _ScriptedQuoteError(this.error, this.remaining);

  final RoutedSwapQuoteError error;
  int? remaining;
}

enum _EventKind {
  progress,
  completed,
  failed,
  gasSpent,
  approvalHash,
  cancelled,
  aborted,
}

/// `RoutedSwapEvent`.
class _Event {
  _Event._(
    this.at,
    this.kind, {
    this.details,
    this.txHash,
    this.coin,
    this.amount,
  });

  _Event.progress(int at, Map<String, dynamic> details)
    : this._(at, _EventKind.progress, details: details);

  _Event.completed(int at, Map<String, dynamic> details)
    : this._(at, _EventKind.completed, details: details);

  _Event.failed(int at, Map<String, dynamic> details)
    : this._(at, _EventKind.failed, details: details);

  _Event.gas(int at, _Gas gas)
    : this._(
        at,
        _EventKind.gasSpent,
        txHash: gas.txHash,
        coin: gas.coin,
        amount: gas.amount,
      );

  _Event.approvalHash(int at, String txHash)
    : this._(at, _EventKind.approvalHash, txHash: txHash);

  _Event.cancelled(int at) : this._(at, _EventKind.cancelled);

  _Event.aborted(int at) : this._(at, _EventKind.aborted);

  final int at;
  final _EventKind kind;
  final Map<String, dynamic>? details;
  final String? txHash;
  final String? coin;
  final String? amount;

  /// Gas and approval metadata never replace the task state.
  bool get isMetadata =>
      kind == _EventKind.gasSpent || kind == _EventKind.approvalHash;

  bool get isTerminal =>
      kind == _EventKind.completed ||
      kind == _EventKind.failed ||
      kind == _EventKind.cancelled ||
      kind == _EventKind.aborted;
}

class _Gas {
  const _Gas(this.txHash, this.coin, this.amount);

  final String txHash;
  final String coin;
  final String amount;
}

class _Terminal {
  const _Terminal({required this.ok, required this.details});

  final bool ok;
  final Map<String, dynamic> details;

  _Event event(int at) =>
      ok ? _Event.completed(at, details) : _Event.failed(at, details);
}

class _Transition {
  _Transition.progress(Map<String, dynamic> this.details, this.gas)
    : terminal = null,
      tracking = details['state'] == RoutedSwapRunState.trackingBridge.wire;

  _Transition.terminal(_Terminal this.terminal, this.gas)
    : details = null,
      tracking = false;

  final Map<String, dynamic>? details;
  final _Terminal? terminal;
  final List<_Gas> gas;
  final bool tracking;
}

/// One swap: its durable record, its run and its live task.
class _Swap {
  _Swap({required this.plan, required this.createdAt});

  final _Plan plan;
  final int createdAt;
  final List<_Event> events = <_Event>[];

  /// Every task id this swap was ever registered under.
  final Set<int> taskIds = <int>{};
  List<_Transition> transitions = const [];
  int cursor = 0;
  int? taskId;

  /// Status reads of the current state.
  int observed = 0;

  String get uuid => plan.uuid;

  _Event get semantic => events.lastWhere((e) => !e.isMetadata);

  bool get isTerminal => semantic.isTerminal;

  Map<String, dynamic> get lastProgress =>
      events.lastWhere((e) => e.kind == _EventKind.progress).details!;

  /// The engine's current state, from the latest progress event.
  RoutedSwapRunState get engineState {
    final wire = lastProgress['state'];
    return RoutedSwapRunState.values.firstWhere((s) => s.wire == wire);
  }
}
