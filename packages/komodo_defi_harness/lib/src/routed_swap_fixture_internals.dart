part of 'routed_swap_fixture.dart';

/// Bookkeeping for the scripted engine's swaps.
extension _FixtureInternals on RoutedSwapFixture {
  int _now() => _clock?.call() ?? _counter++;

  void _register(_Swap swap) {
    final taskId = _nextTaskId++;
    swap
      ..taskId = taskId
      ..taskIds.add(taskId)
      ..observed = 0;
    _tasks[taskId] = swap;
  }

  void _unregister(_Swap swap) {
    _tasks.remove(swap.taskId);
    swap.taskId = null;
  }

  void _step(_Swap swap) {
    if (swap.cursor >= swap.transitions.length) return;
    final transition = swap.transitions[swap.cursor++];
    swap.observed = 0;
    for (final gas in transition.gas) {
      final recorded = swap.events.any(
        (e) => e.kind == _EventKind.gasSpent && e.txHash == gas.txHash,
      );
      if (!recorded) swap.events.add(_Event.gas(_now(), gas));
    }
    final details = transition.details;
    if (details == null) {
      swap.events.add(transition.terminal!.event(_now()));
      return;
    }
    // Tracking persists only a changed update (`update_tracking`).
    if (transition.tracking &&
        jsonEncode(swap.lastProgress) == jsonEncode(details)) {
      return;
    }
    swap.events.add(_Event.progress(_now(), details));
  }

  void _resume(_Swap swap) {
    final ladder = swap.plan.ladder;
    final confirmation = ladder.indexWhere(
      (tick) => tick.state == RoutedSwapRunState.waitingSourceConfirmation,
    );
    swap
      ..transitions = swap.plan.transitions([
        RoutedSwapTick.waitingSourceConfirmation,
        if (confirmation >= 0) ...ladder.sublist(confirmation + 1),
      ], previous: null)
      ..cursor = 0
      ..observed = 0;
  }

  _Swap _swapByUuid(String uuid) {
    final wanted = _normalizeUuid(uuid);
    return _swaps.firstWhere(
      (swap) => swap.uuid == wanted,
      orElse: () =>
          throw ArgumentError.value(uuid, 'uuid', 'no routed swap recorded'),
    );
  }

  RoutedSwapQuote? _quoteFor(String from, String to, String amount) {
    final scripted = _quotes[_pairKey(from, to)];
    if (scripted == null) return null;
    for (final quote in scripted.reversed) {
      if (quote.amount != null && _sameNumber(quote.amount!, amount)) {
        return quote;
      }
    }
    for (final quote in scripted.reversed) {
      if (quote.amount == null) return quote;
    }
    return null;
  }

  Map<String, dynamic>? _historyShape(Map<String, dynamic> request) {
    final invalid = _shape(
      request,
      strings: const {'status_filter'},
      optionalStrings: const {'uuid', 'my_coin', 'other_coin'},
      counts: const {'limit', 'page_number'},
      optionalCounts: const {'from_timestamp', 'to_timestamp'},
    );
    if (invalid != null) return invalid;
    final params = _params(request);
    final uuid = params['uuid'];
    if (uuid is String && !_uuidPattern.hasMatch(uuid)) {
      return _invalidRequest(request, 'invalid UUID `$uuid`');
    }
    final filter = params['status_filter'];
    const filters = {'in_flight', 'terminal', 'all'};
    if (filter != null && !filters.contains(filter)) {
      return _invalidRequest(
        request,
        'unknown variant `$filter`, expected one of `in_flight`, `terminal`, '
        '`all`',
      );
    }
    if (params['page_number'] == 0) {
      return _invalidRequest(
        request,
        'invalid value: integer `0`, expected a nonzero usize',
      );
    }
    return null;
  }
}

Map<String, dynamic> _status(_Swap swap) {
  final semantic = swap.semantic;
  return switch (semantic.kind) {
    _EventKind.progress => {
      'status': 'InProgress',
      'details': semantic.details,
    },
    _EventKind.completed => {'status': 'Ok', 'details': semantic.details},
    _EventKind.failed => {'status': 'Error', 'details': semantic.details},
    _EventKind.cancelled => {
      'status': 'Error',
      'details': _synthetic(
        swap,
        'TaskCancelled',
        'Routed swap cancelled before broadcast',
      ),
    },
    _EventKind.aborted => {
      'status': 'Error',
      'details': _synthetic(
        swap,
        'AbortedOnRestart',
        'Swap aborted by node restart before broadcast',
      ),
    },
    _EventKind.gasSpent || _EventKind.approvalHash => throw StateError(
      'informational event used as task state',
    ),
  };
}

/// `SyntheticTerminalError`: the history-only outcomes, with no
/// `error_data`.
Map<String, dynamic> _synthetic(_Swap swap, String errorType, String error) {
  Map<String, dynamic>? route;
  for (final event in swap.events.reversed) {
    if (event.kind != _EventKind.progress) continue;
    route = event.details!['executed_route'] as Map<String, dynamic>?;
    if (route != null) break;
  }
  return {
    'uuid': swap.uuid,
    'provider': _provider,
    if (route != null) 'executed_route': route,
    'error_type': errorType,
    'error': error,
  };
}

/// `RoutedSwapDbRepr::history_entry`.
Map<String, dynamic> _entry(_Swap swap) {
  final index = swap.events.lastIndexWhere((e) => !e.isMetadata);
  final semantic = swap.events[index];
  int? finishedAt;
  if (semantic.kind == _EventKind.cancelled) {
    finishedAt = semantic.at;
    for (final event in swap.events.skip(index + 1)) {
      if (event.kind == _EventKind.approvalHash && event.txHash!.isNotEmpty) {
        finishedAt = event.at;
      }
    }
  } else if (semantic.isTerminal) {
    finishedAt = semantic.at;
  }

  final approvals = <String>[];
  final gasSpent = <Map<String, dynamic>>[];
  final totals = <String, Decimal>{};
  for (final event in swap.events) {
    final hash = switch (event.kind) {
      _EventKind.progress => event.details!['approve_tx_hash'] as String?,
      _EventKind.approvalHash => event.txHash,
      _ => null,
    };
    if (hash != null && !approvals.contains(hash)) approvals.add(hash);
    if (event.kind == _EventKind.gasSpent) {
      gasSpent.add({
        'tx_hash': event.txHash,
        'coin': event.coin,
        'amount': event.amount,
      });
      totals[event.coin!] =
          (totals[event.coin!] ?? Decimal.zero) + Decimal.parse(event.amount!);
    }
  }
  return {
    'created_at': swap.createdAt,
    'updated_at': swap.events.last.at,
    if (finishedAt != null) 'finished_at': finishedAt,
    'requested': {
      'from': swap.plan.from,
      'to': swap.plan.to,
      'amount': _decimalText(swap.plan.amount),
    },
    'min_to_amount_accepted': _decimalText(swap.plan.minToAmount),
    'approval_tx_hashes': approvals,
    'gas_spent': gasSpent,
    'total_gas_spent': [
      for (final entry in totals.entries)
        {'coin': entry.key, 'amount': entry.value.toString()},
    ],
    'swap': _status(swap),
  };
}

/// `ORDER BY started_at DESC, uuid ASC`.
List<_Swap> _sorted(List<_Swap> swaps) => [...swaps]
  ..sort((a, b) {
    final byCreated = b.createdAt.compareTo(a.createdAt);
    return byCreated != 0 ? byCreated : a.uuid.compareTo(b.uuid);
  });

/// Serde rejecting a request before the handler runs: the dispatcher's
/// `InvalidRequest`. [strings], [numbers], [counts] and [booleans] must not
/// be null when present; the `optional` sets are `Option<T>` fields, which
/// accept null.
Map<String, dynamic>? _shape(
  Map<String, dynamic> request, {
  Set<String>? allowed,
  Set<String> required = const {},
  Set<String> strings = const {},
  Set<String> optionalStrings = const {},
  Set<String> numbers = const {},
  Set<String> counts = const {},
  Set<String> optionalCounts = const {},
  Set<String> booleans = const {},
}) {
  final raw = request['params'];
  if (raw != null && raw is! Map) {
    return _invalidRequest(request, 'invalid type: expected a map');
  }
  final params = _params(request);
  for (final key in params.keys) {
    if (allowed != null && !allowed.contains(key)) {
      return _invalidRequest(request, 'unknown field `$key`');
    }
  }
  for (final key in required) {
    if (!params.containsKey(key)) {
      return _invalidRequest(request, 'missing field `$key`');
    }
  }
  for (final entry in params.entries) {
    final key = entry.key;
    final value = entry.value;
    final nullable =
        optionalStrings.contains(key) || optionalCounts.contains(key);
    if (value == null) {
      if (nullable) continue;
      if (strings.contains(key) ||
          numbers.contains(key) ||
          counts.contains(key) ||
          booleans.contains(key)) {
        return _invalidRequest(
          request,
          'invalid type: null, expected a value for `$key`',
        );
      }
      continue;
    }
    final valid = switch (key) {
      _ when strings.contains(key) || optionalStrings.contains(key) =>
        value is String,
      _ when numbers.contains(key) =>
        value is num || value is String && Decimal.tryParse(value) != null,
      _ when counts.contains(key) || optionalCounts.contains(key) =>
        value is int && value >= 0,
      _ when booleans.contains(key) => value is bool,
      _ => true,
    };
    if (!valid) {
      return _invalidRequest(request, 'invalid type for `$key`: $value');
    }
  }
  return null;
}

/// `validate_request_options` then `validate_slippage`.
Map<String, dynamic>? _options(
  Map<String, dynamic> request, {
  bool providerOnly = false,
}) {
  final params = _params(request);
  final provider = params['provider'];
  if (provider != null && provider != _provider) {
    return _scriptedError(
      request,
      RoutedSwapQuoteError.invalidParam(
        'provider',
        'Unsupported routed swap provider',
      ),
    );
  }
  if (providerOnly) return null;
  final order = params['order'];
  if (order != null && order != 'cheapest' && order != 'fastest') {
    return _scriptedError(
      request,
      RoutedSwapQuoteError.invalidParam(
        'order',
        'Unsupported routed swap order',
      ),
    );
  }
  final slippage = params['slippage'];
  if (slippage is num && !(slippage >= 0 && slippage <= 0.5)) {
    return _scriptedError(
      request,
      RoutedSwapQuoteError.amountOutOfBounds(
        param: 'slippage',
        value: _f64Text(slippage),
        min: '0',
        max: '0.5',
      ),
    );
  }
  return null;
}

Map<String, dynamic> _invalidRequest(
  Map<String, dynamic> request,
  String detail,
) => _error(
  request,
  type: 'InvalidRequest',
  message: 'Error parsing request: $detail',
  data: detail,
  path: 'dispatcher',
);

Map<String, dynamic> _scriptedError(
  Map<String, dynamic> request,
  RoutedSwapQuoteError error,
) => _error(
  request,
  type: error.errorType,
  message: error.message,
  data: error.errorData,
);

Map<String, dynamic> _ok(Map<String, dynamic> request, Object result) =>
    _wireMap({
      'mmrpc': '2.0',
      'result': result,
      // `MmRpcResponse.id` is an `Option` without `skip_serializing_if`: the
      // one null KDF does send.
      'id': request['id'],
    });

/// A top-level MMRPC error: the serialized `MmError` flattened beside
/// `mmrpc`. Distinct from a terminal task `Error` result.
Map<String, dynamic> _error(
  Map<String, dynamic> request, {
  required String type,
  required String message,
  required Object data,
  String path = 'routed_swap',
}) => _wireMap({
  'mmrpc': '2.0',
  'error': message,
  'error_path': path,
  'error_trace': '$path:1]',
  'error_type': type,
  'error_data': data,
  'id': request['id'],
});
